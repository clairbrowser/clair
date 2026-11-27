// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Foundation
import Testing

@testable import ClairUI

// MARK: The rows (add-tab-folders design D4)

@MainActor
struct FolderRowsTests {
  private func pin(_ title: String, tab: TabID = ClairTabIDNone, folder: FolderID? = nil) -> FakePin {
    let open = tab == ClairTabIDNone ? nil : FakeTab(id: tab, title: title, pinID: title)
    return FakePin(id: title, url: "https://\(title.lowercased()).example/", title: title, tab: open, folderID: folder)
  }

  private func folder(_ name: String, open: Bool = true, _ pins: [FakePin] = []) -> FakePinnedItem {
    FakePinnedItem(folder: FakeFolder(id: name, name: name, isOpen: open, pins: pins))
  }

  private func titles(_ rows: [PinsLogic.PinnedRow]) -> [String] {
    rows.map { row in
      switch row {
      case .pin(let pin, let folder): folder == nil ? pin.title : "  \(pin.title)"
      case .split(let split, let folder):
        (folder == nil ? "" : "  ") + split.pins.map(\.title).joined(separator: "|")
      case .folder(let folder): "[\(folder.name)]"
      }
    }
  }

  @Test func anOpenFolderListsItsTabsIndentedUnderIt() {
    let items = [FakePinnedItem(pin: pin("Mail")), folder("Docs", [pin("Spec"), pin("Plan")])]
    #expect(
      titles(PinsLogic.pinnedRows(items, collapsed: false, highlighted: ClairTabIDNone))
        == ["Mail", "[Docs]", "  Spec", "  Plan"])
  }

  @Test func aClosedFolderListsItsOpenTabs() {
    // Selected or not, as in Arc; an unopened one isn't listed.
    let items = [folder("Docs", open: false, [pin("Spec", tab: 5), pin("Plan"), pin("Note", tab: 6)])]
    for highlighted in [ClairTabIDNone, 5] {
      #expect(
        titles(PinsLogic.pinnedRows(items, collapsed: false, highlighted: highlighted))
          == ["[Docs]", "  Spec", "  Note"])
    }
    let idle = [folder("Docs", open: false, [pin("Spec"), pin("Plan")])]
    #expect(titles(PinsLogic.pinnedRows(idle, collapsed: false, highlighted: ClairTabIDNone)) == ["[Docs]"])
  }

  @Test func anEmptyFolderListsItsRowAlone() {
    for open in [true, false] {
      #expect(titles(PinsLogic.pinnedRows([folder("Ideas", open: open)], collapsed: false, highlighted: 1)) == ["[Ideas]"])
    }
  }

  @Test func aCollapsedSectionListsOnlyTheActiveRowWithoutItsFolder() {
    let items = [FakePinnedItem(pin: pin("Mail")), folder("Docs", [pin("Spec", tab: 5)])]
    #expect(titles(PinsLogic.pinnedRows(items, collapsed: true, highlighted: 5)) == ["Spec"])
    #expect(PinsLogic.pinnedRows(items, collapsed: true, highlighted: ClairTabIDNone).isEmpty)
    // Folders alone still offer the chevron.
    #expect(PinsLogic.offersCollapse(pinCount: [folder("Ideas")].count, collapsed: false))
  }

  @Test func theIconShowsOpenClosedAndOpenTabs() {
    let open = FakeFolder(id: "a", name: "A", isOpen: true, pins: [pin("Spec", tab: 3)])
    let closed = FakeFolder(id: "b", name: "B", isOpen: false, pins: [pin("Spec")])
    let busy = FakeFolder(id: "c", name: "C", isOpen: false, pins: [pin("Plan"), pin("Spec", tab: 3)])
    #expect(PinsLogic.folderIcon(open) == .open)
    #expect(PinsLogic.folderIcon(closed) == .closed)
    #expect(PinsLogic.folderIcon(busy) == .closedWithOpenTabs)
  }

  @Test func closeThisFolderShowsOnHoverWhileATabIsOpen() {
    let busy = FakeFolder(id: "c", name: "C", isOpen: true, pins: [pin("Spec", tab: 3)])
    let idle = FakeFolder(id: "d", name: "D", pins: [pin("Spec")])
    #expect(PinsLogic.showsCloseFolder(busy, isHovered: true))
    #expect(!PinsLogic.showsCloseFolder(busy, isHovered: false))
    #expect(!PinsLogic.showsCloseFolder(idle, isHovered: true))
    #expect(PinsLogic.closeFolderHelp == "Close This Folder")
  }

  @Test func theTabCommandsSkipAClosedFoldersTabs() {
    let items = [FakePinnedItem(pin: pin("P")), folder("Docs", open: false, [pin("S")])]
    let today = [FakeTab(id: 10, title: "X")]
    #expect(PinsLogic.commandRows(items: items, highlighted: ClairTabIDNone, today: today) == [.pin("P"), .tab(10)])
    let open = [FakePinnedItem(pin: pin("P")), folder("Docs", [pin("S")])]
    #expect(
      PinsLogic.commandRows(items: open, highlighted: ClairTabIDNone, today: today) == [.pin("P"), .pin("S"), .tab(10)])
  }

  // MARK: Gaps (D4)

  /// P; F open with a, b; G closed with c and e open, d not; H open and
  /// empty; Q.
  private var sample: [any ClairPinnedItem] {
    [
      FakePinnedItem(pin: pin("P")),
      folder("F", [pin("a", folder: "F"), pin("b", folder: "F")]),
      folder("G", open: false, [pin("c", tab: 9, folder: "G"), pin("d", folder: "G"), pin("e", tab: 10, folder: "G")]),
      folder("H"),
      FakePinnedItem(pin: pin("Q")),
    ]
  }

  private func drop(_ destination: Int, moving: Int? = nil, collapsed: Bool = false) -> PinsLogic.ListDrop {
    let items = sample
    let rows = PinsLogic.pinnedRows(items, collapsed: collapsed, highlighted: 9)
    return PinsLogic.listDrop(
      destination: destination, rows: rows, items: items, collapsed: collapsed, boundaryCount: 1, today: [],
      movingPinnedRow: moving)
  }

  @Test func gapsAroundFoldersLandInsideOrAfterThem() {
    #expect(titles(PinsLogic.pinnedRows(sample, collapsed: false, highlighted: 9)) == [
      "P", "[F]", "  a", "  b", "[G]", "  c", "  e", "[H]", "Q",
    ])
    #expect(drop(0) == .pinned(0))
    #expect(drop(1) == .pinned(1))
    // Under an open folder's row, between its tabs and below its last.
    #expect(drop(2) == .folder("F", 0))
    #expect(drop(3) == .folder("F", 1))
    #expect(drop(4) == .folder("F", 2))
    // Under a closed folder's row, and between the tabs it lists, is in it;
    // below its last listed tab is after the folder.
    #expect(drop(5) == .folder("G", 0))
    #expect(drop(6) == .folder("G", 2))
    #expect(drop(7) == .pinned(3))
    // Under an open, empty folder's row: first in it.
    #expect(drop(8) == .folder("H", 0))
    #expect(drop(9) == .pinned(5))
  }

  @Test func aLiftedRowNoLongerCounts() {
    // P after F's row: first in F.
    #expect(drop(2, moving: 0) == .folder("F", 0))
    // b moved above a.
    #expect(drop(2, moving: 3) == .folder("F", 0))
    // a moved out to the top.
    #expect(drop(0, moving: 2) == .pinned(0))
    // F moved to the end: after Q, among the items without F.
    #expect(drop(9, moving: 1) == .pinned(4))
    // F dropped below its own last tab lands in itself, which the window
    // ignores.
    #expect(drop(4, moving: 1) == .folder("F", 2))
  }

  @Test func aCollapsedSectionDropsBeforeTheActiveRowOrAtTheEnd() {
    #expect(drop(0, collapsed: true) == .folder("G", 0))
    #expect(drop(1, collapsed: true) == .pinned(5))
  }

  @Test func foldersDontLandInFolders() {
    #expect(!FolderDropView.accepts(.folder("F")))
    #expect(FolderDropView.accepts(.tab(3)))
    #expect(FolderDropView.accepts(.pin("p")))
    #expect(SidebarDragItem(payload: SidebarDragItem.folder("f-1").payload) == .folder("f-1"))
  }
}

// MARK: Menus and dialogs (add-tab-folders design D6, D7, D10)

@MainActor
struct FolderMenuTests {
  @Test func thePlusMenuOffersNewFolderAfterNewSpace() {
    #expect(SpacesLogic.plusMenu(showsSpaces: true) == [.newSpace, .newFolder, .divider, .newTab])
    #expect(SpacesLogic.plusMenu(showsSpaces: false) == [.newTab])
  }

  @Test func theFolderMenuOffersMoveToSpaceWithTwoSpaces() {
    let titles = { (canMove: Bool) in PinsLogic.folderMenu(name: "Docs", canMoveToSpace: canMove).map { $0?.title } }
    #expect(
      titles(true) == ["Turn “Docs” into Space", nil, "Rename…", nil, "Duplicate", "Move to Space", nil, "Delete"])
    #expect(titles(false) == ["Turn “Docs” into Space", nil, "Rename…", nil, "Duplicate", nil, "Delete"])
  }

  @Test func aFoldersNameKeepsItsOwnWhenEmptied() {
    #expect(PinsLogic.folderNameChange(draft: " Trip ", current: "Untitled") == .rename("Trip"))
    #expect(PinsLogic.folderNameChange(draft: "  ", current: "Untitled") == .unchanged)
    #expect(PinsLogic.folderNameChange(draft: "Untitled", current: "Untitled") == .unchanged)
  }

  @Test func newFolderIsTheTabMenusItemAfterPinTab() {
    let main = NSMenu()
    let tabs = NSMenuItem(title: "Tab", action: nil, keyEquivalent: "")
    tabs.tag = PinsMenu.tabMenuTag
    tabs.submenu = NSMenu(title: "Tab")
    main.addItem(tabs)
    let menu = PinsMenu()
    menu.install(in: main)
    let titles = tabs.submenu?.items.map(\.title) ?? []
    #expect(Array(titles.prefix(2)) == ["Pin Tab", "New Folder…"])
    #expect(PinsLogic.title(of: .newFolder, in: PinsLogic.MenuState()) == "New Folder…")
    // Disabled in incognito and guest windows.
    #expect(!PinsLogic.isEnabled(.newFolder, in: PinsLogic.MenuState(showsPins: false)))
    #expect(PinsLogic.isEnabled(.newFolder, in: PinsLogic.MenuState()))
  }

  @Test func theNewFolderDialogNeedsAName() throws {
    let state = ProfileNameState()
    var page = PinDialogs.newFolderPage(state: state)
    #expect(page.title == "New Folder…")
    #expect(page.buttons.map(\.title) == ["Cancel", "Create"])
    #expect(page.buttons.last?.isEnabled == false)
    state.text = "  "
    page = PinDialogs.newFolderPage(state: state)
    #expect(page.buttons.last?.isEnabled == false)
    state.text = "Inbox"
    page = PinDialogs.newFolderPage(state: state)
    #expect(page.buttons.last?.isEnabled == true)
  }

  @Test func theDeleteConfirmationIsWordedForClair() {
    let page = PinDialogs.deleteFolderPage(name: "Inbox")
    #expect(page.title == "Delete your “Inbox” folder?")
    #expect(page.message == "Deleting this folder will remove the tabs inside it.")
    #expect(page.buttons.map(\.title) == ["Cancel", "Delete Folder"])
    #expect(page.buttons.last?.role == .destructive)
  }

  @Test func aSpaceWithFoldersAsksBeforeDeleting() {
    #expect(SpacesLogic.deletionNeedsConfirmation(tabCount: 0, folderCount: 1))
    #expect(!SpacesLogic.deletionNeedsConfirmation(tabCount: 0, folderCount: 0))
    #expect(SpacesLogic.deletionMessage(tabCount: 0, folderCount: 1) == "Its folder will be removed.")
    #expect(SpacesLogic.deletionMessage(tabCount: 0, folderCount: 2) == "Its 2 folders will be removed.")
    #expect(SpacesLogic.deletionMessage(tabCount: 2, folderCount: 1) == "Its 2 tabs will close, and its folder will be removed.")
  }
}

// MARK: The window (add-tab-folders design D4, D6 to D8, D10, D11)

@MainActor
struct FolderWindowTests {
  @Test func newFolderAddsUntitledLastWithItsNameInAField() {
    let w = PinWindow()
    w.host.addPin(url: "https://mail.example/", title: "Mail")
    w.host.addPin(url: "https://docs.example/", title: "Docs")
    w.controller.newFolder()
    let folder = w.model.pinnedItems.last?.folder
    #expect(folder?.name == "Untitled")
    #expect(folder?.isOpen == true)
    #expect(w.model.pinnedItems.count == 3)
    #expect(w.model.renaming?.row == .folder(folder?.folderID ?? ""))
    #expect(w.model.renaming?.selectsAll == true)
    // Return keeps the name.
    w.controller.endRenaming(.folder(folder?.folderID ?? ""), change: .rename("Trip"))
    #expect(w.model.pinnedItems.last?.folder?.name == "Trip")
    #expect(w.model.renaming == nil)
  }

  @Test func escapeKeepsUntitled() {
    let w = PinWindow()
    w.controller.newFolder()
    let folderID = w.model.pinnedItems.last?.folder?.folderID ?? ""
    w.controller.endRenaming(.folder(folderID), change: .unchanged)
    #expect(w.model.pinnedItems.last?.folder?.name == "Untitled")
  }

  @Test func newFolderGoesLastWhateverIsSelected() {
    let w = PinWindow()
    let a = w.browser.addTab(title: "A", url: "https://a.example/")
    w.controller.pin(tab: a.tabID)
    w.host.addPin(url: "https://b.example/", title: "B")
    w.host.addPin(url: "https://c.example/", title: "C")
    w.controller.newFolder()
    #expect(w.model.pinnedItems.map { $0.pin?.title ?? $0.folder?.name ?? "" } == ["A", "B", "C", "Untitled"])
  }

  @Test func tabsNewFolderAsksForTheName() throws {
    let w = PinWindow()
    w.controller.perform(.newFolder)
    let dialog = try #require(w.controller.dialogs.showing)
    #expect(dialog.page.title == "New Folder…")
    let state = try #require(PinDialogs.nameState(of: dialog))
    state.text = "Inbox"
    #expect(dialog.page.buttons.last?.isEnabled == true)
    dialog.answer(.accepted)
    #expect(w.model.pinnedItems.last?.folder?.name == "Inbox")
    #expect(w.model.pinnedItems.last?.folder?.isOpen == true)
    // No name field follows.
    #expect(w.model.renaming == nil)
  }

  @Test func cancellingTheDialogAddsNothing() throws {
    let w = PinWindow()
    w.controller.perform(.newFolder)
    try #require(w.controller.dialogs.showing).answer(.cancelled)
    #expect(w.model.pinnedItems.isEmpty)
  }

  @Test func aClickOpensAndClosesAFolder() {
    let w = PinWindow()
    let docs = w.host.addFolder("Docs")
    w.controller.toggleFolder(docs)
    #expect(w.model.pinnedItems.first?.folder?.isOpen == false)
    w.controller.toggleFolder(docs)
    #expect(w.model.pinnedItems.first?.folder?.isOpen == true)
  }

  @Test func dropsLandInFoldersAndFoldersStayAtTheTopLevel() {
    let w = PinWindow()
    let docs = w.host.addFolder("Docs")
    w.host.addPin(url: "https://spec.example/", title: "Spec", folder: docs)
    let tab = w.browser.addTab(title: "Plan", url: "https://plan.example/")
    // A Today tab on the folder's row: its first tab.
    w.controller.drop(.tab(tab.tabID), on: .folder(docs, 0))
    #expect(w.model.pinnedItems.first?.folder.map { PinsLogic.pins(of: $0).map(\.title) } == ["Plan", "Spec"])
    // A favorite on the folder's row leaves the grid.
    let calendar = w.host.addPin(url: "https://cal.example/", title: "Calendar", inSpace: nil)
    w.controller.drop(.pin(calendar), on: .folder(docs, 0))
    #expect(w.model.favorites.isEmpty)
    #expect(w.model.pinnedItems.first?.folder.flatMap { PinsLogic.pins(of: $0).first }?.title == "Calendar")
    // A tab dragged out above the folder.
    let spec = w.model.pins.first { $0.title == "Spec" }?.pinID ?? ""
    w.controller.drop(.pin(spec), on: .pinned(0))
    #expect(w.model.pinnedItems.first?.pin?.title == "Spec")
    // The folder below the divider, or into a folder, stays.
    let other = w.host.addFolder("Other")
    w.controller.drop(.folder(docs), on: .today(0))
    w.controller.drop(.folder(docs), on: .folder(other, 0))
    #expect(w.model.pinnedItems.map { $0.pin?.title ?? $0.folder?.name ?? "" } == ["Spec", "Docs", "Other"])
    // Reordered at the top level.
    w.controller.drop(.folder(other), on: .pinned(0))
    #expect(w.model.pinnedItems.map { $0.pin?.title ?? $0.folder?.name ?? "" } == ["Other", "Spec", "Docs"])
  }

  @Test func deletingAnEmptyFolderDoesntAsk() {
    let w = PinWindow()
    let ideas = w.host.addFolder("Ideas")
    w.controller.deleteFolder(ideas)
    #expect(w.controller.dialogs.showing == nil)
    #expect(w.model.pinnedItems.isEmpty)
  }

  @Test func deletingAFolderWithTabsAsksFirst() throws {
    let w = PinWindow()
    let docs = w.host.addFolder("Docs")
    w.host.addPin(url: "https://spec.example/", title: "Spec", folder: docs)
    w.controller.deleteFolder(docs)
    let dialog = try #require(w.controller.dialogs.showing)
    #expect(dialog.page.title == "Delete your “Docs” folder?")
    dialog.answer(.cancelled)
    #expect(w.model.pinnedItems.count == 1)
    w.controller.deleteFolder(docs)
    try #require(w.controller.dialogs.showing).answer(.accepted)
    #expect(w.model.pinnedItems.isEmpty)
    // Restore Last Closed Tab brings it back with its tab.
    w.host.restoreRemovedFolder()
    #expect(w.model.pinnedItems.first?.folder.map { PinsLogic.pins(of: $0).map(\.title) } == ["Spec"])
  }

  @Test func duplicateAddsACopyRightAfter() {
    let w = PinWindow()
    let docs = w.host.addFolder("Docs")
    w.host.addPin(url: "https://spec.example/", title: "Spec", folder: docs)
    w.host.addPin(url: "https://mail.example/", title: "Mail")
    w.controller.duplicateFolder(docs)
    #expect(w.model.pinnedItems.map { $0.pin?.title ?? $0.folder?.name ?? "" } == ["Docs", "Docs", "Mail"])
    #expect(w.model.pinnedItems[1].folder.map { PinsLogic.pins(of: $0).map(\.title) } == ["Spec"])
  }

  @Test func movingAFolderShowsTheNotice() {
    let w = PinWindow()
    let work = w.host.addSpaces("Work")[0]
    let docs = w.host.addFolder("Docs")
    w.controller.moveFolder(docs, toSpace: work)
    #expect(w.model.pinnedItems.isEmpty)
    #expect(w.host.folderRecords(inSpace: work).map(\.name) == ["Docs"])
    #expect(w.model.notice.notice?.text == "Folder was moved to Work")
  }

  @Test func turningAFolderIntoASpaceShowsIt() {
    let w = PinWindow()
    let trip = w.host.addFolder("Trip")
    w.host.addPin(url: "https://flights.example/", title: "Flights", folder: trip)
    w.host.addPin(url: "https://hotels.example/", title: "Hotels", folder: trip)
    w.controller.turnFolderIntoSpace(trip)
    #expect(w.host.spaces.last?.name == "Trip")
    #expect(w.model.shownSpace?.name == "Trip")
    #expect(w.pinTitles == ["Flights", "Hotels"])
    #expect(w.host.folderRecords(inSpace: FakeHost.homeID).isEmpty)
  }

  @Test func theSidebarsOwnMenuOffersTheHeadersItems() throws {
    let w = PinWindow()
    let space = try #require(w.model.shownSpace)
    let titles = SpaceHeaderView.menuItems(for: space, model: w.model, actions: w.controller).map(\.title)
    #expect(titles == SpacesLogic.headerMenu(spaceCount: 1).map { $0?.title })
    #expect(titles.contains("New Folder"))
  }

  @Test func deletingASpaceWithAnEmptyFolderAsks() throws {
    let w = PinWindow()
    let work = w.host.addSpaces("Work")[0]
    w.host.addFolder("Ideas", inSpace: work)
    _ = w.model.spaces.pinnedItems(inSpace: work)
    w.controller.deleteSpace(work)
    let dialog = try #require(w.controller.dialogs.showing)
    #expect(dialog.page.message == "Its folder will be removed.")
    dialog.answer(.accepted)
    #expect(w.host.spaces.count == 1)
    #expect(w.host.folderRecords(inSpace: work).isEmpty)
  }
}
