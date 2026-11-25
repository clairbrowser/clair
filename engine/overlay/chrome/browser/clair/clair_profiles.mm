// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/clair_profiles.h"

#include <algorithm>
#include <set>
#include <utility>

#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/i18n/case_conversion.h"
#include "base/logging.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/uuid.h"
#include "base/values.h"
#include "chrome/browser/browser_process.h"
#import "chrome/browser/clair/clair_pin_store.h"
#include "chrome/browser/clair/clair_space_store.h"
#import "chrome/browser/clair/clair_space_tabs.h"
#include "chrome/browser/profiles/delete_profile_helper.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_attributes_entry.h"
#include "chrome/browser/profiles/profile_avatar_icon_util.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profile_metrics.h"
#include "chrome/browser/profiles/profiles_state.h"
#include "chrome/common/chrome_constants.h"
#include "components/prefs/pref_registry_simple.h"
#include "components/prefs/pref_service.h"
#include "components/prefs/scoped_user_pref_update.h"

@interface ClairChromiumProfile : NSObject <ClairProfile>
- (instancetype)initWithInfo:(const clair::ClairProfiles::Info&)info;
@end

@implementation ClairChromiumProfile
@synthesize profileID = _profileID;
@synthesize name = _name;

- (instancetype)initWithInfo:(const clair::ClairProfiles::Info&)info {
  if ((self = [super init])) {
    _profileID = base::SysUTF8ToNSString(info.id);
    _name = base::SysUTF8ToNSString(info.name);
  }
  return self;
}
@end

namespace clair {

namespace {

// Names longer than this are cut, as Space names are.
constexpr size_t kMaxNameLength = 200;

ProfileAttributesStorage* Storage() {
  ProfileManager* manager = g_browser_process->profile_manager();
  return manager ? &manager->GetProfileAttributesStorage() : nullptr;
}

PrefService* LocalState() {
  return g_browser_process ? g_browser_process->local_state() : nullptr;
}

std::string Clean(std::string_view name) {
  std::string trimmed(base::TrimWhitespaceASCII(name, base::TRIM_ALL));
  std::string cut;
  base::TruncateUTF8ToByteSize(trimmed, kMaxNameLength, &cut);
  return cut;
}

}  // namespace

// static
ClairProfiles* ClairProfiles::Get() {
  static base::NoDestructor<ClairProfiles> profiles;
  return profiles.get();
}

// static
void ClairProfiles::RegisterPrefs(PrefRegistrySimple* registry) {
  registry->RegisterDictionaryPref(kProfilesPref);
}

// static
std::string ClairProfiles::DefaultID() {
  return chrome::kInitialProfile;
}

// static
std::string ClairProfiles::IDOf(const Profile* profile) {
  return profile ? profile->GetOriginalProfile()->GetBaseName().AsUTF8Unsafe()
                 : std::string();
}

ClairProfiles::ClairProfiles() = default;
ClairProfiles::~ClairProfiles() = default;

void ClairProfiles::Start() {
  if (ProfileAttributesStorage* storage = Storage();
      storage && !observation_.IsObserving()) {
    observation_.Observe(storage);
    ReconcileStoredIDs();
  }
}

std::string ClairProfiles::StoredIDOf(std::string_view directory) {
  PrefService* prefs = LocalState();
  if (!prefs || directory.empty()) {
    return std::string();
  }
  for (const auto [id, value] : prefs->GetDict(kProfilesPref)) {
    if (value.is_string() && value.GetString() == directory) {
      return id;
    }
  }
  if (!Exists(directory)) {
    return std::string();
  }
  std::string id = base::Uuid::GenerateRandomV4().AsLowercaseString();
  ScopedDictPrefUpdate(prefs, kProfilesPref)->Set(id, std::string(directory));
  return id;
}

std::string ClairProfiles::DirectoryOf(std::string_view stored_id) const {
  PrefService* prefs = LocalState();
  const std::string* directory =
      prefs ? prefs->GetDict(kProfilesPref).FindString(stored_id) : nullptr;
  return directory && Exists(*directory) ? *directory : std::string();
}

void ClairProfiles::ReconcileStoredIDs() {
  PrefService* prefs = LocalState();
  ProfileAttributesStorage* storage = Storage();
  if (!prefs || !storage) {
    return;
  }
  std::set<std::string> directories;
  for (ProfileAttributesEntry* entry : storage->GetAllProfilesAttributes()) {
    directories.insert(entry->GetPath().BaseName().AsUTF8Unsafe());
  }
  std::vector<std::string> gone;
  for (const auto [id, value] : prefs->GetDict(kProfilesPref)) {
    if (!value.is_string() || !directories.contains(value.GetString()) ||
        !base::Uuid::ParseLowercase(id).is_valid()) {
      gone.push_back(id);
    }
  }
  if (!gone.empty()) {
    ScopedDictPrefUpdate update(prefs, kProfilesPref);
    for (const std::string& id : gone) {
      update->Remove(id);
    }
  }
  for (const Info& info : List()) {
    StoredIDOf(info.id);
  }
}

std::string ClairProfiles::FallbackID() const {
  const std::string default_id = DefaultID();
  if (Exists(default_id)) {
    return default_id;
  }
  const std::vector<Info> list = List();
  return list.empty() ? default_id : list.front().id;
}

std::vector<ClairProfiles::Info> ClairProfiles::List() const {
  std::vector<Info> list;
  ProfileAttributesStorage* storage = Storage();
  if (!storage) {
    return list;
  }
  std::vector<std::pair<std::u16string, Info>> sorted;
  for (ProfileAttributesEntry* entry : storage->GetAllProfilesAttributes()) {
    if (entry->IsOmitted() || entry->IsEphemeral()) {
      continue;
    }
    std::u16string name = entry->GetLocalProfileName();
    if (name.empty()) {
      name = entry->GetName();
    }
    Info info{entry->GetPath().BaseName().AsUTF8Unsafe(),
              base::UTF16ToUTF8(name)};
    sorted.emplace_back(base::i18n::ToLower(name), std::move(info));
  }
  const std::string default_id = DefaultID();
  std::ranges::stable_sort(sorted, [&default_id](const auto& a, const auto& b) {
    const bool a_default = a.second.id == default_id;
    const bool b_default = b.second.id == default_id;
    if (a_default != b_default) {
      return a_default;
    }
    return a.first < b.first;
  });
  for (auto& [key, info] : sorted) {
    list.push_back(std::move(info));
  }
  return list;
}

base::FilePath ClairProfiles::PathOf(std::string_view id) const {
  ProfileAttributesStorage* storage = Storage();
  if (!storage || id.empty()) {
    return base::FilePath();
  }
  // Only a known profile's directory: an ID never becomes a path by itself.
  for (ProfileAttributesEntry* entry : storage->GetAllProfilesAttributes()) {
    if (!entry->IsOmitted() && entry->GetPath().BaseName().AsUTF8Unsafe() == id) {
      return entry->GetPath();
    }
  }
  return base::FilePath();
}

bool ClairProfiles::Exists(std::string_view id) const {
  return !PathOf(id).empty();
}

Profile* ClairProfiles::LoadedProfile(std::string_view id) const {
  const base::FilePath path = PathOf(id);
  ProfileManager* manager = g_browser_process->profile_manager();
  return path.empty() || !manager ? nullptr : manager->GetProfileByPath(path);
}

void ClairProfiles::Load(std::string_view id,
                         base::OnceCallback<void(Profile*)> done) {
  if (Profile* profile = LoadedProfile(id)) {
    std::move(done).Run(profile);
    return;
  }
  const base::FilePath path = PathOf(id);
  ProfileManager* manager = g_browser_process->profile_manager();
  if (path.empty() || !manager) {
    std::move(done).Run(nullptr);
    return;
  }
  // It runs the callback either way, with null when the load fails.
  manager->LoadProfileByPath(path, /*incognito=*/false, std::move(done));
}

void ClairProfiles::Create(std::string_view name,
                           base::OnceCallback<void(const std::string&)> done) {
  const std::string cleaned = Clean(name);
  if (cleaned.empty()) {
    std::move(done).Run(std::string());
    return;
  }
  ProfileManager::CreateMultiProfileAsync(
      base::UTF8ToUTF16(cleaned), profiles::GetPlaceholderAvatarIndex(),
      /*is_hidden=*/false,
      base::BindOnce(
          [](std::string name, base::OnceCallback<void(const std::string&)> done,
             Profile* profile) {
            if (!profile) {
              LOG(ERROR) << "Clair: couldn't create the profile " << name;
              std::move(done).Run(std::string());
              return;
            }
            std::move(done).Run(IDOf(profile));
          },
          cleaned, std::move(done)));
}

void ClairProfiles::Rename(std::string_view id, std::string_view name) {
  const std::string cleaned = Clean(name);
  if (cleaned.empty() || !Exists(id)) {
    return;
  }
  // profiles::UpdateProfileName needs the loaded profile.
  Load(id, base::BindOnce(
               [](std::string name, Profile* profile) {
                 if (profile) {
                   profiles::UpdateProfileName(profile,
                                               base::UTF8ToUTF16(name));
                 }
               },
               cleaned));
}

void ClairProfiles::Delete(std::string_view id) {
  const base::FilePath path = PathOf(id);
  ProfileManager* manager = g_browser_process->profile_manager();
  // D7: only a profile no Space uses, which is never the last one.
  if (path.empty() || !manager ||
      ClairSpaceStore::Get()->SpaceCountOf(id) > 0 || List().size() <= 1) {
    return;
  }
  manager->GetDeleteProfileHelper().MaybeScheduleProfileForDeletion(
      path, base::DoNothing(),
      ProfileMetrics::ProfileDelete::DELETE_PROFILE_SETTINGS);
}

void ClairProfiles::Changed() {
  NotifyProfiles(ProfileSnapshots());
}

void ClairProfiles::OnProfileAdded(const base::FilePath& profile_path) {
  // D13: its ID, from now on.
  StoredIDOf(profile_path.BaseName().AsUTF8Unsafe());
  Changed();
}

void ClairProfiles::OnProfileWasRemoved(const base::FilePath& profile_path,
                                        const std::u16string& profile_name) {
  // D2: a Space whose profile is gone, as when Chromium's own pages delete
  // it, uses the default profile.
  ClairSpaceStore::Get()->ProfileRemoved(profile_path.BaseName().AsUTF8Unsafe());
  // add-pinned-tabs-and-favorites D9: its favorites go with it.
  ClairPinStore::Get()->RemoveContainer(
      PinContainer::OfProfile(profile_path.BaseName().AsUTF8Unsafe()));
  // add-tab-folders D13: and its ID, once nothing saves it.
  if (PrefService* prefs = LocalState()) {
    const std::string directory = profile_path.BaseName().AsUTF8Unsafe();
    std::vector<std::string> ids;
    for (const auto [id, value] : prefs->GetDict(kProfilesPref)) {
      if (value.is_string() && value.GetString() == directory) {
        ids.push_back(id);
      }
    }
    if (!ids.empty()) {
      ScopedDictPrefUpdate update(prefs, kProfilesPref);
      for (const std::string& id : ids) {
        update->Remove(id);
      }
    }
  }
  Changed();
}

void ClairProfiles::OnProfileNameChanged(const base::FilePath& profile_path,
                                         const std::u16string& old_profile_name) {
  Changed();
}

void ClairProfiles::OnProfileIsOmittedChanged(
    const base::FilePath& profile_path) {
  Changed();
}

NSArray<id<ClairProfile>>* ProfileSnapshots() {
  NSMutableArray<id<ClairProfile>>* profiles = [NSMutableArray array];
  for (const ClairProfiles::Info& info : ClairProfiles::Get()->List()) {
    [profiles addObject:[[ClairChromiumProfile alloc] initWithInfo:info]];
  }
  return profiles;
}

}  // namespace clair
