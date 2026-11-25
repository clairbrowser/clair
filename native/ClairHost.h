// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.
//
// ClairHost.h: the one contract between Chromium and Clair's native layer,
// ClairUI.framework (change 1, native-layer spec and design D4; the window
// contract is replace-browser-window's design D3).
//
// Chromium loads ClairUI.framework from Clair.app/Contents/Frameworks once it
// has built the main menu, takes the bundle's principal class, checks that it
// conforms to ClairUIEntryPoint, and calls +startWithHost: with its
// implementation of ClairHost. From then on, Chromium asks the entry point for
// a ClairWindow for every normal browser window it creates (+windowForBrowser:),
// handing it a ClairBrowser. ClairUI reaches Chromium only through the host and
// those browsers, and Chromium reaches ClairUI only through the entry point and
// the windows it returns.
//
// The header is plain Objective-C, so Chromium includes it from Objective-C++
// and Swift imports it as the ClairHost module (native/module.modulemap).
// Every call happens on the main thread.
//
// Rules for the window contract:
// - Push, coalesced. Chromium tells each ClairWindow, and the host's Spaces
//   observers, what changed, at most once per run-loop turn for each tab and
//   each Space. ClairUI never polls.
// - Snapshots, not pointers. Tabs, suggestions, downloads, extension actions
//   and infobars reach ClairUI as immutable value objects with IDs. A command
//   naming an ID that no longer exists does nothing.
// - Closing. ClairUI never closes a browser window itself: it calls
//   -requestClose, which runs Chromium's beforeunload flow. Chromium tells the
//   ClairWindow -browserDidClose when the window really closes, and the
//   ClairBrowser then ignores every call.
// - Activation. ClairUI never activates the app or orders the window front;
//   Chromium shows and activates its windows itself.
//
// It is an engine input (scripts/engine-key.sh): a change here needs a new
// engine, so keep it small and add to it only what ClairUI needs.

#ifndef CLAIR_NATIVE_CLAIR_HOST_H_
#define CLAIR_NATIVE_CLAIR_HOST_H_

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Why relaunching Clair now, without asking, would interrupt the user. Each
// set bit is one reason; none set means a silent relaunch is safe. The reasons
// and values are Chromium's `smart_restart::RestartabilityState::
// SmartRestartStateFactor`, which the host returns as they are; a bit Chromium
// adds later passes through unnamed.
typedef NS_OPTIONS(NSUInteger, ClairRelaunchBlockers) {
  ClairRelaunchBlockersNone = 0,
  // An incognito or guest window is open; it doesn't come back after a
  // relaunch.
  ClairRelaunchBlockersIncognitoWindow = 1 << 0,
  // A page the user has interacted with has a `beforeunload` handler, so
  // quitting could ask "Leave site?".
  ClairRelaunchBlockersUnloadPrompt = 1 << 1,
  // A download is in progress; quitting would cancel it.
  ClairRelaunchBlockersDownloadInProgress = 1 << 2,
  // Audio is playing.
  ClairRelaunchBlockersAudioPlaying = 1 << 3,
  // A web app window is open.
  ClairRelaunchBlockersAppWindow = 1 << 4,
} NS_SWIFT_NAME(RelaunchBlockers);

// A tab's ID: Chromium's tab handle, stable for the tab's lifetime and never
// reused while Clair runs.
typedef NSInteger ClairTabID NS_SWIFT_NAME(TabID);

// No tab, as in a window whose last tab is closing.
static const ClairTabID ClairTabIDNone = -1;

// A browser window's ID, stable for its lifetime and never reused while Clair
// runs.
typedef NSInteger ClairBrowserID NS_SWIFT_NAME(BrowserID);

// No browser window.
static const ClairBrowserID ClairBrowserIDNone = 0;

// A Space's ID, a UUID string that never changes (add-spaces design D1).
typedef NSString *ClairSpaceID NS_SWIFT_BRIDGED_TYPEDEF NS_SWIFT_NAME(SpaceID);

// A profile's ID: the base name of its directory in Clair's data folder, such
// as "Default" or "Profile 1", which never changes (add-profiles design D1).
typedef NSString *ClairProfileID NS_SWIFT_BRIDGED_TYPEDEF NS_SWIFT_NAME(ProfileID);

// A pin's ID: the UUID string of a pinned tab or favorite, which never changes
// (add-pinned-tabs-and-favorites design D1).
typedef NSString *ClairPinID NS_SWIFT_BRIDGED_TYPEDEF NS_SWIFT_NAME(PinID);

// A folder's ID: the UUID string of a folder in a Space's pinned section,
// which never changes (add-tab-folders design D1).
typedef NSString *ClairFolderID NS_SWIFT_BRIDGED_TYPEDEF NS_SWIFT_NAME(FolderID);

// A bookmark's ID and a bookmark folder's: Chromium's bookmark node IDs,
// stable while Clair runs (add-bookmarks-menu design D3).
typedef int64_t ClairBookmarkID NS_SWIFT_NAME(BookmarkID);
typedef int64_t ClairBookmarkFolderID NS_SWIFT_NAME(BookmarkFolderID);

// No bookmark folder, as when one couldn't be added.
static const ClairBookmarkFolderID ClairBookmarkFolderIDNone = -1;

@protocol ClairLinkRule;
@protocol ClairPin;
@protocol ClairPinnedItem;
@protocol ClairProfile;
@protocol ClairSpace;
@protocol ClairSpacesObserver;
@protocol ClairTab;

// What Chromium does for ClairUI. Chromium implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairHost)
@protocol ClairHost <NSObject>

// The Chromium version compiled into the engine, such as "156.0.8078.73".
// It is also what websites and extensions see.
@property(nonatomic, readonly, copy) NSString *chromiumVersion;

// The ungoogled-chromium release the engine was built from, such as
// "156.0.8078.73-1".
@property(nonatomic, readonly, copy) NSString *ungoogledChromiumVersion;

// What would make a relaunch without asking interrupt the user right now.
- (ClairRelaunchBlockers)silentRelaunchBlockers;

// Quits and reopens Clair through Chromium's own graceful relaunch, which
// restores the open windows and tabs. Chromium's quit confirmations still
// apply, so the user can cancel, for example while a download is running.
- (void)relaunch;

// Tells Chromium that Sparkle's installer is waiting for Clair to quit and will
// then replace the app. From now on, any relaunch reopens Clair only once that
// has happened, so the new version opens, and opens once.
- (void)updateWillInstallOnQuit;

// Opens `url`, chrome:// URLs included, in a new foreground tab of the most
// recently active browser window, or in a new browser window if none is open.
- (void)openURL:(NSURL *)url NS_SWIFT_NAME(open(_:));

// --- Spaces (add-spaces design D1, D2 and D9) ---
// Spaces are app-wide and kept in Chromium's Local State. There is always at
// least one. Changes reach every observer, coalesced to once per run-loop turn
// for each Space and each tab.

// Every Space, in the user's order.
@property(nonatomic, readonly, copy) NSArray<id<ClairSpace>> *spaces;

// The Today tabs of a Space, in its order, across every browser window of the
// profile: every window showing the Space lists all of them, whichever window
// holds each (share-tabs-across-windows design D1). A Peek directly follows its
// parent. The tabs of pinned tabs and favorites aren't among them: they reach
// ClairUI through their pins (-pinnedItemsInSpace:, -favoritesOfProfile:). An
// incognito or guest window's Space (-[ClairBrowser shownSpaceID]) lists that
// window's tabs alone, whose `browserID` is its own. Empty for an unknown
// Space.
- (NSArray<id<ClairTab>> *)tabsInSpace:(ClairSpaceID)spaceID NS_SWIFT_NAME(tabs(inSpace:));

// Starts telling `observer` what changes. Chromium keeps it weakly.
- (void)addObserver:(id<ClairSpacesObserver>)observer NS_SWIFT_NAME(addObserver(_:));

// Adds a Space after the last one, using `profileID`, and returns its ID.
// `icon` is one emoji, or nil. An empty name or an unknown profile is ignored,
// and returns nil.
- (nullable ClairSpaceID)createSpaceNamed:(NSString *)name
                                     icon:(nullable NSString *)icon
                                  profile:(ClairProfileID)profileID
    NS_SWIFT_NAME(createSpace(named:icon:profile:));
// Renames a Space. An empty name is ignored.
- (void)renameSpace:(ClairSpaceID)spaceID to:(NSString *)name NS_SWIFT_NAME(renameSpace(_:to:));
// Sets a Space's icon, one emoji, or removes it with nil.
- (void)setIcon:(nullable NSString *)icon forSpace:(ClairSpaceID)spaceID
    NS_SWIFT_NAME(setIcon(_:forSpace:));
// Moves a Space to `index` in the order.
- (void)moveSpace:(ClairSpaceID)spaceID toIndex:(NSInteger)index NS_SWIFT_NAME(moveSpace(_:to:));
// Deletes a Space: each window showing it shows the Space before it, or the
// one after when it was first, then its tabs close in every window, each with
// its leave-page confirmation, and its pinned tabs and folders are removed
// (add-pinned-tabs-and-favorites design D9, add-tab-folders). Ignored for the
// only Space. ClairUI asks the user first.
- (void)deleteSpace:(ClairSpaceID)spaceID NS_SWIFT_NAME(deleteSpace(_:));
// Moves a tab, with its Peek, to the top of another Space's list, or a pinned
// tab's bound tab, with its pin, to the end of that Space's pinned section,
// outside any folder (add-pinned-tabs-and-favorites design D5). Within a
// profile it keeps its
// page and its window. To a Space of another profile it
// reopens at its URL in that profile, without its Peek and without asking
// before leaving the page (add-profiles design D9). A window whose active tab
// it was shows the destination Space with the tab, or the tab reopened from
// it, active; another window showing a still of it picks its next tab as if
// it had closed there.
- (void)moveTab:(ClairTabID)tabID toSpace:(ClairSpaceID)spaceID NS_SWIFT_NAME(move(tab:toSpace:));

// --- Pinned tabs, folders and favorites (add-pinned-tabs-and-favorites
// design D1 to D6, D10; add-tab-folders design D1 to D3, D7, D8, D11) ---
// A pin is a saved item, kept in Chromium's Local State whether or not a page
// is open: a pinned tab belongs to a Space, a favorite to a profile. While its
// page is open, one tab is bound to it. A Space's pinned section lists items,
// each a pinned tab or a folder; a folder holds pinned tabs only, one level
// deep. Changes reach every observer through
// -[ClairSpacesObserver pinnedItemsDidChange:inSpace:] and
// -favoritesDidChange:ofProfile:. A place in a Space's pinned section is an
// index among its items, pins and folders alike, or, with a folder, an index
// among the folder's pins; a place among favorites is an index among them. An
// index past the end means the end. Every call naming a pin, folder, tab,
// Space or profile that doesn't exist, or a tab of an incognito or guest
// window, does nothing.

// A Space's pinned items, in its order. Empty for an unknown Space.
- (NSArray<id<ClairPinnedItem>> *)pinnedItemsInSpace:(ClairSpaceID)spaceID
    NS_SWIFT_NAME(pinnedItems(inSpace:));
// A profile's favorites, in its order. Empty for an unknown profile.
- (NSArray<id<ClairPin>> *)favoritesOfProfile:(ClairProfileID)profileID
    NS_SWIFT_NAME(favorites(ofProfile:));

// Pins a Today tab at `index` in its Space's pinned section, or in
// `folderID`, a folder of that Space (D5): the pin takes the tab's URL as its
// pinned URL, its title, icon and custom name, and the tab, with its Peek,
// stays open and bound to it. A folder of another Space is ignored.
- (void)pinTab:(ClairTabID)tabID
      inFolder:(nullable ClairFolderID)folderID
       atIndex:(NSInteger)index NS_SWIFT_NAME(pin(tab:inFolder:at:));
// Makes a Today tab a favorite of its profile at `index`, as
// -pinTab:inFolder:atIndex: does.
- (void)favoriteTab:(ClairTabID)tabID atIndex:(NSInteger)index NS_SWIFT_NAME(favorite(tab:at:));
// Moves a pinned tab or favorite to `index` in `spaceID`'s pinned section, or
// in `folderID`, a folder of that Space, with its bound tab: within a Space it
// reorders, or moves into or out of a folder, and a favorite becomes a pinned
// tab. A folder of another Space is ignored. To a Space of another profile,
// the bound tab reopens at its URL in that profile, bound to the pin
// (add-profiles design D9).
- (void)movePin:(ClairPinID)pinID
        toSpace:(ClairSpaceID)spaceID
         folder:(nullable ClairFolderID)folderID
        atIndex:(NSInteger)index NS_SWIFT_NAME(movePin(_:toSpace:folder:at:));
// Moves a pinned tab or favorite to `index` among the favorites of its
// profile (a pinned tab's is its Space's), with its bound tab.
- (void)movePin:(ClairPinID)pinID toFavoritesAtIndex:(NSInteger)index
    NS_SWIFT_NAME(movePin(_:toFavoritesAt:));
// Removes a pinned tab or favorite and closes its bound tab, if any, with its
// leave-page confirmation. Restore Last Closed Tab brings it back in place,
// in its folder while the folder exists (D3, add-tab-folders design D7).
- (void)removePin:(ClairPinID)pinID NS_SWIFT_NAME(removePin(_:));
// Loads the pinned URL in the bound tab as a new navigation, so Back returns
// (D6).
- (void)returnToPinnedURL:(ClairPinID)pinID NS_SWIFT_NAME(returnToPinnedURL(_:));
// Makes the bound tab's current URL, title and icon the pin's.
- (void)replacePinnedURLWithCurrent:(ClairPinID)pinID NS_SWIFT_NAME(replacePinnedURLWithCurrent(_:));
// Sets the pinned URL. Ignored unless it is an http, https, file or chrome
// URL; ClairUI fixes up what the user typed first.
- (void)setPinnedURL:(NSURL *)url forPin:(ClairPinID)pinID NS_SWIFT_NAME(setPinnedURL(_:forPin:));
// Gives a tab, pinned tab or favorite a custom name, which the sidebar and the
// window's title show in place of its page's title (design D8). Nil, or a
// name that is empty once trimmed, clears it. A bound tab's name is its pin's.
- (void)setName:(nullable NSString *)name forTab:(ClairTabID)tabID NS_SWIFT_NAME(setName(_:forTab:));
- (void)setName:(nullable NSString *)name forPin:(ClairPinID)pinID NS_SWIFT_NAME(setName(_:forPin:));
// Closes every Today tab of the Space in every window, each with its
// leave-page confirmation, as Close Tabs Below does. Pinned tabs and favorites
// stay as they are (D4).
- (void)clearTodayInSpace:(ClairSpaceID)spaceID NS_SWIFT_NAME(clearToday(inSpace:));

// --- Folders (add-tab-folders design D1 to D3, D6 to D8, D11) ---

// Adds an empty folder named `name` at `index` among `spaceID`'s pinned
// items and returns its ID. A new folder is open. An empty name, once
// trimmed, or an unknown Space is ignored, and returns nil.
- (nullable ClairFolderID)createFolderNamed:(NSString *)name
                                    inSpace:(ClairSpaceID)spaceID
                                    atIndex:(NSInteger)index
    NS_SWIFT_NAME(createFolder(named:inSpace:at:));
// Renames a folder. An empty name, once trimmed, is ignored.
- (void)renameFolder:(ClairFolderID)folderID to:(NSString *)name NS_SWIFT_NAME(renameFolder(_:to:));
// Opens or closes a folder in every window of this Mac, and keeps it so
// across launches (D3). It isn't part of the folder's record.
- (void)setFolder:(ClairFolderID)folderID open:(BOOL)open NS_SWIFT_NAME(setFolder(_:open:));
// Moves a folder, with its pins and their bound tabs, to `index` among
// `spaceID`'s pinned items: within its Space it reorders. Bound tabs move as
// -movePin:toSpace:folder:atIndex: moves them, across profiles too, and a
// window whose active tab was one of them shows the Space (D11).
- (void)moveFolder:(ClairFolderID)folderID
           toSpace:(ClairSpaceID)spaceID
           atIndex:(NSInteger)index NS_SWIFT_NAME(moveFolder(_:toSpace:at:));
// Adds a copy of the folder right after it, open, with a copy of each of its
// pins in order: their pinned URLs, titles, names and icons, none open (D11).
- (void)duplicateFolder:(ClairFolderID)folderID NS_SWIFT_NAME(duplicateFolder(_:));
// Removes a folder and its pins, then closes their bound tabs, each with its
// leave-page confirmation. Restore Last Closed Tab brings the folder back with
// its pins, in place (D7). ClairUI asks the user first when it has pins.
- (void)deleteFolder:(ClairFolderID)folderID NS_SWIFT_NAME(deleteFolder(_:));
// Close This Folder: closes the bound tab of each of the folder's pins, in
// whichever window holds it, each with its leave-page confirmation, as
// -clearTodayInSpace: does. The pins stay.
- (void)closeTabsInFolder:(ClairFolderID)folderID NS_SWIFT_NAME(closeTabs(inFolder:));
// Adds a Space after the last, named after the folder, without an icon, using
// the folder's Space's profile; makes the folder's pins its pinned tabs, in
// order, with their bound tabs; removes the folder; and returns the new
// Space's ID, or nil when nothing changed (D8).
- (nullable ClairSpaceID)turnFolderIntoSpace:(ClairFolderID)folderID NS_SWIFT_NAME(turnFolderIntoSpace(_:));

// --- Profiles (add-profiles design D1, D7, D9 and D11) ---
// A profile is a Chromium profile: its own cookies, history, logins,
// extensions and downloads. Every Space uses one, and several Spaces may use
// the same one. There is always at least one profile. Changes reach every
// observer through -[ClairSpacesObserver profilesDidChange:].

// Every profile, in Chromium's order: the default profile first, then by name.
@property(nonatomic, readonly, copy) NSArray<id<ClairProfile>> *profiles;

// Creates a profile named `name`, with no Spaces, and calls `completion` with
// its ID once it exists, or with nil when it couldn't be created. An empty
// name is ignored, and calls `completion` with nil at once.
- (void)createProfileNamed:(NSString *)name
                completion:(void (^)(ClairProfileID _Nullable profileID))completion
    NS_SWIFT_NAME(createProfile(named:completion:));
// Renames a profile. An empty name is ignored. Its Spaces keep their names.
- (void)renameProfile:(ClairProfileID)profileID to:(NSString *)name NS_SWIFT_NAME(renameProfile(_:to:));
// Deletes a profile, its data folder and its favorites. Ignored for a profile
// a Space uses, and so for the last one. ClairUI asks the user first.
- (void)deleteProfile:(ClairProfileID)profileID NS_SWIFT_NAME(deleteProfile(_:));

// Makes a Space use another profile. Its tabs, in their order, reopen at their
// URLs in that profile, without their Peeks and without asking before leaving
// their pages; in each window showing the Space, the tab reopened from its
// active one becomes active (add-profiles design D9). Its pinned tabs stay, and
// those with an open page reopen bound to them (add-pinned-tabs-and-favorites
// design D5). ClairUI asks the user first when the Space has open tabs. Ignored for an unknown Space or profile, and
// for the profile the Space uses.
- (void)setProfile:(ClairProfileID)profileID forSpace:(ClairSpaceID)spaceID
    NS_SWIFT_NAME(setProfile(_:forSpace:));

// A profile's download location, read from its prefs, loading the profile if
// it isn't loaded yet: `directory` is the folder its downloads are saved to,
// and `asksWhereToSave` whether each download asks instead. `completion` runs
// once, on the main thread, with a nil `directory` for an unknown profile.
- (void)downloadSettingsForProfile:(ClairProfileID)profileID
                        completion:(void (^)(NSURL *_Nullable directory, BOOL asksWhereToSave))completion
    NS_SWIFT_NAME(downloadSettings(forProfile:completion:));
// Saves a profile's downloads to `directory`, and stops asking where to save.
- (void)setDownloadDirectory:(NSURL *)directory forProfile:(ClairProfileID)profileID
    NS_SWIFT_NAME(setDownloadDirectory(_:forProfile:));
// Makes each download of a profile ask where to save, or stop asking.
- (void)setAsksWhereToSave:(BOOL)asks forProfile:(ClairProfileID)profileID
    NS_SWIFT_NAME(setAsksWhereToSave(_:forProfile:));

// Opens `url` in a new foreground tab of a Space using `profileID`: in the
// most recently active browser window, or a new one if none is open, showing
// the Space of that profile it showed most recently, or else the profile's
// first Space. Ignored for a profile no Space uses.
- (void)openURL:(NSURL *)url inProfile:(ClairProfileID)profileID NS_SWIFT_NAME(open(_:inProfile:));

// --- Link rules (add-link-rules design D1, D3 and D4) ---
// The rules that send links from other apps to a Space, app-wide and kept in
// Chromium's Local State. Chromium matches every http or https link that
// macOS hands it from outside against them, in order, and opens a matching
// link in the first matching rule's Space. A rule whose Space is deleted goes
// with it. Only the Link Rules dialog reads them, when it opens, so there is
// no observer.

// Every rule, in order.
@property(nonatomic, readonly, copy) NSArray<id<ClairLinkRule>> *linkRules;
// Replaces every rule with `rules`, in their order, copying each one's
// properties. A rule with an unknown match, a text that -isValidLinkRuleText:
// rejects or an unknown Space is dropped, as is one repeating an earlier
// rule's match and text.
- (void)replaceLinkRules:(NSArray<id<ClairLinkRule>> *)rules NS_SWIFT_NAME(replaceLinkRules(_:));
// Whether `text` can be a rule's text (D3): once trimmed, it is not empty,
// holds no whitespace, and reads, with "https://" in front when it has no
// scheme, as a valid http or https URL with a host.
- (BOOL)isValidLinkRuleText:(NSString *)text NS_SWIFT_NAME(isValidLinkRuleText(_:));

// --- App settings ---

// Whether Cmd+Q and Clair > Quit Clair ask first, in a dialog on the window
// (-[ClairWindow showQuitConfirmation]): Chromium's warn-before-quitting
// setting, on unless the user turned it off. Setting it applies at once.
@property(nonatomic) BOOL warnsBeforeQuitting;

// Quits as Clair > Quit Clair does, without the warn-before-quitting dialog.
// Chromium still asks about downloads in progress.
- (void)quitWithoutWarning;

@end

// ---------------------------------------------------------------------------
// The window contract (replace-browser-window design D3).
// ---------------------------------------------------------------------------

// The kind of profile a browser window shows.
typedef NS_ENUM(NSInteger, ClairProfileKind) {
  ClairProfileKindRegular = 0,
  // An off-the-record profile: the window uses a dark appearance and says
  // "Incognito" in its sidebar.
  ClairProfileKindIncognito = 1,
  // A guest profile.
  ClairProfileKindGuest = 2,
} NS_SWIFT_NAME(ProfileKind);

// What a tab is doing that the URL field shows as indicators. Each set bit is
// one indicator.
typedef NS_OPTIONS(NSUInteger, ClairTabIndicators) {
  ClairTabIndicatorsNone = 0,
  // The page is capturing the camera.
  ClairTabIndicatorsCamera = 1 << 0,
  // The page is capturing the microphone.
  ClairTabIndicatorsMicrophone = 1 << 1,
  // The page is using the user's location.
  ClairTabIndicatorsLocation = 1 << 2,
  // The page is capturing the screen, a window or a tab.
  ClairTabIndicatorsScreenCapture = 1 << 3,
  // A permission request from the page was blocked.
  ClairTabIndicatorsBlockedPermission = 1 << 4,
} NS_SWIFT_NAME(TabIndicators);

// Where something chosen in the window opens.
typedef NS_ENUM(NSInteger, ClairOpenDisposition) {
  // Navigates the active tab.
  ClairOpenDispositionCurrentTab = 0,
  // Opens a new active tab, at the top of the tab list.
  ClairOpenDispositionNewForegroundTab = 1,
  // Opens a new tab at the top of the tab list, leaving the active tab active.
  ClairOpenDispositionNewBackgroundTab = 2,
  // Opens a new browser window.
  ClairOpenDispositionNewWindow = 3,
} NS_SWIFT_NAME(OpenDisposition);

// Why the command bar is open.
typedef NS_ENUM(NSInteger, ClairCommandBarMode) {
  // Cmd+T, File > New Tab or the sidebar's "New Tab" row: opens empty, and
  // the choice opens in a new tab.
  ClairCommandBarModeNewTab = 0,
  // Cmd+L or a click on the URL field: opens on the active tab's full URL,
  // and the choice navigates the active tab.
  ClairCommandBarModeCurrentTab = 1,
} NS_SWIFT_NAME(CommandBarMode);

// The side DevTools is docked to in the card.
typedef NS_ENUM(NSInteger, ClairDevToolsDockSide) {
  // Not docked: DevTools is in its own window, or closed.
  ClairDevToolsDockSideNone = 0,
  ClairDevToolsDockSideRight = 1,
  ClairDevToolsDockSideBottom = 2,
  ClairDevToolsDockSideLeft = 3,
} NS_SWIFT_NAME(DevToolsDockSide);

// How the active tab's docked DevTools and its page share the card. This is
// Chromium's DevToolsContentsResizingStrategy: DevTools fills the card, and
// the page sits on top of it at `pageBounds`, as
// ApplyDevToolsContentsResizingStrategy() lays them out.
typedef struct NS_SWIFT_NAME(DevToolsLayout) {
  ClairDevToolsDockSide dockSide;
  // The page's bounds within the card, in points, with the origin at the
  // card's top-left corner. Empty, with `hidesPage` false, means that the
  // page fills the card.
  NSRect pageBounds;
  // DevTools asks for the page to be hidden.
  bool hidesPage;
} ClairDevToolsLayout;

// The state of find in page in the active tab.
typedef struct NS_SWIFT_NAME(FindResult) {
  // The 1-based position of the selected match, or 0 when there's none.
  NSInteger activeMatch;
  // How many matches the page has so far.
  NSInteger matchCount;
  // Whether the search has finished; until then, `matchCount` may grow.
  bool finished;
} ClairFindResult;

// A surface in the window that Chromium's bubbles attach to.
typedef NS_ENUM(NSInteger, ClairAnchorKind) {
  // The URL field's site-controls button: page info, permission prompts and
  // the popups of extensions that aren't pinned.
  ClairAnchorKindSiteControls = 0,
  // One of the URL field's indicators, named by the matching
  // ClairTabIndicators value.
  ClairAnchorKindIndicator = 1,
  // A pinned extension action's button, named by its extension ID.
  ClairAnchorKindExtensionAction = 2,
  // The downloads button.
  ClairAnchorKindDownloads = 3,
} NS_SWIFT_NAME(AnchorKind);

// The edge of an anchor rectangle that a bubble attaches to.
typedef NS_ENUM(NSInteger, ClairAnchorEdge) {
  // The rectangle's trailing edge: a control in the sidebar, with the bubble
  // to its right.
  ClairAnchorEdgeTrailing = 0,
  // The rectangle's bottom edge: the card's top-leading corner, used while the
  // sidebar is hidden, revealed as an overlay, or the window is in full screen.
  ClairAnchorEdgeBottom = 1,
} NS_SWIFT_NAME(AnchorEdge);

// Where a bubble attaches.
typedef struct NS_SWIFT_NAME(BubbleAnchor) {
  // The rectangle, in the window's coordinates (origin at the bottom left).
  NSRect rect;
  ClairAnchorEdge edge;
} ClairAnchor;

// What the user chose in an infobar.
typedef NS_ENUM(NSInteger, ClairInfobarAction) {
  ClairInfobarActionOK = 0,
  ClairInfobarActionCancel = 1,
  ClairInfobarActionLink = 2,
  // The infobar's close button.
  ClairInfobarActionDismiss = 3,
} NS_SWIFT_NAME(InfobarAction);

// What a suggestion in the command bar is.
typedef NS_ENUM(NSInteger, ClairSuggestionKind) {
  // A search with the default search engine, or with a keyword's engine.
  ClairSuggestionKindSearch = 0,
  // A URL as typed.
  ClairSuggestionKindURL = 1,
  // A page from history or the most visited sites.
  ClairSuggestionKindHistory = 2,
  // A tab open in this profile.
  ClairSuggestionKindOpenTab = 3,
  // A page the user bookmarked, whether bookmarks or history suggested it
  // (add-bookmarks-menu design D8). It never has an icon of its own.
  ClairSuggestionKindBookmark = 4,
} NS_SWIFT_NAME(SuggestionKind);

// Where a download is.
typedef NS_ENUM(NSInteger, ClairDownloadState) {
  ClairDownloadStateInProgress = 0,
  ClairDownloadStatePaused = 1,
  ClairDownloadStateComplete = 2,
  ClairDownloadStateCancelled = 3,
  // Failed, for example because the network dropped; it may be resumable.
  ClairDownloadStateInterrupted = 4,
} NS_SWIFT_NAME(DownloadState);

// The whole app's download progress, as the Dock shows it: the running
// downloads of every profile, paused ones included.
typedef struct {
  // How many downloads are running; with none, there's no progress to show.
  NSInteger count;
  // Whether any of them has an unknown size. The Dock then shows no ring.
  bool isIndeterminate;
  // Bytes received over bytes expected, for the downloads of known size.
  double fraction;
} ClairDownloadProgress NS_SWIFT_NAME(DownloadProgress);

// An infobar on a tab, such as "Clair is being controlled by automated test
// software" or an extension debugging the browser. Chromium implements it as
// a snapshot.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairInfobar)
@protocol ClairInfobar <NSObject>
// Unique among the tab's infobars while it shows.
@property(nonatomic, readonly) NSInteger infobarID;
// The infobar's text.
@property(nonatomic, readonly, copy) NSString *message;
// The link after the message, if it has one.
@property(nonatomic, readonly, copy, nullable) NSString *linkText;
// The default button's label, if it has one.
@property(nonatomic, readonly, copy, nullable) NSString *okButtonLabel;
// The other button's label, if it has one.
@property(nonatomic, readonly, copy, nullable) NSString *cancelButtonLabel;
// The icon before the message, if it has one.
@property(nonatomic, readonly, nullable) NSImage *icon;
@end

// A tab, as a snapshot of its state when Chromium posted it. Chromium
// implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairTab)
@protocol ClairTab <NSObject>
@property(nonatomic, readonly) ClairTabID tabID;
// The page's title, or what Chromium shows for a page without one.
@property(nonatomic, readonly, copy) NSString *title;
// The URL the tab shows, which is the pending URL while a navigation the user
// started hasn't committed, or nil when it has none or isn't a valid NSURL.
@property(nonatomic, readonly, copy, nullable) NSURL *url;
// The full URL formatted for people, as Chromium's omnibox shows it while
// editing: unescaped, with internationalized domain names in Unicode.
@property(nonatomic, readonly, copy) NSString *urlText;
// The URL's host formatted for people, with internationalized domain names in
// Unicode, or nil when the URL has no host.
@property(nonatomic, readonly, copy, nullable) NSString *displayHost;
// Whether the tab shows the new tab page.
@property(nonatomic, readonly) BOOL isNewTabPage;
// Whether Chromium rates the page as not secure (its WARNING and DANGEROUS
// security levels): plain HTTP, certificate errors, active mixed content.
@property(nonatomic, readonly) BOOL isNotSecure;
// The page's favicon, or nil while it has none, as on the new tab page.
@property(nonatomic, readonly, nullable) NSImage *favicon;
// Whether the tab is loading a new document in its main frame, the state in
// which Chromium's toolbar shows stop and its tab strip a spinner
// (WebContents::IsLoading() && ShouldShowLoadingUI()). A frame loading on its
// own or a same-document navigation doesn't count.
@property(nonatomic, readonly) BOOL isLoading;
// How far that load has got, from 0 to 1 (WebContents::GetLoadProgress()).
// Only meaningful while `isLoading`.
@property(nonatomic, readonly) double loadProgress;
// Whether back and forward can go anywhere.
@property(nonatomic, readonly) BOOL canGoBack;
@property(nonatomic, readonly) BOOL canGoForward;
// Whether the tab is playing sound, or has recently.
@property(nonatomic, readonly) BOOL isAudible;
// Whether the user muted the tab.
@property(nonatomic, readonly) BOOL isMuted;
// Whether the page's renderer crashed or was killed; the card shows the
// crashed-page view instead of the page.
@property(nonatomic, readonly) BOOL isCrashed;
// The indicators the URL field shows for the tab.
@property(nonatomic, readonly) ClairTabIndicators indicators;
// The tab's infobars, top first.
@property(nonatomic, readonly, copy) NSArray<id<ClairInfobar>> *infobars;
// The tab this one is a Peek of, or ClairTabIDNone for a normal tab
// (add-peek design D3). A Peek follows its parent directly in the tab order.
@property(nonatomic, readonly) ClairTabID peekParentID;
// The tab's Peek, or ClairTabIDNone.
@property(nonatomic, readonly) ClairTabID peekID;
// The Space the tab belongs to (add-spaces design D2). A Peek's is its
// parent's, and a pinned tab's its pin's. An incognito or guest tab's is its
// window's own Space. Empty for a favorite's tab, which belongs to its profile
// (add-pinned-tabs-and-favorites design D2).
@property(nonatomic, readonly, copy) ClairSpaceID spaceID;
// The browser window that holds the tab.
@property(nonatomic, readonly) ClairBrowserID browserID;
// The pin the tab is bound to, or nil for a Today tab, a Peek and an incognito
// or guest tab (add-pinned-tabs-and-favorites design D2).
@property(nonatomic, readonly, copy, nullable) ClairPinID pinID;
// The tab's custom name, which rows and the window's title show in place of
// `title`, or nil (design D8). A bound tab's is its pin's.
@property(nonatomic, readonly, copy, nullable) NSString *name;
@end

// A pinned tab or favorite, as a snapshot (add-pinned-tabs-and-favorites design
// D10). Chromium implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairPin)
@protocol ClairPin <NSObject>
@property(nonatomic, readonly, copy) ClairPinID pinID;
// Whether it is a favorite rather than a pinned tab.
@property(nonatomic, readonly) BOOL isFavorite;
// A pinned tab's Space, or nil for a favorite. A pin in a folder is in the
// folder's Space.
@property(nonatomic, readonly, copy, nullable) ClairSpaceID spaceID;
// The folder holding the pinned tab, or nil outside one and for a favorite
// (add-tab-folders design D2).
@property(nonatomic, readonly, copy, nullable) ClairFolderID folderID;
// A favorite's profile, or for a pinned tab its Space's.
@property(nonatomic, readonly, copy) ClairProfileID profileID;
// The pinned URL: what opens when the pin is selected without a page, and
// what Back to Pinned URL loads.
@property(nonatomic, readonly, copy) NSURL *url;
// The page's title when the bound tab was last at the pinned URL, or the URL
// formatted for people when there has never been one. Never empty.
@property(nonatomic, readonly, copy) NSString *title;
// The custom name, or nil (design D8).
@property(nonatomic, readonly, copy, nullable) NSString *name;
// The page's icon when the bound tab was last at the pinned URL, or nil.
@property(nonatomic, readonly, nullable) NSImage *icon;
// The bound tab, or ClairTabIDNone while the pin's page isn't open.
@property(nonatomic, readonly) ClairTabID tabID;
// The bound tab's snapshot and then its Peek's, if it has one; empty while
// unbound. Later changes reach ClairUI through -[ClairSpacesObserver
// tabDidChange:].
@property(nonatomic, readonly, copy) NSArray<id<ClairTab>> *tabs;
// Whether the bound tab is at the pinned URL: its committed URL, or the URL
// first requested before redirects, is the pinned URL, ignoring the fragment
// (design D2). YES while unbound.
@property(nonatomic, readonly) BOOL isAtPinnedURL;
@end

// A folder in a Space's pinned section, as a snapshot (add-tab-folders design
// D2). Chromium implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairFolder)
@protocol ClairFolder <NSObject>
@property(nonatomic, readonly, copy) ClairFolderID folderID;
@property(nonatomic, readonly, copy) ClairSpaceID spaceID;
// Never empty.
@property(nonatomic, readonly, copy) NSString *name;
// Whether it's open on this Mac (D3). A new folder is.
@property(nonatomic, readonly) BOOL isOpen;
// Its pinned tabs, in its order.
@property(nonatomic, readonly, copy) NSArray<id<ClairPin>> *pins;
@end

// One item of a Space's pinned section: a pinned tab or a folder; exactly one
// of the two is set (add-tab-folders design D2). Chromium implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairPinnedItem)
@protocol ClairPinnedItem <NSObject>
@property(nonatomic, readonly, nullable) id<ClairPin> pin;
@property(nonatomic, readonly, nullable) id<ClairFolder> folder;
@end

// A Space, as a snapshot (add-spaces design D9). Chromium implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairSpace)
@protocol ClairSpace <NSObject>
@property(nonatomic, readonly, copy) ClairSpaceID spaceID;
// Never empty.
@property(nonatomic, readonly, copy) NSString *name;
// One emoji, or nil.
@property(nonatomic, readonly, copy, nullable) NSString *icon;
// The profile the Space's tabs use (add-profiles design D2).
@property(nonatomic, readonly, copy) ClairProfileID profileID;
@end

// A profile, as a snapshot (add-profiles design D1). Chromium implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairProfile)
@protocol ClairProfile <NSObject>
@property(nonatomic, readonly, copy) ClairProfileID profileID;
// The name Chromium shows for it. Never empty.
@property(nonatomic, readonly, copy) NSString *name;
@end

// How a link rule matches a link's URL, ignoring its fragment
// (add-link-rules design D3).
typedef NS_ENUM(NSInteger, ClairLinkRuleMatch) {
  // "URLs containing": the URL contains the text, ignoring case.
  ClairLinkRuleMatchContains = 0,
  // "this exact URL": the URL is the text, read as a URL.
  ClairLinkRuleMatchExact = 1,
  // "URLs starting with": the URL starts with the text, read as a URL.
  ClairLinkRuleMatchPrefix = 2,
} NS_SWIFT_NAME(LinkRuleMatch);

// A link rule (add-link-rules design D4): links from other apps that match
// `text` as `match` says open in `spaceID`. Chromium implements it as a
// snapshot, and ClairUI as the rules it hands to -[ClairHost replaceLinkRules:].
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairLinkRule)
@protocol ClairLinkRule <NSObject>
@property(nonatomic, readonly) ClairLinkRuleMatch match;
// As the user typed it, trimmed: a domain or URL, with or without a scheme.
@property(nonatomic, readonly, copy) NSString *text;
@property(nonatomic, readonly, copy) ClairSpaceID spaceID;
@end

// A bookmark, as a snapshot (add-bookmarks-menu design D3). Chromium implements
// it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairBookmark)
@protocol ClairBookmark <NSObject>
@property(nonatomic, readonly) ClairBookmarkID bookmarkID;
// The bookmark's name, which the Bookmarks menu shows.
@property(nonatomic, readonly, copy) NSString *title;
// The bookmarked page, or nil when it isn't a valid NSURL.
@property(nonatomic, readonly, copy, nullable) NSURL *url;
// The folder that holds it: Other Bookmarks or one of its folders.
@property(nonatomic, readonly) ClairBookmarkFolderID folderID;
// Whether Bookmark This Page… has just added it, rather than found it already
// there. It picks the bookmark dialog's title.
@property(nonatomic, readonly) BOOL isNew;
@end

// A folder a bookmark can be saved in, as a snapshot (add-bookmarks-menu design
// D3). Chromium implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairBookmarkFolder)
@protocol ClairBookmarkFolder <NSObject>
@property(nonatomic, readonly) ClairBookmarkFolderID folderID;
// Chromium's name for it. ClairUI calls the folder at depth 0 "Bookmarks".
@property(nonatomic, readonly, copy) NSString *title;
// 0 for Other Bookmarks itself, 1 for its folders, and so on.
@property(nonatomic, readonly) NSInteger depth;
@end

// What ClairUI implements to hear about Spaces and their tabs, app-wide
// (add-spaces design D9). Chromium posts at most once per run-loop turn for
// each Space and each tab, and posts a Space's tab list before any window
// hears that one of its new tabs became active.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairSpacesObserver)
@protocol ClairSpacesObserver <NSObject>
// Spaces were added, removed, renamed, given an icon or reordered. `spaces`
// is the new list, in order.
- (void)spacesDidChange:(NSArray<id<ClairSpace>> *)spaces NS_SWIFT_NAME(spacesDidChange(_:));
// A Space's tabs were added, closed or moved, in any window. `tabs` is its
// new list, in order, as -[ClairHost tabsInSpace:] returns it.
- (void)tabsDidChange:(NSArray<id<ClairTab>> *)tabs inSpace:(ClairSpaceID)spaceID
    NS_SWIFT_NAME(tabsDidChange(_:inSpace:));
// One tab's state changed.
- (void)tabDidChange:(id<ClairTab>)tab NS_SWIFT_NAME(tabDidChange(_:));
// Profiles were created, renamed or deleted (add-profiles design D1).
// `profiles` is the new list, as -[ClairHost profiles] returns it. A change
// of a Space's profile arrives through -spacesDidChange:.
- (void)profilesDidChange:(NSArray<id<ClairProfile>> *)profiles NS_SWIFT_NAME(profilesDidChange(_:));
// A Space's pinned tabs or folders were added, removed, moved, renamed,
// edited, bound or unbound, a folder was opened or closed, or a pin's title,
// icon or place against its pinned URL changed (add-pinned-tabs-and-favorites
// design D10, add-tab-folders design D2). `items` is the new list, as
// -[ClairHost pinnedItemsInSpace:] returns it.
- (void)pinnedItemsDidChange:(NSArray<id<ClairPinnedItem>> *)items inSpace:(ClairSpaceID)spaceID
    NS_SWIFT_NAME(pinnedItemsDidChange(_:inSpace:));
// The same for a profile's favorites.
- (void)favoritesDidChange:(NSArray<id<ClairPin>> *)favorites ofProfile:(ClairProfileID)profileID
    NS_SWIFT_NAME(favoritesDidChange(_:ofProfile:));
@end

// A suggestion in the command bar. Chromium implements it as a snapshot of an
// AutocompleteMatch.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairSuggestion)
@protocol ClairSuggestion <NSObject>
// Unique within its autocomplete session.
@property(nonatomic, readonly) NSInteger suggestionID;
// What it is, which picks its icon when it has none of its own.
@property(nonatomic, readonly) ClairSuggestionKind kind;
// The row's title: the page's title, or the search terms.
@property(nonatomic, readonly, copy) NSString *contents;
// The row's second line, such as the URL, or empty.
@property(nonatomic, readonly, copy) NSString *descriptionText;
// Where choosing it goes, or nil if Chromium can't express it as an NSURL.
@property(nonatomic, readonly, copy, nullable) NSURL *destination;
// The page's favicon or the engine's icon, or nil to use the kind's icon.
@property(nonatomic, readonly, nullable) NSImage *icon;
// Whether a tab of this profile already shows the destination; choosing the
// suggestion then switches to that tab.
@property(nonatomic, readonly) BOOL hasTabMatch;
// The keyword of the search engine the suggestion offers to search with Tab,
// such as "wiki", or nil.
@property(nonatomic, readonly, copy, nullable) NSString *keyword;
// That engine's name, such as "Wikipedia", or nil.
@property(nonatomic, readonly, copy, nullable) NSString *keywordName;
// That engine's icon, which the field shows while its search is offered, or
// nil when the profile has none for it (yet: one that loads later comes in a
// new update of the same suggestions).
@property(nonatomic, readonly, nullable) NSImage *keywordIcon;
// Whether -deleteSuggestion: can delete it, such as a page from history or
// an earlier search. Always NO in the empty-query list.
@property(nonatomic, readonly) BOOL canDelete;
@end

// What a ClairExtensionPrompt asks.
typedef NS_ENUM(NSInteger, ClairExtensionPromptKind) {
  // Installing an extension. ClairUI words the sheet.
  ClairExtensionPromptKindInstall = 0,
  // Removing an extension. ClairUI words the sheet.
  ClairExtensionPromptKindRemove = 1,
  // Any other prompt, such as re-enabling an extension or an optional
  // permission request. The sheet uses Chromium's text.
  ClairExtensionPromptKindOther = 2,
} NS_SWIFT_NAME(ExtensionPromptKind);

// A confirmation for an extension. Chromium implements it as a snapshot.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairExtensionPrompt)
@protocol ClairExtensionPrompt <NSObject>
// Names the prompt in answers and dismissals.
@property(nonatomic, readonly) NSInteger promptID;
@property(nonatomic, readonly) ClairExtensionPromptKind kind;
@property(nonatomic, readonly, copy) NSString *extensionName;
@property(nonatomic, readonly, nullable) NSImage *icon;
// For ClairExtensionPromptKindRemove, the display name of the other extension
// that asked for the removal (chrome.management.uninstall); nil when the user
// started it or the extension is removing itself.
@property(nonatomic, readonly, copy, nullable) NSString *requestedByName;
// What the extension can do, one entry per permission. An entry's details
// follow it on their own lines, indented. Empty when there's nothing to list.
@property(nonatomic, readonly, copy) NSArray<NSString *> *permissions;
// Chromium's text, for ClairExtensionPromptKindOther; empty otherwise.
@property(nonatomic, readonly, copy) NSString *title;
@property(nonatomic, readonly, copy) NSString *permissionsHeading;
@property(nonatomic, readonly, copy) NSString *acceptLabel;
@property(nonatomic, readonly, copy) NSString *cancelLabel;
@end

// An extension's toolbar action. Chromium implements it as a snapshot.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairExtensionAction)
@protocol ClairExtensionAction <NSObject>
// The extension's ID, which names the action in commands.
@property(nonatomic, readonly, copy) NSString *extensionID;
// The extension's name, as chrome://extensions shows it (label-extensions-by-name
// design D1).
@property(nonatomic, readonly, copy) NSString *name;
// The action's title for the active tab, or the name when that's empty: the
// button's tooltip and VoiceOver label.
@property(nonatomic, readonly, copy) NSString *title;
// The action's icon for the active tab.
@property(nonatomic, readonly, nullable) NSImage *icon;
// The badge text for the active tab, or empty.
@property(nonatomic, readonly, copy) NSString *badgeText;
// The badge's colour, opaque, or nil for the default.
@property(nonatomic, readonly, nullable) NSColor *badgeBackgroundColor;
// The badge text's colour (chrome.action.setBadgeTextColor), or nil for one
// that contrasts with the background.
@property(nonatomic, readonly, nullable) NSColor *badgeTextColor;
// Whether the user pinned it to the sidebar.
@property(nonatomic, readonly) BOOL isPinned;
// Whether it can run on the active tab.
@property(nonatomic, readonly) BOOL isEnabled;
// Whether running it opens a popup.
@property(nonatomic, readonly) BOOL hasPopup;
@end

// A download of the window's profile from this session. Chromium implements
// it as a snapshot.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairDownload)
@protocol ClairDownload <NSObject>
// Chromium's download GUID.
@property(nonatomic, readonly, copy) NSString *downloadID;
// The name of the file it saves to.
@property(nonatomic, readonly, copy) NSString *fileName;
@property(nonatomic, readonly) ClairDownloadState state;
// How much has arrived, in bytes.
@property(nonatomic, readonly) int64_t receivedBytes;
// The total size, or 0 when it isn't known.
@property(nonatomic, readonly) int64_t totalBytes;
// Whether Chromium needs the user to keep or discard it, as for a dangerous
// file type, and what it says about it.
@property(nonatomic, readonly) BOOL needsDecision;
@property(nonatomic, readonly, copy, nullable) NSString *warningText;
// Whether an interrupted download can be resumed.
@property(nonatomic, readonly) BOOL canResume;
// Whether the user has opened it or seen it in the downloads list since it
// finished.
@property(nonatomic, readonly) BOOL isSeen;
@end

@protocol ClairAutocomplete;

// What the command bar implements to hear from its autocomplete session.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairAutocompleteDelegate)
@protocol ClairAutocompleteDelegate <NSObject>
// The suggestions changed, best first. Results arrive over time; `finished`
// says that no more will come for the current query. A list with the same
// suggestion IDs in the same order as the last one only adds icons, such as
// favicons fetched after the rows were first sent.
- (void)autocomplete:(id<ClairAutocomplete>)session
    didUpdateSuggestions:(NSArray<id<ClairSuggestion>> *)suggestions
                finished:(BOOL)finished
    NS_SWIFT_NAME(autocomplete(_:didUpdate:finished:));
@end

// One command bar session on Chromium's AutocompleteController for the
// window's profile (design D11). Chromium implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairAutocomplete)
@protocol ClairAutocomplete <NSObject>
// The search engine in keyword mode, after -acceptKeywordOfSuggestion:, or
// nil. Its name and icon show in the field. An icon that loads later comes
// with a new update of the suggestions.
@property(nonatomic, readonly, copy, nullable) NSString *keyword;
@property(nonatomic, readonly, copy, nullable) NSString *keywordName;
@property(nonatomic, readonly, nullable) NSImage *keywordIcon;

// Starts a query for `text`, replacing the one running. An empty `text` lists
// the window's tabs, most recently used first, then the most visited sites.
- (void)queryText:(NSString *)text NS_SWIFT_NAME(query(_:));

// Enters keyword mode for the suggestion's engine, as Tab does in the omnibox,
// and runs `text` against it.
- (void)acceptKeywordOfSuggestion:(NSInteger)suggestionID text:(NSString *)text
    NS_SWIFT_NAME(acceptKeyword(ofSuggestion:text:));

// Leaves keyword mode and runs `text` as a plain query.
- (void)clearKeywordWithText:(NSString *)text NS_SWIFT_NAME(clearKeyword(text:));

// Opens a suggestion from the latest results. A suggestion with a tab match
// switches to that tab instead, in its window.
- (void)openSuggestion:(NSInteger)suggestionID disposition:(ClairOpenDisposition)disposition
    NS_SWIFT_NAME(open(suggestion:disposition:));

// Deletes a suggestion from the latest results wherever Chromium keeps it,
// as the omnibox does, then sends the updated list. Ignored for a suggestion
// that can't be deleted.
- (void)deleteSuggestion:(NSInteger)suggestionID NS_SWIFT_NAME(delete(suggestion:));

// Ends the session. It sends nothing more, and ignores every later call.
- (void)stop;
@end

// Which way a history menu goes from the active tab's current page.
typedef NS_ENUM(NSInteger, ClairHistoryDirection) {
  ClairHistoryDirectionBack = 0,
  ClairHistoryDirectionForward = 1,
} NS_SWIFT_NAME(HistoryDirection);

// What an item in a history menu is.
typedef NS_ENUM(NSInteger, ClairHistoryItemKind) {
  // A page in the tab's history.
  ClairHistoryItemKindPage = 0,
  // "Show Full History", which opens Chromium's history page. It comes last,
  // after a separator, and only outside incognito.
  ClairHistoryItemKindShowFullHistory = 1,
} NS_SWIFT_NAME(HistoryItemKind);

// An item in a history menu. Chromium implements it as a snapshot.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairHistoryItem)
@protocol ClairHistoryItem <NSObject>
// Unique within its menu session; names the item in -openItem:disposition:.
@property(nonatomic, readonly) NSInteger itemID;
@property(nonatomic, readonly) ClairHistoryItemKind kind;
// The page's title, or its URL when it has none; the item's label.
@property(nonatomic, readonly, copy) NSString *title;
// The page's URL, or nil for "Show Full History".
@property(nonatomic, readonly, copy, nullable) NSURL *url;
// The page's favicon, or nil while it has none yet; it may arrive later
// through -historyMenu:itemsDidChange:. Always nil for "Show Full History".
@property(nonatomic, readonly, nullable) NSImage *icon;
@end

@protocol ClairHistoryMenu;

// What ClairUI implements to hear from a history menu session.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairHistoryMenuDelegate)
@protocol ClairHistoryMenuDelegate <NSObject>
// The items changed: a favicon arrived, or the tab navigated. `items` is the
// whole list, which is empty when the tab can no longer go that way.
- (void)historyMenu:(id<ClairHistoryMenu>)menu itemsDidChange:(NSArray<id<ClairHistoryItem>> *)items
    NS_SWIFT_NAME(historyMenu(_:itemsDidChange:));
@end

// One back or forward history menu on Chromium's BackForwardMenuModel for the
// active tab (arc-navigation-feedback design D3). Chromium implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairHistoryMenu)
@protocol ClairHistoryMenu <NSObject>
// The pages in the session's direction, nearest first, up to Chromium's own
// menu's limit, then "Show Full History".
@property(nonatomic, readonly, copy) NSArray<id<ClairHistoryItem>> *items;
// Goes to an item's page in the active tab, or opens it as `disposition`
// says, as choosing it in Chromium's menu would. "Show Full History" ignores
// `disposition`. It ends the session.
- (void)openItem:(NSInteger)itemID disposition:(ClairOpenDisposition)disposition
    NS_SWIFT_NAME(open(item:disposition:));
// Ends the session without choosing. It sends nothing more, and ignores every
// later call.
- (void)close;
@end

// Where the window's close, minimize and zoom buttons go. The window ClairBrowser
// hands over adopts it, and AppKit's own title bar layout puts the buttons
// there, so no later title bar layout moves them. ClairUI sets it as the
// sidebar moves.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairWindowControls)
@protocol ClairWindowControls <NSObject>

// The close button's top-leading corner, from the window's top-leading corner,
// in points. The other buttons follow at AppKit's spacing.
@property(nonatomic) CGPoint windowControlsOrigin;

// Whether the buttons are hidden, as while the sidebar is hidden or a page is
// in full screen.
@property(nonatomic) BOOL windowControlsHidden;

@end

// One native browser window's browser: its tabs, pages and commands. Chromium
// implements it, one per native window, and keeps owning the browser.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairBrowser)
@protocol ClairBrowser <NSObject>

// The window Chromium created for this browser, which ClairUI styles and fills.
// It dispatches Chromium's commands and key equivalents, and adopts
// ClairWindowControls.
@property(nonatomic, readonly) NSWindow<ClairWindowControls> *window;

// The kind of profile the window's tabs use.
@property(nonatomic, readonly) ClairProfileKind profileKind;

// The window's ID, which its tabs carry as their `browserID`.
@property(nonatomic, readonly) ClairBrowserID browserID;

// The Space the window shows (add-spaces design D3). Its active tab always
// belongs to it: when another tab becomes active for any reason, the window
// shows that tab's Space, except while it shows a still (-stillTabID), whose
// placeholder tab belongs to no Space. Its rows are all of -[ClairHost
// tabsInSpace:], whichever window holds each (share-tabs-across-windows design
// D1). An incognito or guest window shows a Space of its own, which isn't in
// -[ClairHost spaces] and can't be switched, and lists only the tabs with its
// own `browserID`.
@property(nonatomic, readonly, copy) ClairSpaceID shownSpaceID;

// The active tab, or ClairTabIDNone. While the window shows a still, it is
// the hidden placeholder tab, which has no row.
@property(nonatomic, readonly) ClairTabID activeTabID;

// --- The still (share-tabs-across-windows design D2) ---
// When another window takes the tab this window shows, this window keeps a
// still of its page over a hidden placeholder tab, until it becomes key again
// (and takes the tab back), the user selects another row or Space, or the tab
// closes. -[ClairWindow stillDidChange] tells ClairUI when either changes.
// The tab the still shows, whose row stays highlighted, or ClairTabIDNone when
// the window shows no still.
@property(nonatomic, readonly) ClairTabID stillTabID;
// The page as it was when the tab left, without its Peek, or nil when the copy
// failed or there's no still. ClairUI draws it dimmed over the card, or dims
// the card alone when it is nil.
@property(nonatomic, readonly, nullable) NSImage *stillImage;

// The view holding a tab's page, or nil for an unknown tab. The card shows the
// active tab's view.
- (nullable NSView *)pageViewForTab:(ClairTabID)tabID NS_SWIFT_NAME(pageView(for:));

// The active tab's docked DevTools view, or nil when DevTools isn't docked,
// and how it shares the card with the page.
@property(nonatomic, readonly, nullable) NSView *devToolsView;
@property(nonatomic, readonly) ClairDevToolsLayout devToolsLayout;

// The extensions with an action, pinned ones first in the user's order.
@property(nonatomic, readonly, copy) NSArray<id<ClairExtensionAction>> *extensionActions;

// The window's profile's downloads from this session, newest first.
@property(nonatomic, readonly, copy) NSArray<id<ClairDownload>> *downloads;
// The whole app's download progress, as the Dock shows it.
@property(nonatomic, readonly) ClairDownloadProgress downloadProgress;

// --- Spaces ---
// Shows a Space (add-spaces design D3, share-tabs-across-windows design D3):
// activates the tab last active in it in this window unless another window
// shows it, or else the Space's most recently active tab that no window shows,
// taking it from the window that holds it, or else opens a new tab page in it
// with the command bar. Ignored for an unknown Space and in incognito and
// guest windows.
- (void)showSpace:(ClairSpaceID)spaceID NS_SWIFT_NAME(showSpace(_:));

// --- Tabs ---
// Every command naming a tab works on any tab of the window's rows, whichever
// window holds it (share-tabs-across-windows design D1 and D3).
// Makes the tab active. A tab another window holds moves here with its Peek,
// without reloading; if that window was showing it, it keeps a still.
- (void)activateTab:(ClairTabID)tabID NS_SWIFT_NAME(activate(tab:));
// Closes the tab, in whichever window holds it, with its leave-page
// confirmation. Closing the active tab first shows, in order, the tab the user
// selected it from, the row above or the row below in the window's Space
// (add-spaces design D4), taking it from another window if need be. A bound
// tab's pin stays, unbound (add-pinned-tabs-and-favorites design D2, D4).
- (void)closeTab:(ClairTabID)tabID NS_SWIFT_NAME(close(tab:));
// Closes every row below it in its Space, in whichever window holds each, each
// with its leave-page confirmation.
- (void)closeTabsBelowTab:(ClairTabID)tabID NS_SWIFT_NAME(closeTabs(below:));
// Moves the tab, with its Peek, to `index` in its Space's list, as
// -[ClairHost tabsInSpace:] counts it, Peeks included. The tab ends at
// `index` and its Peek right after it.
- (void)moveTab:(ClairTabID)tabID toIndex:(NSInteger)index NS_SWIFT_NAME(move(tab:to:));
// Opens a copy of the tab, with its history, as Chromium's Duplicate does.
- (void)duplicateTab:(ClairTabID)tabID NS_SWIFT_NAME(duplicate(tab:));
// Mutes or unmutes the tab.
- (void)setMuted:(BOOL)muted forTab:(ClairTabID)tabID NS_SWIFT_NAME(setMuted(_:tab:));

// --- Pins (add-pinned-tabs-and-favorites design D4, D5) ---
// Selects a pinned tab or favorite of the window's profile: activates its
// bound tab as -activateTab: does, or opens its pinned URL in a new tab bound
// to it. A pinned tab of another Space shows that Space. Ignored in incognito
// and guest windows.
- (void)openPin:(ClairPinID)pinID NS_SWIFT_NAME(openPin(_:));
// Unpins a pinned tab or favorite: the pin goes, and its bound tab, or a new
// one opened at its pinned URL in this window, joins the Today tabs of its
// Space (the shown Space for a favorite) at `index`, keeping the custom name.
- (void)unpin:(ClairPinID)pinID toIndex:(NSInteger)index NS_SWIFT_NAME(unpin(_:to:));

// --- Peek (add-peek design D3); `tabID` names the parent or its Peek ---
// Closes the tab's Peek, with its leave-page confirmation, and makes the
// parent active.
- (void)closePeekOfTab:(ClairTabID)tabID NS_SWIFT_NAME(closePeek(of:));
// Turns the tab's Peek into a normal, active tab directly below its parent.
- (void)expandPeekOfTab:(ClairTabID)tabID NS_SWIFT_NAME(expandPeek(of:));

// --- Navigation of the active tab: back, forward, reload (which also
// reloads a crashed page) and stop ---
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stop;

// Opens `url`, chrome:// URLs included.
- (void)openURL:(NSURL *)url disposition:(ClairOpenDisposition)disposition
    NS_SWIFT_NAME(open(_:disposition:));

// Starts a command bar session. Chromium keeps `delegate` weakly.
- (id<ClairAutocomplete>)startAutocompleteWithMode:(ClairCommandBarMode)mode
                                          delegate:(id<ClairAutocompleteDelegate>)delegate
    NS_SWIFT_NAME(startAutocomplete(mode:delegate:));

// Starts a history menu session for the active tab, or returns nil when the
// tab can't go that way. Chromium keeps `delegate` weakly. ClairUI starts one
// when the user opens the back or forward button's menu and closes it when
// the menu closes.
- (nullable id<ClairHistoryMenu>)startHistoryMenuWithDirection:(ClairHistoryDirection)direction
                                                      delegate:(id<ClairHistoryMenuDelegate>)delegate
    NS_SWIFT_NAME(startHistoryMenu(direction:delegate:));

// Gives the active tab's page keyboard focus, as when the command bar or find
// closes.
- (void)focusPage;

// --- Find in page, in the active tab ---
// Finds `text`, or the next match in `forward` direction when it's the same
// text as before. Results arrive through -[ClairWindow findResultDidChange:].
- (void)findText:(NSString *)text forward:(BOOL)forward NS_SWIFT_NAME(find(_:forward:));
// Ends find: clears the highlights and keeps the selected match selected.
- (void)stopFinding;

// --- Site controls ---
// Opens Chromium's page info for the active tab, attached to the site controls
// or to one indicator (`indicator` is ignored for other kinds).
- (void)showPageInfoAtAnchor:(ClairAnchorKind)kind indicator:(ClairTabIndicators)indicator
    NS_SWIFT_NAME(showPageInfo(at:indicator:));

// --- Extensions ---
// Runs the action as Chromium's toolbar would. Its popup, if any, comes back
// through -[ClairWindow showExtensionPopup:...], attached to `anchor`, which is
// ClairAnchorKindExtensionAction for a pinned action's tile, or
// ClairAnchorKindSiteControls.
- (void)runExtensionAction:(NSString *)extensionID anchor:(ClairAnchorKind)anchor
    NS_SWIFT_NAME(runExtensionAction(_:anchor:));
// Pins the action to the sidebar, or unpins it.
- (void)setExtensionAction:(NSString *)extensionID pinned:(BOOL)pinned
    NS_SWIFT_NAME(setExtensionAction(_:pinned:));
// The popup's popover closed, for example because the user clicked outside it.
- (void)extensionPopupDidClose;
// The extension's right-click menu, or nil if the extension is gone.
- (nullable NSMenu *)contextMenuForExtension:(NSString *)extensionID
    NS_SWIFT_NAME(contextMenu(forExtension:));
// The user answered a confirmation from -[ClairWindow showExtensionPrompt:],
// or its window closed, which counts as a cancel. Called once per prompt.
- (void)answerExtensionPrompt:(NSInteger)promptID accepted:(BOOL)accepted
    NS_SWIFT_NAME(answerExtensionPrompt(_:accepted:));

// --- Downloads: open a finished one in its default app (which counts as
// seen), reveal it in Finder, cancel it, or resume an interrupted one ---
- (void)openDownload:(NSString *)downloadID NS_SWIFT_NAME(openDownload(_:));
- (void)showDownloadInFinder:(NSString *)downloadID NS_SWIFT_NAME(showDownloadInFinder(_:));
- (void)cancelDownload:(NSString *)downloadID NS_SWIFT_NAME(cancelDownload(_:));
- (void)resumeDownload:(NSString *)downloadID NS_SWIFT_NAME(resumeDownload(_:));
// For a download that needs a decision: keep or discard it.
- (void)keepDownload:(NSString *)downloadID NS_SWIFT_NAME(keepDownload(_:));
- (void)discardDownload:(NSString *)downloadID NS_SWIFT_NAME(discardDownload(_:));
// The user looked at the downloads list: finished downloads count as seen.
- (void)markDownloadsSeen;

// --- Infobars ---
// The user chose one of the infobar's buttons, its link or its close button.
- (void)infobar:(NSInteger)infobarID ofTab:(ClairTabID)tabID didChoose:(ClairInfobarAction)action
    NS_SWIFT_NAME(infobar(_:tab:didChoose:));

// --- Bookmarks (add-bookmarks-menu design D3, D6) ---
// The bookmarks of the window's profile, or of its original profile in an
// incognito or guest window. Clair uses one list, Chromium's Other Bookmarks,
// and keeps the Bookmarks Bar empty. Bookmarks are added by the
// IDC_BOOKMARK_THIS_TAB command, which then calls -[ClairWindow
// showBookmarkDialog:]. Every call naming a bookmark or folder that no longer
// exists, as when it was removed while the dialog was open, does nothing.

// The folders a bookmark can be saved in, in the bookmark dialog's order:
// Other Bookmarks, then its folders, depth-first in their order. The Bookmarks
// Bar, managed bookmarks and Mobile Bookmarks aren't among them. Empty until
// the bookmarks have loaded.
@property(nonatomic, readonly, copy) NSArray<id<ClairBookmarkFolder>> *bookmarkFolders;
// Renames a bookmark and moves it to the end of `folderID`, one of
// -bookmarkFolders; a bookmark already there stays in place. An empty `title`
// becomes the page's title: the window's active tab's when it shows the
// bookmark's URL, or else the URL formatted for people. An unknown folder
// leaves it where it is.
- (void)updateBookmark:(ClairBookmarkID)bookmarkID
                 title:(NSString *)title
                folder:(ClairBookmarkFolderID)folderID
    NS_SWIFT_NAME(updateBookmark(_:title:folder:));
// Deletes a bookmark.
- (void)removeBookmark:(ClairBookmarkID)bookmarkID NS_SWIFT_NAME(removeBookmark(_:));
// Adds a folder named `title` at the end of Other Bookmarks and returns its
// ID. An empty `title`, once trimmed, is ignored and returns
// ClairBookmarkFolderIDNone, as before the bookmarks have loaded.
- (ClairBookmarkFolderID)addBookmarkFolder:(NSString *)title NS_SWIFT_NAME(addBookmarkFolder(_:));

// --- The window ---
// The window's close button. While another regular window of the profile is
// open, the window's tabs move to the most recently active one and no tab
// closes (share-tabs-across-windows design D4); otherwise it runs Chromium's
// close flow, with its beforeunload prompts, which may keep the window open.
- (void)requestClose;

@end

// One native browser window, drawn by ClairUI. ClairUI implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairWindow)
@protocol ClairWindow <NSObject>

// The view that holds the active page in the card. Tab-modal dialogs centre on
// it.
@property(nonatomic, readonly) NSView *pageContainerView;

// Whether the sidebar is hidden, for View > Hide Sidebar's title.
@property(nonatomic, readonly) BOOL isSidebarHidden;

// Whether Shift+clicking a link opens it in a Peek rather than a new window
// (add-peek design D10). Read each time a link opens.
@property(nonatomic, readonly) BOOL opensPeekOnShiftClick;

// Whether a link to another site clicked in a pinned tab's or favorite's page
// opens in a Peek rather than navigating it (add-pinned-tabs-and-favorites
// design D7). Read each time such a link opens.
@property(nonatomic, readonly) BOOL opensPeekForOtherSites;

// --- Peek ---
// The active Peek's page kept an Esc for itself. For `duration` seconds,
// another Esc closes the Peek; ClairUI shows Confirm for as long.
- (void)peekDidKeepEscape:(NSTimeInterval)duration NS_SWIFT_NAME(peekDidKeepEscape(for:));

// --- Tabs and Spaces ---
// The tabs themselves reach ClairUI through the host's ClairSpacesObserver.
// The window shows another Space (add-spaces design D3). `previousSpaceID` is
// the Space it showed before, or nil for none. It comes before the
// -activeTabDidChange: that shows the new Space's tab.
// `outgoingBrowserID` is the window this one's group swaps it in for
// (add-profiles design D3, D12), or ClairBrowserIDNone: the window then
// didn't show `previousSpaceID` itself, and takes the outgoing one's sidebar
// and open Manage Spaces. It comes before the window is ordered in.
- (void)shownSpaceDidChange:(ClairSpaceID)spaceID
                       from:(nullable ClairSpaceID)previousSpaceID
               swappedInFor:(ClairBrowserID)outgoingBrowserID
    NS_SWIFT_NAME(shownSpaceDidChange(_:from:swappedInFor:));
// Another tab became active; its page view is -[ClairBrowser pageViewForTab:].
- (void)activeTabDidChange:(ClairTabID)tabID NS_SWIFT_NAME(activeTabDidChange(_:));
// The active tab's docked DevTools view or layout changed.
- (void)devToolsDidChange;

// --- Quitting ---
// The user pressed Cmd+Q or chose Clair > Quit Clair while warnsBeforeQuitting
// is on, no download is in progress and this is the key browser window, or
// the most recently active one, which Chromium then activates. ClairUI asks in
// a dialog on the window and, if the user confirms, calls -[ClairHost
// quitWithoutWarning]. Another call while that dialog shows or waits does
// nothing.
- (void)showQuitConfirmation;

// --- Bookmarks (add-bookmarks-menu design D4, D6) ---
// Shows the bookmark dialog for `bookmark`, which Bookmarks > Bookmark This
// Page… or Edit Bookmark… (Shift+Cmd+B) has just added or found for the active
// tab's page. ClairUI saves and removes it through -[ClairBrowser
// updateBookmark:title:folder:] and -removeBookmark:.
- (void)showBookmarkDialog:(id<ClairBookmark>)bookmark NS_SWIFT_NAME(showBookmarkDialog(_:));
// Says, once for the whole app, that what was in a Bookmarks Bar has moved to
// the Bookmarks menu. ClairUI owns the text.
- (void)showBookmarksBarNotice;

// --- Commands ---
// Opens the command bar.
- (void)showCommandBarWithMode:(ClairCommandBarMode)mode NS_SWIFT_NAME(showCommandBar(mode:));
// View > Hide Sidebar and Cmd+S.
- (void)toggleSidebar;

// --- Find ---
// Opens the find field holding `text`, all selected, and focuses it.
- (void)showFindWithText:(NSString *)text NS_SWIFT_NAME(showFind(text:));
// Closes the find field.
- (void)hideFind;
// The match count or the selected match changed.
- (void)findResultDidChange:(ClairFindResult)result NS_SWIFT_NAME(findResultDidChange(_:));

// --- What the card shows ---
// The window started or stopped showing a still, or its image changed
// (-[ClairBrowser stillTabID] and -stillImage).
- (void)stillDidChange;
// The URL of the link under the pointer, or nil to hide the status capsule.
- (void)statusTextDidChange:(nullable NSString *)text NS_SWIFT_NAME(statusTextDidChange(_:));
// Shows a short confirmation at the bottom of the card, such as "Copied Link".
- (void)showToast:(NSString *)message NS_SWIFT_NAME(showToast(_:));
// The page asked for full screen, or left it: the card shows the page alone,
// with no sidebar, insets or corners. Chromium puts the window into macOS full
// screen itself.
- (void)pageFullscreenDidChange:(BOOL)fullscreen NS_SWIFT_NAME(pageFullscreenDidChange(_:));
// The exclusive-access notice, such as "Press Esc to exit full screen", or nil
// to hide it.
- (void)showExclusiveAccessNotice:(nullable NSString *)text NS_SWIFT_NAME(showExclusiveAccessNotice(_:));

// --- Chromium's bubbles ---
// Where a bubble for `kind` attaches now: the control in the sidebar, or the
// card's top-leading corner when the sidebar isn't shown in place.
// `indicator` names the indicator for ClairAnchorKindIndicator, and
// `extensionID` the action for ClairAnchorKindExtensionAction; other kinds
// ignore them. An indicator or action the sidebar doesn't show falls back to
// the site controls or the extensions button.
- (ClairAnchor)anchorForKind:(ClairAnchorKind)kind
                   indicator:(ClairTabIndicators)indicator
                 extensionID:(nullable NSString *)extensionID
    NS_SWIFT_NAME(anchor(for:indicator:extensionID:));

// --- Extensions ---
// The actions, pinned order, icons or badges changed.
- (void)extensionActionsDidChange:(NSArray<id<ClairExtensionAction>> *)actions
    NS_SWIFT_NAME(extensionActionsDidChange(_:));
// Shows an extension's popup page in a window beside `anchor`, at `size`.
- (void)showExtensionPopup:(NSView *)view
                      size:(NSSize)size
                 extension:(NSString *)extensionID
                    anchor:(ClairAnchorKind)anchor
    NS_SWIFT_NAME(showExtensionPopup(_:size:extension:anchor:));
// The popup page resized itself.
- (void)extensionPopupDidResize:(NSSize)size NS_SWIFT_NAME(extensionPopupDidResize(_:));
// Chromium closed the popup, for example because the extension called
// window.close().
- (void)closeExtensionPopup;
// Asks the user to confirm an install or removal, in a sheet on the window.
// ClairUI answers through -[ClairBrowser answerExtensionPrompt:accepted:].
- (void)showExtensionPrompt:(id<ClairExtensionPrompt>)prompt NS_SWIFT_NAME(showExtensionPrompt(_:));
// Chromium no longer needs the answer. ClairUI closes the sheet and doesn't
// answer. An ID that's already answered or dismissed does nothing.
- (void)dismissExtensionPrompt:(NSInteger)promptID NS_SWIFT_NAME(dismissExtensionPrompt(_:));

// --- Downloads ---
// One of the window's profile's downloads started, progressed, finished, or
// was opened or removed; the progress is the app-wide one at that moment.
- (void)downloadsDidChange:(NSArray<id<ClairDownload>> *)downloads
                  progress:(ClairDownloadProgress)progress NS_SWIFT_NAME(downloadsDidChange(_:progress:));
// The app-wide progress changed: a download of any profile, whether or not
// it has a window, started, progressed, paused or ended.
- (void)downloadProgressDidChange:(ClairDownloadProgress)progress NS_SWIFT_NAME(downloadProgressDidChange(_:));

// --- The window ---
// Chromium is closing the window. ClairUI lets go of its views and the
// browser; Chromium closes the NSWindow itself.
- (void)browserDidClose;

@end

// What ClairUI.framework's principal class (NSPrincipalClass) implements.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairUIEntryPoint)
@protocol ClairUIEntryPoint <NSObject>

// Called once, after Chromium has built the main menu. ClairUI keeps `host`
// for as long as the app runs.
+ (void)startWithHost:(id<ClairHost>)host NS_SWIFT_NAME(start(host:));

// Called for every normal browser window Chromium creates, incognito and guest
// windows included, after +startWithHost:. ClairUI styles `browser.window`,
// fills it and returns the window, which Chromium keeps until it closes. It
// never returns nil: Chromium stops on a nil window rather than showing its
// own.
+ (id<ClairWindow>)windowForBrowser:(id<ClairBrowser>)browser NS_SWIFT_NAME(window(for:));

@end

NS_ASSUME_NONNULL_END

#endif  // CLAIR_NATIVE_CLAIR_HOST_H_
