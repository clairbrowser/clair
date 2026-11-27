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
    beginNamingNewFolder()
  }

  /// add-tab-folders D6: a folder New Folder added gets its name field once
  /// it's listed, which may be with a later update than the call's.
  private func beginNamingNewFolder() {
    guard let folderID = pendingNewFolder, isListed(.folder(folderID)) else { return }
    pendingNewFolder = nil
    model.renaming = RowRename(row: .folder(folderID), selectsAll: true, caret: nil)
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
    case .folder(let folderID): model.pinnedItems.contains { $0.folder?.folderID == folderID }
    }
  }

  /// What the Tabs menu's pin items and View › Collapse Pinned Tabs act on.
  var pinMenuState: PinsLogic.MenuState {
    guard model.showsPins else { return PinsLogic.MenuState(showsPins: false) }
    // The row's highlight stays on a split's leading pane; the commands are
    // the focused pane's.
    let highlighted = model.highlightedTab
    let commandTab = model.commandTab
    let pin = model.pin(ofTab: commandTab)
    let rows = TabListLogic.rows(model.tabs)
    return PinsLogic.MenuState(
      showsPins: true,
      activeIsToday: pin == nil && rows.contains { $0.tabID == highlighted || $0.tabID == commandTab },
      activePinIsFavorite: pin?.isFavorite,
      todayRowCount: TabListLogic.rowCount(model.tabs),
      isCollapsed: model.isPinnedSectionCollapsed)
  }

  /// One of the Tabs menu's pin items, or View › Collapse Pinned Tabs.
  func perform(_ command: PinsLogic.MainMenuCommand) {
    let highlighted = model.commandTab
    switch command {
    case .togglePin:
      if let pin = model.pin(ofTab: highlighted) {
        if !pin.isFavorite {
          unpin(pin.pinID)
        }
      } else if highlighted != ClairTabIDNone {
        pin(tab: highlighted)
      }
    case .pinToFavorites:
      if let pin = model.pin(ofTab: highlighted) {
        if !pin.isFavorite {
          pinToFavorites(pin: pin.pinID)
        }
      } else if highlighted != ClairTabIDNone {
        pinToFavorites(tab: highlighted)
      }
    case .clearToday:
      clearToday()
    case .toggleCollapse:
      togglePinnedSection()
    case .newFolder:
      newFolderWithDialog()
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
    // At the end of the pinned section, outside any folder.
    model.spaces.pin(tab: tab, at: model.pinnedItems.count)
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
    case .folder(let folderID):
      // An empty name keeps the folder's (add-tab-folders D6).
      if let name { model.spaces.renameFolder(folderID, to: name) }
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
    case (.tab(let tabID), .folder(let folderID, let index)):
      model.spaces.pin(tab: tabID, inFolder: folderID, at: index)
    case (.tab(let tabID), .today(let index)):
      move(tab: tabID, to: index)
    case (.tab(let tabID), .favorites(let index)):
      model.spaces.favorite(tab: tabID, at: index)
    case (.pin(let pinID), .pinned(let index)):
      model.spaces.movePin(pinID, toSpace: model.shownSpaceID, at: index)
    case (.pin(let pinID), .folder(let folderID, let index)):
      model.spaces.movePin(pinID, toSpace: model.shownSpaceID, folder: folderID, at: index)
    case (.pin(let pinID), .today(let index)):
      browser?.unpin(pinID, to: index)
    case (.pin(let pinID), .favorites(var index)):
      // A favorite moved within the grid lands where it was dropped, the
      // others closing up behind it. The slot counts tiles, a split one, as
      // the engine's index does.
      if let from = model.favoriteItems.firstIndex(where: { item in
        PinsLogic.allPins([item]).contains { $0.pinID == pinID }
      }), from < index {
        index -= 1
      }
      model.spaces.movePin(pinID, toFavoritesAt: index)
    // add-tab-folders D4: a folder moves only within the pinned section's
    // top level; dropped anywhere else, it stays where it was.
    case (.folder(let folderID), .pinned(let index)):
      model.spaces.moveFolder(folderID, toSpace: model.shownSpaceID, at: index)
    case (.folder, _):
      break
    }
  }

  // MARK: Folders (add-tab-folders design D4, D6 to D8, D11)

  /// New Folder in the plus menu, the header's menu and the sidebar's: an
  /// open folder named "Untitled" at the end of the pinned section, whose
  /// name field shows once it's listed.
  func newFolder() {
    guard model.showsPins else { return }
    if model.isPinnedSectionCollapsed {
      pinsPreferences.setCollapsed(false, for: model.shownSpaceID)
    }
    guard
      let folderID = model.spaces.createFolder(
        named: PinsLogic.newFolderName, inSpace: model.shownSpaceID, at: model.pinnedItems.count)
    else { return }
    pendingNewFolder = folderID
    beginNamingNewFolder()
  }

  /// Tabs › New Folder…: asks for the name, then adds the folder, without a
  /// name field.
  func newFolderWithDialog() {
    guard model.showsPins else { return }
    let spaces = model.spaces
    let spaceID = model.shownSpaceID
    PinDialogs.showNewFolder(on: dialogs) { [weak self] name in
      guard let self else { return }
      if model.isPinnedSectionCollapsed && model.shownSpaceID == spaceID {
        pinsPreferences.setCollapsed(false, for: spaceID)
      }
      spaces.createFolder(named: name, inSpace: spaceID, at: spaces.pinnedItems(inSpace: spaceID).count)
    }
  }

  func toggleFolder(_ folderID: FolderID) {
    guard let folder = model.spaces.folder(folderID) else { return }
    model.spaces.setFolder(folderID, open: !folder.isOpen)
  }

  func closeTabs(inFolder folderID: FolderID) {
    model.spaces.closeTabs(inFolder: folderID)
  }

  /// D8: the window shows the new Space, with the switching animation.
  func turnFolderIntoSpace(_ folderID: FolderID) {
    guard let spaceID = model.spaces.turnFolderIntoSpace(folderID) else { return }
    showSpace(spaceID)
  }

  func duplicateFolder(_ folderID: FolderID) {
    model.spaces.duplicateFolder(folderID)
  }

  /// D11: at the end of the other Space's pinned section. A window whose
  /// active tab was in it follows it; otherwise a notice says where it went.
  func moveFolder(_ folderID: FolderID, toSpace spaceID: SpaceID) {
    guard let space = model.spaces.space(spaceID), let folder = model.spaces.folder(folderID) else { return }
    let highlighted = model.highlightedTab
    let holdsActive = highlighted != ClairTabIDNone && PinsLogic.pins(of: folder).contains { $0.tabID == highlighted }
    model.spaces.moveFolder(folderID, toSpace: spaceID, at: Int.max)
    if !holdsActive {
      model.notice.show(
        Notice(text: SpacesLogic.folderMovedNotice(space.name), identifier: Self.movedNoticeID),
        for: NoticeState.copiedDuration)
    }
  }

  /// D7: an empty folder goes at once; one with tabs asks first.
  func deleteFolder(_ folderID: FolderID) {
    guard let folder = model.spaces.folder(folderID) else { return }
    let spaces = model.spaces
    guard PinsLogic.folderDeletionNeedsConfirmation(folder) else {
      spaces.deleteFolder(folderID)
      return
    }
    dialogs.show(ClairDialog(PinDialogs.deleteFolderPage(name: folder.name))) { answer in
      if answer == .accepted {
        spaces.deleteFolder(folderID)
      }
    }
  }
}
