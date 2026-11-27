// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import ClairUI

/// One regular window on a fake host with its controller, its preferences in
/// their own suite (add-pinned-tabs-and-favorites).
@MainActor
struct PinWindow {
  let host = FakeHost()
  let browser: FakeBrowser
  let controller: BrowserWindowController
  let defaults: UserDefaults

  init(suite: String = #function) {
    defaults = UserDefaults(suiteName: "PinsTests." + suite)!
    defaults.removePersistentDomain(forName: "PinsTests." + suite)
    browser = FakeBrowser(host: host)
    controller = BrowserWindowController(
      browser: browser, spaces: browser.spaces, preferences: SidebarPreferences(defaults: defaults),
      peekPreference: PeekPreference(defaults: defaults), pinsPreferences: PinsPreferences(defaults: defaults))
    browser.clairWindow = controller
  }

  var model: BrowserWindowModel { controller.model }
  var pinTitles: [String] { model.pins.map(\.title) }
  var todayTitles: [String] { TabListLogic.rows(model.tabs).map(\.title) }
}

// MARK: The favorites grid (favorites spec, design "Arc reference")

struct FavoritesLayoutTests {
  /// Arc's measurements at its default 228 pt sidebar: columns, rows, tile
  /// width and the grid's height for 1 to 9 favorites.
  @Test(arguments: [
    (1, 1, 1, 212.0, 63.0), (2, 2, 1, 102.0, 63.0), (3, 3, 1, 65.333, 63.0), (4, 4, 1, 47.0, 63.0),
    (5, 3, 2, 65.333, 118.0), (6, 3, 2, 65.333, 118.0), (7, 4, 2, 47.0, 118.0), (8, 4, 2, 47.0, 118.0),
    (9, 3, 3, 65.333, 173.0),
  ])
  func matchesArc(count: Int, columns: Int, rows: Int, tileWidth: Double, height: Double) {
    let layout = FavoritesLayout(count: count, width: SidebarState.defaultWidth)
    #expect(layout.columns == columns)
    #expect(layout.rows == rows)
    #expect(abs(layout.tileWidth - tileWidth) < 0.01)
    #expect(abs(layout.height - height) < 0.01, "height \(layout.height)")
  }

  @Test func eightFavoritesAreSquare() {
    let layout = FavoritesLayout(count: 8, width: SidebarState.defaultWidth)
    #expect(layout.tileWidth == FavoritesLayout.tileHeight)
  }

  @Test func fiveFillTheSecondRowFromTheLeadingEdge() {
    let layout = FavoritesLayout(count: 5, width: SidebarState.defaultWidth)
    #expect(layout.frame(of: 3).minX == FavoritesLayout.inset)
    #expect(layout.frame(of: 3).minY == FavoritesLayout.inset + FavoritesLayout.tileHeight + FavoritesLayout.gap)
  }

  @Test func aTileDroppedOnTheGridTakesTheSlotUnderIt() {
    let layout = FavoritesLayout(count: 2, width: SidebarState.defaultWidth)
    // Between the two tiles, and past the last.
    #expect(layout.dropIndex(at: CGPoint(x: layout.frame(of: 1).minX - 2, y: 20)) == 1)
    #expect(layout.dropIndex(at: CGPoint(x: 220, y: 20)) == 2)
    #expect(layout.dropIndex(at: CGPoint(x: 10, y: 20)) == 0)
  }

  @Test func noFavoritesTakeNoRoom() {
    #expect(FavoritesLayout(count: 0, width: 228).height == 0)
  }
}

// MARK: The rules (PinsLogic)

@MainActor
struct PinsLogicTests {
  private func pin(_ title: String, tab: FakeTab? = nil, name: String? = nil, atPinnedURL: Bool = true) -> FakePin {
    FakePin(id: title, url: "https://\(title.lowercased()).example/", title: title, name: name, tab: tab, isAtPinnedURL: atPinnedURL)
  }

  @Test func theSelectedPinnedTabShowsMinusAndTheOthersCross() {
    #expect(PinsLogic.rowButton(isSelected: true) == .closeKeepingPin)
    #expect(PinsLogic.rowButton(isSelected: false) == .removePin)
    #expect(PinsLogic.RowButton.closeKeepingPin.help == "Close and Keep Pinned")
    #expect(PinsLogic.RowButton.closeKeepingPin.shortcut == ["⌘", "W"])
    #expect(PinsLogic.RowButton.removePin.help == "Remove Pin")
  }

  @Test func aNavigatedPinnedTabReadsItsCurrentTitle() {
    let guide = FakeTab(id: 1, title: "Guide", url: "https://docs.example/guide", pinID: "Docs")
    let navigated = pin("Docs", tab: guide, atPinnedURL: false)
    #expect(PinsLogic.isNavigatedAway(navigated))
    #expect(PinsLogic.title(of: navigated, tab: guide) == "Guide")
    // At its pinned URL, or closed, it reads the pinned page's title.
    #expect(PinsLogic.title(of: pin("Docs", tab: guide), tab: guide) == "Docs")
    #expect(!PinsLogic.isNavigatedAway(pin("Docs")))
    // A name wins everywhere.
    #expect(PinsLogic.title(of: pin("Docs", tab: guide, name: "Manual", atPinnedURL: false), tab: guide) == "Manual")
  }

  @Test func aCollapsedSectionKeepsOnlyTheSelectedRow() {
    let open = FakeTab(id: 7, title: "Mail", pinID: "Mail")
    let items = [pin("Docs"), pin("Mail", tab: open), pin("News")].map { FakePinnedItem(pin: $0) }
    #expect(PinsLogic.pinnedRows(items, collapsed: false, highlighted: 7).count == 3)
    #expect(PinsLogic.pinnedRows(items, collapsed: true, highlighted: 7).compactMap(\.pin?.title) == ["Mail"])
    #expect(PinsLogic.pinnedRows(items, collapsed: true, highlighted: 99).isEmpty)
  }

  @Test func theDividerAndClearShowWithTodayTabs() {
    #expect(!PinsLogic.showsDivider(todayRowCount: 0, showsPins: true))
    #expect(PinsLogic.showsDivider(todayRowCount: 2, showsPins: true))
    #expect(!PinsLogic.showsClear(todayRowCount: 2, showsPins: true, isSidebarHovered: false))
    #expect(PinsLogic.showsClear(todayRowCount: 2, showsPins: true, isSidebarHovered: true))
    #expect(!PinsLogic.showsClear(todayRowCount: 0, showsPins: true, isSidebarHovered: true))
  }

  @Test func theHeaderOffersCollapsingWithPinsOrWhileCollapsed() {
    #expect(PinsLogic.offersCollapse(pinCount: 2, collapsed: false))
    #expect(!PinsLogic.offersCollapse(pinCount: 0, collapsed: false))
    // The last pin unpinned while collapsed: the chevron stays, pointing
    // sideways, so the section can be expanded again.
    #expect(PinsLogic.offersCollapse(pinCount: 0, collapsed: true))
  }

  @Test func incognitoAndGuestWindowsShowNoDividerOrClear() {
    // No pinned section there, so nothing to divide and nothing Clear does.
    #expect(!PinsLogic.showsDivider(todayRowCount: 2, showsPins: false))
    #expect(!PinsLogic.showsClear(todayRowCount: 2, showsPins: false, isSidebarHovered: true))
  }

  @Test func tooltipsShowTheNameAloneOrTheTitleWithTheHint() {
    #expect(PinsLogic.tooltip(title: "Example Domain", name: "Fruit Co") == "Fruit Co")
    #expect(PinsLogic.tooltip(title: "Example Domain", name: nil) == "Example Domain\nDouble-click to rename")
    #expect(PinsLogic.tooltip(title: "", name: nil) == nil)
  }

  @Test func keepingANameRenamesClearsOrChangesNothing() {
    #expect(PinsLogic.nameChange(draft: " Fruit Co ", current: nil) == .rename("Fruit Co"))
    #expect(PinsLogic.nameChange(draft: "Fruit Co", current: "Fruit Co") == .unchanged)
    #expect(PinsLogic.nameChange(draft: "  ", current: "Fruit Co") == .clear)
    #expect(PinsLogic.nameChange(draft: "", current: nil) == .unchanged)
  }

  @Test(arguments: [
    ("https://docs.example.com/api", "https://docs.example.com/api"),
    ("docs.example.com", "https://docs.example.com"),
    ("localhost:8000/x", "https://localhost:8000/x"),
    ("chrome://settings", "chrome://settings"),
    ("file:///Users/test/a.html", "file:///Users/test/a.html"),
  ])
  func pinnedURLsAreFixedUp(text: String, url: String) {
    #expect(PinsLogic.fixedUpURL(text)?.absoluteString == url)
  }

  @Test(arguments: ["not a url", "", "example", "javascript:alert(1)", "ftp://example.com", "https://"])
  func saveIsOffWithoutAURL(text: String) {
    #expect(PinsLogic.fixedUpURL(text) == nil)
    #expect(!PinDialogs.canSave(text))
  }

  @Test func copyLinkOfAClosedPinCopiesItsPinnedURL() {
    #expect(PinsLogic.link(of: pin("Mail")) == "https://mail.example/")
    let open = FakeTab(id: 3, title: "Inbox", url: "https://mail.example/inbox", pinID: "Mail")
    #expect(PinsLogic.link(of: pin("Mail", tab: open)) == "https://mail.example/inbox")
  }

  @Test func commandNumbersCountEveryPinThenTodayRows() {
    let today = [FakeTab(id: 10, title: "X"), FakeTab(id: 11, title: "X peek", peekParentID: 10), FakeTab(id: 12)]
    let rows = PinsLogic.commandRows(pins: [pin("P"), pin("Q")], today: today)
    #expect(rows == [.pin("P"), .pin("Q"), .tab(10), .tab(12)])
  }

  @Test func dropsInTheListFindTheirSection() {
    let today = [FakeTab(id: 1), FakeTab(id: 2, peekID: 3), FakeTab(id: 3, peekParentID: 2), FakeTab(id: 4)]
    // Two pinned rows, the row of the divider and "New Tab", then three
    // Today rows.
    let items = [pin("P"), pin("Q")].map { FakePinnedItem(pin: $0) }
    let rows = PinsLogic.pinnedRows(items, collapsed: false, highlighted: ClairTabIDNone)
    func drop(_ destination: Int, pin: Int? = nil, row: Int? = nil) -> PinsLogic.ListDrop {
      PinsLogic.listDrop(
        destination: destination, rows: rows, items: items, boundaryCount: 1, today: today, movingPinnedRow: pin,
        movingTodayRow: row)
    }
    // A Today tab between the two pinned tabs is pinned second.
    #expect(drop(1, row: 0) == .pinned(1))
    // A pinned tab moved past the other, to the end of the section.
    #expect(drop(2, pin: 0) == .pinned(1))
    // A pinned tab below the second Today row: Peeks counted.
    #expect(drop(5, pin: 1) == .today(3))
    // A pinned tab dragged out to the top of Today, below "New Tab".
    #expect(drop(3, pin: 0) == .today(0))
    // A Today row moved to the top of Today, or to its end.
    #expect(drop(3, row: 2) == .today(0))
    #expect(drop(6, row: 0) == .today(3))
  }

  @Test func aRowDroppedAboveTheDividerPinsWhileTheSectionIsEmpty() {
    let today = [FakeTab(id: 1), FakeTab(id: 2)]
    // No pinned rows: the row of the divider and "New Tab", then two Today
    // rows. Above it pins; below it is the top of Today.
    #expect(
      PinsLogic.listDrop(destination: 0, rows: [], items: [], boundaryCount: 1, today: today, movingTodayRow: 1)
        == .pinned(0))
    #expect(
      PinsLogic.listDrop(destination: 1, rows: [], items: [], boundaryCount: 1, today: today, movingTodayRow: 1)
        == .today(0))
  }

  @Test func sidebarDragsCarryTextOfTheirOwnType() {
    // The app's Info.plist declares the type as text (package.sh, checked by
    // scripts/package.test.sh); a test host doesn't, so only this holds here: a
    // page's plain text isn't of the type.
    #expect(SidebarDragItem.type.identifier == "com.clairbrowser.clair.sidebar-item")
    #expect(!UTType.utf8PlainText.conforms(to: SidebarDragItem.type))
    #expect(SidebarDragItem(payload: SidebarDragItem.tab(7).payload) == .tab(7))
    #expect(SidebarDragItem(payload: SidebarDragItem.pin("p").payload) == .pin("p"))
  }

  @Test func theMenusListTheirItemsInOrder() {
    let today = PinsLogic.todayMenu(isMuted: false, canMoveToSpace: false, canPin: true).compactMap { $0?.title }
    #expect(
      today == [
        "Copy Link", "Rename…", "Duplicate", "Mute", "Split with Tab", "Pin Tab", "Pin to Favorites", "Close Tab",
        "Close Tabs Below",
      ])
    let pinned = PinsLogic.pinnedMenu(isOpen: true, isMuted: false, canMoveToSpace: true).compactMap { $0?.title }
    #expect(
      pinned == [
        "Copy Link", "Rename…", "Mute", "Edit Pinned Page", "Duplicate", "Split with Tab", "Move to Space",
        "Pin to Favorites", "Unpin Tab",
      ])
    let favorite = PinsLogic.favoriteMenu(isShown: true, isOpen: true, isMuted: false).compactMap { $0?.title }
    #expect(
      favorite == [
        "Copy Link", "Rename…", "Mute", "Edit Pinned Page", "Duplicate", "Split with Tab", "Close Tab",
        "Remove Favorite",
      ])
    #expect(!PinsLogic.favoriteMenu(isShown: false, isOpen: false, isMuted: false).contains { $0?.title == "Close Tab" })
  }

  /// add-split-view, "The split row's menu": a chip's menu has no Split
  /// with Tab or Edit Pinned Page, and Separate Tabs.
  @Test func aSplitChipsMenusSeparateTheSplit() {
    let today = PinsLogic.todayMenu(isMuted: false, canMoveToSpace: false, canPin: true, inSplit: true)
      .compactMap { $0?.title }
    #expect(
      today == [
        "Copy Link", "Rename…", "Duplicate", "Mute", "Separate Tabs", "Pin Tab", "Pin to Favorites", "Close Tab",
        "Close Tabs Below",
      ])
    let pinned = PinsLogic.pinnedMenu(isOpen: false, isMuted: false, canMoveToSpace: false, inSplit: true)
      .compactMap { $0?.title }
    #expect(pinned == ["Copy Link", "Rename…", "Mute", "Duplicate", "Separate Tabs", "Pin to Favorites", "Unpin Tab"])
    let favorite = PinsLogic.favoriteMenu(isShown: false, isOpen: false, isMuted: false, inSplit: true)
      .compactMap { $0?.title }
    #expect(favorite == ["Copy Link", "Rename…", "Mute", "Duplicate", "Separate Tabs", "Remove Favorite"])
  }

  @Test func privateWindowsMenusHaveNoPinItems() {
    let today = PinsLogic.todayMenu(isMuted: true, canMoveToSpace: false, canPin: false).compactMap { $0?.title }
    #expect(!today.contains("Pin Tab") && !today.contains("Pin to Favorites"))
    #expect(today.contains("Unmute"))
  }

  @Test func aClosedPinCantMuteOrReplaceItsURL() {
    let closed = pin("Docs")
    #expect(PinsLogic.pinnedMenu(isOpen: false, isMuted: false, canMoveToSpace: false).compactMap { $0 }
      .first { $0.command == .mute }?.isEnabled == false)
    #expect(PinsLogic.editPinnedPageMenu(closed).first?.isEnabled == false)
    let guide = FakeTab(id: 1, title: "Guide", pinID: "Docs")
    #expect(PinsLogic.editPinnedPageMenu(pin("Docs", tab: guide, atPinnedURL: false)).first?.isEnabled == true)
  }

  @Test func theMainMenuItemsFollowTheSelectedRow() {
    var state = PinsLogic.MenuState(activeIsToday: true, todayRowCount: 2)
    #expect(PinsLogic.title(of: .togglePin, in: state) == "Pin Tab")
    #expect(PinsLogic.isEnabled(.togglePin, in: state))
    #expect(!PinsLogic.isEnabled(.backToPinnedURL, in: state))
    #expect(!PinsLogic.isEnabled(.closeKeepingPin, in: state))
    #expect(PinsLogic.isEnabled(.clearToday, in: state))
    state = PinsLogic.MenuState(activePinIsFavorite: false, activePinIsNavigatedAway: false, todayRowCount: 0)
    #expect(PinsLogic.title(of: .togglePin, in: state) == "Unpin Tab")
    #expect(!PinsLogic.isEnabled(.backToPinnedURL, in: state))
    #expect(PinsLogic.isEnabled(.closeKeepingPin, in: state))
    #expect(!PinsLogic.isEnabled(.clearToday, in: state))
    state.activePinIsNavigatedAway = true
    #expect(PinsLogic.isEnabled(.backToPinnedURL, in: state))
    state.isCollapsed = true
    #expect(PinsLogic.title(of: .toggleCollapse, in: state) == "Expand Pinned Tabs")
  }

  @Test func incognitoDisablesEveryPinItem() {
    let state = PinsLogic.MenuState(showsPins: false, activeIsToday: true, todayRowCount: 3)
    for command in PinsLogic.MainMenuCommand.allCases {
      #expect(!PinsLogic.isEnabled(command, in: state))
    }
  }
}

// MARK: Preferences

struct PinsPreferencesTests {
  private func fresh(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "PinsPreferencesTests." + name)!
    defaults.removePersistentDomain(forName: "PinsPreferencesTests." + name)
    return defaults
  }

  @Test func eachSpaceRemembersItsCollapse() {
    let preferences = PinsPreferences(defaults: fresh(#function))
    preferences.setCollapsed(true, for: "work")
    #expect(preferences.isCollapsed("work"))
    #expect(!preferences.isCollapsed("home"))
    preferences.setCollapsed(false, for: "work")
    #expect(!preferences.isCollapsed("work"))
  }

  @Test func theFavoritesBoxNeverReturnsOnceDismissed() {
    let preferences = PinsPreferences(defaults: fresh(#function))
    #expect(preferences.showsFavoritesHint(for: "Default", favoriteCount: 0))
    preferences.finishFavoritesHint(for: "Default")
    #expect(!preferences.showsFavoritesHint(for: "Default", favoriteCount: 0))
    // Another profile still shows its own.
    #expect(preferences.showsFavoritesHint(for: "Profile 1", favoriteCount: 0))
    #expect(!preferences.showsFavoritesHint(for: "Profile 1", favoriteCount: 2))
  }

  @Test func peekForOtherSitesIsOnUntilTurnedOff() {
    let defaults = fresh(#function)
    let preference = PeekPreference(defaults: defaults)
    #expect(preference.opensForOtherSites)
    defaults.set(false, forKey: PeekPreference.otherSitesKey)
    #expect(!preference.opensForOtherSites)
  }

  @Test func theLinksPageSaysWhatTheToggleDoes() {
    #expect(LinksSettingsView.otherSitesLabel == "Open a Peek window when clicking on links to other sites")
    #expect(LinksSettingsView.otherSitesNote == "Note: This only affects Favorites and Pinned tabs")
  }
}

// MARK: The fakes keep the engine's rules (design D2 to D6)

@MainActor
struct FakePinsTests {
  @Test func pinningMovesATabToTheBottomOfThePinnedSectionWithItsPage() {
    let w = PinWindow()
    let mail = w.browser.addTab(title: "Mail", url: "https://mail.example/")
    let docs = w.browser.addTab(title: "Docs", url: "https://docs.example/")
    w.controller.pin(tab: mail.tabID)
    w.controller.pin(tab: docs.tabID)
    #expect(w.pinTitles == ["Mail", "Docs"])
    #expect(w.todayTitles.isEmpty)
    // Docs stays active, its page open, bound to its pin.
    #expect(w.model.activePin?.title == "Docs")
    #expect(w.model.activeTab?.title == "Docs")
  }

  @Test func unpinningPutsTheTabAtTheTopOfTodayWithItsName() {
    let w = PinWindow()
    w.browser.addTab(title: "News")
    let docs = w.browser.addTab(title: "Docs", url: "https://docs.example/")
    w.controller.pin(tab: docs.tabID)
    let pinID = w.model.pins[0].pinID
    w.controller.endRenaming(.pin(pinID), change: .rename("Manual"))
    w.controller.perform(.togglePin)
    #expect(w.pinTitles.isEmpty)
    #expect(w.model.tabs.first?.name == "Manual")
    #expect(w.model.tabs.first?.tabID == docs.tabID)
  }

  @Test func closingAPinnedTabKeepsItsRowAndShowsTheTabItCameFrom() {
    let w = PinWindow()
    let news = w.browser.addTab(title: "News")
    let mail = w.browser.addTab(title: "Mail", url: "https://mail.example/")
    w.controller.pin(tab: mail.tabID)
    w.browser.setActive(news.tabID)
    w.controller.openPin(w.model.pins[0].pinID)
    #expect(w.model.activePin?.title == "Mail")
    w.controller.perform(.closeKeepingPin)
    #expect(w.pinTitles == ["Mail"])
    #expect(w.model.pins[0].tabID == ClairTabIDNone)
    #expect(w.model.activeTabID == news.tabID)
    // Selecting it again opens its pinned URL.
    w.controller.openPin(w.model.pins[0].pinID)
    #expect(w.model.activeTab?.url?.absoluteString == "https://mail.example/")
  }

  @Test func theNextTabPassesOverPinsWithoutAPage() {
    let w = PinWindow()
    w.host.addPin(url: "https://m.example/", title: "M")
    let u = w.browser.addTab(title: "U")
    let t = w.browser.addTab(title: "T")
    w.browser.close(tab: t.tabID)
    #expect(w.model.activeTabID == u.tabID)
    #expect(w.model.pins[0].tabID == ClairTabIDNone)
  }

  @Test func closingATabSelectedFromAFavoriteShowsTheFavorite() {
    let w = PinWindow()
    let mail = w.browser.addTab(title: "Mail", url: "https://mail.example/")
    w.controller.pinToFavorites(tab: mail.tabID)
    #expect(w.model.favorites.map(\.title) == ["Mail"])
    let t = w.browser.addTab(title: "T")
    w.browser.close(tab: t.tabID)
    #expect(w.model.activePin?.title == "Mail")
  }

  @Test func backToPinnedURLLoadsItAndBackReturns() {
    let w = PinWindow()
    let docs = w.browser.addTab(title: "Docs", url: "https://docs.example/")
    w.controller.pin(tab: docs.tabID)
    let pinID = w.model.pins[0].pinID
    w.browser.change(w.host.boundTab(of: pinID)!.with(title: "Guide", url: "https://docs.example/guide"))
    // The engine posts the pins again once the navigation commits.
    w.host.rebind(pinID, to: w.host.boundTab(of: pinID)!)
    #expect(PinsLogic.isNavigatedAway(w.model.pins[0]))
    #expect(w.controller.pinMenuState.activePinIsNavigatedAway)
    w.controller.perform(.backToPinnedURL)
    #expect(!PinsLogic.isNavigatedAway(w.model.pins[0]))
    #expect(w.model.activeTab?.canGoBack == true)
  }

  @Test func replaceAndEditSetThePinnedURL() {
    let w = PinWindow()
    let docs = w.browser.addTab(title: "Docs", url: "https://docs.example/")
    w.controller.pin(tab: docs.tabID)
    let pinID = w.model.pins[0].pinID
    w.browser.change(w.host.boundTab(of: pinID)!.with(title: "Guide", url: "https://docs.example/guide"))
    w.controller.replacePinnedURL(pinID)
    #expect(w.model.pins[0].url.absoluteString == "https://docs.example/guide")
    #expect(!PinsLogic.isNavigatedAway(w.model.pins[0]))
    w.model.spaces.setPinnedURL(URL(string: "https://docs.example/api")!, forPin: pinID)
    #expect(w.model.pins[0].url.absoluteString == "https://docs.example/api")
  }

  @Test func clearTodayClosesTodayTabsOnly() {
    let w = PinWindow()
    let mail = w.browser.addTab(title: "Mail", url: "https://mail.example/")
    w.controller.pin(tab: mail.tabID)
    w.browser.addTab(title: "A")
    w.browser.addTab(title: "B")
    #expect(w.controller.pinMenuState.todayRowCount == 2)
    w.controller.perform(.clearToday)
    #expect(w.todayTitles.isEmpty)
    #expect(w.model.activePin?.title == "Mail")
    #expect(w.pinTitles == ["Mail"])
  }

  @Test func removingAPinClosesItsPageAndRestoreBringsItBackInPlace() {
    let w = PinWindow()
    for title in ["A", "Docs", "C"] {
      w.host.addPin(url: "https://\(title.lowercased()).example/", title: title)
    }
    let docs = w.model.pins[1].pinID
    w.controller.removePin(docs)
    #expect(w.pinTitles == ["A", "C"])
    w.host.restoreRemovedPin()
    #expect(w.pinTitles == ["A", "Docs", "C"])
  }

  @Test func movingAPinnedTabPutsItAtTheEndOfTheOtherSpace() {
    let w = PinWindow()
    let research = w.host.addSpaces("Research")[0]
    w.host.addPin(url: "https://one.example/", title: "One", inSpace: research)
    w.host.addPin(url: "https://two.example/", title: "Two", inSpace: research)
    w.host.addPin(url: "https://mail.example/", title: "Mail")
    w.controller.movePin(w.model.pins[0].pinID, toSpace: research)
    #expect(w.pinTitles.isEmpty)
    #expect(w.host.pins(inSpace: research).map(\.title) == ["One", "Two", "Mail"])
  }

  @Test func favoritesAreTheSameInEverySpaceOfTheProfile() {
    let w = PinWindow()
    let travel = w.host.addSpaces("Travel")[0]
    w.host.addPin(url: "https://mail.example/", title: "Mail", inSpace: nil)
    #expect(w.model.favorites.map(\.title) == ["Mail"])
    w.browser.showSpace(travel)
    #expect(w.model.favorites.map(\.title) == ["Mail"])
    // A Space of another profile shows that profile's.
    let work = w.host.addProfile("Work")
    let workSpace = w.host.createSpace(named: "Work", icon: nil, profile: work)!
    w.host.addPin(url: "https://tracker.example/", title: "Tracker", inSpace: nil, profile: work)
    w.browser.showSpace(workSpace)
    #expect(w.model.favorites.map(\.title) == ["Tracker"])
  }

  @Test func theFavoritesBoxGoesOnceTheProfileHasAFavorite() {
    let w = PinWindow()
    #expect(w.model.showsFavoritesHint)
    let mail = w.browser.addTab(title: "Mail", url: "https://mail.example/")
    w.controller.pinToFavorites(tab: mail.tabID)
    #expect(!w.model.showsFavoritesHint)
    w.controller.removePin(w.model.favorites[0].pinID)
    #expect(w.model.favorites.isEmpty)
    #expect(!w.model.showsFavoritesHint)
  }

  @Test func dismissingTheFavoritesBoxKeepsItGone() {
    let w = PinWindow()
    w.controller.dismissFavoritesHint()
    #expect(!w.model.showsFavoritesHint)
    #expect(!PinsPreferences(defaults: w.defaults).showsFavoritesHint(for: FakeHost.defaultProfileID, favoriteCount: 0))
  }

  @Test func collapsingKeepsTheActiveRowAndFollowsEveryWindow() {
    let w = PinWindow()
    let other = BrowserWindowController(
      browser: FakeBrowser(host: w.host), spaces: w.browser.spaces,
      preferences: SidebarPreferences(defaults: w.defaults), pinsPreferences: PinsPreferences(defaults: w.defaults))
    let mail = w.browser.addTab(title: "Mail", url: "https://mail.example/")
    w.host.addPin(url: "https://docs.example/", title: "Docs")
    w.controller.pin(tab: mail.tabID)
    w.controller.perform(.toggleCollapse)
    #expect(w.model.isPinnedSectionCollapsed)
    #expect(other.model.isPinnedSectionCollapsed)
    let visible = PinsLogic.pinnedRows(w.model.pinnedItems, collapsed: true, highlighted: w.model.highlightedTab)
    #expect(visible.compactMap(\.pin?.title) == ["Mail"])
    w.controller.togglePinnedSection()
    #expect(!w.model.isPinnedSectionCollapsed)
  }

  @Test func renamingCommitsCancelsAndClears() {
    let w = PinWindow()
    let tab = w.browser.addTab(title: "Example Domain")
    w.controller.beginRenaming(RowRename(row: .tab(tab.tabID), selectsAll: true, caret: nil))
    #expect(w.model.renaming?.row == .tab(tab.tabID))
    w.controller.endRenaming(.tab(tab.tabID), change: .rename("Fruit Co"))
    #expect(w.model.renaming == nil)
    #expect(w.model.tabs.first?.name == "Fruit Co")
    w.controller.endRenaming(.tab(tab.tabID), change: .unchanged)
    #expect(w.model.tabs.first?.name == "Fruit Co")
    w.controller.endRenaming(.tab(tab.tabID), change: .clear)
    #expect(w.model.tabs.first?.name == nil)
  }

  @Test func incognitoWindowsShowNoPins() {
    let host = FakeHost()
    host.addPin(url: "https://mail.example/", title: "Mail")
    host.addPin(url: "https://cal.example/", title: "Cal", inSpace: nil)
    let browser = FakeBrowser(host: host, profileKind: .incognito)
    let controller = BrowserWindowController(browser: browser, spaces: browser.spaces)
    browser.clairWindow = controller
    let tab = browser.addTab(title: "Private")
    #expect(controller.model.pins.isEmpty)
    #expect(controller.model.favorites.isEmpty)
    controller.perform(.togglePin)
    controller.pin(tab: tab.tabID)
    #expect(host.pins(inSpace: FakeHost.homeID).count == 1)
    #expect(TabListLogic.rows(controller.model.tabs).count == 1)
  }

  @Test func draggingBetweenSectionsCallsTheEngine() {
    let w = PinWindow()
    let a = w.browser.addTab(title: "A", url: "https://a.example/")
    let b = w.browser.addTab(title: "B", url: "https://b.example/")
    w.controller.drop(.tab(a.tabID), on: .pinned(0))
    w.controller.drop(.tab(b.tabID), on: .favorites(0))
    #expect(w.pinTitles == ["A"])
    #expect(w.model.favorites.map(\.title) == ["B"])
    w.controller.drop(.pin(w.model.favorites[0].pinID), on: .pinned(0))
    #expect(w.pinTitles == ["B", "A"])
    w.controller.drop(.pin(w.model.pins[1].pinID), on: .today(0))
    #expect(w.pinTitles == ["B"])
    #expect(w.todayTitles.first == "A")
  }
}
