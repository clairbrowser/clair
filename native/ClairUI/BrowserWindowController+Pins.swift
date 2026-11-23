// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// The window's pinned tabs, favorites and tab names
/// (add-pinned-tabs-and-favorites design D4 to D6, D8, D11).
extension BrowserWindowController {
  // MARK: Keeping the model up to date

  /// Reads the pins, the collapse and the favorites box again.
  func pinsChanged() {
    model.reloadPins()
    refreshPinPreferences()
    if let rename = model.renaming, !isListed(rename.row) {
      model.renaming = nil
    }
  }

  /// The collapse of the shown Space's pinned section and the favorites box,
  /// from the user's preferences. `animatingCollapse` animates a change of
  /// the collapse, and nothing else, as in Arc.
  func refreshPinPreferences(animatingCollapse: Bool = false) {
    let collapsed = model.showsPins && pinsPreferences.isCollapsed(model.shownSpaceID)
    if animatingCollapse && collapsed != model.isPinnedSectionCollapsed {
      withAnimation(SpaceHeaderView.collapseAnimation) { model.isPinnedSectionCollapsed = collapsed }
    } else {
      model.isPinnedSectionCollapsed = collapsed
    }
    guard model.showsPins, let profileID = model.profileID else {
      model.showsFavoritesHint = false
      return
    }
    // A profile that has had a favorite never shows the box again.
    if !model.favorites.isEmpty {
      pinsPreferences.finishFavoritesHint(for: profileID)
    }
    model.showsFavoritesHint = pinsPreferences.showsFavoritesHint(
      for: profileID, favoriteCount: model.favorites.count)
  }

  private func isListed(_ row: RowRename.Row) -> Bool {
    switch row {
    case .tab(let tabID): model.tabs.contains { $0.tabID == tabID }
    case .pin(let pinID): model.pins.contains { $0.pinID == pinID } || model.favorites.contains { $0.pinID == pinID }
    }
  }

  /// What the Tabs and View menus' Clair items act on.
  var pinMenuState: PinsLogic.MenuState {
    guard model.showsPins else { return PinsLogic.MenuState(showsPins: false) }
    let highlighted = model.highlightedTab
    let pin = model.pin(ofTab: highlighted)
    return PinsLogic.MenuState(
      showsPins: true,
      activeIsToday: pin == nil && TabListLogic.rows(model.tabs).contains { $0.tabID == highlighted },
      activePinIsFavorite: pin?.isFavorite,
      activePinIsNavigatedAway: pin.map(PinsLogic.isNavigatedAway) ?? false,
      todayRowCount: TabListLogic.rowCount(model.tabs),
      isCollapsed: model.isPinnedSectionCollapsed)
  }

  /// One of the main menu's Clair items.
  func perform(_ command: PinsLogic.MainMenuCommand) {
    let highlighted = model.highlightedTab
    switch command {
    case .togglePin:
      if let pin = model.pin(ofTab: highlighted) {
        if !pin.isFavorite {
          unpin(pin.pinID)
        }
      } else if highlighted != ClairTabIDNone {
        pin(tab: highlighted)
      }
    case .backToPinnedURL:
      if let pin = model.pin(ofTab: highlighted) {
        returnToPinnedURL(pin.pinID)
      }
    case .closeKeepingPin:
      if let pin = model.pin(ofTab: highlighted) {
        closeKeepingPin(pin.pinID)
      }
    case .clearToday:
      clearToday()
    case .toggleCollapse:
      togglePinnedSection()
    }
  }

  // MARK: PinActions

  func openPin(_ pinID: PinID) {
    guard let pin = model.spaces.pin(pinID) else {
      browser?.openPin(pinID)
      return
    }
    // A pinned tab with a Peek shows with its Peek (add-peek D4).
    if let tab = model.tab(ofPin: pin), tab.peekID != ClairTabIDNone {
      browser?.activate(tab: tab.peekID)
      return
    }
    browser?.openPin(pinID)
  }

  func pin(tab: TabID) {
    guard model.showsPins else { return }
    model.spaces.pin(tab: tab, at: model.pins.count)
  }

  func pinToFavorites(tab: TabID) {
    guard model.showsPins else { return }
    model.spaces.favorite(tab: tab, at: model.favorites.count)
  }

  func pinToFavorites(pin: PinID) {
    guard model.showsPins else { return }
    model.spaces.movePin(pin, toFavoritesAt: model.favorites.count)
  }

  func unpin(_ pinID: PinID) {
    browser?.unpin(pinID, to: 0)
  }

  func removePin(_ pinID: PinID) {
    model.spaces.removePin(pinID)
  }

  func closeKeepingPin(_ pinID: PinID) {
    guard let pin = model.spaces.pin(pinID), pin.tabID != ClairTabIDNone else { return }
    browser?.close(tab: pin.tabID)
  }

  func returnToPinnedURL(_ pinID: PinID) {
    model.spaces.returnToPinnedURL(pinID)
  }

  func replacePinnedURL(_ pinID: PinID) {
    model.spaces.replacePinnedURLWithCurrent(pinID)
  }

  func editPinnedURL(_ pinID: PinID) {
    guard let pin = model.spaces.pin(pinID) else { return }
    PinDialogs.showEditURL(of: pin, on: dialogs, spaces: model.spaces)
  }

  func copyLink(ofPin pinID: PinID) {
    guard let pin = model.spaces.pin(pinID) else { return }
    copyLinkToPasteboard(PinsLogic.link(of: pin))
  }

  func duplicate(pin pinID: PinID) {
    guard let pin = model.spaces.pin(pinID) else { return }
    if pin.tabID != ClairTabIDNone {
      browser?.duplicate(tab: pin.tabID)
    } else {
      // pinned-tabs spec: the same URL as a new Today tab at the top.
      browser?.open(pin.url, disposition: .newForegroundTab)
    }
  }

  func setMuted(_ muted: Bool, pin pinID: PinID) {
    guard let pin = model.spaces.pin(pinID), pin.tabID != ClairTabIDNone else { return }
    browser?.setMuted(muted, tab: pin.tabID)
  }

  func movePin(_ pinID: PinID, toSpace spaceID: SpaceID) {
    guard let space = model.spaces.space(spaceID), let pin = model.spaces.pin(pinID) else { return }
    let isActive = pin.tabID != ClairTabIDNone && pin.tabID == model.highlightedTab
    // spaces spec: at the end of the other Space's pinned section.
    model.spaces.movePin(pinID, toSpace: spaceID, at: Int.max)
    if !isActive {
      model.notice.show(
        Notice(text: SpacesLogic.movedNotice(space.name), identifier: Self.movedNoticeID),
        for: NoticeState.copiedDuration)
    }
  }

  func beginRenaming(_ rename: RowRename) {
    guard model.showsPins else { return }
    // Double-click selects the row too, as its first click did.
    model.renaming = rename
  }

  func endRenaming(_ row: RowRename.Row, change: PinsLogic.NameChange) {
    if model.renaming?.row == row {
      model.renaming = nil
    }
    let name: String?
    switch change {
    case .unchanged: return
    case .rename(let new): name = new
    case .clear: name = nil
    }
    switch row {
    case .tab(let tabID): model.spaces.setName(name, forTab: tabID)
    case .pin(let pinID): model.spaces.setName(name, forPin: pinID)
    }
  }

  func renameFavorite(_ pinID: PinID) {
    guard let pin = model.spaces.pin(pinID) else { return }
    PinDialogs.showRename(of: pin, on: dialogs, spaces: model.spaces)
  }

  func clearToday() {
    guard model.showsPins, TabListLogic.rowCount(model.tabs) > 0 else { return }
    model.spaces.clearToday(inSpace: model.shownSpaceID)
  }

  func togglePinnedSection() {
    guard model.showsPins else { return }
    pinsPreferences.setCollapsed(!model.isPinnedSectionCollapsed, for: model.shownSpaceID)
  }

  func dismissFavoritesHint() {
    guard let profileID = model.profileID else { return }
    pinsPreferences.finishFavoritesHint(for: profileID)
    model.showsFavoritesHint = false
  }

  func drop(_ item: SidebarDragItem, on target: SidebarDropTarget) {
    guard model.showsPins else {
      if case .tab(let tabID) = item, case .today(let index) = target {
        move(tab: tabID, to: index)
      }
      return
    }
    switch (item, target) {
    case (.tab(let tabID), .pinned(let index)):
      model.spaces.pin(tab: tabID, at: index)
    case (.tab(let tabID), .today(let index)):
      move(tab: tabID, to: index)
    case (.tab(let tabID), .favorites(let index)):
      model.spaces.favorite(tab: tabID, at: index)
    case (.pin(let pinID), .pinned(let index)):
      model.spaces.movePin(pinID, toSpace: model.shownSpaceID, at: index)
    case (.pin(let pinID), .today(let index)):
      browser?.unpin(pinID, to: index)
    case (.pin(let pinID), .favorites(var index)):
      // A favorite moved within the grid lands where it was dropped, the
      // others closing up behind it.
      if let from = model.favorites.firstIndex(where: { $0.pinID == pinID }), from < index {
        index -= 1
      }
      model.spaces.movePin(pinID, toFavoritesAt: index)
    }
  }
}
