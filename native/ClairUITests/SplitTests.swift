// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Testing

@testable import ClairUI

/// Split view's rules (add-split-view design D3, D8, D9, D13).
struct SplitLogicTests {
  let area = CGRect(x: 10, y: 0, width: 1010, height: 700)

  @Test func thePanesShareTheAreaBesideTheGap() {
    let panes = SplitLogic.paneFrames(in: area, ratio: 0.5)
    #expect(panes[0] == CGRect(x: 10, y: 0, width: 500, height: 700))
    #expect(panes[1] == CGRect(x: 520, y: 0, width: 500, height: 700))
    #expect(SplitLogic.dividerFrame(in: area, ratio: 0.5) == CGRect(x: 510, y: 0, width: 10, height: 700))
    let uneven = SplitLogic.paneFrames(in: area, ratio: 0.3)
    #expect(uneven[0].width == 300 && uneven[1].width == 700)
  }

  @Test func theDividerKeepsEachPageWideEnough() {
    // 1000 pt beside the gap: each page at least 210 pt.
    #expect(SplitLogic.ratio(forDividerAt: 0, width: 1010, current: 0.5) == 0.21)
    #expect(SplitLogic.ratio(forDividerAt: 1010, width: 1010, current: 0.5) == 0.79)
    #expect(SplitLogic.ratio(forDividerAt: 305, width: 1010, current: 0.5) == 0.3)
    // Too narrow for two such pages: the ratio holds.
    #expect(SplitLogic.ratio(forDividerAt: 100, width: 400, current: 0.4) == 0.4)
  }

  @Test func theDividerSnapsToEqualPanesNearTheCentre() {
    #expect(SplitLogic.snappedRatio(forDividerAt: 520, width: 1010, current: 0.5) == 0.5)
    #expect(SplitLogic.snappedRatio(forDividerAt: 600, width: 1010, current: 0.5) != 0.5)
  }

  @Test func theSingleMenuListsTodaysOtherUnsplitTabs() {
    let mail = FakeTab(id: 1, title: "Mail")
    let news = FakeTab(id: 2, title: "News", splitPartnerID: 3, isLeadingPane: true)
    let docs = FakeTab(id: 3, title: "Docs", splitPartnerID: 2)
    let plan = FakeTab(id: 4, title: "Plan")
    let menu = SplitLogic.singlePageMenu(shown: 1, today: [mail, news, docs, plan])
    #expect(menu == [.heading("Split with Tab"), .tab(4, title: "Plan"), .separator, .newTab])
    #expect(SplitLogic.splitWithTabSubmenu(for: 4, today: [mail, plan]) == [.tab(1, title: "Mail"), .separator, .newTab])
  }

  @Test func aPanesMenuMovesTheOtherWay() {
    #expect(
      SplitLogic.paneMenu(isLeading: true) == [
        .moveLeft(isEnabled: false), .moveRight(isEnabled: true), .separator, .separateTabs, .closeThisTab,
      ])
    #expect(SplitLogic.paneMenu(isLeading: false).prefix(2) == [.moveLeft(isEnabled: true), .moveRight(isEnabled: false)])
  }

  @Test func aDropLandsOnTheHalfOrThePaneUnderIt() {
    let bounds = CGRect(x: 0, y: 0, width: 1010, height: 700)
    #expect(SplitLogic.dropZone(at: CGPoint(x: 100, y: 10), in: bounds, split: nil) == .half(.leading))
    #expect(SplitLogic.dropZone(at: CGPoint(x: 900, y: 10), in: bounds, split: nil) == .half(.trailing))
    let split = ShownSplit(leadingID: 1, trailingID: 2, ratio: 0.3, focusedIndex: 0)
    #expect(SplitLogic.dropZone(at: CGPoint(x: 400, y: 10), in: bounds, split: split) == .pane(1))
    #expect(SplitLogic.dropZone(at: CGPoint(x: 200, y: 10), in: bounds, split: split) == .pane(0))
    #expect(SplitLogic.dropZone(at: CGPoint(x: 2000, y: 10), in: bounds, split: split) == nil)
    // The page slides to the other half.
    #expect(SplitLogic.slidFrame(in: bounds, dropSide: .leading).minX == 510)
  }

  @Test func shownTabsAndSplitRowsMakeNoDropZone() {
    let shown = FakeTab(id: 1, title: "Shown")
    let other = FakeTab(id: 2, title: "Other")
    let paired = FakeTab(id: 3, title: "Paired", splitPartnerID: 4)
    #expect(SplitLogic.acceptsDrop(of: other, shown: nil, activeTabID: 1))
    #expect(!SplitLogic.acceptsDrop(of: shown, shown: nil, activeTabID: 1))
    #expect(!SplitLogic.acceptsDrop(of: paired, shown: nil, activeTabID: 1))
    let split = ShownSplit(leadingID: 1, trailingID: 5, ratio: 0.5, focusedIndex: 0)
    #expect(!SplitLogic.acceptsDrop(of: shown, shown: split, activeTabID: 1))
    #expect(SplitLogic.acceptsDrop(of: other, shown: split, activeTabID: 1))
    // A closed pin opens first, unless it's a pinned split's, which is a
    // split row.
    #expect(SplitLogic.acceptsDrop(of: nil, shown: nil, activeTabID: 1))
    #expect(!SplitLogic.acceptsDrop(of: nil, isPinnedSplit: true, shown: nil, activeTabID: 1))
  }

  @Test func theLinkStatusNamesWhatAClickDoes() {
    let url = "https://example.com/"
    #expect(SplitLogic.linkStatus(url: url, modifiers: [], opensPeekOnShiftClick: true, inPeek: false) == url)
    #expect(
      SplitLogic.linkStatus(url: url, modifiers: .option, opensPeekOnShiftClick: true, inPeek: false)
        == "Open https://example.com/ in Split View")
    #expect(
      SplitLogic.linkStatus(url: url, modifiers: .shift, opensPeekOnShiftClick: true, inPeek: false)
        == "Open https://example.com/ in Peek")
    #expect(SplitLogic.linkStatus(url: url, modifiers: .shift, opensPeekOnShiftClick: false, inPeek: false) == url)
    #expect(SplitLogic.linkStatus(url: url, modifiers: .option, opensPeekOnShiftClick: true, inPeek: true) == url)
    #expect(SplitLogic.linkStatus(url: url, modifiers: [.option, .command], opensPeekOnShiftClick: true, inPeek: false) == url)
  }

  @Test func theCommandBarCentresOnThePaneInsideTheWindow() {
    let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
    #expect(SplitLogic.commandBarMinX(width: 600, pane: nil, bounds: bounds) == 300)
    #expect(SplitLogic.commandBarMinX(width: 400, pane: CGRect(x: 700, y: 0, width: 500, height: 800), bounds: bounds) == 750)
    // Narrower than the bar: kept inside the window.
    #expect(SplitLogic.commandBarMinX(width: 600, pane: CGRect(x: 900, y: 0, width: 300, height: 800), bounds: bounds) == 600)
  }

  /// D9: a pinned tab or favorite whose page is in a split can't make
  /// another.
  @MainActor
  @Test func splitWithTabIsDisabledOnASplitPin() {
    let split = FakePin(
      id: "p", url: "https://mail.example/", title: "Mail", tab: FakeTab(id: 1, title: "Mail", splitPartnerID: 2))
    let lone = FakePin(id: "q", url: "https://news.example/", title: "News", tab: FakeTab(id: 3, title: "News"))
    let menu = PinsLogic.pinnedMenu(isOpen: true, isMuted: false, canMoveToSpace: false)
    let splitItem = PinMenus.items(menu, pin: split, actions: nil).first { $0.title == "Split with Tab" }
    let loneItem = PinMenus.items(menu, pin: lone, actions: nil).first { $0.title == "Split with Tab" }
    if case .disabledSubmenu = splitItem {} else { Issue.record("Split with Tab isn't disabled") }
    if case .submenu = loneItem {} else { Issue.record("Split with Tab isn't a submenu") }
  }

  /// A split's pane headers show with the toolbar off, where Hide Toolbar
  /// would do nothing.
  @Test(arguments: [true, false])
  func theHeadersMenuOffersHideToolbarOnlyWhileItsOn(showsToolbar: Bool) {
    let titles = PageToolbar.menuItems(canCopy: true, showsToolbar: showsToolbar, copy: {}, hide: {}).map(\.title)
    #expect(titles == (showsToolbar ? ["Copy URL", nil, "Hide Toolbar"] : ["Copy URL"]))
    let blank = PageToolbar.menuItems(canCopy: false, showsToolbar: showsToolbar, copy: {}, hide: {}).map(\.title)
    #expect(blank == (showsToolbar ? ["Hide Toolbar"] : []))
  }

  @Test func paneHeadersExpandWhileFocusedOrHovered() {
    let leading = PageHeaderContent.pane(leading: true, toggle: true, expanded: false)
    #expect(leading.showsSidebarToggle && !leading.showsReload && !leading.showsSplitButton && leading.showsClose)
    #expect(leading.trailingFixedCount == 1)
    // With the toolbar off, the sidebar keeps the toggle.
    let untoggled = PageHeaderContent.pane(leading: true, toggle: false, expanded: false)
    #expect(!untoggled.showsSidebarToggle && untoggled.leadingCount == 2)
    let trailing = PageHeaderContent.pane(leading: false, toggle: false, expanded: true)
    #expect(!trailing.showsSidebarToggle && trailing.showsReload && trailing.showsSplitButton)
    #expect(trailing.trailingFixedCount == 3)
    #expect(trailing.identifier == "clair.paneToolbar.1")
    #expect(PageHeaderContent.tab.showsSplitButton && !PageHeaderContent.tab.showsClose)
    #expect(!PageHeaderContent.peek.showsSplitButton)
  }
}

/// One row for a split, its tabs in pane order (add-split-view D2).
struct SplitRowListTests {
  @Test func aSplitsTrailingPaneFoldsIntoItsRow() {
    let mail = FakeTab(id: 1, title: "Mail")
    let news = FakeTab(id: 2, title: "News", splitPartnerID: 3, isLeadingPane: true)
    let docs = FakeTab(id: 3, title: "Docs", splitPartnerID: 2)
    let tabs: [any ClairTab] = [mail, news, docs]
    #expect(TabListLogic.rows(tabs).map(\.title) == ["Mail", "News"])
    #expect(TabListLogic.highlightedRow(activeTabID: 3, in: tabs) == 2)
    #expect(TabListLogic.rowFamily(2, in: tabs) == [2, 3])
    #expect(SplitLogic.shownSplit(activeTabID: 3, in: tabs) == ShownSplit(leadingID: 2, trailingID: 3, ratio: 0.5, focusedIndex: 1))
    #expect(SplitLogic.shownSplit(activeTabID: 1, in: tabs) == nil)
  }
}

/// The fake engine's splits, which the window tests rely on (add-split-view
/// tasks 1.3).
@MainActor
struct FakeSplitTests {
  let browser = FakeBrowser()
  let window = RecordingWindow()
  let mail: FakeTab
  let news: FakeTab
  let docs: FakeTab

  init() {
    browser.clairWindow = window
    docs = browser.addTab(title: "Docs")
    news = browser.addTab(title: "News")
    mail = browser.addTab(title: "Mail")
  }

  private func tab(_ tab: FakeTab) -> FakeTab { browser.host.tab(tab.tabID)! }

  @Test func splittingMakesTheOtherTabTrailingAndFocused() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    #expect(tab(mail).splitPartnerID == docs.tabID && tab(mail).isLeadingPane)
    #expect(tab(docs).splitPartnerID == mail.tabID && !tab(docs).isLeadingPane)
    #expect(browser.activeTabID == docs.tabID)
    #expect(browser.isShowingSplit(of: mail.tabID))
    // Already in a split: nothing.
    browser.split(tab: news.tabID, with: docs.tabID, side: .trailing)
    #expect(tab(news).splitPartnerID == ClairTabIDNone)
  }

  @Test func aLeadingSideDropPutsTheOtherTabFirst() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .leading)
    #expect(tab(docs).isLeadingPane && !tab(mail).isLeadingPane)
  }

  @Test func swappingKeepsTheFocus() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    browser.swapSplit(of: docs.tabID)
    #expect(tab(docs).isLeadingPane)
    #expect(browser.activeTabID == docs.tabID)
  }

  @Test func theRatioIsKept() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    browser.setSplitRatio(0.3, of: mail.tabID)
    #expect(abs(tab(mail).splitRatio - 0.3) < 0.001 && abs(tab(docs).splitRatio - 0.3) < 0.001)
  }

  @Test func separatingKeepsBothTabsInPaneOrder() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    browser.separateSplit(of: mail.tabID)
    #expect(tab(mail).splitPartnerID == ClairTabIDNone && tab(docs).splitPartnerID == ClairTabIDNone)
    #expect(browser.tabs.contains { $0.tabID == mail.tabID } && browser.tabs.contains { $0.tabID == docs.tabID })
  }

  @Test func closingAPaneLeavesTheOtherAlone() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    browser.close(tab: docs.tabID)
    #expect(!browser.tabs.contains { $0.tabID == docs.tabID })
    #expect(tab(mail).splitPartnerID == ClairTabIDNone)
    #expect(browser.activeTabID == mail.tabID)
  }

  @Test func closingTheSplitClosesBothPanes() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    browser.closeSplit(of: mail.tabID)
    #expect(!browser.tabs.contains { $0.tabID == mail.tabID || $0.tabID == docs.tabID })
    #expect(browser.activeTabID == news.tabID)
  }

  @Test func replacingAPaneTakesItsPlace() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    browser.replacePane(of: docs.tabID, with: news.tabID)
    #expect(tab(mail).splitPartnerID == news.tabID && tab(news).splitPartnerID == mail.tabID)
    #expect(tab(docs).splitPartnerID == ClairTabIDNone)
    #expect(browser.activeTabID == news.tabID)
  }

  @Test func aNewTabSplitAddsANewTabPage() {
    browser.splitWithNewTab(mail.tabID)
    let page = tab(mail).splitPartnerID
    #expect(page != ClairTabIDNone)
    #expect(browser.host.tab(page)?.urlText == "chrome://newtab/")
    #expect(browser.activeTabID == page)
  }

  @Test func aPeekOpensInSplitWithItsParent() {
    let peek = browser.openPeek(of: mail.tabID, title: "Peek")!
    browser.openPeekInSplit(of: mail.tabID)
    #expect(tab(mail).splitPartnerID == peek.tabID)
    #expect(tab(peek).peekParentID == ClairTabIDNone)
    #expect(browser.activeTabID == peek.tabID)
  }

  @Test func showingASplitFocusesThePaneFocusedLast() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    browser.activate(tab: news.tabID)
    browser.showSplit(of: mail.tabID)
    #expect(browser.activeTabID == docs.tabID)
  }
}

/// Pinned and favorited splits in the fake store (add-split-view D10).
@MainActor
struct FakePinnedSplitTests {
  let host = FakeHost()

  @Test func aPinnedSplitIsOneItem() {
    host.addPin(url: "https://mail.example/", title: "Mail")
    host.addSplit(("https://news.example/", "News"), ("https://docs.example/", "Docs"), ratio: 0.4)
    let items = host.pinnedItems(inSpace: FakeHost.homeID)
    #expect(items.count == 2)
    let split = items[1].split
    #expect(split?.pins.map(\.title) == ["News", "Docs"])
    #expect(abs((split?.ratio ?? 0) - 0.4) < 0.001)
    #expect(split?.pins.allSatisfy { $0.pinnedSplitID == split?.pinnedSplitID } == true)
    let rows = PinsLogic.pinnedRows(items, collapsed: false, highlighted: ClairTabIDNone)
    #expect(rows.count == 2)
    if case .split = rows[1] {} else { Issue.record("The split isn't one row") }
  }

  @Test func separatingPutsItsPinsInItsPlace() {
    host.addSplit(("https://news.example/", "News"), ("https://docs.example/", "Docs"))
    host.addPin(url: "https://mail.example/", title: "Mail")
    let splitID = host.pinnedItems(inSpace: FakeHost.homeID)[0].split!.pinnedSplitID
    host.separatePinnedSplit(splitID)
    let titles = host.pinnedItems(inSpace: FakeHost.homeID).map { $0.pin?.title ?? "" }
    #expect(titles == ["News", "Docs", "Mail"])
  }

  @Test func aFavoritedSplitIsOneTile() {
    host.addSplit(("https://news.example/", "News"), ("https://docs.example/", "Docs"), inSpace: nil)
    let items = host.favorites(ofProfile: FakeHost.defaultProfileID)
    #expect(items.count == 1)
    #expect(items[0].split?.isFavorite == true)
    #expect(PinsLogic.allPins(items).map(\.title) == ["News", "Docs"])
  }
}

/// The window's split view (add-split-view D3, D9).
@MainActor
struct SplitWindowTests {
  let browser = FakeBrowser()
  let controller: BrowserWindowController
  let mail: FakeTab
  let docs: FakeTab

  init() {
    let defaults = UserDefaults(suiteName: "ClairUITests.Split.\(UUID().uuidString)")!
    controller = BrowserWindowController(
      browser: browser, spaces: browser.spaces, preferences: SidebarPreferences(defaults: defaults),
      peekPreference: PeekPreference(defaults: defaults))
    browser.clairWindow = controller
    docs = browser.addTab(title: "Docs", url: "https://docs.example/")
    mail = browser.addTab(title: "Mail", url: "https://mail.example/")
  }

  @Test func eachPaneShowsItsPage() {
    let root = controller.rootView
    #expect(root.secondCard.isHidden || controller.model.shownSplit == nil)
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    #expect(controller.model.shownSplit == ShownSplit(leadingID: mail.tabID, trailingID: docs.tabID, ratio: 0.5, focusedIndex: 1))
    #expect(root.card.pageView === browser.pageView(for: mail.tabID))
    #expect(root.secondCard.pageView === browser.pageView(for: docs.tabID))
    #expect(root.focusedCard === root.secondCard)
    // Swapped: the pages change cards.
    browser.swapSplit(of: docs.tabID)
    #expect(root.card.pageView === browser.pageView(for: docs.tabID))
    #expect(root.secondCard.pageView === browser.pageView(for: mail.tabID))
    // Separated: the focused tab alone.
    browser.separateSplit(of: docs.tabID)
    #expect(controller.model.shownSplit == nil)
    #expect(root.card.pageView === browser.pageView(for: docs.tabID))
    #expect(root.secondCard.pageView == nil)
  }

  @Test func addSplitViewWhileSplitShowsAToast() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    controller.addSplitView()
    #expect(controller.model.toast?.message == "Cannot Add New Pane")
  }

  @Test func addSplitViewOpensTheCommandBarOnTheNewPane() {
    controller.addSplitView()
    let split = controller.model.shownSplit
    #expect(split?.leadingID == mail.tabID)
    #expect(split?.focusedIndex == 1)
    #expect(controller.model.commandBar != nil)
  }

  @Test func aTabsMenuSplitsItWithTheChosenTab() {
    let items = controller.splitWithTabItems(tab: docs.tabID, pin: nil)
    #expect(items.compactMap(\.title) == ["Mail", "New Tab"])
    guard case .icon(_, _, let run) = items[0] else {
      Issue.record("Mail isn't an item with its favicon")
      return
    }
    run()
    #expect(browser.host.tab(docs.tabID)?.splitPartnerID == mail.tabID)
    #expect(browser.host.tab(docs.tabID)?.isLeadingPane == true)
    #expect(browser.activeTabID == mail.tabID)
  }

  @Test func theMenuBarItemsFollowTheSplit() {
    let menu = SplitMenu()
    menu.currentController = { [controller] in controller }
    let main = NSMenu()
    for (title, tag) in [("Tab", PinsMenu.tabMenuTag), ("View", PinsMenu.viewMenuTag)] {
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      item.tag = tag
      item.submenu = NSMenu(title: title)
      main.addItem(item)
    }
    #expect(menu.install(in: main))
    let view = main.items[1].submenu!
    #expect(view.items.prefix(3).map(\.title) == ["Add Split View", "Close Split Pane", "Separate Tabs"])
    let close = menu.items[.closeSplitPane]!
    #expect(close.keyEquivalent == "-" && close.keyEquivalentModifierMask == [.control, .shift])
    #expect(!menu.validateMenuItem(close))
    #expect(menu.validateMenuItem(menu.items[.splitWithTab]!))
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    #expect(menu.validateMenuItem(close))
    #expect(!menu.validateMenuItem(menu.items[.splitWithTab]!))
    // Close Split Pane closes the focused pane.
    menu.choose(close)
    #expect(!browser.tabs.contains { $0.tabID == docs.tabID })
    #expect(controller.model.shownSplit == nil)
  }

  @Test func theDividerSnapsToEqualPanesAsItMoves() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    let root = controller.rootView
    root.frame = CGRect(x: 0, y: 0, width: 1400, height: 900)
    root.layoutSubtreeIfNeeded()
    let width = root.pageArea.width
    let divider = root.splitDivider
    divider.onDrag?(width / 2 - 150, false)
    #expect(controller.model.liveSplitRatio != 0.5)
    // Within the snap distance, before letting go: equal panes.
    divider.onDrag?(width / 2 + 12, false)
    #expect(controller.model.liveSplitRatio == 0.5)
    divider.onDrag?(width / 2 + 12, true)
    #expect(browser.host.tab(mail.tabID)?.splitRatio == 0.5)
    // The grabber rests faint until the pointer is over it.
    #expect(divider.grabberAlpha == SplitDividerView.restingAlpha)
  }

  /// Double-clicking the divider centres it; the second click doesn't drag
  /// it back to the pointer.
  @Test func doubleClickingTheDividerCentresIt() throws {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    let root = controller.rootView
    root.frame = CGRect(x: 0, y: 0, width: 1400, height: 900)
    root.layoutSubtreeIfNeeded()
    let width = root.pageArea.width
    let divider = root.splitDivider
    divider.onDrag?(width / 2 - 150, true)
    #expect((browser.host.tab(mail.tabID)?.splitRatio ?? 0.5) < 0.45)
    let point = divider.convert(CGPoint(x: divider.bounds.midX, y: divider.bounds.midY), to: nil)
    for count in [1, 2] {
      for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = try #require(
          NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: count, pressure: 1))
        if type == .leftMouseDown { divider.mouseDown(with: event) } else { divider.mouseUp(with: event) }
      }
    }
    #expect(browser.host.tab(mail.tabID)?.splitRatio == 0.5)
    #expect(controller.model.liveSplitRatio == 0.5)
  }

  @Test func theDividerKeepsTheRatioItsLetGoAt() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    let root = controller.rootView
    root.frame = CGRect(x: 0, y: 0, width: 1400, height: 900)
    root.layoutSubtreeIfNeeded()
    let width = root.pageArea.width
    root.splitDivider.onDrag?(width / 2 - 150, true)
    let ratio = browser.host.tab(mail.tabID)?.splitRatio ?? 0.5
    #expect(ratio < 0.45)
    #expect(abs(ratio - (controller.model.liveSplitRatio ?? ratio)) < 0.001)
  }

  @Test func aDraggedRatioBelongsToItsSplit() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    guard let split = controller.model.shownSplit else {
      Issue.record("No split")
      return
    }
    controller.model.liveSplitPanes = split.paneIDs
    controller.model.liveSplitRatio = 0.3
    #expect(controller.model.liveRatio(of: split) == 0.3)
    let other = ShownSplit(leadingID: 90, trailingID: 91, ratio: 0.6, focusedIndex: 0)
    #expect(controller.model.liveRatio(of: other) == nil)
    // Another split shown, or none: the dragged ratio goes.
    browser.separateSplit(of: docs.tabID)
    controller.settleSplitRatio()
    #expect(controller.model.liveSplitRatio == nil)
  }

  @Test func theTrailingPanesPageFillsTheWindowInPageFullScreen() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    let root = controller.rootView
    root.frame = CGRect(x: 0, y: 0, width: 1400, height: 900)
    controller.model.isPageFullscreen = true
    root.needsLayout = true
    root.layoutSubtreeIfNeeded()
    #expect(controller.model.shownSplit?.focusedIndex == 1)
    #expect(root.focusedCard === root.secondCard)
    #expect(!root.secondCard.isHidden && root.card.isHidden)
    #expect(root.secondCard.frame == root.pageArea)
    #expect(root.secondCard.pageView === browser.pageView(for: docs.tabID))
  }

  @Test func pinCommandsActOnTheFocusedPane() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    // The row stays highlighted on its leading pane.
    #expect(controller.model.highlightedTab == mail.tabID)
    #expect(controller.model.commandTab == docs.tabID)
  }

  @Test func aFavoriteDroppedInPlaceStaysThereAfterASplit() {
    let host = browser.host
    host.addSplit(("https://news.example/", "News"), ("https://docs.example/", "Docs"), inSpace: nil)
    let c = host.addPin(url: "https://c.example/", title: "C", inSpace: nil)
    host.addPin(url: "https://d.example/", title: "D", inSpace: nil)
    host.addPin(url: "https://e.example/", title: "E", inSpace: nil)
    // Slot 2, just after C's tile: where it is.
    controller.drop(.pin(c), on: .favorites(2))
    #expect(
      host.favoriteRecords(ofProfile: FakeHost.defaultProfileID).map(\.title) == ["News", "Docs", "C", "D", "E"])
  }

  @Test func aDraggedSplitShowsBothIcons() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    #expect(controller.model.icons(of: .tab(mail.tabID)).count == 2)
    let other = browser.addTab(title: "Other", url: "https://other.example/")
    #expect(controller.model.icons(of: .tab(other.tabID)).count == 1)
  }

  @Test func theSplitButtonsMenuHasAHeadingAndItsTabs() {
    var chosen: SplitLogic.MenuEntry?
    let entries = SplitLogic.singlePageMenu(shown: docs.tabID, today: browser.tabs)
    let menu = SplitButton.menu(entries, icon: { _ in nil }) { chosen = $0 }
    #expect(menu.items.map(\.title) == ["Split with Tab", "Mail", "", "New Tab"])
    #expect(menu.items[0].isSectionHeader)
    // A page without a favicon shows the globe.
    #expect(menu.items[1].image === HistoryMenuBuilder.placeholderIcon)
    if #available(macOS 27, *) {
      #expect(menu.items[1].preferredImageVisibility == .visible)
    }
    let mailItem = menu.items[1]
    _ = (mailItem.target as? NSObject)?.perform(mailItem.action, with: mailItem)
    #expect(chosen == .tab(mail.tabID, title: "Mail"))
    let pane = SplitButton.menu(SplitLogic.paneMenu(isLeading: true), icon: { _ in nil }) { _ in }
    #expect(!pane.items[0].isEnabled && pane.items[1].isEnabled)
  }

  @Test func theLinkStatusLaysTheWindowOutWhenItsWordsChange() {
    let superview = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    let host = SelfSizingHostingView(rootView: CapsuleText(text: "https://docs.example/", identifier: "clair.status"))
    host.tracksWidth = true
    superview.addSubview(host)
    host.frame = CGRect(origin: .zero, size: host.fittingSize)
    superview.layoutSubtreeIfNeeded()
    #expect(!superview.needsLayout)
    // Option's words make it wider, at the same height.
    host.rootView = CapsuleText(text: "Option-click to open in split view: https://docs.example/", identifier: "clair.status")
    host.layoutSubtreeIfNeeded()
    #expect(superview.needsLayout)
  }

  @Test func theSplitRowStandsForBothTabs() {
    browser.split(tab: mail.tabID, with: docs.tabID, side: .trailing)
    #expect(TabListLogic.rows(controller.model.tabs).map(\.title) == ["Mail"])
    #expect(controller.model.highlightedTab == mail.tabID)
  }
}
