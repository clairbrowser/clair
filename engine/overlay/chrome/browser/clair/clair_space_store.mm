// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/clair_space_store.h"

#include <algorithm>
#include <set>
#include <tuple>
#include <utility>

#include "base/check.h"
#include "base/no_destructor.h"
#include "base/strings/string_util.h"
#include "base/uuid.h"
#include "base/values.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/clair/clair_order_key.h"
#include "chrome/browser/clair/clair_profiles.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#include "components/prefs/pref_registry_simple.h"
#include "components/prefs/pref_service.h"

namespace clair {

namespace {

constexpr int kVersion = 1;
constexpr char kVersionKey[] = "version";
constexpr char kSpacesKey[] = "spaces";
constexpr char kOrderKey[] = "order";
constexpr char kNameKey[] = "name";
constexpr char kIconKey[] = "icon";
constexpr char kProfileKey[] = "profile";

// The directory of the profile saved as `stored` (add-tab-folders D13), or
// the one a Space falls back to (add-profiles design D2).
std::string ExistingProfile(const std::string* stored) {
  ClairProfiles* profiles = ClairProfiles::Get();
  std::string directory =
      stored ? profiles->DirectoryOf(*stored) : std::string();
  return directory.empty() ? profiles->FallbackID() : directory;
}

// `text` without surrounding whitespace, cut to `max` bytes on a character
// boundary.
std::string Clean(std::string_view text, size_t max) {
  std::string trimmed(base::TrimWhitespaceASCII(text, base::TRIM_ALL));
  std::string cut;
  base::TruncateUTF8ToByteSize(trimmed, max, &cut);
  return cut;
}

// An icon is kept only whole: a cut emoji would be a different one.
std::string CleanIcon(std::string_view icon) {
  std::string trimmed(base::TrimWhitespaceASCII(icon, base::TRIM_ALL));
  return trimmed.size() <= ClairSpaceStore::kMaxIconLength &&
                 base::IsStringUTF8(trimmed)
             ? trimmed
             : std::string();
}

}  // namespace

// static
void ClairSpaceStore::RegisterPrefs(PrefRegistrySimple* registry) {
  registry->RegisterDictionaryPref(kSpacesPref);
  registry->RegisterStringPref(kLastSpacePref, std::string());
  registry->RegisterDictionaryPref(kWindowsPref);
}

// static
ClairSpaceStore* ClairSpaceStore::Get() {
  static base::NoDestructor<ClairSpaceStore> store(
      g_browser_process->local_state());
  return store.get();
}

ClairSpaceStore::ClairSpaceStore(PrefService* local_state)
    : prefs_(local_state) {
  CHECK(prefs_);
  Load();
}

void ClairSpaceStore::Load() {
  spaces_.clear();
  const base::DictValue& stored = prefs_->GetDict(kSpacesPref);
  const std::optional<int> version = stored.FindInt(kVersionKey);
  const base::DictValue* entries = stored.FindDict(kSpacesKey);
  if (version == kVersion && entries) {
    for (const auto [id, value] : *entries) {
      const base::DictValue* entry = value.GetIfDict();
      const std::string* name = entry ? entry->FindString(kNameKey) : nullptr;
      const std::string* order = entry ? entry->FindString(kOrderKey) : nullptr;
      // add-tab-folders D12: a Space without a sort key, as saved before it,
      // is left out.
      if (!base::Uuid::ParseLowercase(id).is_valid() || !name || !order ||
          !IsValidOrderKey(*order)) {
        continue;
      }
      Space space{id, Clean(*name, kMaxNameLength), std::string(),
                  ExistingProfile(entry->FindString(kProfileKey)), *order};
      if (space.name.empty()) {
        continue;
      }
      if (const std::string* icon = entry->FindString(kIconKey)) {
        space.icon = CleanIcon(*icon);
      }
      spaces_.push_back(std::move(space));
    }
    Sort();
  }
  // There are no existing users to migrate (design, Context): anything else
  // starts over with one Space.
  if (spaces_.empty()) {
    spaces_.push_back({base::Uuid::GenerateRandomV4().AsLowercaseString(),
                       kFirstSpaceName, std::string(),
                       ClairProfiles::DefaultID(),
                       OrderKeyBetween(std::string(), std::string())});
    Save();
  }
}

void ClairSpaceStore::Save() {
  ClairProfiles* profiles = ClairProfiles::Get();
  base::DictValue entries;
  for (const Space& space : spaces_) {
    base::DictValue entry;
    entry.Set(kNameKey, space.name);
    if (!space.icon.empty()) {
      entry.Set(kIconKey, space.icon);
    }
    // add-tab-folders D13: the profile's ID, not its directory.
    entry.Set(kProfileKey, profiles->StoredIDOf(space.profile));
    entry.Set(kOrderKey, space.order);
    entries.Set(space.id, std::move(entry));
  }
  base::DictValue stored;
  stored.Set(kVersionKey, kVersion);
  stored.Set(kSpacesKey, std::move(entries));
  prefs_->SetDict(kSpacesPref, std::move(stored));
}

void ClairSpaceStore::Sort() {
  std::ranges::sort(spaces_, [](const Space& a, const Space& b) {
    return std::tie(a.order, a.id) < std::tie(b.order, b.id);
  });
}

std::string ClairSpaceStore::KeyAt(size_t index, std::string_view moving) {
  for (int attempt = 0; attempt < 2; ++attempt) {
    std::vector<const Space*> others;
    for (const Space& space : spaces_) {
      if (space.id != moving) {
        others.push_back(&space);
      }
    }
    const size_t at = std::min(index, others.size());
    const std::string before = at > 0 ? others[at - 1]->order : std::string();
    const std::string after =
        at < others.size() ? others[at]->order : std::string();
    std::string key = OrderKeyBetween(before, after);
    if (!key.empty()) {
      return key;
    }
    // Two Spaces share a key, as when two Macs placed one each in the same
    // gap: every Space gets a new key, in the order they're in.
    std::string previous;
    for (Space& space : spaces_) {
      space.order = OrderKeyBetween(previous, std::string());
      previous = space.order;
    }
  }
  return OrderKeyBetween(spaces_.back().order, std::string());
}

void ClairSpaceStore::Changed() {
  Save();
  for (Observer& observer : observers_) {
    observer.OnSpacesChanged();
  }
}

const Space* ClairSpaceStore::Find(std::string_view id) const {
  auto it = std::ranges::find(spaces_, id, &Space::id);
  return it == spaces_.end() ? nullptr : &*it;
}

std::optional<size_t> ClairSpaceStore::IndexOf(std::string_view id) const {
  auto it = std::ranges::find(spaces_, id, &Space::id);
  if (it == spaces_.end()) {
    return std::nullopt;
  }
  return static_cast<size_t>(it - spaces_.begin());
}

std::string ClairSpaceStore::Create(std::string_view name,
                                    std::string_view icon,
                                    std::string_view profile) {
  Space space{base::Uuid::GenerateRandomV4().AsLowercaseString(),
              Clean(name, kMaxNameLength), CleanIcon(icon),
              std::string(profile), std::string()};
  if (space.name.empty() || !ClairProfiles::Get()->Exists(profile)) {
    return std::string();
  }
  // D12: after the last.
  space.order = KeyAt(spaces_.size(), space.id);
  std::string id = space.id;
  spaces_.push_back(std::move(space));
  Changed();
  return id;
}

void ClairSpaceStore::Rename(std::string_view id, std::string_view name) {
  std::string cleaned = Clean(name, kMaxNameLength);
  auto it = std::ranges::find(spaces_, id, &Space::id);
  if (it == spaces_.end() || cleaned.empty() || it->name == cleaned) {
    return;
  }
  it->name = std::move(cleaned);
  Changed();
}

void ClairSpaceStore::SetIcon(std::string_view id, std::string_view icon) {
  std::string cleaned = CleanIcon(icon);
  auto it = std::ranges::find(spaces_, id, &Space::id);
  if (it == spaces_.end() || it->icon == cleaned) {
    return;
  }
  it->icon = std::move(cleaned);
  Changed();
}

void ClairSpaceStore::Move(std::string_view id, int index) {
  std::optional<size_t> from = IndexOf(id);
  if (!from) {
    return;
  }
  const size_t to = static_cast<size_t>(
      std::clamp(index, 0, static_cast<int>(spaces_.size()) - 1));
  if (to == *from) {
    return;
  }
  // add-tab-folders D12: only the Space that moved gets a new key.
  const std::string key = KeyAt(to, id);
  auto it = std::ranges::find(spaces_, id, &Space::id);
  it->order = key;
  Sort();
  Changed();
}

bool ClairSpaceStore::Remove(std::string_view id) {
  std::optional<size_t> index = IndexOf(id);
  if (!index || spaces_.size() <= 1) {
    return false;
  }
  spaces_.erase(spaces_.begin() + *index);
  Changed();
  return true;
}

bool ClairSpaceStore::SetProfile(std::string_view id, std::string_view profile) {
  auto it = std::ranges::find(spaces_, id, &Space::id);
  if (it == spaces_.end() || it->profile == profile ||
      !ClairProfiles::Get()->Exists(profile)) {
    return false;
  }
  it->profile = std::string(profile);
  Changed();
  return true;
}

void ClairSpaceStore::ProfileRemoved(std::string_view profile) {
  // The default profile itself may be the one removed, through Chromium's
  // own pages.
  const std::string fallback = ClairProfiles::Get()->FallbackID();
  bool changed = false;
  for (Space& space : spaces_) {
    if (space.profile == profile && space.profile != fallback) {
      space.profile = fallback;
      changed = true;
    }
  }
  if (changed) {
    Changed();
  }
}

int ClairSpaceStore::SpaceCountOf(std::string_view profile) const {
  return static_cast<int>(std::ranges::count(spaces_, profile, &Space::profile));
}

std::string ClairSpaceStore::ProfileOf(std::string_view id) const {
  const Space* space = Find(id);
  return space ? space->profile : std::string();
}

std::string ClairSpaceStore::WindowSpace(std::string_view group) const {
  const std::string* space =
      prefs_->GetDict(kWindowsPref).FindString(std::string(group));
  return space && Contains(*space) ? *space : std::string();
}

void ClairSpaceStore::SetWindowSpace(std::string_view group,
                                     std::string_view space) {
  if (group.empty() || !Contains(space)) {
    return;
  }
  const std::string* stored =
      prefs_->GetDict(kWindowsPref).FindString(std::string(group));
  if (stored && *stored == space) {
    return;
  }
  base::DictValue windows = prefs_->GetDict(kWindowsPref).Clone();
  windows.Set(std::string(group), std::string(space));
  prefs_->SetDict(kWindowsPref, std::move(windows));
}

void ClairSpaceStore::KeepWindows(const std::set<std::string>& groups) {
  base::DictValue windows;
  for (const auto [group, space] : prefs_->GetDict(kWindowsPref)) {
    if (groups.contains(group) && space.is_string()) {
      windows.Set(group, space.GetString());
    }
  }
  prefs_->SetDict(kWindowsPref, std::move(windows));
}

std::string ClairSpaceStore::last_space() const {
  const std::string& last = prefs_->GetString(kLastSpacePref);
  return Contains(last) ? last : first();
}

void ClairSpaceStore::SetLastSpace(std::string_view id) {
  // Not while quitting: each window that closes makes another key, and the
  // next launch opens the Space shown before the quit (add-profiles D6).
  if (browser_shutdown::IsTryingToQuit() ||
      browser_shutdown::HasShutdownStarted()) {
    return;
  }
  if (Contains(id) && prefs_->GetString(kLastSpacePref) != id) {
    prefs_->SetString(kLastSpacePref, std::string(id));
  }
}

void ClairSpaceStore::AddObserver(Observer* observer) {
  observers_.AddObserver(observer);
}

void ClairSpaceStore::RemoveObserver(Observer* observer) {
  observers_.RemoveObserver(observer);
}

}  // namespace clair
