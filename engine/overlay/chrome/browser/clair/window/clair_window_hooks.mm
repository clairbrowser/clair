// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/window/clair_window_hooks.h"

#import <AppKit/AppKit.h>

#include <set>

#include "base/apple/foundation_util.h"
#include "base/files/file_path.h"
#include "base/no_destructor.h"
#include "base/values.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/common/pref_names.h"
#import "chrome/browser/clair/ClairHost.h"
#include "chrome/browser/clair/clair_bookmark_bar_drain.h"
#include "chrome/browser/clair/clair_link_rule_store.h"
#include "chrome/browser/clair/clair_native_layer.h"
#import "chrome/browser/clair/clair_pin_store.h"
#include "chrome/browser/clair/clair_profiles.h"
#include "chrome/browser/clair/clair_space_store.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#import "chrome/browser/clair/window/clair_native_window.h"
#include "chrome/browser/clair/window/clair_peeks.h"
#include "chrome/browser/clair/window/clair_splits.h"
#include "chrome/browser/headless/headless_mode_util.h"
#include "chrome/browser/prefs/session_startup_pref.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_delegate.h"
#include "components/autofill/core/common/autofill_prefs.h"
#include "components/download/public/common/download_item.h"
#include "components/password_manager/core/common/password_manager_pref_names.h"
#include "components/pref_registry/pref_registry_syncable.h"
#include "components/prefs/pref_registry_simple.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/download_item_utils.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/web_contents.h"
#include "ui/menus/simple_menu_model.h"
#include "url/gurl.h"

namespace {

// D17's prefs, all off.
constexpr const char* kOffPrefs[] = {
    password_manager::prefs::kCredentialsEnableService,
    password_manager::prefs::kCredentialsEnableAutosignin,
    autofill::prefs::kAutofillProfileEnabled,
    autofill::prefs::kAutofillCreditCardEnabled,
};

ClairBrowserWindow* KeyNativeWindow() {
  ClairNativeWindow* window =
      base::apple::ObjCCast<ClairNativeWindow>(NSApp.keyWindow);
  return window ? window.browserWindow : nullptr;
}

}  // namespace

// View > Hide Sidebar (D10): toggles the key native window's sidebar, and
// reads "Show Sidebar" while it's hidden.
@interface ClairSidebarMenuTarget : NSObject <NSMenuItemValidation>
@end

@implementation ClairSidebarMenuTarget

- (void)toggleSidebar:(id)sender {
  if (ClairBrowserWindow* window = KeyNativeWindow()) {
    [window->clair_window() toggleSidebar];
  }
}

- (BOOL)validateMenuItem:(NSMenuItem*)item {
  ClairBrowserWindow* window = KeyNativeWindow();
  id<ClairWindow> clair_window = window ? window->clair_window() : nil;
  item.title = clair_window.isSidebarHidden ? @"Show Sidebar" : @"Hide Sidebar";
  return clair_window != nil;
}

@end

namespace clair {

BrowserWindow* CreateNativeBrowserWindow(BrowserWindowInterface* browser) {
  if (!IsNativeLayerRunning() ||
      browser->GetType() != BrowserWindowInterface::Type::TYPE_NORMAL) {
    return nullptr;
  }
  // Browser is the only desktop BrowserWindowInterface.
  return new ClairBrowserWindow(static_cast<Browser*>(browser));
}

bool IsInNativeWindow(gfx::NativeView view) {
  NSView* ns_view = view.GetNativeNSView();
  return base::apple::ObjCCast<ClairNativeWindow>(ns_view.window) != nil;
}

void RemoveUnavailableContextMenuItems(ui::SimpleMenuModel* model) {
  for (size_t i = model->GetItemCount(); i > 0; --i) {
    switch (model->GetCommandIdAt(i - 1)) {
      case IDC_CONTENT_CONTEXT_OPEN_IN_READING_MODE:
      case IDC_CONTENT_CONTEXT_LISTEN_TO_THIS_PAGE:
      case IDC_CONTENT_CONTEXT_GENERATE_QR_CODE:
      case IDC_SEND_TAB_TO_SELF:
      case IDC_CONTENT_CONTEXT_LENS_REGION_SEARCH:
      case IDC_CONTENT_CONTEXT_SEARCHLENSFORIMAGE:
      case IDC_CONTENT_CONTEXT_TRANSLATE:
      case IDC_CONTENT_CONTEXT_PARTIAL_TRANSLATE:
        model->RemoveItemAt(i - 1);
        break;
      default:
        break;
    }
  }
  for (size_t i = model->GetItemCount(); i > 0; --i) {
    const size_t index = i - 1;
    if (model->GetTypeAt(index) != ui::MenuModel::TYPE_SEPARATOR) {
      continue;
    }
    const bool at_end = index == 0 || index + 1 == model->GetItemCount();
    const bool doubled =
        index + 1 < model->GetItemCount() &&
        model->GetTypeAt(index + 1) == ui::MenuModel::TYPE_SEPARATOR;
    if (at_end || doubled) {
      model->RemoveItemAt(index);
    }
  }
}

bool ShowQuitConfirmation() {
  ClairBrowserWindow* window = KeyNativeWindow();
  if (!window) {
    ForEachCurrentBrowserWindowInterfaceOrderedByActivation(
        [&](BrowserWindowInterface* browser) {
          window = ClairBrowserWindow::FromBrowser(browser);
          return window == nullptr;
        });
    if (!window) {
      return false;
    }
    window->Activate();
  }
  id<ClairWindow> clair_window = window->clair_window();
  if (!clair_window) {
    return false;
  }
  [clair_window showQuitConfirmation];
  return true;
}

bool IsNativeWindow(const BrowserWindowInterface* browser) {
  return browser && ClairBrowserWindow::FromBrowser(browser);
}

int NewTabIndex(const TabStripModel& model,
                int index,
                ui::PageTransition transition,
                int add_types) {
  TabStripModelDelegate* delegate = model.delegate();
  if (!delegate || !IsNativeWindow(delegate->GetBrowserWindowInterface())) {
    return -1;
  }
  const bool forced = add_types & AddTabTypes::ADD_FORCE_INDEX;
  const bool link = ui::PageTransitionTypeIncludingQualifiersIs(
      transition, ui::PAGE_TRANSITION_LINK);
  // A link without a forced position, or any tab with none, goes to the top.
  // Session restore and Reopen Closed Tab insert at their old positions and
  // don't come through here.
  if ((link && !forced) || index < 0) {
    return 0;
  }
  return -1;
}

bool UpdateDevTools(content::WebContents* inspected_contents) {
  ClairBrowserWindow* window =
      ClairBrowserWindow::FromWebContents(inspected_contents);
  if (!window) {
    return false;
  }
  if (window->browser()->tab_strip_model()->GetActiveWebContents() ==
      inspected_contents) {
    window->UpdateDevTools();
  }
  return true;
}

bool CanDockDevTools(content::WebContents* inspected_contents) {
  return ClairBrowserWindow::FromWebContents(inspected_contents) != nullptr;
}

gfx::Rect PageInfoAnchorRect(BrowserWindowInterface* browser) {
  ClairBrowserWindow* window = ClairBrowserWindow::FromBrowser(browser);
  return window ? window->SiteControlsAnchorInScreen() : gfx::Rect();
}

bool ShowToast(BrowserWindowInterface* browser, const std::u16string& text) {
  ClairBrowserWindow* window = ClairBrowserWindow::FromBrowser(browser);
  if (!window) {
    return false;
  }
  window->ShowToast(text);
  return true;
}

bool UpdateTargetURL(content::WebContents* source, const GURL& url) {
  ClairBrowserWindow* window = ClairBrowserWindow::FromWebContents(source);
  if (!window) {
    return false;
  }
  // The active page's links, or a split's other pane's (add-split-view
  // D13a).
  content::WebContents* active =
      window->browser()->tab_strip_model()->GetActiveWebContents();
  if (active && window->PagesShownWith(active).contains(source)) {
    window->SetStatusURL(url, source);
  }
  return true;
}

bool ContentsMouseEvent(content::WebContents* source, bool exited) {
  ClairBrowserWindow* window = ClairBrowserWindow::FromWebContents(source);
  if (!window) {
    return false;
  }
  if (exited) {
    window->SetStatusURL(GURL(), source);
  }
  return true;
}

namespace {

// The native window whose page `source` is, when Shift+click opens Peeks in
// it.
ClairBrowserWindow* PeekWindowFor(BrowserWindowInterface* browser,
                                  content::WebContents* source) {
  ClairBrowserWindow* window = ClairBrowserWindow::FromBrowser(browser);
  if (!window || !window->peeks() || !source ||
      window->browser()->tab_strip_model()->GetIndexOfWebContents(source) ==
          TabStripModel::kNoTab) {
    return nullptr;
  }
  id<ClairWindow> clair_window = window->clair_window();
  return clair_window && clair_window.opensPeekOnShiftClick ? window : nullptr;
}

}  // namespace

namespace {

// The native window whose page `source` is, for a link Option+clicked in it
// (add-split-view D6).
ClairBrowserWindow* SplitWindowFor(BrowserWindowInterface* browser,
                                   content::WebContents* source) {
  ClairBrowserWindow* window = ClairBrowserWindow::FromBrowser(browser);
  if (!window || !window->splits() || !source ||
      window->browser()->tab_strip_model()->GetIndexOfWebContents(source) ==
          TabStripModel::kNoTab) {
    return nullptr;
  }
  return window;
}

}  // namespace

bool MaybeOpenLink(BrowserWindowInterface* browser,
                   content::WebContents* source,
                   const content::OpenURLParams& params,
                   base::OnceCallback<void(content::NavigationHandle&)>&
                       navigation_handle_callback,
                   content::WebContents** result) {
  // add-split-view D6: Option+click (split-on-option-click.patch). From a
  // Peek or a split's pane it loads there or in the other pane; otherwise
  // Chromium makes the split.
  if (params.disposition == WindowOpenDisposition::NEW_SPLIT_VIEW) {
    ClairBrowserWindow* window = SplitWindowFor(browser, source);
    return window && window->splits()->OpenLink(
                         source, params, navigation_handle_callback, result);
  }
  // Shift+click is NEW_WINDOW on macOS; the context menu's Open Link in New
  // Window isn't renderer-initiated, and window.open() without a click has
  // no user gesture.
  if (params.disposition != WindowOpenDisposition::NEW_WINDOW ||
      !params.is_renderer_initiated || !params.user_gesture) {
    return false;
  }
  ClairBrowserWindow* window = PeekWindowFor(browser, source);
  if (!window) {
    return false;
  }
  *result =
      window->peeks()->OpenURL(source, params, navigation_handle_callback);
  return true;
}

bool MaybeOpenLink(BrowserWindowInterface* browser,
                   content::WebContents* source,
                   std::unique_ptr<content::WebContents>& new_contents,
                   const GURL& target_url,
                   WindowOpenDisposition disposition,
                   bool user_gesture,
                   content::WebContents** result) {
  if (disposition == WindowOpenDisposition::NEW_SPLIT_VIEW && user_gesture) {
    ClairBrowserWindow* window = SplitWindowFor(browser, source);
    return window &&
           window->splits()->OpenLink(source, new_contents, target_url, result);
  }
  // A link with a target, such as target="_blank", creates its contents
  // first and arrives here.
  if (disposition != WindowOpenDisposition::NEW_WINDOW || !user_gesture ||
      !new_contents) {
    return false;
  }
  ClairBrowserWindow* window = PeekWindowFor(browser, source);
  if (!window) {
    return false;
  }
  *result = window->peeks()->AddContents(source, std::move(new_contents),
                                         target_url, user_gesture);
  return true;
}

bool ShowNewDownload(download::DownloadItem* item) {
  BrowserWindowInterface* browser = nullptr;
  if (content::WebContents* contents =
          content::DownloadItemUtils::GetWebContents(item)) {
    browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents);
  }
  if (!browser) {
    // A download without a tab belongs to the last active window of its
    // profile.
    Profile* profile = Profile::FromBrowserContext(
        content::DownloadItemUtils::GetBrowserContext(item));
    ForEachCurrentBrowserWindowInterfaceOrderedByActivation(
        [&](BrowserWindowInterface* candidate) {
          if (profile && candidate->GetProfile()->GetOriginalProfile() ==
                             profile->GetOriginalProfile()) {
            browser = candidate;
            return false;
          }
          return true;
        });
  }
  // The sidebar's downloads button shows it; Chromium's bubble doesn't.
  return IsNativeWindow(browser);
}

void RegisterProfilePrefOverrides(user_prefs::PrefRegistrySyncable* registry) {
  for (const char* pref : kOffPrefs) {
    registry->SetDefaultPrefValue(pref, base::Value(false));
  }
}

void ApplyStartupPref(SessionStartupPref* pref) {
  if (pref && !headless::IsHeadlessMode()) {
    pref->type = SessionStartupPref::LAST;
  }
}

void RegisterLocalStatePrefs(PrefRegistrySimple* registry) {
  ClairSpaceStore::RegisterPrefs(registry);
  // add-pinned-tabs-and-favorites D1: the pins, beside the Spaces.
  ClairPinStore::RegisterPrefs(registry);
  // add-link-rules D1: the link rules, beside them.
  ClairLinkRuleStore::RegisterPrefs(registry);
  // add-bookmarks-menu D6: whether the Bookmarks Bar notice has shown, once
  // for the whole app.
  ClairBookmarkBarDrain::RegisterPrefs(registry);
  // add-tab-folders D13: the IDs the stores save for profiles.
  ClairProfiles::RegisterPrefs(registry);
  // add-profiles D1: Chromium's profile picker never shows at launch, however
  // many profiles exist (ProfilePicker::AvailabilityOnStartup::kDisabled).
  registry->SetDefaultPrefValue(prefs::kBrowserProfilePickerAvailabilityOnStartup,
                                base::Value(1));
}

void ApplyPasswordAndAutofillOverrides(Profile* profile) {
  static base::NoDestructor<std::set<base::FilePath>> applied;
  Profile* original = profile->GetOriginalProfile();
  if (!applied->insert(original->GetPath()).second) {
    return;
  }
  PrefService* prefs = original->GetPrefs();
  for (const char* pref : kOffPrefs) {
    // A 0.1.x profile may have turned them on; follow the new default.
    if (prefs->HasPrefPath(pref)) {
      prefs->ClearPref(pref);
    }
  }
}

void InstallNativeWindowMenus() {
  NSMenu* main_menu = NSApp.mainMenu;

  // add-profiles D10: no Profiles menu. ProfileMenuController sets its item's
  // `hidden` on every rebuild, so the item leaves the menu bar; the controller
  // keeps updating an item nobody sees.
  if (NSMenuItem* profiles = [main_menu itemWithTag:IDC_PROFILE_MAIN_MENU]) {
    [main_menu removeItem:profiles];
  }
  // add-tab-switcher-and-tabs-menu D5: no Tab menu; ClairUI's Tabs menu takes
  // its place. Deleted rather than hidden, as a hidden item still fires its
  // key equivalent (Ctrl+Tab, Search Tabs). AppController looks it up by tag
  // whenever a window becomes main: its TabMenuBridge then fills nil, and
  // -onVerticalTabStripModeChanged: returns early.
  if (NSMenuItem* tab_menu = [main_menu itemWithTag:IDC_TAB_MENU]) {
    [main_menu removeItem:tab_menu];
  }
  // add-profiles D10: Settings › Advanced replaces "Warn Before Quitting",
  // which has no tag; it's found by its action, with the separator after it.
  if (NSMenu* app_menu = main_menu.itemArray.firstObject.submenu) {
    NSInteger found = -1;
    for (NSMenuItem* item in app_menu.itemArray) {
      if (item.action == NSSelectorFromString(@"toggleConfirmToQuit:")) {
        found = [app_menu indexOfItem:item];
        break;
      }
    }
    if (found >= 0) {
      [app_menu removeItemAtIndex:found];
      if (found < app_menu.numberOfItems &&
          [app_menu itemAtIndex:found].separatorItem) {
        [app_menu removeItemAtIndex:found];
      } else if (found > 0 && [app_menu itemAtIndex:found - 1].separatorItem) {
        [app_menu removeItemAtIndex:found - 1];
      }
    }
  }

  // Hide the items of features the window doesn't host, and drop their key
  // equivalents, which a hidden item would still fire.
  NSMutableArray<NSMenu*>* menus = [NSMutableArray arrayWithObject:main_menu];
  NSMenuItem* save_page = nil;
  NSMenu* view_menu = [main_menu itemWithTag:IDC_VIEW_MENU].submenu;
  while (menus.count) {
    NSMenu* menu = menus.lastObject;
    [menus removeLastObject];
    for (NSMenuItem* item in menu.itemArray) {
      if (item.submenu) {
        [menus addObject:item.submenu];
      }
      if (ClairIsRemovedCommand(static_cast<int>(item.tag))) {
        item.hidden = YES;
        item.keyEquivalent = @"";
      }
      if (item.tag == IDC_SAVE_PAGE) {
        save_page = item;
      }
    }
  }

  // add-bookmarks-menu D1: the Bookmarks menu starts with Bookmark This
  // Page… on Shift+Cmd+B, then Manage Bookmarks. Chromium's two separators
  // around Bookmark This Tab… go: BookmarkMenuBridge deletes them at its first
  // rebuild anyway, and leaves fixed items where they are, so the order holds.
  // The loop above has cleared Cmd+D from the item, and Shift+Cmd+B from
  // View > Always Show Bookmarks Bar.
  if (NSMenu* bookmarks = [main_menu itemWithTag:IDC_BOOKMARKS_MENU].submenu) {
    for (NSMenuItem* item in bookmarks.itemArray) {
      if (item.separatorItem && item.tag == IDC_BOOKMARK_THIS_TAB) {
        [bookmarks removeItem:item];
      }
    }
    if (NSMenuItem* bookmark_page =
            [bookmarks itemWithTag:IDC_BOOKMARK_THIS_TAB]) {
      [bookmarks removeItem:bookmark_page];
      [bookmarks insertItem:bookmark_page atIndex:0];
      bookmark_page.keyEquivalent = @"b";
      bookmark_page.keyEquivalentModifierMask =
          NSEventModifierFlagCommand | NSEventModifierFlagShift;
    }
  }

  // Save Page As… moves to Shift+Cmd+S, as in Arc, and Cmd+S hides the
  // sidebar.
  save_page.keyEquivalent = @"s";
  save_page.keyEquivalentModifierMask =
      NSEventModifierFlagCommand | NSEventModifierFlagShift;

  static ClairSidebarMenuTarget* target = [[ClairSidebarMenuTarget alloc] init];
  if (view_menu && ![view_menu itemWithTag:kClairHideSidebarTag]) {
    NSMenuItem* hide_sidebar =
        [[NSMenuItem alloc] initWithTitle:@"Hide Sidebar"
                                   action:@selector(toggleSidebar:)
                            keyEquivalent:@"s"];
    hide_sidebar.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    hide_sidebar.tag = kClairHideSidebarTag;
    hide_sidebar.target = target;
    [view_menu insertItem:hide_sidebar atIndex:0];
    [view_menu insertItem:[NSMenuItem separatorItem] atIndex:1];
  }
}

}  // namespace clair
