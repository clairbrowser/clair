// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_CLAIR_SPACE_TABS_H_
#define CHROME_BROWSER_CLAIR_CLAIR_SPACE_TABS_H_

#import <Foundation/Foundation.h>

#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "base/callback_list.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_multi_source_observation.h"
#include "base/supports_user_data.h"
#include "chrome/browser/clair/clair_pin_store.h"
#include "chrome/browser/clair/clair_space_store.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/infobars/core/infobar_manager.h"
#include "components/tabs/public/tab_interface.h"

#if !defined(__OBJC__)
#error "clair_space_tabs.h returns Objective-C snapshots; include it from .mm files"
#endif

#import "chrome/browser/clair/ClairHost.h"

class Browser;
class ClairBrowserWindow;
class SessionService;
class Profile;
class TabStripModel;

namespace content {
class WebContents;
}  // namespace content

// add-spaces design D2: one per profile. It observes the tab strip of every
// native window of the profile and keeps, for each Space, an ordered list of
// tab handles across all of them. The order is Clair's: the tab strip's order
// no longer means anything to the user, except that a Peek directly follows
// its parent. Each tab carries its Space as WebContents user data, which
// moves with it between windows and comes back with it from a session.
//
// It also owns what ClairUI hears about tabs (D9): their snapshots, and the
// Space lists and tab changes it pushes to the host's ClairSpacesObserver,
// coalesced to once per run-loop turn per Space and per tab.
//
// An off-the-record profile (incognito, guest) has no Spaces: all its tabs
// belong to one Space of its own, which isn't in ClairSpaceStore.
//
// add-pinned-tabs-and-favorites D2: a tab showing a pin's page is bound to the
// pin. It carries the pin's ID in its tag and in the session, and is in no
// Space's list: a pinned tab is listed with its pin, in the pin's order, and a
// favorite's tab belongs to the profile. A bound tab's Peek is in no list
// either; it follows its parent. A tab's custom name rides in its tag, or in
// its pin's record while bound.
class ClairSpaceTabs : public base::SupportsUserData::Data,
                       public TabStripModelObserver,
                       public infobars::InfoBarManager::Observer,
                       public clair::ClairPinStore::Observer {
 public:
  // The lists of `profile`'s tabs, created on first use.
  static ClairSpaceTabs* ForProfile(Profile* profile);
  // The lists holding `contents`, or null.
  static ClairSpaceTabs* ForWebContents(content::WebContents* contents);
  // Every profile's lists.
  static std::vector<ClairSpaceTabs*> All();
  // Pushes every profile's pending changes now, before a window hears that
  // its active tab changed (D9).
  static void FlushAll();

  // D6: a restored tab's Space and its place in the Space's list, read from
  // the session before the tab joins a strip.
  static void SetRestoredTag(content::WebContents* contents,
                             const std::string& space,
                             std::optional<int> rank);
  // add-profiles D6: the window group a restored tab's window belonged to.
  static void SetRestoredWindowTag(content::WebContents* contents,
                                   const std::string& group);
  // add-pinned-tabs-and-favorites D3: the pin a restored tab was bound to and
  // its custom name, read from the session before the tab joins a strip. A
  // new tab opened for a pin carries the pin the same way.
  static void SetRestoredPinTag(content::WebContents* contents,
                                const std::string& pin,
                                const std::string& name);
  static void SetPendingPin(content::WebContents* contents,
                            const std::string& pin);
  static std::string WindowTag(content::WebContents* contents);
  // add-profiles D6: the restored tab a window selected in place of the new
  // tab page session restore dropped. Taking it forgets it.
  static void SetRestoredNewTabWasSelected(content::WebContents* contents);
  static bool TakeRestoredNewTabWasSelected(content::WebContents* contents);
  // The tags session restore and Reopen Closed Tab need to put `contents`
  // back: its Space, its index in the Space's list, its window's group, its
  // pin and its name. Empty for a tab with no Space, as an incognito one.
  static std::map<std::string, std::string> SessionTags(
      content::WebContents* contents);

  // share-tabs-across-windows D2: a window's placeholder, the hidden new tab
  // page it shows under a still. It's in no Space and has no row or session
  // tags. MarkPlaceholder() runs before the tab joins a strip.
  static void MarkPlaceholder(content::WebContents* contents);
  static bool IsPlaceholder(content::WebContents* contents);

  explicit ClairSpaceTabs(Profile* profile);
  ClairSpaceTabs(const ClairSpaceTabs&) = delete;
  ClairSpaceTabs& operator=(const ClairSpaceTabs&) = delete;
  ~ClairSpaceTabs() override;

  Profile* profile() const { return profile_; }
  // Whether the profile's tabs belong to the user's Spaces.
  bool is_regular() const { return private_space_.empty(); }
  // An off-the-record profile's own Space; empty for a regular profile.
  const std::string& private_space() const { return private_space_; }

  // A native window of the profile opened or is closing.
  void AddBrowser(ClairBrowserWindow* window);
  void RemoveBrowser(ClairBrowserWindow* window);

  // The Space `contents` belongs to, or empty while it isn't listed: a Today
  // tab's, a bound pinned tab's pin's, or a Peek's parent's. A favorite's
  // tab, and its Peek, have none.
  std::string SpaceOf(content::WebContents* contents) const;
  std::string SpaceOf(const tabs::TabInterface* tab) const;
  // Whether `tab` has a row or follows one: a Today tab, a bound tab, or the
  // Peek of either.
  bool IsListed(const tabs::TabInterface* tab) const;

  // --- Pins (add-pinned-tabs-and-favorites D2 to D5) ---
  // The pin `tab` is bound to, or empty.
  std::string PinOf(const tabs::TabInterface* tab) const;
  // The tab bound to `pin` among the profile's, or null.
  tabs::TabInterface* BoundTab(std::string_view pin) const;
  // Whether `tab` is bound to a favorite.
  bool IsFavoriteTab(const tabs::TabInterface* tab) const;
  // The bound tabs of a Space's pinned tabs, its folders' included, in the
  // sidebar's order (add-tab-folders D9).
  std::vector<tabs::TabInterface*> PinnedTabsIn(const std::string& space) const;
  // The bound tabs of the profile's favorites, in their order.
  std::vector<tabs::TabInterface*> FavoriteTabs() const;
  // The tab's custom name: its pin's while bound, or its own.
  std::string NameOf(const tabs::TabInterface* tab) const;
  // Sets a Today tab's name, or its pin's while bound.
  void SetName(tabs::TabInterface* tab, const std::string& name);
  // D5: makes the Today row `tab` a pin at `index` in `container`, keeping
  // its page, its Peek and its name. Returns the pin's ID, or empty.
  std::string PinTab(tabs::TabInterface* tab,
                     const clair::PinContainer& container,
                     size_t index);
  // D5: the pin bound to `tab` is going: `tab`, with its Peek, joins
  // `space`'s Today list at `index`, keeping its name.
  void UnbindToToday(tabs::TabInterface* tab,
                     const std::string& space,
                     int index);
  // D2: whether `tab`'s page is at its pin's pinned URL.
  bool IsAtPinnedURL(const tabs::TabInterface* tab) const;
  // D7: the Peek of the bound `parent` was expanded into a tab: it joins the
  // top of the Today list of `space`.
  void PeekExpanded(tabs::TabInterface* peek, const std::string& space);
  // D5: `tab` is about to close as it reopens in another profile, bound to
  // its pin there: it lets go of the pin, and stays in no list.
  void UnbindForReopen(tabs::TabInterface* tab);
  // The Space `tab` belongs to, or will once it's listed: a tab restored from
  // a session or moved from another window carries its Space before the
  // lists hear of it, and Chromium may make it active first. Empty for a new
  // tab, which joins the Space its window shows.
  std::string IntendedSpaceOf(tabs::TabInterface* tab) const;
  // A Space's tabs in its order, Peeks included; with `browser`, only those
  // the browser holds.
  std::vector<tabs::TabInterface*> TabsIn(const std::string& space) const;
  std::vector<tabs::TabInterface*> TabsIn(const std::string& space,
                                          const Browser* browser) const;
  // The Spaces that have tabs here, in no particular order.
  std::vector<std::string> SpacesWithTabs() const;

  // A tab's snapshot for ClairUI.
  id<ClairTab> Snapshot(content::WebContents* contents) const;
  NSArray<id<ClairTab>>* Snapshots(const std::string& space) const;
  // A pin's snapshot, with its bound tab and Peek if they're this profile's.
  id<ClairPin> PinSnapshot(const clair::Pin& pin) const;

  // D2: moves `tab`, with its Peek, to `index` in its Space's list: the tab
  // ends at `index` and its Peek right after it. Touches no strip.
  void MoveTab(tabs::TabInterface* tab, int index);
  // D5: moves `tab`, with its Peek, to right after `anchor` and its Peek, or
  // to right before `anchor`. Both are rows of the same Space.
  void MoveTabBeside(tabs::TabInterface* tab,
                     tabs::TabInterface* anchor,
                     bool after);
  // D7: moves `tab`, with its Peek, to the top of `space`'s list.
  void SetSpace(tabs::TabInterface* tab, const std::string& space);
  // add-peek: `peek`, right after `parent` in the strip, became its Peek; it
  // joins the parent's Space, right after it.
  void PeekLinked(tabs::TabInterface* parent, tabs::TabInterface* peek);
  // D7: `space` was deleted; any tab still in it, as one whose leave-page
  // confirmation is up, joins `fallback`.
  void SpaceRemoved(const std::string& space, const std::string& fallback);

  // share-tabs-across-windows D1: between these, `tab` moves from one
  // window's strip to another's and keeps its Space and its place in it.
  void BeginMove(tabs::TabInterface* tab);
  void EndMove(tabs::TabInterface* tab);
  // D2: the placeholder `tab`, in `model`, becomes an ordinary tab at the top
  // of the Space its window shows.
  void ListPlaceholder(TabStripModel* model, tabs::TabInterface* tab);

  // What to push at the end of this run-loop turn.
  void ListChanged(const std::string& space);
  // Every list, as when its tabs' window changed group: their session tags
  // are written again.
  void AllListsChanged();
  void TabChanged(content::WebContents* contents);
  // Pushes now.
  void Flush();

  // TabStripModelObserver:
  void OnTabStripModelChanged(TabStripModel* model,
                              const TabStripModelChange& change,
                              const TabStripSelectionChange& selection) override;
  void OnTabChangedAt(tabs::TabInterface* tab,
                      TabChangeType change_type) override;
  void OnTabStripModelDestroyed(TabStripModel* model) override;

  // clair::ClairPinStore::Observer:
  void OnPinsChanged(const clair::PinContainer& container) override;

  // infobars::InfoBarManager::Observer:
  void OnInfoBarAdded(infobars::InfoBar* infobar) override;
  void OnInfoBarRemoved(infobars::InfoBar* infobar, bool animate) override;
  void OnInfoBarReplaced(infobars::InfoBar* old_infobar,
                         infobars::InfoBar* new_infobar) override;
  void OnManagerWillBeDestroyed(infobars::InfoBarManager* manager) override;

 private:
  class ProgressObserver;

  // Lists `tab`, just inserted at `index` in `model`, by D2's rules.
  void Insert(TabStripModel* model, tabs::TabInterface* tab, int index);
  // Takes `tab` out of its list, and unbinds it; returns its Space, or empty.
  std::string Remove(const tabs::TabInterface* tab);
  // add-pinned-tabs-and-favorites D2, D3: binds `tab`, with its Peek, to
  // `pin`, taking them out of any list. Returns whether it did: a pin that
  // isn't this profile's, or has a tab, stays as it is.
  bool Bind(tabs::TabInterface* tab, const std::string& pin);
  // The bound tab's pin changed: its row and snapshot are pushed again, and
  // its title and icon follow its page while it's at the pinned URL.
  void BoundTabUpdated(content::WebContents* contents);
  void BoundFaviconUpdated(content::WebContents* contents, NSImage* icon);
  // Pushes the pins of `tab`'s container.
  void BoundChanged(const tabs::TabInterface* tab);
  // D3: the pin the session records for `tab`: the one it's bound to, or the
  // one it was bound to before Remove Pin while that can come back.
  std::string SessionPinOf(const tabs::TabInterface* tab) const;
  // Takes `tab` out of its Space's list, leaving it bound; returns the Space.
  std::string RemoveFromLists(const tabs::TabInterface* tab);
  // Forgets `tab`'s binding. `keep_tag` keeps the pin in its tag, for
  // Restore Last Closed Tab.
  void Unbind(const tabs::TabInterface* tab, bool keep_tag);
  // Puts `tab`, with its Peek, in `space`'s Today list at `index`.
  void ListInToday(tabs::TabInterface* tab, const std::string& space, int index);
  // The Space a tab whose pin went joins: its own if it still exists, its
  // window's, or else OwnSpace().
  std::string FallbackSpaceFor(tabs::TabInterface* tab) const;
  // Whether `space` exists and uses this profile.
  bool IsOwnSpace(const std::string& space) const;
  // The Space of this profile a tab with none joins: the one a new window of
  // the profile shows, or clair.last_space while the profile has none.
  std::string OwnSpace() const;
  // `tab` and its Peek, if it has one in the same window.
  std::vector<tabs::TabInterface*> FamilyOf(tabs::TabInterface* tab) const;
  // Takes `tab`'s family out of `list` and returns its handles, in order.
  std::vector<tabs::TabHandle> TakeFamily(std::vector<tabs::TabHandle>& list,
                                          tabs::TabInterface* tab) const;
  // The window holding `model`, or null.
  ClairBrowserWindow* WindowFor(const TabStripModel* model) const;

  // Watches a tab's infobars and load progress.
  void Watch(content::WebContents* contents);
  void Unwatch(content::WebContents* contents);
  void InfobarChanged(infobars::InfoBar* infobar);

  // D6: records each tab's Space and index in the session where they changed.
  void WriteSessionTags(const std::string& space);
  // D6: session restore has created every window of `profile`; the restored
  // ranks have done their work.
  void SessionRestored(Profile* profile, int tab_count);
  // Records `tab`'s tags in the session if they changed; `rank` is its index
  // in its Today list, or -1 for a bound tab.
  void WriteTabTags(tabs::TabInterface* tab,
                    SessionService* service,
                    const std::string& space,
                    int rank);
  void PostFlush();

  const raw_ptr<Profile> profile_;
  std::string private_space_;
  std::map<std::string, std::vector<tabs::TabHandle>> lists_;
  // add-pinned-tabs-and-favorites D2: each bound pin's tab.
  std::map<std::string, tabs::TabHandle> bound_;
  // Bound tabs whose session tags may have changed.
  std::set<tabs::TabHandle> changed_bound_;
  std::vector<raw_ptr<ClairBrowserWindow>> windows_;
  // Tabs moving between windows (BeginMove).
  std::set<tabs::TabHandle> moving_;
  std::set<std::string> changed_spaces_;
  std::set<int32_t> changed_tabs_;
  bool flush_posted_ = false;
  base::CallbackListSubscription session_restored_subscription_;
  base::ScopedMultiSourceObservation<infobars::InfoBarManager,
                                     infobars::InfoBarManager::Observer>
      infobar_observations_{this};
  std::vector<std::unique_ptr<ProgressObserver>> progress_observers_;
  base::WeakPtrFactory<ClairSpaceTabs> weak_factory_{this};
};

namespace infobars {
class InfoBar;
}  // namespace infobars

namespace clair {

// The IDs ClairUI knows a tab and an infobar by: what a snapshot carries and
// what the bridge resolves.
ClairTabID TabIDOf(content::WebContents* contents);
NSInteger InfobarIDOf(const infobars::InfoBar* infobar);

// The host's Space calls (add-spaces design D9), for clair_native_layer.mm.
// They keep the store, the lists and the windows in step.

// Starts telling `observer` what changes; kept weakly.
void AddSpacesObserver(id<ClairSpacesObserver> observer);
// Every Space, as snapshots, in order.
NSArray<id<ClairSpace>>* SpaceSnapshots();
// A Space's tabs in every profile, or an off-the-record profile's own Space's.
NSArray<id<ClairTab>>* TabsInSpace(const std::string& space);
// Pushes a Space's tab list to the observers.
void NotifyTabsInSpace(const std::string& space);
// Pushes one tab's snapshot to the observers.
void NotifyTab(id<ClairTab> tab);
// Pushes the profiles to the observers (add-profiles D1).
void NotifyProfiles(NSArray<id<ClairProfile>>* profiles);
// D7.
void DeleteSpace(const std::string& space);
// D7, add-profiles D9: within a profile the tab keeps its page; to a Space of
// another profile it reopens there. Either way a window whose active tab it
// was shows the Space.
void MoveTabToSpace(tabs::TabInterface* tab, const std::string& space);
// add-profiles D9: makes `space` use `profile` and reopens its tabs there.
void SetSpaceProfile(const std::string& space, const std::string& profile);
// add-profiles D8: when the last-used profile has no Space, the profile of
// clair.last_space becomes the last-used one.
void KeepLastUsedProfileOnASpace();

// --- Pins (add-pinned-tabs-and-favorites design D2 to D6, D9, D10) ---
// The tab bound to `pin`, in any profile, or null.
tabs::TabInterface* BoundTabOf(std::string_view pin);
// A container's pins, as snapshots, in order.
NSArray<id<ClairPin>>* PinSnapshots(const PinContainer& container);
// add-tab-folders D2: a Space's pinned items, pins and folders, as snapshots,
// in order.
NSArray<id<ClairPinnedItem>>* PinnedItemSnapshots(const std::string& space);
// Pushes a container's pins to the observers at the end of this run-loop
// turn, or with the next FlushAll().
void PinsChanged(const PinContainer& container);
// The host's pin calls. `folder` is a folder of the tab's Space, or empty.
void PinTab(tabs::TabInterface* tab,
            const std::string& folder,
            size_t index,
            bool favorite);
void MovePin(const std::string& pin, const PinContainer& to, size_t index);
// add-tab-folders D7, D8, D11: the host's folder calls that reach tabs.
void MoveFolder(const std::string& folder,
                const std::string& space,
                size_t index);
void DuplicateFolder(const std::string& folder);
void DeleteFolder(const std::string& folder);
void CloseTabsInFolder(const std::string& folder);
// Returns the new Space's ID, or empty.
std::string TurnFolderIntoSpace(const std::string& folder);
void RemovePin(const std::string& pin);
void ReturnToPinnedURL(const std::string& pin);
void ReplacePinnedURLWithCurrent(const std::string& pin);
void SetPinnedURL(const std::string& pin, const GURL& url);
void SetPinName(const std::string& pin, const std::string& name);
void ClearToday(const std::string& space);
// The browser's pin calls, for `window`.
void OpenPin(ClairBrowserWindow* window, const std::string& pin);
void Unpin(ClairBrowserWindow* window, const std::string& pin, int index);
// D3: Restore Last Closed Tab in `window`: puts back the pin removed last, if
// that's newer than the newest entry Chromium would restore. Returns whether
// it did.
bool RestoreRemovedPin(ClairBrowserWindow* window);
// Whether `window` has a removed pin to put back.
bool HasRemovedPin(ClairBrowserWindow* window);
// Restore Last Closed Tab in `window`, which may show a Space of another
// profile than the tab or pin closed last (add-profiles D3): restores in the
// group's member whose profile closed something last, which the group then
// shows. Returns false when Chromium's own command should run in `window`.
bool RestoreLastClosed(ClairBrowserWindow* window);
// Whether Restore Last Closed Tab has anything to bring back in `window`'s
// group.
bool CanRestoreLastClosed(ClairBrowserWindow* window);
// D7: whether `url` is on another site than `current`: another scheme or
// host.
bool IsOtherSite(const GURL& url, const GURL& current);
// D7: whether a URL the user enters to open in `window`'s current tab opens
// in a new Today tab instead: the tab is a favorite's, and `url` is on
// another site.
bool LeavesFavorite(ClairBrowserWindow* window, const GURL& url);
// D8: every window's title follows its active tab's name.
void UpdateWindowTitles();

}  // namespace clair

#endif  // CHROME_BROWSER_CLAIR_CLAIR_SPACE_TABS_H_
