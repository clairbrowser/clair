// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/clair_importer.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <cstdlib>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "base/apple/foundation_util.h"
#include "base/files/file_enumerator.h"
#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/cancelable_task_tracker.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/thread_pool.h"
#include "base/time/time.h"
#include "base/values.h"
#include "chrome/browser/bookmarks/bookmark_model_factory.h"
#import "chrome/browser/clair/clair_pin_store.h"
#include "chrome/browser/clair/clair_profiles.h"
#include "chrome/browser/clair/clair_space_store.h"
#import "chrome/browser/clair/clair_space_tabs.h"
#import "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/clair/window/clair_splits.h"
#include "chrome/browser/clair/window/clair_window_group.h"
#include "chrome/browser/history/history_service_factory.h"
#include "chrome/browser/importer/profile_writer.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "components/bookmarks/browser/base_bookmark_model_observer.h"
#include "components/bookmarks/browser/bookmark_model.h"
#include "components/bookmarks/browser/bookmark_node.h"
#include "components/favicon_base/favicon_usage_data.h"
#include "components/history/core/browser/history_backend.h"
#include "components/history/core/browser/history_database.h"
#include "components/history/core/browser/history_db_task.h"
#include "components/history/core/browser/history_service.h"
#include "components/history/core/browser/history_types.h"
#include "components/history/core/browser/url_row.h"
#include "components/keyed_service/core/service_access_type.h"
#include "components/sessions/core/command_storage_backend.h"
#include "components/sessions/core/command_storage_manager.h"
#include "components/sessions/core/command_storage_read_status.h"
#include "components/sessions/core/session_service_commands.h"
#include "components/sessions/core/session_types.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/restore_type.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/referrer.h"
#include "extensions/browser/disable_reason.h"
#include "extensions/browser/extension_registrar.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/install_approval.h"
#include "extensions/browser/webstore_installer.h"
#include "sql/database.h"
#include "sql/statement.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"

namespace clair {

namespace {

// D10: the private folders ClairUI makes, in the temporary directory.
constexpr char kFolderPrefix[] = "clair-import-";
// D8 step 6: pages written per batch.
constexpr size_t kHistoryBatchSize = 1000;
// The largest icon a pin keeps (ClairPinStore::kMaxIconSize).
constexpr int kMaxPinIconSize = 64;

// --- The plan (design D3) ---

struct PlanTab {
  GURL url;
  std::string title;
  std::string name;
};

struct PlanItem {
  enum class Kind { kTab, kSplit, kFolder };
  Kind kind = Kind::kTab;
  PlanTab tab;
  // A split's panes, leading first, and the leading pane's share.
  std::vector<PlanTab> panes;
  double ratio = 0.5;
  // A folder's name and items.
  std::string name;
  std::vector<PlanItem> children;
};

struct PlanBookmark {
  bool is_folder = false;
  std::string title;
  GURL url;
  std::vector<PlanBookmark> children;
};

struct PlanSpace {
  std::string name;
  std::string icon;
  std::vector<PlanItem> pinned;
  std::vector<PlanItem> today;
};

struct PlanExtension {
  std::string id;
  std::string name;
  bool enabled = true;
  bool pinned = false;
  std::optional<base::DictValue> manifest;
};

struct PlanProfile {
  std::string source_name;
  // Exactly one is set: an existing profile's ID, or a new profile's name.
  std::string existing;
  std::string new_name;
  std::vector<PlanSpace> spaces;
  std::vector<PlanItem> favorites;
  std::optional<std::vector<PlanBookmark>> bookmarks;
  base::FilePath history_db;
  base::FilePath safari_history;
  base::FilePath favicons_db;
  base::FilePath sessions;
  std::string session_space;
  std::vector<PlanExtension> extensions;
};

struct Plan {
  std::string source;
  base::FilePath folder;
  std::vector<PlanProfile> profiles;
};

std::string StringOf(const base::DictValue& dict, std::string_view key) {
  const std::string* value = dict.FindString(key);
  return value ? *value : std::string();
}

PlanTab ParseTab(const base::DictValue& dict) {
  return {GURL(StringOf(dict, "url")), StringOf(dict, "title"),
          StringOf(dict, "name")};
}

std::vector<PlanItem> ParseItems(const base::ListValue* list) {
  std::vector<PlanItem> items;
  if (!list) {
    return items;
  }
  for (const base::Value& value : *list) {
    const base::DictValue* dict = value.GetIfDict();
    if (!dict) {
      continue;
    }
    PlanItem item;
    if (const base::DictValue* tab = dict->FindDict("tab")) {
      item.kind = PlanItem::Kind::kTab;
      item.tab = ParseTab(*tab);
    } else if (const base::DictValue* split = dict->FindDict("split")) {
      item.kind = PlanItem::Kind::kSplit;
      if (const base::ListValue* panes = split->FindList("panes")) {
        for (const base::Value& pane : *panes) {
          if (pane.is_dict()) {
            item.panes.push_back(ParseTab(pane.GetDict()));
          }
        }
      }
      item.ratio = split->FindDouble("ratio").value_or(0.5);
    } else if (const base::DictValue* folder = dict->FindDict("folder")) {
      item.kind = PlanItem::Kind::kFolder;
      item.name = StringOf(*folder, "name");
      item.children = ParseItems(folder->FindList("children"));
    } else {
      continue;
    }
    items.push_back(std::move(item));
  }
  return items;
}

std::vector<PlanBookmark> ParseBookmarks(const base::ListValue& list) {
  std::vector<PlanBookmark> bookmarks;
  for (const base::Value& value : list) {
    const base::DictValue* dict = value.GetIfDict();
    if (!dict) {
      continue;
    }
    PlanBookmark bookmark;
    if (const base::DictValue* url = dict->FindDict("bookmark")) {
      bookmark.title = StringOf(*url, "title");
      bookmark.url = GURL(StringOf(*url, "url"));
    } else if (const base::DictValue* folder = dict->FindDict("folder")) {
      bookmark.is_folder = true;
      bookmark.title = StringOf(*folder, "name");
      if (const base::ListValue* children = folder->FindList("children")) {
        bookmark.children = ParseBookmarks(*children);
      }
    } else {
      continue;
    }
    bookmarks.push_back(std::move(bookmark));
  }
  return bookmarks;
}

base::FilePath PathOf(const base::DictValue* dict, std::string_view key) {
  if (!dict) {
    return base::FilePath();
  }
  const std::string value = StringOf(*dict, key);
  return value.empty() ? base::FilePath() : base::FilePath(value);
}

std::optional<Plan> ParsePlan(const std::string& json) {
  std::optional<base::DictValue> root =
      base::JSONReader::ReadDict(json, base::JSON_PARSE_RFC);
  if (!root || root->FindInt("version").value_or(0) != 1) {
    return std::nullopt;
  }
  Plan plan;
  plan.source = StringOf(*root, "source");
  plan.folder = PathOf(&*root, "folder");
  const base::ListValue* profiles = root->FindList("profiles");
  if (!profiles) {
    return std::nullopt;
  }
  for (const base::Value& value : *profiles) {
    const base::DictValue* dict = value.GetIfDict();
    const base::DictValue* destination =
        dict ? dict->FindDict("destination") : nullptr;
    if (!destination) {
      continue;
    }
    PlanProfile profile;
    profile.source_name = StringOf(*dict, "sourceName");
    profile.existing = StringOf(*destination, "profile");
    profile.new_name = StringOf(*destination, "newProfile");
    if (profile.existing.empty() == profile.new_name.empty()) {
      continue;
    }
    if (const base::ListValue* spaces = dict->FindList("spaces")) {
      for (const base::Value& space_value : *spaces) {
        const base::DictValue* space = space_value.GetIfDict();
        if (!space) {
          continue;
        }
        profile.spaces.push_back({StringOf(*space, "name"),
                                  StringOf(*space, "icon"),
                                  ParseItems(space->FindList("pinned")),
                                  ParseItems(space->FindList("today"))});
      }
    }
    profile.favorites = ParseItems(dict->FindList("favorites"));
    if (const base::ListValue* bookmarks = dict->FindList("bookmarks")) {
      profile.bookmarks = ParseBookmarks(*bookmarks);
    }
    const base::DictValue* history = dict->FindDict("history");
    profile.history_db = PathOf(history, "chromiumDB");
    profile.safari_history = PathOf(history, "safariJSON");
    profile.favicons_db = PathOf(dict->FindDict("favicons"), "chromiumDB");
    if (const base::DictValue* session = dict->FindDict("session")) {
      profile.sessions = PathOf(session, "chromiumSessions");
      profile.session_space = StringOf(*session, "space");
    }
    if (const base::ListValue* extensions = dict->FindList("extensions")) {
      for (const base::Value& extension_value : *extensions) {
        const base::DictValue* extension = extension_value.GetIfDict();
        if (!extension) {
          continue;
        }
        PlanExtension planned;
        planned.id = StringOf(*extension, "id");
        planned.name = StringOf(*extension, "name");
        planned.enabled = extension->FindBool("enabled").value_or(true);
        planned.pinned = extension->FindBool("pinned").value_or(false);
        if (const std::string* manifest = extension->FindString("manifest")) {
          planned.manifest =
              base::JSONReader::ReadDict(*manifest, base::JSON_PARSE_RFC);
        }
        if (!planned.id.empty()) {
          profile.extensions.push_back(std::move(planned));
        }
      }
    }
    plan.profiles.push_back(std::move(profile));
  }
  return plan;
}

// --- The summary (D3) ---

struct Counts {
  int spaces = 0;
  int favorites = 0;
  int pinned_tabs = 0;
  int today_tabs = 0;
  int bookmarks = 0;
  int history = 0;
  int extensions = 0;

  base::DictValue ToDict() const {
    return base::DictValue()
        .Set("spaces", spaces)
        .Set("favorites", favorites)
        .Set("pinnedTabs", pinned_tabs)
        .Set("todayTabs", today_tabs)
        .Set("bookmarks", bookmarks)
        .Set("history", history)
        .Set("extensions", extensions);
  }
};

struct Summary {
  Counts imported;
  Counts already;
  std::vector<std::pair<std::string, std::string>> skipped;

  void Skip(std::string reason, std::string name) {
    skipped.emplace_back(std::move(reason), std::move(name));
  }

  std::string ToJSON() const {
    base::ListValue list;
    for (const auto& [reason, name] : skipped) {
      list.Append(base::DictValue().Set("reason", reason).Set("name", name));
    }
    base::DictValue root = base::DictValue()
                               .Set("imported", imported.ToDict())
                               .Set("alreadyInClair", already.ToDict())
                               .Set("skipped", std::move(list));
    return base::WriteJson(root).value_or("{}");
  }
};

// Whether a tab's URL can be a tab in Clair: a web page, a file or one of
// Clair's own pages. Arc's and Dia's own schemes can't.
bool IsOpenableURL(const GURL& url) {
  return url.is_valid() &&
         (url.SchemeIsHTTPOrHTTPS() || url.SchemeIsFile() ||
          url.SchemeIs("chrome") || url.SchemeIs("about"));
}

// --- Reading the copies, on a blocking sequence (D7) ---

// SQLite's quick_check: a copy torn as it was made fails it (D7).
bool PassesQuickCheck(sql::Database& db) {
  sql::Statement check(db.GetUniqueStatement("PRAGMA quick_check"));
  return check.Step() && check.ColumnString(0) == "ok";
}

struct HistoryRead {
  bool ok = false;
  history::URLRows rows;
};

base::Time FromChromiumTime(int64_t microseconds) {
  return base::Time::FromDeltaSinceWindowsEpoch(
      base::Microseconds(microseconds));
}

// A Chromium `History` copy's visible pages.
HistoryRead ReadChromiumHistory(const base::FilePath& path) {
  HistoryRead result;
  sql::Database db(sql::DatabaseOptions(), /*tag=*/"History");
  if (!db.Open(path) || !PassesQuickCheck(db)) {
    return result;
  }
  sql::Statement pages(db.GetUniqueStatement(
      "SELECT url, title, visit_count, typed_count, last_visit_time "
      "FROM urls WHERE hidden = 0 AND last_visit_time > 0"));
  while (pages.Step()) {
    GURL url(pages.ColumnStringView(0));
    if (!url.is_valid()) {
      continue;
    }
    history::URLRow row(url);
    row.set_title(base::UTF8ToUTF16(pages.ColumnStringView(1)));
    row.set_visit_count(std::max(1, pages.ColumnInt(2)));
    row.set_typed_count(pages.ColumnInt(3));
    row.set_last_visit(FromChromiumTime(pages.ColumnInt64(4)));
    row.set_hidden(false);
    result.rows.push_back(std::move(row));
  }
  result.ok = pages.Succeeded();
  return result;
}

// Safari's exported `History.json` (D6): `history[]` with `url`, `title`,
// `time_usec` (microseconds since 1970) and `visit_count`. A page listed
// more than once keeps its latest visit.
HistoryRead ReadSafariHistory(const base::FilePath& path) {
  HistoryRead result;
  std::string text;
  if (!base::ReadFileToString(path, &text)) {
    return result;
  }
  std::optional<base::DictValue> root =
      base::JSONReader::ReadDict(text, base::JSON_PARSE_RFC);
  const base::ListValue* entries = root ? root->FindList("history") : nullptr;
  if (!entries) {
    return result;
  }
  std::map<GURL, size_t> index_of;
  for (const base::Value& value : *entries) {
    const base::DictValue* entry = value.GetIfDict();
    if (!entry) {
      continue;
    }
    GURL url(StringOf(*entry, "url"));
    std::optional<double> time = entry->FindDouble("time_usec");
    if (!url.is_valid() || !time || *time <= 0) {
      continue;
    }
    const base::Time visit =
        base::Time::UnixEpoch() + base::Microseconds(static_cast<int64_t>(*time));
    const int count =
        static_cast<int>(entry->FindDouble("visit_count").value_or(1));
    if (auto found = index_of.find(url); found != index_of.end()) {
      history::URLRow& row = result.rows[found->second];
      if (visit > row.last_visit()) {
        row.set_last_visit(visit);
      }
      row.set_visit_count(row.visit_count() + std::max(1, count));
      continue;
    }
    history::URLRow row(url);
    row.set_title(base::UTF8ToUTF16(StringOf(*entry, "title")));
    row.set_visit_count(std::max(1, count));
    row.set_last_visit(visit);
    row.set_hidden(false);
    index_of[url] = result.rows.size();
    result.rows.push_back(std::move(row));
  }
  result.ok = true;
  return result;
}

struct FaviconsRead {
  bool ok = false;
  favicon_base::FaviconUsageDataList favicons;
  // Each wanted page's icon, at most 64 pixels wide, for its pin.
  std::map<GURL, std::vector<unsigned char>> page_icons;
};

// D8 step 7: the icons of `pages` in a Chromium `Favicons` copy.
FaviconsRead ReadFavicons(const base::FilePath& path, std::set<GURL> pages) {
  FaviconsRead result;
  sql::Database db(sql::DatabaseOptions(), /*tag=*/"Thumbnail");
  if (!db.Open(path) || !PassesQuickCheck(db)) {
    return result;
  }
  // Chromium's favicon_base::IconType::kFavicon.
  sql::Statement icons(db.GetUniqueStatement(
      "SELECT m.page_url, f.url, b.image_data, b.width "
      "FROM icon_mapping m JOIN favicons f ON m.icon_id = f.id "
      "JOIN favicon_bitmaps b ON b.icon_id = f.id "
      "WHERE f.icon_type = 1 AND b.width > 0"));
  struct Best {
    GURL icon;
    std::vector<unsigned char> png;
    int width = 0;
  };
  // Per icon, the bitmap nearest 32 pixels; per page, the largest up to 64.
  std::map<GURL, Best> by_icon;
  std::map<GURL, std::set<GURL>> pages_of_icon;
  std::map<GURL, Best> by_page;
  while (icons.Step()) {
    GURL page(icons.ColumnStringView(0));
    if (!pages.contains(page)) {
      continue;
    }
    GURL icon(icons.ColumnStringView(1));
    const int width = icons.ColumnInt(3);
    if (!icon.is_valid()) {
      continue;
    }
    pages_of_icon[icon].insert(page);
    Best& best = by_icon[icon];
    if (best.width == 0 || std::abs(width - 32) < std::abs(best.width - 32)) {
      best = {icon, icons.ColumnBlobAsVector(2), width};
    }
    Best& page_best = by_page[page];
    if (width <= kMaxPinIconSize && width > page_best.width) {
      page_best = {icon, icons.ColumnBlobAsVector(2), width};
    }
  }
  for (auto& [icon, best] : by_icon) {
    favicon_base::FaviconUsageData data;
    data.favicon_url = icon;
    data.png_data = std::move(best.png);
    data.urls = pages_of_icon[icon];
    result.favicons.push_back(std::move(data));
  }
  for (auto& [page, best] : by_page) {
    if (!best.png.empty()) {
      result.page_icons[page] = std::move(best.png);
    }
  }
  result.ok = icons.Succeeded();
  return result;
}

struct SessionRead {
  bool ok = false;
  std::vector<PlanItem> pinned;
  std::vector<PlanItem> today;
};

// D13: Chrome's last session, read from the copy of its `Sessions` folder
// with Chromium's own reader, on `backend`'s sequence. Each window, in order,
// gives its pinned tabs and its other tabs; the two tabs of a split become
// one split with its ratio; groups are ignored.
SessionRead ReadChromeSession(
    scoped_refptr<sessions::CommandStorageBackend> backend) {
  SessionRead result;
  sessions::CommandStorageBackend::ReadCommandsResult read =
      backend->ReadLastSessionCommands();
  std::vector<std::unique_ptr<sessions::SessionWindow>> windows;
  SessionID active_window = SessionID::InvalidValue();
  std::string platform_session;
  std::set<SessionID> discarded;
  [[maybe_unused]] sessions::SessionReplayResult replay =
      sessions::RestoreSessionFromCommands(read.commands, &windows,
                                           &active_window, &platform_session,
                                           &discarded);
  for (const std::unique_ptr<sessions::SessionWindow>& window : windows) {
    if (window->type != sessions::SessionWindow::TYPE_NORMAL) {
      continue;
    }
    std::vector<sessions::SessionTab*> tabs;
    for (const std::unique_ptr<sessions::SessionTab>& tab : window->tabs) {
      tabs.push_back(tab.get());
    }
    std::ranges::stable_sort(tabs, {}, &sessions::SessionTab::tab_visual_index);
    std::map<split_tabs::SplitTabId, double> ratios;
    for (const std::unique_ptr<sessions::SessionSplitTab>& split :
         window->split_tabs) {
      ratios[split->id_] = split->split_visual_data_.split_ratio();
    }
    // The first tab of each split, waiting for its partner.
    std::map<split_tabs::SplitTabId, std::pair<PlanTab, bool>> waiting;
    for (sessions::SessionTab* tab : tabs) {
      if (tab->navigations.empty()) {
        continue;
      }
      const sessions::SerializedNavigationEntry& entry =
          tab->navigations[tab->normalized_navigation_index()];
      PlanTab page{entry.virtual_url(), base::UTF16ToUTF8(entry.title()), ""};
      std::vector<PlanItem>& list = tab->pinned ? result.pinned : result.today;
      if (tab->split_id) {
        auto partner = waiting.find(*tab->split_id);
        if (partner == waiting.end()) {
          waiting[*tab->split_id] = {page, tab->pinned};
          continue;
        }
        PlanItem split;
        split.kind = PlanItem::Kind::kSplit;
        split.panes = {partner->second.first, page};
        auto ratio = ratios.find(*tab->split_id);
        split.ratio = ratio != ratios.end() ? ratio->second : 0.5;
        (partner->second.second ? result.pinned : result.today)
            .push_back(std::move(split));
        waiting.erase(partner);
        continue;
      }
      PlanItem item;
      item.tab = page;
      list.push_back(std::move(item));
    }
    // A split whose partner wasn't saved is a tab.
    for (auto& [id, tab] : waiting) {
      PlanItem item;
      item.tab = tab.first;
      (tab.second ? result.pinned : result.today).push_back(std::move(item));
    }
  }
  result.ok = !sessions::IsCommandStorageReadError(read.status);
  return result;
}

// --- History, on the history thread (D8 step 6) ---

// Keeps the pages the destination hasn't visited at or after the source's
// last visit, looked up in its visits, and drops pages history would expire.
class FilterHistoryTask : public history::HistoryDBTask {
 public:
  using Done = base::OnceCallback<void(history::URLRows kept, int already)>;

  FilterHistoryTask(history::URLRows rows, Done done)
      : rows_(std::move(rows)), done_(std::move(done)) {}

  bool RunOnDBThread(history::HistoryBackend* backend,
                     history::HistoryDatabase* db) override {
    for (history::URLRow& row : rows_) {
      if (backend && backend->IsExpiredVisitTime(row.last_visit())) {
        continue;
      }
      history::URLRow existing;
      const history::URLID id = db ? db->GetRowForURL(row.url(), &existing) : 0;
      history::VisitRow visit;
      if (id && db->GetMostRecentVisitForURL(
                    id, &visit, history::VisitQuery404sPolicy::kInclude404s) &&
          visit.visit_time >= row.last_visit()) {
        ++already_;
        continue;
      }
      kept_.push_back(std::move(row));
    }
    return true;
  }

  void DoneRunOnMainThread() override {
    std::move(done_).Run(std::move(kept_), already_);
  }

 private:
  history::URLRows rows_;
  history::URLRows kept_;
  int already_ = 0;
  Done done_;
};

// --- Waiting for the bookmarks to load ---

class BookmarksWaiter : public bookmarks::BaseBookmarkModelObserver {
 public:
  BookmarksWaiter(bookmarks::BookmarkModel* model, base::OnceClosure loaded)
      : loaded_(std::move(loaded)) {
    observation_.Observe(model);
  }

  void BookmarkModelChanged() override {}
  void BookmarkModelLoaded(bool) override {
    observation_.Reset();
    std::move(loaded_).Run();
  }
  void BookmarkModelBeingDeleted() override { observation_.Reset(); }

 private:
  base::OnceClosure loaded_;
  base::ScopedObservation<bookmarks::BookmarkModel,
                          bookmarks::BaseBookmarkModelObserver>
      observation_{this};
};

// --- The import ---

class ClairImport;
ClairImport* g_import = nullptr;

// One import (D8): its profiles one after another, each through its steps,
// then the summary. It deletes itself when done.
class ClairImport {
 public:
  ClairImport(Plan plan,
              base::RepeatingCallback<void(double, const std::string&)> progress,
              base::OnceCallback<void(const std::string&)> done)
      : plan_(std::move(plan)),
        progress_(std::move(progress)),
        done_(std::move(done)),
        blocking_(base::ThreadPool::CreateSequencedTaskRunner(
            {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
             base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN})) {
    // Five steps per profile, and one per extension.
    total_steps_ = static_cast<int>(plan_.profiles.size()) * 5;
    for (const PlanProfile& profile : plan_.profiles) {
      total_steps_ += static_cast<int>(profile.extensions.size());
    }
    total_steps_ = std::max(total_steps_, 1);
  }

  void Start() { NextProfile(); }

 private:
  // --- Progress ---

  void Report(const std::string& phase, double within_step = 0) {
    progress_.Run(std::clamp((steps_done_ + within_step) / total_steps_, 0.0,
                             1.0),
                  phase);
  }

  void StepDone() { ++steps_done_; }

  // --- Profiles (D8 step 1) ---

  void NextProfile() {
    if (index_ >= plan_.profiles.size()) {
      Finish();
      return;
    }
    const PlanProfile& planned = plan_.profiles[index_];
    Report("profiles");
    if (!planned.existing.empty()) {
      LoadProfile(planned.existing);
      return;
    }
    ClairProfiles::Get()->Create(
        FreeProfileName(planned.new_name),
        base::BindOnce(&ClairImport::LoadProfile, weak_factory_.GetWeakPtr()));
  }

  // " 2", " 3" and so on until no profile has the name.
  static std::string FreeProfileName(const std::string& name) {
    std::set<std::string> taken;
    for (const ClairProfiles::Info& info : ClairProfiles::Get()->List()) {
      taken.insert(info.name);
    }
    std::string candidate = name.empty() ? "Imported" : name;
    for (int n = 2; taken.contains(candidate); ++n) {
      candidate = (name.empty() ? "Imported" : name) + " " +
                  base::NumberToString(n);
    }
    return candidate;
  }

  void LoadProfile(const std::string& id) {
    if (id.empty() || !ClairProfiles::Get()->Exists(id)) {
      SkipProfile();
      return;
    }
    ClairProfiles::Get()->Load(
        id, base::BindOnce(&ClairImport::ProfileLoaded,
                           weak_factory_.GetWeakPtr(), id));
  }

  void SkipProfile() {
    summary_.Skip("importFailed", plan_.profiles[index_].source_name);
    steps_done_ += 5 + static_cast<int>(plan_.profiles[index_].extensions.size());
    ++index_;
    NextProfile();
  }

  void ProfileLoaded(const std::string& id, Profile* profile) {
    if (!profile) {
      SkipProfile();
      return;
    }
    profile_ = profile;
    profile_id_ = id;
    StepDone();
    PlanProfile& planned = plan_.profiles[index_];
    if (!planned.sessions.empty()) {
      // Made here, on the UI thread, as the backend asks; it reads on, and is
      // deleted on, the blocking sequence. It looks in `<path>/Sessions`.
      auto backend = base::MakeRefCounted<sessions::CommandStorageBackend>(
          blocking_, planned.sessions.DirName(),
          sessions::CommandStorageManager::SessionType::kSessionRestore,
          /*encryptor=*/nullptr);
      blocking_->PostTaskAndReplyWithResult(
          FROM_HERE, base::BindOnce(&ReadChromeSession, std::move(backend)),
          base::BindOnce(&ClairImport::OnSessionRead,
                         weak_factory_.GetWeakPtr()));
      return;
    }
    WriteSidebar();
  }

  // D13: Chrome's tabs join its profile's Space.
  void OnSessionRead(SessionRead read) {
    PlanProfile& planned = plan_.profiles[index_];
    if (!read.ok) {
      summary_.Skip("unreadableData", planned.source_name + "'s tabs");
    }
    if (!read.pinned.empty() || !read.today.empty() ||
        planned.spaces.empty()) {
      planned.spaces.push_back({planned.session_space.empty()
                                    ? planned.source_name
                                    : planned.session_space,
                                "", std::move(read.pinned),
                                std::move(read.today)});
    }
    WriteSidebar();
  }

  // --- Spaces, pins, folders, splits and favorites (D8 steps 2, 3) ---

  void WriteSidebar() {
    Report("sidebar");
    PlanProfile& planned = plan_.profiles[index_];
    // A new profile left with no Space gets one named after it.
    if (planned.spaces.empty() && !planned.new_name.empty() &&
        ClairSpaceStore::Get()->SpaceCountOf(profile_id_) == 0) {
      planned.spaces.push_back({ProfileName(), "", {}, {}});
    }
    space_ids_.clear();
    for (const PlanSpace& space : planned.spaces) {
      const std::string id = FindOrCreateSpace(space);
      space_ids_.push_back(id);
      if (id.empty()) {
        continue;
      }
      WritePinned(id, space.pinned);
    }
    WriteFavorites(planned.favorites);
    WriteToday();
  }

  std::string ProfileName() const {
    for (const ClairProfiles::Info& info : ClairProfiles::Get()->List()) {
      if (info.id == profile_id_) {
        return info.name;
      }
    }
    return plan_.profiles[index_].new_name;
  }

  // D8 step 2: a Space named like one of the profile's receives the import.
  std::string FindOrCreateSpace(const PlanSpace& space) {
    ClairSpaceStore* store = ClairSpaceStore::Get();
    const std::string name = space.name.empty() ? "Imported" : space.name;
    for (const Space& existing : store->spaces()) {
      if (existing.profile == profile_id_ && existing.name == name) {
        ++summary_.already.spaces;
        return existing.id;
      }
    }
    const std::string id = store->Create(name, space.icon, profile_id_);
    if (!id.empty()) {
      ++summary_.imported.spaces;
    }
    return id;
  }

  // The URLs a container already holds, its splits' included.
  static std::set<GURL> URLsIn(const PinContainer& container) {
    std::set<GURL> urls;
    for (const Pin* pin : ClairPinStore::Get()->PinsIn(container)) {
      urls.insert(pin->url);
    }
    return urls;
  }

  // Writes tabs and splits at the end of `container`, skipping URLs it
  // already holds.
  void WritePins(const PinContainer& container,
                 const std::vector<PlanItem>& items,
                 int Counts::* field) {
    ClairPinStore* store = ClairPinStore::Get();
    std::set<GURL> urls = URLsIn(container);
    for (const PlanItem& item : items) {
      const size_t end = store->ChildrenOf(container).size();
      if (item.kind == PlanItem::Kind::kTab) {
        if (!IsOpenableURL(item.tab.url)) {
          summary_.Skip("invalidURL", item.tab.url.possibly_invalid_spec());
          continue;
        }
        if (urls.contains(item.tab.url)) {
          ++(summary_.already.*field);
          continue;
        }
        const std::string id = store->Create(container, end, item.tab.url,
                                             item.tab.title, item.tab.name);
        if (!id.empty()) {
          urls.insert(item.tab.url);
          pin_urls_.emplace_back(id, item.tab.url);
          ++(summary_.imported.*field);
        }
      } else if (item.kind == PlanItem::Kind::kSplit &&
                 item.panes.size() == 2) {
        const PlanTab& lead = item.panes[0];
        const PlanTab& trail = item.panes[1];
        if (!IsOpenableURL(lead.url) || !IsOpenableURL(trail.url)) {
          summary_.Skip("invalidURL", lead.url.possibly_invalid_spec());
          continue;
        }
        if (urls.contains(lead.url) && urls.contains(trail.url)) {
          summary_.already.*field += 2;
          continue;
        }
        const std::string split = store->CreateSplit(
            container, end, item.ratio, {lead.url, lead.title, lead.name},
            {trail.url, trail.title, trail.name});
        if (split.empty()) {
          continue;
        }
        urls.insert(lead.url);
        urls.insert(trail.url);
        for (const Pin* pin : store->PinsOfSplit(split)) {
          pin_urls_.emplace_back(pin->id, pin->url);
        }
        summary_.imported.*field += 2;
      }
    }
  }

  // D8 step 3: pins, folders and pinned splits at the end of the Space's
  // pinned section, folders closed; a folder named like one of the Space's
  // receives its pins.
  void WritePinned(const std::string& space,
                   const std::vector<PlanItem>& items) {
    ClairPinStore* store = ClairPinStore::Get();
    const PinContainer section = PinContainer::OfSpace(space);
    std::vector<PlanItem> loose;
    auto flush_loose = [&] {
      WritePins(section, loose, &Counts::pinned_tabs);
      loose.clear();
    };
    for (const PlanItem& item : items) {
      if (item.kind != PlanItem::Kind::kFolder) {
        loose.push_back(item);
        continue;
      }
      flush_loose();
      std::string folder;
      for (const Folder* existing : store->FoldersIn(space)) {
        if (existing->name == item.name) {
          folder = existing->id;
          break;
        }
      }
      if (folder.empty()) {
        folder = store->CreateFolder(space, store->ChildrenOf(section).size(),
                                     item.name.empty() ? "Folder" : item.name);
        if (folder.empty()) {
          continue;
        }
        store->SetOpen(folder, false);
      }
      WritePins(PinContainer::OfFolder(space, folder), item.children,
                &Counts::pinned_tabs);
    }
    flush_loose();
  }

  // Favorites after the profile's own, in the source's order.
  void WriteFavorites(const std::vector<PlanItem>& items) {
    std::vector<PlanItem> flat;
    for (const PlanItem& item : items) {
      if (item.kind == PlanItem::Kind::kFolder) {
        flat.insert(flat.end(), item.children.begin(), item.children.end());
      } else {
        flat.push_back(item);
      }
    }
    WritePins(PinContainer::OfProfile(profile_id_), flat, &Counts::favorites);
  }

  // --- Today tabs (D8 step 4) ---

  void WriteToday() {
    bool any = false;
    for (const PlanSpace& space : plan_.profiles[index_].spaces) {
      any = any || !space.today.empty();
    }
    ClairWindowGroup* group =
        any ? ClairWindowGroup::MostRecentlyActive(nullptr) : nullptr;
    if (!group) {
      if (any) {
        summary_.Skip("importFailed", "Today tabs");
      }
      SidebarDone();
      return;
    }
    group->EnsureMember(profile_id_,
                        base::BindOnce(&ClairImport::WriteTodayIn,
                                       weak_factory_.GetWeakPtr()));
  }

  void WriteTodayIn(ClairBrowserWindow* member) {
    const PlanProfile& planned = plan_.profiles[index_];
    if (!member) {
      summary_.Skip("importFailed", "Today tabs");
      SidebarDone();
      return;
    }
    ClairSpaceTabs* lists = ClairSpaceTabs::ForProfile(profile_.get());
    for (size_t i = 0; i < planned.spaces.size() && i < space_ids_.size();
         ++i) {
      const std::string& space = space_ids_[i];
      if (space.empty() || planned.spaces[i].today.empty()) {
        continue;
      }
      std::set<GURL> urls;
      const std::vector<tabs::TabInterface*> existing = lists->TabsIn(space);
      for (tabs::TabInterface* tab : existing) {
        urls.insert(URLOf(tab));
      }
      int rank = static_cast<int>(existing.size());
      for (const PlanItem& item : planned.spaces[i].today) {
        if (item.kind == PlanItem::Kind::kTab) {
          if (!IsOpenableURL(item.tab.url)) {
            summary_.Skip("invalidURL", item.tab.url.possibly_invalid_spec());
            continue;
          }
          if (urls.contains(item.tab.url)) {
            ++summary_.already.today_tabs;
            continue;
          }
          if (AddUnloadedTab(member, item.tab, space, rank++)) {
            urls.insert(item.tab.url);
            ++summary_.imported.today_tabs;
          }
        } else if (item.kind == PlanItem::Kind::kSplit &&
                   item.panes.size() == 2) {
          const PlanTab& lead = item.panes[0];
          const PlanTab& trail = item.panes[1];
          if (!IsOpenableURL(lead.url) || !IsOpenableURL(trail.url)) {
            summary_.Skip("invalidURL", lead.url.possibly_invalid_spec());
            continue;
          }
          if (urls.contains(lead.url) && urls.contains(trail.url)) {
            summary_.already.today_tabs += 2;
            continue;
          }
          tabs::TabInterface* leading =
              AddUnloadedTab(member, lead, space, rank++);
          tabs::TabInterface* trailing =
              AddUnloadedTab(member, trail, space, rank++);
          if (leading && trailing && member->splits()) {
            member->splits()->Make(leading, trailing, /*other_leading=*/false,
                                   item.ratio, /*focus=*/nullptr);
          }
          urls.insert(lead.url);
          urls.insert(trail.url);
          summary_.imported.today_tabs += (leading ? 1 : 0) + (trailing ? 1 : 0);
        }
      }
    }
    SidebarDone();
  }

  static GURL URLOf(tabs::TabInterface* tab) {
    content::WebContents* contents = tab ? tab->GetContents() : nullptr;
    if (!contents) {
      return GURL();
    }
    const GURL committed = contents->GetLastCommittedURL();
    return committed.is_empty() ? contents->GetVisibleURL() : committed;
  }

  // A tab of `space` at `rank` in its list, in `member`'s strip, its page not
  // loaded until it's selected, as session restore's background tabs.
  tabs::TabInterface* AddUnloadedTab(ClairBrowserWindow* member,
                                     const PlanTab& tab,
                                     const std::string& space,
                                     int rank) {
    Profile* profile = member->browser()->GetProfile();
    content::WebContents::CreateParams params(profile);
    params.initially_hidden = true;
    params.desired_renderer_state =
        content::WebContents::CreateParams::kNoRendererProcess;
    std::unique_ptr<content::WebContents> contents =
        content::WebContents::Create(params);
    // Its Space, place and name before it joins the strip, as a restored
    // tab's (add-spaces D6).
    ClairSpaceTabs::SetRestoredTag(contents.get(), space, rank);
    if (!tab.name.empty()) {
      ClairSpaceTabs::SetRestoredPinTag(contents.get(), std::string(),
                                        tab.name);
    }
    std::unique_ptr<content::NavigationEntry> entry =
        content::NavigationController::CreateNavigationEntry(
            tab.url, content::Referrer(), /*initiator_origin=*/std::nullopt,
            /*initiator_base_url=*/std::nullopt,
            ui::PAGE_TRANSITION_AUTO_BOOKMARK,
            /*is_renderer_initiated=*/false, std::string(), profile,
            /*blob_url_loader_factory=*/nullptr);
    entry->SetTitle(base::UTF8ToUTF16(tab.title));
    std::vector<std::unique_ptr<content::NavigationEntry>> entries;
    entries.push_back(std::move(entry));
    contents->GetController().Restore(0, content::RestoreType::kRestored,
                                      &entries);
    content::WebContents* raw = contents.get();
    TabStripModel* strip = member->browser()->tab_strip_model();
    strip->InsertWebContentsAt(strip->count(), std::move(contents),
                               AddTabTypes::ADD_NONE);
    return tabs::TabInterface::MaybeGetFromContents(raw);
  }

  void SidebarDone() {
    StepDone();
    WriteBookmarks();
  }

  // --- Bookmarks (D8 step 5) ---

  void WriteBookmarks() {
    const PlanProfile& planned = plan_.profiles[index_];
    bookmarks::BookmarkModel* model =
        BookmarkModelFactory::GetForBrowserContext(profile_.get());
    if (!planned.bookmarks || planned.bookmarks->empty() || !model) {
      BookmarksDone();
      return;
    }
    Report("bookmarks");
    if (!model->loaded()) {
      bookmarks_waiter_ = std::make_unique<BookmarksWaiter>(
          model, base::BindOnce(&ClairImport::WriteBookmarks,
                                weak_factory_.GetWeakPtr()));
      return;
    }
    bookmarks_waiter_.reset();
    AddBookmarks(model, model->other_node(), *planned.bookmarks);
    BookmarksDone();
  }

  // Appends `items` to `parent` as they are: a folder named like one in the
  // same place merges into it, and a URL already there is skipped. Never the
  // Bookmarks Bar, so its Heads Up dialog doesn't show.
  void AddBookmarks(bookmarks::BookmarkModel* model,
                    const bookmarks::BookmarkNode* parent,
                    const std::vector<PlanBookmark>& items) {
    for (const PlanBookmark& item : items) {
      if (item.is_folder) {
        const std::u16string title = base::UTF8ToUTF16(item.title);
        const bookmarks::BookmarkNode* folder = nullptr;
        for (const auto& child : parent->children()) {
          if (child->is_folder() && child->GetTitle() == title) {
            folder = child.get();
            break;
          }
        }
        if (!folder) {
          folder = model->AddFolder(parent, parent->children().size(), title);
        }
        if (folder) {
          AddBookmarks(model, folder, item.children);
        }
        continue;
      }
      if (!item.url.is_valid()) {
        summary_.Skip("invalidURL", item.url.possibly_invalid_spec());
        continue;
      }
      const bool present = std::ranges::any_of(
          parent->children(), [&](const auto& child) {
            return child->is_url() && child->url() == item.url;
          });
      if (present) {
        ++summary_.already.bookmarks;
        continue;
      }
      if (model->AddURL(parent, parent->children().size(),
                        base::UTF8ToUTF16(item.title), item.url)) {
        ++summary_.imported.bookmarks;
        icon_pages_.insert(item.url);
      }
    }
  }

  void BookmarksDone() {
    StepDone();
    ReadHistory();
  }

  // --- History (D8 step 6) ---

  void ReadHistory() {
    const PlanProfile& planned = plan_.profiles[index_];
    if (planned.history_db.empty() && planned.safari_history.empty()) {
      HistoryDone();
      return;
    }
    Report("history");
    const bool safari = !planned.safari_history.empty();
    blocking_->PostTaskAndReplyWithResult(
        FROM_HERE,
        safari ? base::BindOnce(&ReadSafariHistory, planned.safari_history)
               : base::BindOnce(&ReadChromiumHistory, planned.history_db),
        base::BindOnce(&ClairImport::OnHistoryRead, weak_factory_.GetWeakPtr(),
                       safari));
  }

  void OnHistoryRead(bool safari, HistoryRead read) {
    if (!read.ok) {
      summary_.Skip("unreadableData", "History");
      HistoryDone();
      return;
    }
    history_rows_ = std::move(read.rows);
    history_next_ = 0;
    // add-browser-import design, Open Questions: History and the command bar
    // treat every source alike but the actor's, so Safari's visits say so and
    // the others take Chromium's generic import source.
    visit_source_ = safari ? history::SOURCE_SAFARI_IMPORTED
                           : history::SOURCE_OS_MIGRATION_IMPORTED;
    NextHistoryBatch();
  }

  void NextHistoryBatch() {
    history::HistoryService* service = HistoryServiceFactory::GetForProfile(
        profile_.get(), ServiceAccessType::EXPLICIT_ACCESS);
    if (!service || history_next_ >= history_rows_.size()) {
      history_rows_.clear();
      HistoryDone();
      return;
    }
    const size_t end =
        std::min(history_rows_.size(), history_next_ + kHistoryBatchSize);
    history::URLRows batch(
        std::make_move_iterator(history_rows_.begin() + history_next_),
        std::make_move_iterator(history_rows_.begin() + end));
    Report("history", static_cast<double>(history_next_) /
                          static_cast<double>(history_rows_.size()));
    history_next_ = end;
    // The filter runs on the history thread after the previous batch's
    // writes, so it sees them.
    service->ScheduleDBTask(
        FROM_HERE,
        std::make_unique<FilterHistoryTask>(
            std::move(batch), base::BindOnce(&ClairImport::HistoryFiltered,
                                             weak_factory_.GetWeakPtr())),
        &tracker_);
  }

  void HistoryFiltered(history::URLRows kept, int already) {
    summary_.already.history += already;
    if (!kept.empty()) {
      summary_.imported.history += static_cast<int>(kept.size());
      base::MakeRefCounted<ProfileWriter>(profile_.get())->AddHistoryPage(
          kept, visit_source_);
    }
    NextHistoryBatch();
  }

  void HistoryDone() {
    StepDone();
    ReadFaviconsStep();
  }

  // --- Favicons (D8 step 7) ---

  void ReadFaviconsStep() {
    const PlanProfile& planned = plan_.profiles[index_];
    for (const auto& [pin, url] : pin_urls_) {
      icon_pages_.insert(url);
    }
    for (const PlanSpace& space : planned.spaces) {
      for (const PlanItem& item : space.today) {
        icon_pages_.insert(item.tab.url);
        for (const PlanTab& pane : item.panes) {
          icon_pages_.insert(pane.url);
        }
      }
    }
    if (planned.favicons_db.empty() || icon_pages_.empty()) {
      FaviconsDone();
      return;
    }
    Report("favicons");
    blocking_->PostTaskAndReplyWithResult(
        FROM_HERE,
        base::BindOnce(&ReadFavicons, planned.favicons_db, icon_pages_),
        base::BindOnce(&ClairImport::OnFaviconsRead,
                       weak_factory_.GetWeakPtr()));
  }

  void OnFaviconsRead(FaviconsRead read) {
    if (!read.ok) {
      summary_.Skip("unreadableData", "Icons");
    }
    if (!read.favicons.empty()) {
      base::MakeRefCounted<ProfileWriter>(profile_.get())->AddFavicons(
          read.favicons);
    }
    // Each pin's icon is the source's for its URL.
    ClairPinStore* store = ClairPinStore::Get();
    for (const auto& [pin, url] : pin_urls_) {
      auto png = read.page_icons.find(url);
      if (png == read.page_icons.end() || !store->Find(pin)) {
        continue;
      }
      NSData* data = [NSData dataWithBytes:png->second.data()
                                    length:png->second.size()];
      if (NSImage* image = [[NSImage alloc] initWithData:data]) {
        store->SetIcon(pin, image);
      }
    }
    FaviconsDone();
  }

  void FaviconsDone() {
    StepDone();
    pin_urls_.clear();
    icon_pages_.clear();
    extension_next_ = 0;
    NextExtension();
  }

  // --- Extensions (D8 step 8) ---

  void NextExtension() {
    const PlanProfile& planned = plan_.profiles[index_];
    if (extension_next_ >= planned.extensions.size()) {
      installer_contents_.reset();
      ++index_;
      NextProfile();
      return;
    }
    const PlanExtension& extension = planned.extensions[extension_next_];
    Report("extensions");
    const std::string name = extension.name.empty() ? extension.id
                                                    : extension.name;
    if (extensions::ExtensionRegistry::Get(profile_.get())->GetInstalledExtension(
            extension.id)) {
      summary_.Skip("alreadyInstalled", name);
      ExtensionDone();
      return;
    }
    if (!extension.manifest) {
      // Without the installed manifest there's nothing to approve the
      // store's version against, and Clair doesn't ask.
      summary_.Skip("storeFailed", name);
      ExtensionDone();
      return;
    }
    if (!installer_contents_) {
      // The installer downloads through a WebContents of the profile.
      installer_contents_ = content::WebContents::Create(
          content::WebContents::CreateParams(profile_.get()));
    }
    // No prompt while the store's version asks for no more than the one the
    // user installed in the source.
    std::unique_ptr<extensions::InstallApproval> approval =
        extensions::InstallApproval::CreateWithNoInstallPrompt(
            profile_.get(), extension.id, extension.manifest->Clone(),
            /*strict_manifest_check=*/false);
    approval->skip_post_install_ui = true;
    auto installer = base::MakeRefCounted<extensions::WebstoreInstaller>(
        profile_.get(),
        base::BindOnce(&ClairImport::ExtensionInstalled,
                       weak_factory_.GetWeakPtr()),
        base::BindOnce(&ClairImport::ExtensionFailed,
                       weak_factory_.GetWeakPtr()),
        installer_contents_.get(), extension.id, std::move(approval),
        extensions::WebstoreInstaller::INSTALL_SOURCE_OTHER);
    installer->Start();
  }

  void ExtensionInstalled(const std::string& id) {
    const PlanExtension& extension =
        plan_.profiles[index_].extensions[extension_next_];
    ++summary_.imported.extensions;
    if (!extension.enabled) {
      extensions::ExtensionRegistrar::Get(profile_.get())->DisableExtension(
          id, {extensions::disable_reason::DISABLE_USER_ACTION});
    }
    ToolbarActionsModel* model = ToolbarActionsModel::Get(profile_.get());
    if (extension.pinned && model && model->HasAction(id) &&
        !model->IsActionPinned(id)) {
      model->SetActionVisibility(id, true);
    }
    ExtensionDone();
  }

  void ExtensionFailed(const std::string& id,
                       const std::string& error,
                       extensions::WebstoreInstaller::FailureReason reason) {
    const PlanExtension& extension =
        plan_.profiles[index_].extensions[extension_next_];
    LOG(WARNING) << "Clair import: " << id << " didn't install: " << error;
    summary_.Skip("storeFailed",
                  extension.name.empty() ? extension.id : extension.name);
    ExtensionDone();
  }

  void ExtensionDone() {
    StepDone();
    ++extension_next_;
    // A new task, so an installer finishes unwinding first.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&ClairImport::NextExtension,
                                  weak_factory_.GetWeakPtr()));
  }

  // --- The end ---

  void Finish() {
    progress_.Run(1, "extensions");
    RemoveFolder(plan_.folder);
    std::string summary = summary_.ToJSON();
    auto done = std::move(done_);
    g_import = nullptr;
    delete this;
    std::move(done).Run(summary);
  }

 public:
  // D10: removes `folder` once it's checked to be an import's private folder
  // in the temporary directory, never anything else the plan names.
  static void RemoveFolder(const base::FilePath& folder) {
    if (folder.empty()) {
      return;
    }
    base::ThreadPool::PostTask(
        FROM_HERE,
        {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
         base::TaskShutdownBehavior::BLOCK_SHUTDOWN},
        base::BindOnce(
            [](base::FilePath folder) {
              base::FilePath temp;
              if (!base::GetTempDir(&temp)) {
                return;
              }
              const base::FilePath real = base::MakeAbsoluteFilePath(folder);
              const base::FilePath real_temp = base::MakeAbsoluteFilePath(temp);
              if (real.empty() || real.DirName() != real_temp ||
                  !base::StartsWith(real.BaseName().value(), kFolderPrefix)) {
                LOG(ERROR) << "Clair import: not removing " << folder;
                return;
              }
              base::DeletePathRecursively(real);
            },
            folder));
  }

 private:
  Plan plan_;
  base::RepeatingCallback<void(double, const std::string&)> progress_;
  base::OnceCallback<void(const std::string&)> done_;
  scoped_refptr<base::SequencedTaskRunner> blocking_;
  Summary summary_;
  int total_steps_ = 1;
  int steps_done_ = 0;

  // The profile being imported.
  size_t index_ = 0;
  raw_ptr<Profile> profile_ = nullptr;
  std::string profile_id_;
  // Each planned Space's ID, or empty when it couldn't be made.
  std::vector<std::string> space_ids_;
  // The pins written, with their URLs, for their icons.
  std::vector<std::pair<std::string, GURL>> pin_urls_;
  // The pages whose icons come over.
  std::set<GURL> icon_pages_;
  std::unique_ptr<BookmarksWaiter> bookmarks_waiter_;
  history::URLRows history_rows_;
  size_t history_next_ = 0;
  history::VisitSource visit_source_ = history::SOURCE_OS_MIGRATION_IMPORTED;
  base::CancelableTaskTracker tracker_;
  size_t extension_next_ = 0;
  std::unique_ptr<content::WebContents> installer_contents_;
  base::WeakPtrFactory<ClairImport> weak_factory_{this};
};

}  // namespace

void ApplyImportPlan(
    const std::string& plan_json,
    base::RepeatingCallback<void(double, const std::string&)> progress,
    base::OnceCallback<void(const std::string&)> done) {
  std::optional<Plan> plan = ParsePlan(plan_json);
  if (!plan || g_import) {
    LOG(ERROR) << "Clair import: "
               << (plan ? "another import is running" : "the plan didn't parse");
    if (plan && !g_import) {
      ClairImport::RemoveFolder(plan->folder);
    }
    Summary summary;
    summary.Skip("importFailed", plan ? plan->source : std::string("Import"));
    std::move(done).Run(summary.ToJSON());
    return;
  }
  g_import = new ClairImport(std::move(*plan), std::move(progress),
                             std::move(done));
  g_import->Start();
}

void RemoveLeftoverImportFolders() {
  base::ThreadPool::PostTask(
      FROM_HERE,
      {base::MayBlock(), base::TaskPriority::BEST_EFFORT,
       base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN},
      base::BindOnce([] {
        base::FilePath temp;
        if (!base::GetTempDir(&temp)) {
          return;
        }
        base::FileEnumerator folders(
            temp, /*recursive=*/false, base::FileEnumerator::DIRECTORIES,
            std::string(kFolderPrefix) + "*");
        for (base::FilePath folder = folders.Next(); !folder.empty();
             folder = folders.Next()) {
          base::DeletePathRecursively(folder);
        }
      }));
}

}  // namespace clair
