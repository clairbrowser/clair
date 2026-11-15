// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#import "chrome/browser/clair/clair_pin_store.h"

#import <AppKit/AppKit.h>

#include <algorithm>
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
#include "chrome/browser/clair/clair_profiles.h"
#include "chrome/browser/clair/clair_space_store.h"
#include "chrome/common/chrome_paths.h"
#include "components/prefs/pref_registry_simple.h"
#include "components/prefs/pref_service.h"

namespace clair {

namespace {

constexpr int kVersion = 1;
constexpr char kVersionKey[] = "version";
constexpr char kSpacesKey[] = "spaces";
constexpr char kProfilesKey[] = "profiles";
constexpr char kItemsKey[] = "items";
constexpr char kURLKey[] = "url";
constexpr char kTitleKey[] = "title";
constexpr char kNameKey[] = "name";
// Reserved for folders (D1); always empty now.
constexpr char kParentKey[] = "parent";
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

}  // namespace

// static
PinContainer PinContainer::OfSpace(std::string_view space) {
  return PinContainer{std::string(space), std::string()};
}

// static
PinContainer PinContainer::OfProfile(std::string_view profile) {
  return PinContainer{std::string(), std::string(profile)};
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

bool SamePinnedURL(const GURL& url, const GURL& pinned) {
  return url.is_valid() && pinned.is_valid() &&
         url.GetWithoutRef() == pinned.GetWithoutRef();
}

// static
void ClairPinStore::RegisterPrefs(PrefRegistrySimple* registry) {
  registry->RegisterDictionaryPref(kPinsPref);
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
  spaces_.clear();
  profiles_.clear();
  const base::DictValue& stored = prefs_->GetDict(kPinsPref);
  const base::DictValue* items = stored.FindDict(kItemsKey);
  if (stored.FindInt(kVersionKey) != kVersion || !items) {
    return;
  }
  std::set<std::string> seen;
  auto read_lists = [&](const char* key, bool favorites) {
    const base::DictValue* lists = stored.FindDict(key);
    if (!lists) {
      return;
    }
    for (const auto [owner, value] : *lists) {
      const PinContainer container = favorites ? PinContainer::OfProfile(owner)
                                               : PinContainer::OfSpace(owner);
      if (!value.is_list() || !IsValid(container)) {
        continue;
      }
      std::vector<std::string> ids;
      for (const base::Value& entry : value.GetList()) {
        const std::string* id = entry.GetIfString();
        const base::DictValue* item = id ? items->FindDict(*id) : nullptr;
        const std::string* url = item ? item->FindString(kURLKey) : nullptr;
        if (!id || !IsPinID(*id) || !url || !seen.insert(*id).second) {
          continue;
        }
        Pin pin;
        pin.id = *id;
        pin.container = container;
        pin.url = GURL(*url);
        if (!IsPinnableURL(pin.url)) {
          continue;
        }
        if (const std::string* title = item->FindString(kTitleKey)) {
          pin.title = Clean(*title, kMaxTitleLength);
        }
        if (const std::string* name = item->FindString(kNameKey)) {
          pin.name = Clean(*name, kMaxNameLength);
        }
        ids.push_back(pin.id);
        pins_[pin.id] = std::move(pin);
      }
      if (!ids.empty()) {
        (favorites ? profiles_ : spaces_)[std::string(owner)] = std::move(ids);
      }
    }
  };
  read_lists(kSpacesKey, /*favorites=*/false);
  read_lists(kProfilesKey, /*favorites=*/true);
}

void ClairPinStore::Save() {
  auto write_lists = [](const std::map<std::string, std::vector<std::string>>&
                            lists) {
    base::DictValue dict;
    for (const auto& [owner, ids] : lists) {
      if (ids.empty()) {
        continue;
      }
      base::ListValue list;
      for (const std::string& id : ids) {
        list.Append(id);
      }
      dict.Set(owner, std::move(list));
    }
    return dict;
  };
  base::DictValue items;
  for (const auto& [id, pin] : pins_) {
    base::DictValue item;
    item.Set(kURLKey, pin.url.spec());
    item.Set(kTitleKey, pin.title);
    if (!pin.name.empty()) {
      item.Set(kNameKey, pin.name);
    }
    item.Set(kParentKey, std::string());
    items.Set(id, std::move(item));
  }
  base::DictValue stored;
  stored.Set(kVersionKey, kVersion);
  stored.Set(kSpacesKey, write_lists(spaces_));
  stored.Set(kProfilesKey, write_lists(profiles_));
  stored.Set(kItemsKey, std::move(items));
  prefs_->SetDict(kPinsPref, std::move(stored));
}

void ClairPinStore::Changed(const PinContainer& container) {
  Save();
  for (Observer& observer : observers_) {
    observer.OnPinsChanged(container);
  }
}

bool ClairPinStore::IsValid(const PinContainer& container) const {
  if (container.is_favorites()) {
    return container.space.empty() &&
           ClairProfiles::Get()->Exists(container.profile);
  }
  return !container.space.empty() &&
         ClairSpaceStore::Get()->Contains(container.space);
}

std::vector<std::string>* ClairPinStore::ListOf(const PinContainer& container) {
  return container.is_favorites() ? &profiles_[container.profile]
                                  : &spaces_[container.space];
}

const std::vector<std::string>* ClairPinStore::ListOf(
    const PinContainer& container) const {
  const auto& lists = container.is_favorites() ? profiles_ : spaces_;
  auto found = lists.find(container.is_favorites() ? container.profile
                                                   : container.space);
  return found == lists.end() ? nullptr : &found->second;
}

const Pin* ClairPinStore::Find(std::string_view id) const {
  auto found = pins_.find(std::string(id));
  return found == pins_.end() ? nullptr : &found->second;
}

std::vector<const Pin*> ClairPinStore::PinsIn(
    const PinContainer& container) const {
  std::vector<const Pin*> result;
  if (const std::vector<std::string>* ids = ListOf(container)) {
    for (const std::string& id : *ids) {
      if (const Pin* pin = Find(id)) {
        result.push_back(pin);
      }
    }
  }
  return result;
}

std::optional<size_t> ClairPinStore::IndexOf(std::string_view id) const {
  const Pin* pin = Find(id);
  const std::vector<std::string>* ids = pin ? ListOf(pin->container) : nullptr;
  if (!ids) {
    return std::nullopt;
  }
  auto it = std::ranges::find(*ids, id);
  if (it == ids->end()) {
    return std::nullopt;
  }
  return static_cast<size_t>(it - ids->begin());
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
  pin.url = url;
  pin.title = Clean(title, kMaxTitleLength);
  pin.name = Clean(name, kMaxNameLength);
  std::vector<std::string>* ids = ListOf(container);
  ids->insert(ids->begin() + std::min(index, ids->size()), pin.id);
  std::string id = pin.id;
  pins_[id] = std::move(pin);
  Changed(container);
  return id;
}

std::optional<size_t> ClairPinStore::Take(std::string_view id) {
  const Pin* pin = Find(id);
  if (!pin) {
    return std::nullopt;
  }
  std::vector<std::string>* ids = ListOf(pin->container);
  auto it = std::ranges::find(*ids, id);
  if (it == ids->end()) {
    return std::nullopt;
  }
  const size_t index = static_cast<size_t>(it - ids->begin());
  ids->erase(it);
  return index;
}

bool ClairPinStore::Move(std::string_view id,
                         const PinContainer& container,
                         size_t index) {
  auto found = pins_.find(std::string(id));
  if (found == pins_.end() || !IsValid(container)) {
    return false;
  }
  const PinContainer from = found->second.container;
  const std::optional<size_t> old_index = Take(id);
  std::vector<std::string>* ids = ListOf(container);
  const size_t at = std::min(index, ids->size());
  ids->insert(ids->begin() + at, std::string(id));
  if (from == container && old_index == at) {
    return false;
  }
  found->second.container = container;
  if (from != container) {
    Changed(from);
  }
  Changed(container);
  return true;
}

void ClairPinStore::Remove(std::string_view id, bool remember) {
  auto found = pins_.find(std::string(id));
  if (found == pins_.end()) {
    return;
  }
  const std::optional<size_t> index = Take(id);
  Pin pin = std::move(found->second);
  pins_.erase(found);
  if (remember) {
    Removal removal;
    removal.pin = pin;
    removal.index = index.value_or(0);
    removal.time = base::Time::Now();
    // The same pin removed twice keeps only its latest removal.
    std::erase_if(removals_,
                  [&](const Removal& old) { return old.pin.id == pin.id; });
    removals_.push_front(std::move(removal));
    while (removals_.size() > kMaxRemovals) {
      // Its icon goes once it can't come back.
      DeleteIcon(removals_.back().pin.id);
      removals_.pop_back();
    }
  } else {
    DeleteIcon(pin.id);
  }
  Changed(pin.container);
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
  for (Observer& observer : observers_) {
    observer.OnPinsChanged(found->second.container);
  }
}

std::vector<std::string> ClairPinStore::RemoveContainer(
    const PinContainer& container) {
  std::vector<std::string> removed;
  auto& lists = container.is_favorites() ? profiles_ : spaces_;
  auto found = lists.find(container.is_favorites() ? container.profile
                                                   : container.space);
  if (found != lists.end()) {
    removed = std::move(found->second);
    lists.erase(found);
  }
  for (const std::string& id : removed) {
    pins_.erase(id);
    DeleteIcon(id);
  }
  // D9: the user confirmed, so none of them comes back.
  std::erase_if(removals_, [&](const Removal& removal) {
    if (removal.pin.container != container) {
      return false;
    }
    DeleteIcon(removal.pin.id);
    return true;
  });
  if (!removed.empty()) {
    Changed(container);
  }
  return removed;
}

const ClairPinStore::Removal* ClairPinStore::NewestRemoval(
    std::string_view profile) const {
  for (const Removal& removal : removals_) {
    if (ProfileOf(removal.pin) == profile && IsValid(removal.pin.container)) {
      return &removal;
    }
  }
  return nullptr;
}

bool ClairPinStore::WasRemoved(std::string_view id) const {
  return std::ranges::any_of(
      removals_, [&](const Removal& removal) { return removal.pin.id == id; });
}

bool ClairPinStore::Restore(std::string_view id) {
  auto found = std::ranges::find_if(
      removals_, [&](const Removal& removal) { return removal.pin.id == id; });
  if (found == removals_.end() || pins_.contains(found->pin.id) ||
      !IsValid(found->pin.container)) {
    return false;
  }
  Removal removal = std::move(*found);
  removals_.erase(found);
  std::vector<std::string>* ids = ListOf(removal.pin.container);
  ids->insert(ids->begin() + std::min(removal.index, ids->size()),
              removal.pin.id);
  const PinContainer container = removal.pin.container;
  pins_[removal.pin.id] = std::move(removal.pin);
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
    changed.insert(pin->container);
  }
  for (const PinContainer& container : changed) {
    for (Observer& observer : observers_) {
      observer.OnPinsChanged(container);
    }
  }
}

void ClairPinStore::AddObserver(Observer* observer) {
  observers_.AddObserver(observer);
}

void ClairPinStore::RemoveObserver(Observer* observer) {
  observers_.RemoveObserver(observer);
}

}  // namespace clair
