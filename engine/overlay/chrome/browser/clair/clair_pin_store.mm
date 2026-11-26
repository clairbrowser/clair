// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#import "chrome/browser/clair/clair_pin_store.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <set>
#include <utility>

#include "base/check.h"
#include "base/files/file_enumerator.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/path_service.h"
#include "base/strings/string_util.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/thread_pool.h"
#include "base/uuid.h"
#include "base/values.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/clair/clair_order_key.h"
#include "chrome/browser/clair/clair_profiles.h"
#include "chrome/browser/clair/clair_space_store.h"
#include "chrome/common/chrome_paths.h"
#include "components/prefs/pref_registry_simple.h"
#include "components/prefs/pref_service.h"

namespace clair {

namespace {

constexpr int kVersion = 1;
constexpr char kVersionKey[] = "version";
constexpr char kItemsKey[] = "items";
constexpr char kKindKey[] = "kind";
constexpr char kPinKind[] = "pin";
constexpr char kFolderKind[] = "folder";
// add-split-view D10.
constexpr char kSplitKind[] = "split";
constexpr char kSplitKey[] = "split";
constexpr char kIndexKey[] = "index";
constexpr char kRatioKey[] = "ratio";
constexpr char kSpaceKey[] = "space";
constexpr char kFolderKey[] = "folder";
constexpr char kProfileKey[] = "profile";
constexpr char kOrderKey[] = "order";
constexpr char kURLKey[] = "url";
constexpr char kTitleKey[] = "title";
constexpr char kNameKey[] = "name";
constexpr char kIconDirName[] = "Clair Pin Icons";
constexpr char kIconExtension[] = ".png";

// `text` without surrounding whitespace, cut to `max` bytes on a character
// boundary.
std::string Clean(std::string_view text, size_t max) {
  std::string trimmed(base::TrimWhitespaceASCII(text, base::TRIM_ALL));
  std::string cut;
  base::TruncateUTF8ToByteSize(trimmed, max, &cut);
  return cut;
}

bool IsPinID(std::string_view id) {
  return base::Uuid::ParseLowercase(id).is_valid();
}

// add-split-view D10: a split's ratio, as the divider allows it.
double ClampRatio(double ratio) {
  return std::isfinite(ratio) ? std::clamp(ratio, 0.05, 0.95) : 0.5;
}

// D6: the schemes a pinned URL may have.
bool IsPinnableURL(const GURL& url) {
  return url.is_valid() &&
         (url.SchemeIsHTTPOrHTTPS() || url.SchemeIsFile() ||
          url.SchemeIs("chrome"));
}

// At most kMaxIconSize pixels square, as PNG data; nil when it can't be
// drawn.
NSData* PNGOf(NSImage* image) {
  if (!image) {
    return nil;
  }
  // The largest representation, whose pixels are what Retina shows.
  NSInteger pixels = 0;
  for (NSImageRep* rep in image.representations) {
    pixels = std::max({pixels, rep.pixelsWide, rep.pixelsHigh});
  }
  if (pixels <= 0) {
    pixels = static_cast<NSInteger>(std::max(image.size.width, image.size.height));
  }
  pixels = std::clamp<NSInteger>(pixels, 1, ClairPinStore::kMaxIconSize);
  NSBitmapImageRep* bitmap = [[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes:nullptr
                    pixelsWide:pixels
                    pixelsHigh:pixels
                 bitsPerSample:8
               samplesPerPixel:4
                      hasAlpha:YES
                      isPlanar:NO
                colorSpaceName:NSDeviceRGBColorSpace
                   bytesPerRow:0
                  bitsPerPixel:0];
  if (!bitmap) {
    return nil;
  }
  NSGraphicsContext* context =
      [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
  if (!context) {
    return nil;
  }
  [NSGraphicsContext saveGraphicsState];
  NSGraphicsContext.currentContext = context;
  context.imageInterpolation = NSImageInterpolationHigh;
  [image drawInRect:NSMakeRect(0, 0, pixels, pixels)
           fromRect:NSZeroRect
          operation:NSCompositingOperationCopy
           fraction:1];
  [NSGraphicsContext restoreGraphicsState];
  return [bitmap representationUsingType:NSBitmapImageFileTypePNG
                              properties:@{}];
}

// An icon file as the sidebar draws it: 16 points square.
NSImage* IconFromPNG(NSData* data) {
  NSImage* image = data.length ? [[NSImage alloc] initWithData:data] : nil;
  if (image) {
    image.size = NSMakeSize(16, 16);
  }
  return image;
}

// On the file sequence: reads every pin's icon, and deletes the files of pins
// that are gone, as after a crash mid-delete (Risks).
std::map<std::string, std::vector<uint8_t>> LoadIcons(
    base::FilePath dir,
    std::set<std::string> ids) {
  std::map<std::string, std::vector<uint8_t>> icons;
  base::FileEnumerator files(dir, /*recursive=*/false,
                             base::FileEnumerator::FILES);
  for (base::FilePath path = files.Next(); !path.empty(); path = files.Next()) {
    const std::string id = path.BaseName().RemoveExtension().AsUTF8Unsafe();
    if (path.Extension() != kIconExtension || !ids.contains(id)) {
      base::DeleteFile(path);
      continue;
    }
    if (std::optional<std::vector<uint8_t>> bytes =
            base::ReadFileToBytes(path)) {
      icons[id] = std::move(*bytes);
    }
  }
  return icons;
}

void WriteIcon(base::FilePath dir,
               base::FilePath path,
               std::vector<uint8_t> bytes) {
  if (!base::CreateDirectory(dir)) {
    return;
  }
  base::WriteFile(path, bytes);
}

// add-tab-folders D11: a duplicated pin's icon is a copy of the file.
void CopyIcon(base::FilePath from, base::FilePath to) {
  if (base::PathExists(from)) {
    base::CopyFile(from, to);
  }
}

}  // namespace

// static
PinContainer PinContainer::OfSpace(std::string_view space) {
  return PinContainer{std::string(space), std::string(), std::string()};
}

// static
PinContainer PinContainer::OfFolder(std::string_view space,
                                    std::string_view folder) {
  return PinContainer{std::string(space), std::string(folder), std::string()};
}

// static
PinContainer PinContainer::OfProfile(std::string_view profile) {
  return PinContainer{std::string(), std::string(), std::string(profile)};
}

PinContainer PinContainer::Section() const {
  return is_favorites() ? OfProfile(profile) : OfSpace(space);
}

Pin::Pin() = default;
Pin::Pin(const Pin&) = default;
Pin& Pin::operator=(const Pin&) = default;
Pin::~Pin() = default;

ClairPinStore::Removal::Removal() = default;
ClairPinStore::Removal::Removal(const Removal&) = default;
ClairPinStore::Removal& ClairPinStore::Removal::operator=(const Removal&) =
    default;
ClairPinStore::Removal::~Removal() = default;

namespace {

// A URL without its query and fragment.
GURL WithoutQueryAndRef(const GURL& url) {
  GURL::Replacements replacements;
  replacements.ClearQuery();
  replacements.ClearRef();
  return url.ReplaceComponents(replacements);
}

}  // namespace

bool SamePinnedURL(const GURL& url, const GURL& pinned) {
  // As in Arc: another query or fragment is still the pinned URL.
  return url.is_valid() && pinned.is_valid() &&
         WithoutQueryAndRef(url) == WithoutQueryAndRef(pinned);
}

// static
void ClairPinStore::RegisterPrefs(PrefRegistrySimple* registry) {
  registry->RegisterDictionaryPref(kPinsPref);
  registry->RegisterListPref(kClosedFoldersPref);
}

// static
ClairPinStore* ClairPinStore::Get() {
  static base::NoDestructor<ClairPinStore> store(
      g_browser_process->local_state());
  return store.get();
}

ClairPinStore::ClairPinStore(PrefService* local_state)
    : prefs_(local_state),
      file_runner_(base::ThreadPool::CreateSequencedTaskRunner(
          {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
           base::TaskShutdownBehavior::BLOCK_SHUTDOWN})) {
  CHECK(prefs_);
  base::FilePath user_data;
  if (base::PathService::Get(chrome::DIR_USER_DATA, &user_data)) {
    icon_dir_ = user_data.Append(kIconDirName);
  }
  Load();
  if (!icon_dir_.empty()) {
    std::set<std::string> ids;
    for (const auto& [id, pin] : pins_) {
      ids.insert(id);
    }
    file_runner_->PostTaskAndReplyWithResult(
        FROM_HERE, base::BindOnce(&LoadIcons, icon_dir_, std::move(ids)),
        base::BindOnce(&ClairPinStore::IconsLoaded,
                       weak_factory_.GetWeakPtr()));
  }
}

void ClairPinStore::Load() {
  pins_.clear();
  folders_.clear();
  closed_.clear();
  const base::DictValue& stored = prefs_->GetDict(kPinsPref);
  const base::DictValue* items = stored.FindDict(kItemsKey);
  // add-tab-folders D1: the first pin store's lists aren't converted; its
  // items have no kind, so none is kept.
  if (stored.FindInt(kVersionKey) == kVersion && items) {
    ClairSpaceStore* spaces = ClairSpaceStore::Get();
    // Folders first, so pins can find theirs.
    for (const auto [id, value] : *items) {
      const base::DictValue* item = value.GetIfDict();
      const std::string* kind = item ? item->FindString(kKindKey) : nullptr;
      if (!kind || *kind != kFolderKind || !IsPinID(id)) {
        continue;
      }
      const std::string* space = item->FindString(kSpaceKey);
      const std::string* order = item->FindString(kOrderKey);
      const std::string* name = item->FindString(kNameKey);
      if (!space || !spaces->Contains(*space) || !order ||
          !IsValidOrderKey(*order) || !name) {
        continue;
      }
      // A folder's own "folder", which this change never writes, is
      // ignored: folders hold pins only.
      Folder folder{id, *space, *order, Clean(*name, kMaxNameLength)};
      if (!folder.name.empty()) {
        folders_[id] = std::move(folder);
      }
    }
    // The place a pin or a split names: a Space's section, a folder of it,
    // or a profile's favorites; nullopt when it's gone.
    auto place_of = [&](const base::DictValue& item)
        -> std::optional<PinContainer> {
      const std::string* space = item.FindString(kSpaceKey);
      const std::string* profile = item.FindString(kProfileKey);
      if (space) {
        if (!spaces->Contains(*space)) {
          return std::nullopt;
        }
        // D1: in its folder, in the folder's Space, while the folder
        // exists; at its own Space's top level otherwise.
        const std::string* folder = item.FindString(kFolderKey);
        auto found = folder ? folders_.find(*folder) : folders_.end();
        if (found != folders_.end()) {
          return PinContainer::OfFolder(found->second.space, found->first);
        }
        return PinContainer::OfSpace(*space);
      }
      if (profile) {
        // D13: the profile's ID on this Mac.
        const std::string directory =
            ClairProfiles::Get()->DirectoryOf(*profile);
        if (directory.empty()) {
          return std::nullopt;
        }
        return PinContainer::OfProfile(directory);
      }
      return std::nullopt;
    };
    // add-split-view D10: splits next, so their pins can find them.
    for (const auto [id, value] : *items) {
      const base::DictValue* item = value.GetIfDict();
      const std::string* kind = item ? item->FindString(kKindKey) : nullptr;
      const std::string* order = item ? item->FindString(kOrderKey) : nullptr;
      if (!kind || *kind != kSplitKind || !IsPinID(id) || !order ||
          !IsValidOrderKey(*order) || folders_.contains(id)) {
        continue;
      }
      std::optional<PinContainer> place = place_of(*item);
      if (!place) {
        continue;
      }
      PinnedSplit split;
      split.id = id;
      split.container = *place;
      split.order = *order;
      split.ratio = ClampRatio(item->FindDouble(kRatioKey).value_or(0.5));
      splits_[id] = std::move(split);
    }
    for (const auto [id, value] : *items) {
      const base::DictValue* item = value.GetIfDict();
      const std::string* kind = item ? item->FindString(kKindKey) : nullptr;
      const std::string* url = item ? item->FindString(kURLKey) : nullptr;
      if (!kind || *kind != kPinKind || !IsPinID(id) || !url ||
          folders_.contains(id) || splits_.contains(id)) {
        continue;
      }
      Pin pin;
      pin.id = id;
      pin.url = GURL(*url);
      if (!IsPinnableURL(pin.url)) {
        continue;
      }
      if (const std::string* split_id = item->FindString(kSplitKey)) {
        // A pin of a split takes its split's place.
        auto split = splits_.find(*split_id);
        const std::optional<int> index = item->FindInt(kIndexKey);
        if (split == splits_.end() || !index || *index < 0 || *index > 1) {
          continue;
        }
        pin.split = split->first;
        pin.split_index = *index;
        pin.container = split->second.container;
        if (const std::string* title = item->FindString(kTitleKey)) {
          pin.title = Clean(*title, kMaxTitleLength);
        }
        if (const std::string* name = item->FindString(kNameKey)) {
          pin.name = Clean(*name, kMaxNameLength);
        }
        pins_[pin.id] = std::move(pin);
        continue;
      }
      const std::string* order = item->FindString(kOrderKey);
      if (!order || !IsValidOrderKey(*order)) {
        continue;
      }
      pin.order = *order;
      const std::string* space = item->FindString(kSpaceKey);
      const std::string* profile = item->FindString(kProfileKey);
      if (space) {
        if (!spaces->Contains(*space)) {
          continue;
        }
        pin.container = PinContainer::OfSpace(*space);
        // D1: in its folder, in the folder's Space, while the folder
        // exists; at its own Space's top level otherwise.
        const std::string* folder = item->FindString(kFolderKey);
        auto found = folder ? folders_.find(*folder) : folders_.end();
        if (found != folders_.end()) {
          pin.container =
              PinContainer::OfFolder(found->second.space, found->first);
        }
      } else if (profile) {
        // D13: the profile's ID on this Mac.
        const std::string directory =
            ClairProfiles::Get()->DirectoryOf(*profile);
        if (directory.empty()) {
          continue;
        }
        pin.container = PinContainer::OfProfile(directory);
      } else {
        continue;
      }
      if (const std::string* title = item->FindString(kTitleKey)) {
        pin.title = Clean(*title, kMaxTitleLength);
      }
      if (const std::string* name = item->FindString(kNameKey)) {
        pin.name = Clean(*name, kMaxNameLength);
      }
      pins_[pin.id] = std::move(pin);
    }
  }
  for (const base::Value& value : prefs_->GetList(kClosedFoldersPref)) {
    if (const std::string* id = value.GetIfString();
        id && folders_.contains(*id)) {
      closed_.insert(*id);
    }
  }
  RepairSplits();
  Index();
}

void ClairPinStore::RepairSplits() {
  for (auto it = splits_.begin(); it != splits_.end();) {
    std::vector<Pin*> panes;
    bool leading = false;
    bool trailing = false;
    for (auto& [id, pin] : pins_) {
      if (pin.split == it->first) {
        panes.push_back(&pin);
        (pin.split_index == 0 ? leading : trailing) = true;
      }
    }
    if (panes.size() == 2 && leading && trailing) {
      ++it;
      continue;
    }
    // The pins it has take its place, in pane order, each with a key of its
    // own after the split's.
    std::ranges::sort(panes, {}, &Pin::split_index);
    std::string order = it->second.order;
    for (Pin* pin : panes) {
      pin->split.clear();
      pin->split_index = 0;
      pin->container = it->second.container;
      pin->order = order;
      order = OrderKeyBetween(order, std::string());
    }
    it = splits_.erase(it);
  }
}

void ClairPinStore::Save() {
  ClairProfiles* profiles = ClairProfiles::Get();
  base::DictValue items;
  for (const auto& [id, folder] : folders_) {
    base::DictValue item;
    item.Set(kKindKey, kFolderKind);
    item.Set(kSpaceKey, folder.space);
    item.Set(kOrderKey, folder.order);
    item.Set(kNameKey, folder.name);
    items.Set(id, std::move(item));
  }
  // The place a pin or a split names.
  auto set_place = [&](base::DictValue& item, const PinContainer& container) {
    if (container.is_favorites()) {
      // D13: the profile's ID, not its directory.
      item.Set(kProfileKey, profiles->StoredIDOf(container.profile));
    } else {
      item.Set(kSpaceKey, container.space);
      if (container.is_folder()) {
        item.Set(kFolderKey, container.folder);
      }
    }
  };
  // add-split-view D10.
  for (const auto& [id, split] : splits_) {
    base::DictValue item;
    item.Set(kKindKey, kSplitKind);
    set_place(item, split.container);
    item.Set(kOrderKey, split.order);
    item.Set(kRatioKey, split.ratio);
    items.Set(id, std::move(item));
  }
  for (const auto& [id, pin] : pins_) {
    base::DictValue item;
    item.Set(kKindKey, kPinKind);
    if (!pin.split.empty()) {
      // A split's pin names its split and pane, not a place.
      item.Set(kSplitKey, pin.split);
      item.Set(kIndexKey, pin.split_index);
    } else {
      set_place(item, pin.container);
      item.Set(kOrderKey, pin.order);
    }
    item.Set(kURLKey, pin.url.spec());
    item.Set(kTitleKey, pin.title);
    if (!pin.name.empty()) {
      item.Set(kNameKey, pin.name);
    }
    items.Set(id, std::move(item));
  }
  base::DictValue stored;
  stored.Set(kVersionKey, kVersion);
  stored.Set(kItemsKey, std::move(items));
  prefs_->SetDict(kPinsPref, std::move(stored));
}

void ClairPinStore::SaveClosed() {
  base::ListValue closed;
  for (const std::string& id : closed_) {
    closed.Append(id);
  }
  prefs_->SetList(kClosedFoldersPref, std::move(closed));
}

void ClairPinStore::Index() {
  std::map<PinContainer, std::vector<std::pair<std::string, std::string>>>
      keyed;
  for (const auto& [id, folder] : folders_) {
    keyed[PinContainer::OfSpace(folder.space)].emplace_back(folder.order, id);
  }
  for (const auto& [id, pin] : pins_) {
    // A split's pins have its place (add-split-view D10).
    if (pin.split.empty()) {
      keyed[pin.container].emplace_back(pin.order, id);
    }
  }
  for (const auto& [id, split] : splits_) {
    keyed[split.container].emplace_back(split.order, id);
  }
  children_.clear();
  for (auto& [container, entries] : keyed) {
    // By key, then by ID.
    std::ranges::sort(entries);
    std::vector<std::string>& ids = children_[container];
    for (auto& [order, id] : entries) {
      ids.push_back(std::move(id));
    }
  }
}

void ClairPinStore::Changed(const PinContainer& container) {
  Index();
  Save();
  Notify(container);
}

void ClairPinStore::Notify(const PinContainer& container) {
  const PinContainer section = container.Section();
  for (Observer& observer : observers_) {
    observer.OnPinsChanged(section);
  }
}

bool ClairPinStore::IsValid(const PinContainer& container) const {
  if (container.is_favorites()) {
    return container.space.empty() && container.folder.empty() &&
           ClairProfiles::Get()->Exists(container.profile);
  }
  if (container.space.empty() ||
      !ClairSpaceStore::Get()->Contains(container.space)) {
    return false;
  }
  const Folder* folder =
      container.is_folder() ? FindFolder(container.folder) : nullptr;
  return !container.is_folder() || (folder && folder->space == container.space);
}

const Pin* ClairPinStore::Find(std::string_view id) const {
  auto found = pins_.find(std::string(id));
  return found == pins_.end() ? nullptr : &found->second;
}

const Folder* ClairPinStore::FindFolder(std::string_view id) const {
  auto found = folders_.find(std::string(id));
  return found == folders_.end() ? nullptr : &found->second;
}

const PinnedSplit* ClairPinStore::FindSplit(std::string_view id) const {
  auto found = splits_.find(std::string(id));
  return found == splits_.end() ? nullptr : &found->second;
}

std::vector<const Pin*> ClairPinStore::PinsOfSplit(std::string_view id) const {
  std::vector<const Pin*> result;
  if (id.empty() || !FindSplit(id)) {
    return result;
  }
  for (const auto& [pin_id, pin] : pins_) {
    if (pin.split == id) {
      result.push_back(&pin);
    }
  }
  std::ranges::sort(result, {}, &Pin::split_index);
  return result;
}

const Pin* ClairPinStore::PartnerOf(std::string_view pin) const {
  const Pin* record = Find(pin);
  if (!record || record->split.empty()) {
    return nullptr;
  }
  for (const Pin* other : PinsOfSplit(record->split)) {
    if (other != record) {
      return other;
    }
  }
  return nullptr;
}

void ClairPinStore::PlaceSplitPins(const PinnedSplit& split) {
  for (auto& [id, pin] : pins_) {
    if (pin.split == split.id) {
      pin.container = split.container;
      pin.order.clear();
    }
  }
}

std::vector<std::string> ClairPinStore::ChildrenOf(
    const PinContainer& container) const {
  auto found = children_.find(container);
  return found == children_.end() ? std::vector<std::string>()
                                  : found->second;
}

std::vector<const Pin*> ClairPinStore::PinsIn(
    const PinContainer& container) const {
  std::vector<const Pin*> result;
  for (const std::string& id : ChildrenOf(container)) {
    if (const Pin* pin = Find(id)) {
      result.push_back(pin);
    } else if (FindSplit(id)) {
      // add-split-view D10: a split's two, in pane order.
      for (const Pin* pane : PinsOfSplit(id)) {
        result.push_back(pane);
      }
    }
  }
  return result;
}

std::vector<const Pin*> ClairPinStore::AllPinsIn(std::string_view space) const {
  std::vector<const Pin*> result;
  for (const std::string& id : ChildrenOf(PinContainer::OfSpace(space))) {
    if (const Pin* pin = Find(id)) {
      result.push_back(pin);
    } else if (FindSplit(id)) {
      for (const Pin* pane : PinsOfSplit(id)) {
        result.push_back(pane);
      }
    } else if (FindFolder(id)) {
      for (const Pin* child : PinsIn(PinContainer::OfFolder(space, id))) {
        result.push_back(child);
      }
    }
  }
  return result;
}

std::vector<const Folder*> ClairPinStore::FoldersIn(
    std::string_view space) const {
  std::vector<const Folder*> result;
  for (const std::string& id : ChildrenOf(PinContainer::OfSpace(space))) {
    if (const Folder* folder = FindFolder(id)) {
      result.push_back(folder);
    }
  }
  return result;
}

std::optional<size_t> ClairPinStore::IndexOf(std::string_view id) const {
  PinContainer container;
  if (const Pin* pin = Find(id); pin && !pin->split.empty()) {
    // add-split-view D10: a split's pin has its split's place.
    return IndexOf(pin->split);
  }
  if (const Pin* pin = Find(id)) {
    container = pin->container;
  } else if (const PinnedSplit* split = FindSplit(id)) {
    container = split->container;
  } else if (const Folder* folder = FindFolder(id)) {
    container = PinContainer::OfSpace(folder->space);
  } else {
    return std::nullopt;
  }
  auto found = children_.find(container);
  if (found == children_.end()) {
    return std::nullopt;
  }
  auto it = std::ranges::find(found->second, id);
  if (it == found->second.end()) {
    return std::nullopt;
  }
  return static_cast<size_t>(it - found->second.begin());
}

std::string ClairPinStore::ProfileOf(const Pin& pin) const {
  return pin.container.is_favorites()
             ? pin.container.profile
             : ClairSpaceStore::Get()->ProfileOf(pin.container.space);
}

NSImage* ClairPinStore::IconOf(std::string_view id) const {
  auto found = icons_.find(std::string(id));
  return found == icons_.end() ? nil : found->second;
}

bool ClairPinStore::IsOpen(std::string_view folder) const {
  return !closed_.contains(std::string(folder));
}

const std::string& ClairPinStore::OrderOf(std::string_view id) const {
  static const base::NoDestructor<std::string> none;
  if (const Pin* pin = Find(id)) {
    return pin->order;
  }
  if (const Folder* folder = FindFolder(id)) {
    return folder->order;
  }
  if (const PinnedSplit* split = FindSplit(id)) {
    return split->order;
  }
  return *none;
}

bool ClairPinStore::KeyTaken(const PinContainer& container,
                             std::string_view order) const {
  return std::ranges::any_of(ChildrenOf(container), [&](const std::string& id) {
    return OrderOf(id) == order;
  });
}

std::string ClairPinStore::KeyAt(const PinContainer& container,
                                 size_t index,
                                 std::string_view moving) {
  for (int attempt = 0; attempt < 2; ++attempt) {
    std::vector<std::string> others = ChildrenOf(container);
    std::erase(others, std::string(moving));
    const size_t at = std::min(index, others.size());
    const std::string before =
        at > 0 ? OrderOf(others[at - 1]) : std::string();
    const std::string after =
        at < others.size() ? OrderOf(others[at]) : std::string();
    std::string key = OrderKeyBetween(before, after);
    if (!key.empty()) {
      return key;
    }
    // Two children share a key, as when two Macs placed one each in the
    // same gap: every child gets a new key, in the order they're in.
    std::string previous;
    for (const std::string& id : ChildrenOf(container)) {
      std::string next = OrderKeyBetween(previous, std::string());
      if (auto pin = pins_.find(id); pin != pins_.end()) {
        pin->second.order = next;
      } else if (auto folder = folders_.find(id); folder != folders_.end()) {
        folder->second.order = next;
      } else if (auto split = splits_.find(id); split != splits_.end()) {
        split->second.order = next;
      }
      previous = std::move(next);
    }
    Index();
  }
  std::vector<std::string> all = ChildrenOf(container);
  return OrderKeyBetween(all.empty() ? std::string() : OrderOf(all.back()),
                         std::string());
}

std::string ClairPinStore::Create(const PinContainer& container,
                                  size_t index,
                                  const GURL& url,
                                  std::string_view title,
                                  std::string_view name) {
  if (!IsPinnableURL(url) || !IsValid(container)) {
    return std::string();
  }
  Pin pin;
  pin.id = base::Uuid::GenerateRandomV4().AsLowercaseString();
  pin.container = container;
  pin.order = KeyAt(container, index, std::string());
  pin.url = url;
  pin.title = Clean(title, kMaxTitleLength);
  pin.name = Clean(name, kMaxNameLength);
  std::string id = pin.id;
  pins_[id] = std::move(pin);
  Changed(container);
  return id;
}

bool ClairPinStore::Move(std::string_view id,
                         const PinContainer& container,
                         size_t index) {
  if (!IsValid(container)) {
    return false;
  }
  // add-split-view D10: a split's pin moves its split, which goes where a pin
  // goes.
  if (const Pin* pin = Find(id); pin && !pin->split.empty()) {
    return Move(pin->split, container, index);
  }
  if (auto found = splits_.find(std::string(id)); found != splits_.end()) {
    const PinContainer from = found->second.container;
    std::vector<std::string> others = ChildrenOf(container);
    std::erase(others, std::string(id));
    if (from == container && IndexOf(id) == std::min(index, others.size())) {
      return false;
    }
    std::string key = KeyAt(container, index, id);
    found = splits_.find(std::string(id));
    found->second.container = container;
    found->second.order = std::move(key);
    PlaceSplitPins(found->second);
    if (from.Section() != container.Section()) {
      Index();
      Notify(from);
    }
    Changed(container);
    return true;
  }
  const std::optional<size_t> old_index = IndexOf(id);
  if (auto found = pins_.find(std::string(id)); found != pins_.end()) {
    const PinContainer from = found->second.container;
    std::vector<std::string> others = ChildrenOf(container);
    std::erase(others, std::string(id));
    if (from == container && old_index == std::min(index, others.size())) {
      return false;
    }
    std::string key = KeyAt(container, index, id);
    found = pins_.find(std::string(id));
    found->second.container = container;
    found->second.order = std::move(key);
    if (from.Section() != container.Section()) {
      Index();
      Notify(from);
    }
    Changed(container);
    return true;
  }
  auto found = folders_.find(std::string(id));
  // add-tab-folders D1: a folder goes only to a Space's top level.
  if (found == folders_.end() || container.is_favorites() ||
      container.is_folder()) {
    return false;
  }
  const PinContainer from = PinContainer::OfSpace(found->second.space);
  std::vector<std::string> others = ChildrenOf(container);
  std::erase(others, std::string(id));
  if (from == container && old_index == std::min(index, others.size())) {
    return false;
  }
  std::string key = KeyAt(container, index, id);
  found = folders_.find(std::string(id));
  found->second.order = std::move(key);
  if (from != container) {
    // D1: its pins' own Space follows it, and its splits' (add-split-view
    // D10).
    found->second.space = container.space;
    for (auto& [pin_id, pin] : pins_) {
      if (pin.container.folder == id) {
        pin.container.space = container.space;
      }
    }
    for (auto& [split_id, split] : splits_) {
      if (split.container.folder == id) {
        split.container.space = container.space;
      }
    }
    Index();
    Notify(from);
  }
  Changed(container);
  return true;
}

void ClairPinStore::Remember(Removal removal) {
  // The same pin removed twice keeps only its latest removal.
  std::erase_if(removals_, [&](const Removal& old) {
    if (removal.folder && old.folder && old.folder->id == removal.folder->id) {
      return true;
    }
    return !removal.folder && !old.folder && !old.pins.empty() &&
           !removal.pins.empty() && old.pins[0].id == removal.pins[0].id;
  });
  removals_.push_front(std::move(removal));
  while (removals_.size() > kMaxRemovals) {
    // Its icons go once it can't come back.
    Forget(removals_.back());
    removals_.pop_back();
  }
}

void ClairPinStore::Forget(const Removal& removal) {
  for (const Pin& pin : removal.pins) {
    DeleteIcon(pin.id);
  }
}

void ClairPinStore::Remove(std::string_view id, bool remember) {
  auto found = pins_.find(std::string(id));
  if (found == pins_.end()) {
    return;
  }
  // add-split-view D10: a split's pin goes with its split and the other pin.
  if (!found->second.split.empty()) {
    auto split = splits_.find(found->second.split);
    Removal removal;
    std::vector<std::string> ids;
    for (const Pin* pane : PinsOfSplit(found->second.split)) {
      ids.push_back(pane->id);
    }
    for (const std::string& pane_id : ids) {
      auto pane = pins_.find(pane_id);
      removal.pins.push_back(std::move(pane->second));
      pins_.erase(pane);
    }
    const PinContainer container = split->second.container;
    removal.splits.push_back(std::move(split->second));
    splits_.erase(split);
    if (remember) {
      removal.time = base::Time::Now();
      Remember(std::move(removal));
    } else {
      Forget(removal);
    }
    Changed(container);
    return;
  }
  Pin pin = std::move(found->second);
  pins_.erase(found);
  const PinContainer container = pin.container;
  if (remember) {
    Removal removal;
    removal.pins.push_back(std::move(pin));
    removal.time = base::Time::Now();
    Remember(std::move(removal));
  } else {
    DeleteIcon(pin.id);
  }
  Changed(container);
}

// --- Splits (add-split-view D10) ---

std::string ClairPinStore::CreateSplit(const PinContainer& container,
                                       size_t index,
                                       double ratio,
                                       const NewPin& leading,
                                       const NewPin& trailing) {
  if (!IsPinnableURL(leading.url) || !IsPinnableURL(trailing.url) ||
      !IsValid(container)) {
    return std::string();
  }
  PinnedSplit split;
  split.id = base::Uuid::GenerateRandomV4().AsLowercaseString();
  split.container = container;
  split.order = KeyAt(container, index, std::string());
  split.ratio = ClampRatio(ratio);
  int pane = 0;
  for (const NewPin* source : {&leading, &trailing}) {
    Pin pin;
    pin.id = base::Uuid::GenerateRandomV4().AsLowercaseString();
    pin.container = container;
    pin.url = source->url;
    pin.title = Clean(source->title, kMaxTitleLength);
    pin.name = Clean(source->name, kMaxNameLength);
    pin.split = split.id;
    pin.split_index = pane++;
    std::string pin_id = pin.id;
    pins_[pin_id] = std::move(pin);
  }
  std::string id = split.id;
  splits_[id] = std::move(split);
  Changed(container);
  return id;
}

void ClairPinStore::SeparateSplit(std::string_view id) {
  auto split = splits_.find(std::string(id));
  if (split == splits_.end()) {
    return;
  }
  const PinContainer container = split->second.container;
  const std::string order = split->second.order;
  // The leading pin takes the split's key, the trailing one a key between it
  // and the next child's.
  const std::vector<std::string> children = ChildrenOf(container);
  auto at = std::ranges::find(children, id);
  const std::string next = at != children.end() && at + 1 != children.end()
                               ? OrderOf(*(at + 1))
                               : std::string();
  std::vector<std::string> panes;
  for (const Pin* pin : PinsOfSplit(id)) {
    panes.push_back(pin->id);
  }
  splits_.erase(split);
  std::string key = order;
  for (size_t i = 0; i < panes.size(); ++i) {
    Pin& pin = pins_[panes[i]];
    pin.split.clear();
    pin.split_index = 0;
    pin.container = container;
    pin.order = key;
    key = OrderKeyBetween(key, next);
  }
  Index();
  // Without room between the two keys, the trailing pin goes right after the
  // leading one, as KeyAt renumbers. Its empty key puts it first meanwhile,
  // so the leading pin's place is counted without it.
  if (panes.size() == 2 && pins_[panes[1]].order.empty()) {
    std::vector<std::string> others = ChildrenOf(container);
    std::erase(others, panes[1]);
    auto leading = std::ranges::find(others, panes[0]);
    std::string fallback = KeyAt(
        container,
        leading != others.end()
            ? static_cast<size_t>(leading - others.begin()) + 1
            : std::numeric_limits<size_t>::max(),
        panes[1]);
    pins_[panes[1]].order = std::move(fallback);
  }
  Changed(container);
}

void ClairPinStore::TakeOutOfSplit(std::string_view pin_id) {
  const Pin* pin = Find(pin_id);
  const Pin* partner = PartnerOf(pin_id);
  auto split = pin ? splits_.find(pin->split) : splits_.end();
  if (!pin || !partner || split == splits_.end()) {
    return;
  }
  // The other pin takes the split's place and key.
  Pin& kept = pins_[partner->id];
  kept.split.clear();
  kept.split_index = 0;
  kept.container = split->second.container;
  kept.order = split->second.order;
  const PinContainer container = split->second.container;
  Removal removal;
  removal.partner = kept.id;
  removal.splits.push_back(split->second);
  auto found = pins_.find(std::string(pin_id));
  removal.pins.push_back(std::move(found->second));
  pins_.erase(found);
  splits_.erase(split);
  removal.time = base::Time::Now();
  Remember(std::move(removal));
  Changed(container);
}

void ClairPinStore::SetSplitRatio(std::string_view id, double ratio) {
  auto split = splits_.find(std::string(id));
  ratio = ClampRatio(ratio);
  if (split == splits_.end() || std::abs(split->second.ratio - ratio) < 1e-4) {
    return;
  }
  split->second.ratio = ratio;
  Save();
}

void ClairPinStore::SwapSplitPanes(std::string_view id) {
  const PinnedSplit* split = FindSplit(id);
  if (!split) {
    return;
  }
  for (auto& [pin_id, pin] : pins_) {
    if (pin.split == id) {
      pin.split_index = 1 - pin.split_index;
    }
  }
  Changed(split->container);
}

void ClairPinStore::SetName(std::string_view id, std::string_view name) {
  auto found = pins_.find(std::string(id));
  std::string cleaned = Clean(name, kMaxNameLength);
  if (found == pins_.end() || found->second.name == cleaned) {
    return;
  }
  found->second.name = std::move(cleaned);
  Changed(found->second.container);
}

void ClairPinStore::SetTitle(std::string_view id, std::string_view title) {
  auto found = pins_.find(std::string(id));
  std::string cleaned = Clean(title, kMaxTitleLength);
  if (found == pins_.end() || found->second.title == cleaned) {
    return;
  }
  found->second.title = std::move(cleaned);
  Changed(found->second.container);
}

void ClairPinStore::SetURL(std::string_view id, const GURL& url) {
  auto found = pins_.find(std::string(id));
  if (found == pins_.end() || !IsPinnableURL(url) || found->second.url == url) {
    return;
  }
  found->second.url = url;
  Changed(found->second.container);
}

void ClairPinStore::SetIcon(std::string_view id, NSImage* icon) {
  auto found = pins_.find(std::string(id));
  NSData* data = PNGOf(icon);
  if (found == pins_.end() || !data) {
    return;
  }
  NSImage* scaled = IconFromPNG(data);
  if (!scaled) {
    return;
  }
  icons_[found->first] = scaled;
  if (!icon_dir_.empty()) {
    const uint8_t* bytes = static_cast<const uint8_t*>(data.bytes);
    file_runner_->PostTask(
        FROM_HERE,
        base::BindOnce(&WriteIcon, icon_dir_, IconPath(id),
                       std::vector<uint8_t>(bytes, bytes + data.length)));
  }
  Notify(found->second.container);
}

// --- Folders (add-tab-folders D1, D3, D7, D11) ---

std::string ClairPinStore::CreateFolder(std::string_view space,
                                        size_t index,
                                        std::string_view name) {
  const PinContainer section = PinContainer::OfSpace(space);
  std::string cleaned = Clean(name, kMaxNameLength);
  if (cleaned.empty() || !IsValid(section)) {
    return std::string();
  }
  Folder folder{base::Uuid::GenerateRandomV4().AsLowercaseString(),
                std::string(space), KeyAt(section, index, std::string()),
                std::move(cleaned)};
  std::string id = folder.id;
  folders_[id] = std::move(folder);
  Changed(section);
  return id;
}

void ClairPinStore::RenameFolder(std::string_view id, std::string_view name) {
  auto found = folders_.find(std::string(id));
  std::string cleaned = Clean(name, kMaxNameLength);
  if (found == folders_.end() || cleaned.empty() ||
      found->second.name == cleaned) {
    return;
  }
  found->second.name = std::move(cleaned);
  Changed(PinContainer::OfSpace(found->second.space));
}

void ClairPinStore::SetOpen(std::string_view id, bool open) {
  const Folder* folder = FindFolder(id);
  if (!folder || IsOpen(id) == open) {
    return;
  }
  if (open) {
    closed_.erase(std::string(id));
  } else {
    closed_.insert(std::string(id));
  }
  SaveClosed();
  Notify(PinContainer::OfSpace(folder->space));
}

std::string ClairPinStore::DuplicateFolder(std::string_view id) {
  const Folder* original = FindFolder(id);
  const std::optional<size_t> index = IndexOf(id);
  if (!original || !index) {
    return std::string();
  }
  const PinContainer section = PinContainer::OfSpace(original->space);
  Folder copy{base::Uuid::GenerateRandomV4().AsLowercaseString(),
              original->space, KeyAt(section, *index + 1, std::string()),
              original->name};
  const std::vector<const Pin*> pins =
      PinsIn(PinContainer::OfFolder(original->space, original->id));
  // add-split-view D10: its splits are copied as splits.
  std::map<std::string, std::string> split_copies;
  std::vector<PinnedSplit> new_splits;
  for (const Pin* pin : pins) {
    if (pin->split.empty() || split_copies.contains(pin->split)) {
      continue;
    }
    PinnedSplit split = *FindSplit(pin->split);
    split.id = base::Uuid::GenerateRandomV4().AsLowercaseString();
    split.container = PinContainer::OfFolder(copy.space, copy.id);
    split_copies[pin->split] = split.id;
    new_splits.push_back(std::move(split));
  }
  std::vector<Pin> copies;
  for (const Pin* pin : pins) {
    Pin duplicate = *pin;
    duplicate.id = base::Uuid::GenerateRandomV4().AsLowercaseString();
    duplicate.container = PinContainer::OfFolder(copy.space, copy.id);
    if (!duplicate.split.empty()) {
      duplicate.split = split_copies[duplicate.split];
    }
    if (NSImage* icon = IconOf(pin->id)) {
      icons_[duplicate.id] = icon;
      if (!icon_dir_.empty()) {
        file_runner_->PostTask(
            FROM_HERE, base::BindOnce(&CopyIcon, IconPath(pin->id),
                                      IconPath(duplicate.id)));
      }
    }
    copies.push_back(std::move(duplicate));
  }
  std::string copy_id = copy.id;
  folders_[copy_id] = std::move(copy);
  for (PinnedSplit& split : new_splits) {
    std::string split_id = split.id;
    splits_[split_id] = std::move(split);
  }
  for (Pin& duplicate : copies) {
    std::string pin_id = duplicate.id;
    pins_[pin_id] = std::move(duplicate);
  }
  Changed(section);
  return copy_id;
}

std::vector<std::string> ClairPinStore::RemoveFolder(std::string_view id,
                                                     bool remember) {
  auto found = folders_.find(std::string(id));
  if (found == folders_.end()) {
    return {};
  }
  Removal removal;
  removal.folder = found->second;
  removal.folder_was_closed = closed_.contains(found->first);
  const PinContainer section = PinContainer::OfSpace(found->second.space);
  std::vector<std::string> ids;
  for (const Pin* pin : PinsIn(
           PinContainer::OfFolder(found->second.space, found->second.id))) {
    ids.push_back(pin->id);
  }
  for (const std::string& pin_id : ids) {
    auto pin = pins_.find(pin_id);
    removal.pins.push_back(std::move(pin->second));
    pins_.erase(pin);
  }
  // add-split-view D10: its splits go with it.
  for (auto split = splits_.begin(); split != splits_.end();) {
    if (split->second.container.folder == id) {
      removal.splits.push_back(std::move(split->second));
      split = splits_.erase(split);
    } else {
      ++split;
    }
  }
  folders_.erase(found);
  if (closed_.erase(std::string(id)) > 0) {
    SaveClosed();
  }
  if (remember) {
    removal.time = base::Time::Now();
    Remember(std::move(removal));
  } else {
    Forget(removal);
  }
  Changed(section);
  return ids;
}

std::vector<std::string> ClairPinStore::RemoveContainer(
    const PinContainer& container) {
  const PinContainer section = container.Section();
  std::vector<std::string> removed;
  for (auto it = pins_.begin(); it != pins_.end();) {
    if (it->second.container.Section() == section) {
      removed.push_back(it->first);
      DeleteIcon(it->first);
      it = pins_.erase(it);
    } else {
      ++it;
    }
  }
  for (auto it = splits_.begin(); it != splits_.end();) {
    if (it->second.container.Section() == section) {
      it = splits_.erase(it);
    } else {
      ++it;
    }
  }
  bool had_folders = false;
  if (!section.is_favorites()) {
    for (auto it = folders_.begin(); it != folders_.end();) {
      if (it->second.space == section.space) {
        closed_.erase(it->first);
        it = folders_.erase(it);
        had_folders = true;
      } else {
        ++it;
      }
    }
    if (had_folders) {
      SaveClosed();
    }
  }
  // D9: the user confirmed, so none of them comes back.
  std::erase_if(removals_, [&](const Removal& removal) {
    const bool gone =
        removal.folder ? PinContainer::OfSpace(removal.folder->space) == section
                       : !removal.pins.empty() &&
                             removal.pins[0].container.Section() == section;
    if (gone) {
      Forget(removal);
    }
    return gone;
  });
  if (!removed.empty() || had_folders) {
    Changed(section);
  }
  return removed;
}

const ClairPinStore::Removal* ClairPinStore::NewestRemoval(
    std::string_view profile) const {
  for (const Removal& removal : removals_) {
    if (removal.folder) {
      if (ClairSpaceStore::Get()->ProfileOf(removal.folder->space) == profile) {
        return &removal;
      }
      continue;
    }
    if (removal.pins.empty()) {
      continue;
    }
    const Pin& pin = removal.pins[0];
    if (ProfileOf(pin) == profile && IsValid(pin.container.Section())) {
      return &removal;
    }
  }
  return nullptr;
}

bool ClairPinStore::WasRemoved(std::string_view id) const {
  return std::ranges::any_of(removals_, [&](const Removal& removal) {
    return std::ranges::any_of(removal.pins,
                               [&](const Pin& pin) { return pin.id == id; });
  });
}

bool ClairPinStore::RestorePin(std::string_view id) {
  for (const Removal& removal : removals_) {
    if (std::ranges::any_of(removal.pins,
                            [&](const Pin& pin) { return pin.id == id; })) {
      return Restore(&removal);
    }
  }
  return false;
}

bool ClairPinStore::Restore(const Removal* target) {
  auto found = std::ranges::find_if(
      removals_, [&](const Removal& removal) { return &removal == target; });
  if (found == removals_.end()) {
    return false;
  }
  if (found->folder) {
    const PinContainer section = PinContainer::OfSpace(found->folder->space);
    if (!IsValid(section) || folders_.contains(found->folder->id)) {
      return false;
    }
    Removal removal = std::move(*found);
    removals_.erase(found);
    Folder folder = std::move(*removal.folder);
    if (KeyTaken(section, folder.order)) {
      folder.order = KeyAt(section, std::numeric_limits<size_t>::max(),
                           std::string());
    }
    const std::string id = folder.id;
    folders_[id] = std::move(folder);
    if (removal.folder_was_closed) {
      closed_.insert(id);
      SaveClosed();
    }
    for (PinnedSplit& split : removal.splits) {
      split.container = PinContainer::OfFolder(section.space, id);
      std::string split_id = split.id;
      splits_[split_id] = std::move(split);
    }
    for (Pin& pin : removal.pins) {
      if (pins_.contains(pin.id)) {
        continue;
      }
      pin.container = PinContainer::OfFolder(section.space, id);
      std::string pin_id = pin.id;
      pins_[pin_id] = std::move(pin);
    }
    RepairSplits();
    Changed(section);
    return true;
  }
  // add-split-view D10: a split, whole or with the pane closed out of it.
  if (!found->splits.empty()) {
    PinnedSplit split = found->splits[0];
    if (FindSplit(split.id) ||
        std::ranges::any_of(found->pins, [&](const Pin& pin) {
          return pins_.contains(pin.id);
        })) {
      return false;
    }
    Removal removal = std::move(*found);
    removals_.erase(found);
    if (!removal.partner.empty()) {
      // The pin that kept the split's place takes it back into the split,
      // where it is now; without it, the closed pin comes back alone there.
      auto partner = pins_.find(removal.partner);
      Pin pin = std::move(removal.pins[0]);
      if (partner == pins_.end() || !partner->second.split.empty()) {
        pin.split.clear();
        pin.split_index = 0;
        pin.container = IsValid(split.container) ? split.container
                                                 : split.container.Section();
        pin.order = KeyAt(pin.container, std::numeric_limits<size_t>::max(),
                          std::string());
        const PinContainer container = pin.container;
        std::string pin_id = pin.id;
        pins_[pin_id] = std::move(pin);
        Changed(container);
        return true;
      }
      split.container = partner->second.container;
      split.order = partner->second.order;
      partner->second.split = split.id;
      partner->second.split_index = 1 - pin.split_index;
      partner->second.order.clear();
      pin.container = split.container;
      const PinContainer container = split.container;
      std::string pin_id = pin.id;
      pins_[pin_id] = std::move(pin);
      std::string split_id = split.id;
      splits_[split_id] = std::move(split);
      Changed(container);
      return true;
    }
    bool at_end = false;
    if (!IsValid(split.container)) {
      if (!IsValid(split.container.Section())) {
        return false;
      }
      split.container = split.container.Section();
      at_end = true;
    }
    if (at_end || KeyTaken(split.container, split.order)) {
      split.order = KeyAt(split.container, std::numeric_limits<size_t>::max(),
                          std::string());
    }
    const PinContainer container = split.container;
    for (Pin& pin : removal.pins) {
      pin.container = container;
      std::string pin_id = pin.id;
      pins_[pin_id] = std::move(pin);
    }
    std::string split_id = split.id;
    splits_[split_id] = std::move(split);
    Changed(container);
    return true;
  }
  if (found->pins.empty() || pins_.contains(found->pins[0].id) ||
      !IsValid(found->pins[0].container.Section())) {
    return false;
  }
  Removal removal = std::move(*found);
  removals_.erase(found);
  Pin pin = std::move(removal.pins[0]);
  // D7: into its folder while the folder exists, and otherwise to the end of
  // its Space's section; at its key unless that's now taken.
  bool at_end = false;
  if (!IsValid(pin.container)) {
    pin.container = pin.container.Section();
    at_end = true;
  }
  if (at_end || KeyTaken(pin.container, pin.order)) {
    pin.order = KeyAt(pin.container, std::numeric_limits<size_t>::max(),
                      std::string());
  }
  const PinContainer container = pin.container;
  std::string id = pin.id;
  pins_[id] = std::move(pin);
  Changed(container);
  return true;
}

base::FilePath ClairPinStore::IconPath(std::string_view id) const {
  return icon_dir_.AppendASCII(std::string(id) + kIconExtension);
}

void ClairPinStore::DeleteIcon(std::string_view id) {
  icons_.erase(std::string(id));
  if (icon_dir_.empty() || !IsPinID(id)) {
    return;
  }
  file_runner_->PostTask(
      FROM_HERE,
      base::BindOnce([](base::FilePath path) { base::DeleteFile(path); },
                     IconPath(id)));
}

void ClairPinStore::IconsLoaded(
    std::map<std::string, std::vector<uint8_t>> icons) {
  std::set<PinContainer> changed;
  for (auto& [id, bytes] : icons) {
    const Pin* pin = Find(id);
    // A newer icon may have come from a tab meanwhile.
    if (!pin || icons_.contains(id)) {
      continue;
    }
    NSImage* icon =
        IconFromPNG([NSData dataWithBytes:bytes.data() length:bytes.size()]);
    if (!icon) {
      continue;
    }
    icons_[id] = icon;
    changed.insert(pin->container.Section());
  }
  for (const PinContainer& container : changed) {
    Notify(container);
  }
}

void ClairPinStore::AddObserver(Observer* observer) {
  observers_.AddObserver(observer);
}

void ClairPinStore::RemoveObserver(Observer* observer) {
  observers_.RemoveObserver(observer);
}

}  // namespace clair
