// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/clair_native_layer.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <climits>
#include <optional>
#include <string>
#include <vector>

#include "base/apple/bundle_locations.h"
#include "base/apple/foundation_util.h"
#include "base/check.h"
#include "base/command_line.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/process/process.h"
#include "base/strings/sys_string_conversions.h"
#include "base/time/time.h"
#include "chrome/app/chrome_command_ids.h"
#import "chrome/browser/app_controller_mac.h"
#include "chrome/browser/global_keyboard_shortcuts_mac.h"
#import "chrome/browser/clair/ClairHost.h"
#include "chrome/browser/browser_process.h"
#import "chrome/browser/clair/clair_pin_store.h"
#include "chrome/browser/clair/clair_link_rule_store.h"
#include "chrome/browser/clair/clair_profiles.h"
#include "chrome/browser/clair/clair_space_store.h"
#import "chrome/browser/clair/clair_space_tabs.h"
#include "chrome/browser/clair/ungoogled_version.h"
#include "chrome/browser/clair/window/clair_window_group.h"
#include "chrome/browser/clair/window/clair_window_hooks.h"
#include "chrome/browser/download/download_core_service.h"
#include "chrome/browser/download/download_prefs.h"
#include "chrome/browser/lifetime/application_lifetime.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#include "chrome/browser/lifetime/restartability_monitor.h"
#include "chrome/browser/mac/clair_update_relaunch.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_service.h"
#include "components/search_engines/search_engines_switches.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "components/tabs/public/tab_interface.h"
#include "components/version_info/version_info.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "url/gurl.h"

namespace {

// Set in the user defaults by a relaunch from the background, for the process
// that replaces it.
NSString* const kRelaunchedInBackgroundKey = @"ClairRelaunchedInBackground";

// Opens `url` in a new foreground tab of `profile`'s most recently active
// tabbed window. With no browser to hold the tab, Navigate creates a window.
void OpenURLInProfile(const GURL& url, Profile* profile) {
  if (!profile) {
    LOG(ERROR) << "ClairUI: no profile to open " << url.possibly_invalid_spec()
               << " in";
    return;
  }
  NavigateParams params(profile, url, ui::PAGE_TRANSITION_AUTO_BOOKMARK);
  params.disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
  params.window_action = NavigateParams::WindowAction::kShowWindow;
  Navigate(&params);
}

}  // namespace

// Chromium's side of the contract: what ClairUI may ask of the browser.
@interface ClairChromiumHost : NSObject <ClairHost>
@end

namespace {

std::string PinIDOf(ClairPinID pinID) {
  return base::SysNSStringToUTF8(pinID ?: @"");
}

std::string FolderIDOf(ClairFolderID folderID) {
  return base::SysNSStringToUTF8(folderID ?: @"");
}

size_t PinIndexOf(NSInteger index) {
  return index < 0 ? 0 : static_cast<size_t>(index);
}

tabs::TabInterface* TabOf(ClairTabID tabID) {
  return tabID == ClairTabIDNone
             ? nullptr
             : tabs::TabHandle(static_cast<int32_t>(tabID)).Get();
}

// add-link-rules D4: the contract's match, or nullopt for an unknown one.
std::optional<clair::LinkRuleMatch> LinkRuleMatchOf(ClairLinkRuleMatch match) {
  switch (match) {
    case ClairLinkRuleMatchContains:
      return clair::LinkRuleMatch::kContains;
    case ClairLinkRuleMatchExact:
      return clair::LinkRuleMatch::kExact;
    case ClairLinkRuleMatchPrefix:
      return clair::LinkRuleMatch::kPrefix;
  }
  return std::nullopt;
}

ClairLinkRuleMatch ContractMatchOf(clair::LinkRuleMatch match) {
  switch (match) {
    case clair::LinkRuleMatch::kContains:
      return ClairLinkRuleMatchContains;
    case clair::LinkRuleMatch::kExact:
      return ClairLinkRuleMatchExact;
    case clair::LinkRuleMatch::kPrefix:
      return ClairLinkRuleMatchPrefix;
  }
  return ClairLinkRuleMatchContains;
}

}  // namespace

// A link rule, as a snapshot (add-link-rules design D4).
@interface ClairChromiumLinkRule : NSObject <ClairLinkRule>
- (instancetype)initWithRule:(const clair::LinkRule&)rule;
@end

@implementation ClairChromiumLinkRule
@synthesize match = _match;
@synthesize text = _text;
@synthesize spaceID = _spaceID;

- (instancetype)initWithRule:(const clair::LinkRule&)rule {
  if ((self = [super init])) {
    _match = ContractMatchOf(rule.match);
    _text = base::SysUTF8ToNSString(rule.text);
    _spaceID = base::SysUTF8ToNSString(rule.space);
  }
  return self;
}
@end

@implementation ClairChromiumHost

- (NSString*)chromiumVersion {
  return base::SysUTF8ToNSString(version_info::GetVersionNumber());
}

- (NSString*)ungoogledChromiumVersion {
  return @CLAIR_UNGOOGLED_CHROMIUM_VERSION;
}

- (ClairRelaunchBlockers)silentRelaunchBlockers {
  CHECK([NSThread isMainThread]);
  // Chromium's default restart check, which it runs before restarting to
  // apply an update (follow-chromium-restart-check D1). Its reasons are
  // ClairRelaunchBlockers' bits; no window open isn't a reason to wait.
  using Factor = smart_restart::RestartabilityState;
  static_assert(static_cast<NSUInteger>(ClairRelaunchBlockersIncognitoWindow) ==
                static_cast<NSUInteger>(Factor::kIncognito));
  static_assert(static_cast<NSUInteger>(ClairRelaunchBlockersUnloadPrompt) ==
                static_cast<NSUInteger>(Factor::kBeforeUnloadHandler));
  static_assert(
      static_cast<NSUInteger>(ClairRelaunchBlockersDownloadInProgress) ==
      static_cast<NSUInteger>(Factor::kDownload));
  static_assert(static_cast<NSUInteger>(ClairRelaunchBlockersAudioPlaying) ==
                static_cast<NSUInteger>(Factor::kMedia));
  static_assert(static_cast<NSUInteger>(ClairRelaunchBlockersAppWindow) ==
                static_cast<NSUInteger>(Factor::kAppWindow));
  uint32_t factors = smart_restart::RestartabilityMonitor::ComputeCurrentState()
                         .GetRestartabilityStateFactor();
  factors &= ~static_cast<uint32_t>(Factor::kTotalBrowserCountZero);
  return static_cast<ClairRelaunchBlockers>(factors);
}

- (void)relaunch {
  CHECK([NSThread isMainThread]);
  // Chromium's own relaunch: it restores the session, and its quit flow still
  // asks about downloads in progress.
  NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
  if (!NSApp.active) {
    [defaults setBool:YES forKey:kRelaunchedInBackgroundKey];
  }
  chrome::AttemptRelaunch();
  // The quit flow asks about downloads in a nested run loop, so by now the user
  // may have said no. Chromium would keep the relaunch requested, and the next
  // plain quit would reopen Clair.
  if (!browser_shutdown::IsTryingToQuit()) {
    browser_shutdown::SetTryingToQuit(false);
    [defaults removeObjectForKey:kRelaunchedInBackgroundKey];
  }
}

- (void)updateWillInstallOnQuit {
  CHECK([NSThread isMainThread]);
  clair::NoteUpdateWillInstallOnQuit();
}

- (void)openURL:(NSURL*)url {
  CHECK([NSThread isMainThread]);
  GURL gurl(base::SysNSStringToUTF8(url.absoluteString));
  if (!gurl.is_valid()) {
    LOG(ERROR) << "ClairUI: not opening an invalid URL";
    return;
  }
  // The same profile Chromium's own menu commands use, loaded if it isn't yet.
  app_controller_mac::RunInLastProfileSafely(
      base::BindOnce(&OpenURLInProfile, gurl),
      app_controller_mac::kShowProfilePickerOnFailure);
}

// --- Spaces (add-spaces design D1, D2, D7, D9) ---

- (NSArray<id<ClairSpace>>*)spaces {
  CHECK([NSThread isMainThread]);
  return clair::SpaceSnapshots();
}

- (NSArray<id<ClairTab>>*)tabsInSpace:(ClairSpaceID)spaceID {
  CHECK([NSThread isMainThread]);
  return spaceID ? clair::TabsInSpace(base::SysNSStringToUTF8(spaceID)) : @[];
}

- (void)addObserver:(id<ClairSpacesObserver>)observer {
  CHECK([NSThread isMainThread]);
  if (observer) {
    clair::AddSpacesObserver(observer);
  }
}

- (ClairSpaceID)createSpaceNamed:(NSString*)name
                            icon:(NSString*)icon
                         profile:(ClairProfileID)profileID {
  CHECK([NSThread isMainThread]);
  const std::string id = clair::ClairSpaceStore::Get()->Create(
      base::SysNSStringToUTF8(name ?: @""), base::SysNSStringToUTF8(icon ?: @""),
      base::SysNSStringToUTF8(profileID ?: @""));
  return id.empty() ? nil : base::SysUTF8ToNSString(id);
}

- (void)renameSpace:(ClairSpaceID)spaceID to:(NSString*)name {
  CHECK([NSThread isMainThread]);
  clair::ClairSpaceStore::Get()->Rename(base::SysNSStringToUTF8(spaceID ?: @""),
                                        base::SysNSStringToUTF8(name ?: @""));
}

- (void)setIcon:(NSString*)icon forSpace:(ClairSpaceID)spaceID {
  CHECK([NSThread isMainThread]);
  clair::ClairSpaceStore::Get()->SetIcon(base::SysNSStringToUTF8(spaceID ?: @""),
                                         base::SysNSStringToUTF8(icon ?: @""));
}

- (void)moveSpace:(ClairSpaceID)spaceID toIndex:(NSInteger)index {
  CHECK([NSThread isMainThread]);
  clair::ClairSpaceStore::Get()->Move(
      base::SysNSStringToUTF8(spaceID ?: @""),
      static_cast<int>(std::clamp<NSInteger>(index, 0, INT_MAX)));
}

- (void)deleteSpace:(ClairSpaceID)spaceID {
  CHECK([NSThread isMainThread]);
  clair::DeleteSpace(base::SysNSStringToUTF8(spaceID ?: @""));
}

- (void)moveTab:(ClairTabID)tabID toSpace:(ClairSpaceID)spaceID {
  CHECK([NSThread isMainThread]);
  if (tabID == ClairTabIDNone || !spaceID) {
    return;
  }
  tabs::TabInterface* tab = tabs::TabHandle(static_cast<int32_t>(tabID)).Get();
  clair::MoveTabToSpace(tab, base::SysNSStringToUTF8(spaceID));
}

// --- Pins (add-pinned-tabs-and-favorites design D1 to D6, D10) ---

- (NSArray<id<ClairPinnedItem>>*)pinnedItemsInSpace:(ClairSpaceID)spaceID {
  CHECK([NSThread isMainThread]);
  return clair::PinnedItemSnapshots(base::SysNSStringToUTF8(spaceID ?: @""));
}

- (NSArray<id<ClairPin>>*)favoritesOfProfile:(ClairProfileID)profileID {
  CHECK([NSThread isMainThread]);
  return clair::PinSnapshots(clair::PinContainer::OfProfile(
      base::SysNSStringToUTF8(profileID ?: @"")));
}

- (void)pinTab:(ClairTabID)tabID
      inFolder:(ClairFolderID)folderID
       atIndex:(NSInteger)index {
  CHECK([NSThread isMainThread]);
  clair::PinTab(TabOf(tabID), FolderIDOf(folderID), PinIndexOf(index),
                /*favorite=*/false);
}

- (void)favoriteTab:(ClairTabID)tabID atIndex:(NSInteger)index {
  CHECK([NSThread isMainThread]);
  clair::PinTab(TabOf(tabID), std::string(), PinIndexOf(index),
                /*favorite=*/true);
}

- (void)movePin:(ClairPinID)pinID
        toSpace:(ClairSpaceID)spaceID
         folder:(ClairFolderID)folderID
        atIndex:(NSInteger)index {
  CHECK([NSThread isMainThread]);
  const std::string space = base::SysNSStringToUTF8(spaceID ?: @"");
  const std::string folder = FolderIDOf(folderID);
  // add-tab-folders D2: the store refuses a folder of another Space.
  clair::MovePin(PinIDOf(pinID),
                 folder.empty() ? clair::PinContainer::OfSpace(space)
                                : clair::PinContainer::OfFolder(space, folder),
                 PinIndexOf(index));
}

- (void)movePin:(ClairPinID)pinID toFavoritesAtIndex:(NSInteger)index {
  CHECK([NSThread isMainThread]);
  clair::ClairPinStore* store = clair::ClairPinStore::Get();
  const clair::Pin* pin = store->Find(PinIDOf(pinID));
  if (!pin) {
    return;
  }
  clair::MovePin(pin->id,
                 clair::PinContainer::OfProfile(store->ProfileOf(*pin)),
                 PinIndexOf(index));
}

- (void)removePin:(ClairPinID)pinID {
  CHECK([NSThread isMainThread]);
  clair::RemovePin(PinIDOf(pinID));
}

- (void)returnToPinnedURL:(ClairPinID)pinID {
  CHECK([NSThread isMainThread]);
  clair::ReturnToPinnedURL(PinIDOf(pinID));
}

- (void)replacePinnedURLWithCurrent:(ClairPinID)pinID {
  CHECK([NSThread isMainThread]);
  clair::ReplacePinnedURLWithCurrent(PinIDOf(pinID));
}

- (void)setPinnedURL:(NSURL*)url forPin:(ClairPinID)pinID {
  CHECK([NSThread isMainThread]);
  clair::SetPinnedURL(PinIDOf(pinID),
                      GURL(base::SysNSStringToUTF8(url.absoluteString ?: @"")));
}

- (void)setName:(NSString*)name forTab:(ClairTabID)tabID {
  CHECK([NSThread isMainThread]);
  tabs::TabInterface* tab = TabOf(tabID);
  ClairSpaceTabs* lists =
      tab ? ClairSpaceTabs::ForWebContents(tab->GetContents()) : nullptr;
  if (lists) {
    lists->SetName(tab, base::SysNSStringToUTF8(name ?: @""));
    clair::UpdateWindowTitles();
  }
}

- (void)setName:(NSString*)name forPin:(ClairPinID)pinID {
  CHECK([NSThread isMainThread]);
  clair::SetPinName(PinIDOf(pinID), base::SysNSStringToUTF8(name ?: @""));
}

- (void)clearTodayInSpace:(ClairSpaceID)spaceID {
  CHECK([NSThread isMainThread]);
  clair::ClearToday(base::SysNSStringToUTF8(spaceID ?: @""));
}

// --- Folders (add-tab-folders design D1 to D3, D6 to D8, D11) ---

- (ClairFolderID)createFolderNamed:(NSString*)name
                           inSpace:(ClairSpaceID)spaceID
                           atIndex:(NSInteger)index {
  CHECK([NSThread isMainThread]);
  const std::string id = clair::ClairPinStore::Get()->CreateFolder(
      base::SysNSStringToUTF8(spaceID ?: @""), PinIndexOf(index),
      base::SysNSStringToUTF8(name ?: @""));
  return id.empty() ? nil : base::SysUTF8ToNSString(id);
}

- (void)renameFolder:(ClairFolderID)folderID to:(NSString*)name {
  CHECK([NSThread isMainThread]);
  clair::ClairPinStore::Get()->RenameFolder(
      FolderIDOf(folderID), base::SysNSStringToUTF8(name ?: @""));
}

- (void)setFolder:(ClairFolderID)folderID open:(BOOL)open {
  CHECK([NSThread isMainThread]);
  clair::ClairPinStore::Get()->SetOpen(FolderIDOf(folderID), open);
}

- (void)moveFolder:(ClairFolderID)folderID
           toSpace:(ClairSpaceID)spaceID
           atIndex:(NSInteger)index {
  CHECK([NSThread isMainThread]);
  clair::MoveFolder(FolderIDOf(folderID),
                    base::SysNSStringToUTF8(spaceID ?: @""),
                    PinIndexOf(index));
}

- (void)duplicateFolder:(ClairFolderID)folderID {
  CHECK([NSThread isMainThread]);
  clair::DuplicateFolder(FolderIDOf(folderID));
}

- (void)deleteFolder:(ClairFolderID)folderID {
  CHECK([NSThread isMainThread]);
  clair::DeleteFolder(FolderIDOf(folderID));
}

- (void)closeTabsInFolder:(ClairFolderID)folderID {
  CHECK([NSThread isMainThread]);
  clair::CloseTabsInFolder(FolderIDOf(folderID));
}

- (ClairSpaceID)turnFolderIntoSpace:(ClairFolderID)folderID {
  CHECK([NSThread isMainThread]);
  const std::string space = clair::TurnFolderIntoSpace(FolderIDOf(folderID));
  return space.empty() ? nil : base::SysUTF8ToNSString(space);
}

// --- Profiles (add-profiles design D1, D7, D9, D11) ---

- (NSArray<id<ClairProfile>>*)profiles {
  CHECK([NSThread isMainThread]);
  return clair::ProfileSnapshots();
}

- (void)createProfileNamed:(NSString*)name
                completion:(void (^)(ClairProfileID))completion {
  CHECK([NSThread isMainThread]);
  void (^done)(ClairProfileID) = [completion copy];
  clair::ClairProfiles::Get()->Create(
      base::SysNSStringToUTF8(name ?: @""),
      base::BindOnce(
          [](void (^done)(ClairProfileID), const std::string& id) {
            if (done) {
              done(id.empty() ? nil : base::SysUTF8ToNSString(id));
            }
          },
          done));
}

- (void)renameProfile:(ClairProfileID)profileID to:(NSString*)name {
  CHECK([NSThread isMainThread]);
  clair::ClairProfiles::Get()->Rename(base::SysNSStringToUTF8(profileID ?: @""),
                                      base::SysNSStringToUTF8(name ?: @""));
}

- (void)deleteProfile:(ClairProfileID)profileID {
  CHECK([NSThread isMainThread]);
  clair::ClairProfiles::Get()->Delete(base::SysNSStringToUTF8(profileID ?: @""));
}

- (void)setProfile:(ClairProfileID)profileID forSpace:(ClairSpaceID)spaceID {
  CHECK([NSThread isMainThread]);
  clair::SetSpaceProfile(base::SysNSStringToUTF8(spaceID ?: @""),
                         base::SysNSStringToUTF8(profileID ?: @""));
}

- (void)downloadSettingsForProfile:(ClairProfileID)profileID
                        completion:(void (^)(NSURL*, BOOL))completion {
  CHECK([NSThread isMainThread]);
  void (^done)(NSURL*, BOOL) = [completion copy];
  clair::ClairProfiles::Get()->Load(
      base::SysNSStringToUTF8(profileID ?: @""),
      base::BindOnce(
          [](void (^done)(NSURL*, BOOL), Profile* profile) {
            DownloadPrefs* prefs =
                profile ? DownloadPrefs::FromBrowserContext(profile) : nullptr;
            if (!done) {
              return;
            }
            if (!prefs) {
              done(nil, NO);
              return;
            }
            done(base::apple::FilePathToNSURL(prefs->DownloadPath()),
                 prefs->PromptForDownload());
          },
          done));
}

- (void)setDownloadDirectory:(NSURL*)directory forProfile:(ClairProfileID)profileID {
  CHECK([NSThread isMainThread]);
  if (!directory.fileURL) {
    return;
  }
  const base::FilePath path = base::apple::NSURLToFilePath(directory);
  clair::ClairProfiles::Get()->Load(
      base::SysNSStringToUTF8(profileID ?: @""),
      base::BindOnce(
          [](base::FilePath path, Profile* profile) {
            if (!profile) {
              return;
            }
            // download.default_directory and savefile.default_directory, and
            // downloads stop asking where to save.
            DownloadPrefs::FromBrowserContext(profile)->SetDownloadPath(path);
            profile->GetPrefs()->SetBoolean(prefs::kPromptForDownload, false);
          },
          path));
}

- (void)setAsksWhereToSave:(BOOL)asks forProfile:(ClairProfileID)profileID {
  CHECK([NSThread isMainThread]);
  clair::ClairProfiles::Get()->Load(
      base::SysNSStringToUTF8(profileID ?: @""),
      base::BindOnce(
          [](bool asks, Profile* profile) {
            if (profile) {
              profile->GetPrefs()->SetBoolean(prefs::kPromptForDownload, asks);
            }
          },
          static_cast<bool>(asks)));
}

- (void)openURL:(NSURL*)url inProfile:(ClairProfileID)profileID {
  CHECK([NSThread isMainThread]);
  GURL gurl(base::SysNSStringToUTF8(url.absoluteString ?: @""));
  if (!gurl.is_valid()) {
    LOG(ERROR) << "ClairUI: not opening an invalid URL";
    return;
  }
  // D7: the profile's Space shown most recently, or its first.
  const std::string space = ClairWindowGroup::SpaceOfProfile(
      base::SysNSStringToUTF8(profileID ?: @""));
  if (space.empty()) {
    return;
  }
  ClairWindowGroup::OpenInSpace(space, gurl);
}

// --- Link rules (add-link-rules design D1, D3, D4) ---

- (NSArray<id<ClairLinkRule>>*)linkRules {
  CHECK([NSThread isMainThread]);
  NSMutableArray<id<ClairLinkRule>>* rules = [NSMutableArray array];
  for (const clair::LinkRule& rule : clair::ClairLinkRuleStore::Get()->rules()) {
    [rules addObject:[[ClairChromiumLinkRule alloc] initWithRule:rule]];
  }
  return rules;
}

- (void)replaceLinkRules:(NSArray<id<ClairLinkRule>>*)rules {
  CHECK([NSThread isMainThread]);
  std::vector<clair::LinkRule> copies;
  for (id<ClairLinkRule> rule in rules) {
    std::optional<clair::LinkRuleMatch> match = LinkRuleMatchOf(rule.match);
    if (!match) {
      continue;
    }
    copies.push_back({std::string(), *match,
                      base::SysNSStringToUTF8(rule.text ?: @""),
                      base::SysNSStringToUTF8(rule.spaceID ?: @"")});
  }
  // The store drops invalid rules and repeats (D1).
  clair::ClairLinkRuleStore::Get()->Replace(std::move(copies));
}

- (BOOL)isValidLinkRuleText:(NSString*)text {
  CHECK([NSThread isMainThread]);
  return clair::ReadLinkRuleText(base::SysNSStringToUTF8(text ?: @""))
      .has_value();
}

// --- App settings ---

- (BOOL)warnsBeforeQuitting {
  CHECK([NSThread isMainThread]);
  return g_browser_process->local_state()->GetBoolean(
      prefs::kConfirmToQuitEnabled);
}

- (void)setWarnsBeforeQuitting:(BOOL)warns {
  CHECK([NSThread isMainThread]);
  g_browser_process->local_state()->SetBoolean(prefs::kConfirmToQuitEnabled,
                                               warns);
}

- (void)quitWithoutWarning {
  CHECK([NSThread isMainThread]);
  // No menu item as the sender, so clair::MaybeConfirmQuit lets it through.
  [NSApp terminate:nil];
}

@end

namespace clair {

namespace {

// The host ClairUI was started with, kept for the life of the process.
ClairChromiumHost* __strong g_host = nil;

// ClairUI's entry point, once started.
Class<ClairUIEntryPoint> g_entry_point = nil;

// D2: a ClairUI.framework that is present but doesn't load leaves Clair
// without its interface. Say so and quit before any browser window opens,
// rather than fall back to Chromium's window.
[[noreturn]] void FailToStart(const std::string& reason) {
  LOG(ERROR) << "ClairUI: " << reason << "; quitting";
  NSAlert* alert = [[NSAlert alloc] init];
  alert.alertStyle = NSAlertStyleCritical;
  alert.messageText = @"Clair couldn’t start its interface.";
  alert.informativeText =
      @"Clair can’t open windows without it. Download Clair again from "
      @"github.com/clairbrowser/clair to fix it.";
  [alert addButtonWithTitle:@"Quit"];
  [NSApp activateIgnoringOtherApps:YES];
  [alert runModal];
  base::Process::TerminateCurrentProcessImmediately(1);
}

// When to stop keeping a background relaunch in the background. Null otherwise.
base::TimeTicks g_stay_in_background_until;

}  // namespace

bool IsNativeLayerRunning() {
  return g_entry_point != nil;
}

namespace {

// native-quit-confirmation D2, once the quit is known to come from the user:
// shows ClairUI's quit dialog when warn-before-quitting is on and no download
// is in progress. Chromium's own download warning asks otherwise.
bool AskBeforeQuitting() {
  if (!IsNativeLayerRunning() || browser_shutdown::IsTryingToQuit()) {
    return false;
  }
  if (!g_browser_process->local_state()->GetBoolean(
          prefs::kConfirmToQuitEnabled)) {
    return false;
  }
  if (DownloadCoreService::BlockingShutdownCountAllProfiles() > 0) {
    return false;
  }
  return ShowQuitConfirmation();
}

}  // namespace

bool MaybeConfirmQuit(id sender) {
  // A click on Clair > Quit Clair sends the item itself.
  NSMenuItem* item = base::apple::ObjCCast<NSMenuItem>(sender);
  return item && item.tag == IDC_EXIT && AskBeforeQuitting();
}

bool MaybeConfirmKeyboardQuit() {
  // Cmd+Q runs IDC_EXIT through the window's command dispatcher, and
  // chrome::Exit() reaches -confirmQuitIfNeeded with the key still current.
  NSEvent* event = NSApp.currentEvent;
  return event && CommandForKeyEvent(event).chrome_command == IDC_EXIT &&
         AskBeforeQuitting();
}

id<ClairWindow> CreateClairWindow(id<ClairBrowser> browser) {
  CHECK([NSThread isMainThread]);
  CHECK(g_entry_point);
  return [g_entry_point windowForBrowser:browser];
}

bool ShouldStayInBackground() {
  if (g_stay_in_background_until.is_null()) {
    return false;
  }
  if (NSApp.active || base::TimeTicks::Now() >= g_stay_in_background_until) {
    g_stay_in_background_until = base::TimeTicks();
    return false;
  }
  return true;
}

void StartNativeLayer() {
  CHECK([NSThread isMainThread]);
  if (g_host) {
    LOG(ERROR) << "ClairUI: already started";
    return;
  }

  // restore-google-search D3: Google is the default in every country, so
  // Chromium's search engine choice screen never shows. Profiles load after
  // this, and the choice service reads the switch each time it decides.
  base::CommandLine::ForCurrentProcess()->AppendSwitch(
      switches::kDisableSearchEngineChoiceScreen);

  NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
  if ([defaults boolForKey:kRelaunchedInBackgroundKey]) {
    [defaults removeObjectForKey:kRelaunchedInBackgroundKey];
    g_stay_in_background_until = base::TimeTicks::Now() + base::Minutes(1);
  }

  const base::FilePath path = base::apple::OuterBundlePath()
                                  .Append("Contents")
                                  .Append("Frameworks")
                                  .Append("ClairUI.framework");
  NSBundle* bundle =
      [NSBundle bundleWithPath:base::apple::FilePathToNSString(path)];
  if (!bundle) {
    LOG(WARNING) << "ClairUI: no framework at " << path
                 << "; running without the native layer";
    return;
  }
  NSError* error = nil;
  if (![bundle loadAndReturnError:&error]) {
    FailToStart("could not load " + path.value() + ": " +
                base::SysNSStringToUTF8(error.description));
  }
  Class principal = bundle.principalClass;
  if (!principal ||
      ![principal conformsToProtocol:@protocol(ClairUIEntryPoint)] ||
      ![principal respondsToSelector:@selector(windowForBrowser:)]) {
    FailToStart("the principal class of " + path.value() +
                " doesn't conform to ClairUIEntryPoint");
  }

  g_host = [[ClairChromiumHost alloc] init];
  g_entry_point = (Class<ClairUIEntryPoint>)principal;
  // add-profiles D6: the restore setting, read once, before session restore.
  ClairWindowGroup::Start();
  [g_entry_point startWithHost:g_host];
  clair::InstallNativeWindowMenus();
  LOG(INFO) << "ClairUI: started from " << path;
}

}  // namespace clair
