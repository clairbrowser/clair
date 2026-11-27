// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// The window's recent tabs and Ctrl+Tab's switcher
/// (add-tab-switcher-and-tabs-menu design D1 to D4).
extension BrowserWindowController: TabSwitcherHost {
  /// Every tab the window can show from the switcher, by ID: every Space's
  /// tabs, pinned tabs and favorites, of every profile, as the recents span
  /// Spaces and follow a profile swap; an incognito or guest window's own.
  var switcherTabs: [TabID: any ClairTab] {
    var tabs: [TabID: any ClairTab] = [:]
    let spaces = model.spaces
    if model.showsSpaces {
      for space in spaces.spaces {
        for tab in spaces.tabs(inSpace: space.spaceID) { tabs[tab.tabID] = tab }
        for pin in spaces.pins(inSpace: space.spaceID) {
          for tab in pin.tabs { tabs[tab.tabID] = tab }
        }
      }
      for profile in spaces.profiles {
        for pin in spaces.favorites(ofProfile: profile.profileID) {
          for tab in pin.tabs { tabs[tab.tabID] = tab }
        }
      }
    }
    // The window's own, as last reported.
    for tab in model.allTabs { tabs[tab.tabID] = tab }
    return tabs
  }

  /// D1: the window showed another tab; its row moves to the front, or
  /// waits for the list that adds it. The still's placeholder never comes.
  func noteShownTab() {
    let tabID = model.activeTabID
    guard tabID != ClairTabIDNone else { return }
    pendingRecent = recents.show(tabID, in: switcherTabs) ? ClairTabIDNone : tabID
  }

  /// D1: tabs or pins changed somewhere: closed pages leave the recents, and
  /// the switcher closes when the shown tab did.
  func recentTabsChanged() {
    let tabs = switcherTabs
    recents.prune(in: tabs)
    if pendingRecent != ClairTabIDNone, pendingRecent == model.activeTabID, recents.show(pendingRecent, in: tabs) {
      pendingRecent = ClairTabIDNone
    }
    tabSwitcher.tabsDidChange(open: Set(tabs.keys))
  }

  // MARK: TabSwitcherHost

  var switcherWindow: NSWindow { window }

  var switcherMayAct: Bool {
    browser != nil && window.isKeyWindow && dialogs.showing == nil && window.attachedSheet == nil
  }

  /// The recents as the rows they are now: a tab that joined a split since
  /// counts as the split, which a tab's own update, not a list's, says.
  var recentTabIDs: [TabID] {
    recents.prune(in: switcherTabs)
    return recents.ids
  }

  func switcherCards(for entries: [TabID]) -> [SwitcherCard] {
    let tabs = switcherTabs
    return entries.compactMap { SwitcherCard.make($0, in: tabs) }
  }

  func requestSwitcherPreview(of tabID: TabID, size: NSSize, completion: @escaping (NSImage?) -> Void) {
    guard let browser else {
      completion(nil)
      return
    }
    browser.requestPreview(of: tabID, size: size, completion: completion)
  }

  func showFromSwitcher(_ tabID: TabID) {
    browser?.show(tab: tabID)
  }
}
