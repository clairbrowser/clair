// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Foundation
import Testing

@testable import ClairUI

// MARK: Recent tabs (tab-switcher, "Recent tabs"; design D1)

/// A window's recents, read through its controller as Chromium drives it.
@MainActor
struct RecentTabsTests {
  let window = PinWindow()

  private var recents: [String] {
    let tabs = window.controller.switcherTabs
    return window.controller.recentTabIDs.map { tabs[$0]?.title ?? "?\($0)" }
  }

  @Test func theMostRecentComesFirst() {
    let mail = window.browser.addTab(title: "Mail")
    let news = window.browser.addTab(title: "News")
    let docs = window.browser.addTab(title: "Docs")
    window.browser.activate(tab: mail.tabID)
    window.browser.activate(tab: news.tabID)
    window.browser.activate(tab: docs.tabID)
    #expect(recents == ["Docs", "News", "Mail"])
  }

  @Test func theyGoAcrossSpaces() {
    let home = window.browser.shownSpaceID
    let work = window.host.addSpaces("Work")[0]
    window.browser.addTab(title: "Recipes")
    window.browser.showSpace(work)
    window.browser.addTab(title: "Mail")
    // Home shows the tab last shown there.
    window.browser.showSpace(home)
    #expect(recents.prefix(2) == ["Recipes", "Mail"])
  }

  @Test func aPinnedTabLeavesWhenItsPageCloses() throws {
    window.browser.addTab(title: "News")
    let pinID = window.host.addPin(url: "https://mail.example/", title: "Mail")
    window.browser.openPin(pinID)
    window.browser.addTab(title: "Docs")
    #expect(recents == ["Docs", "Mail", "News"])
    window.controller.closeKeepingPin(pinID)
    #expect(recents == ["Docs", "News"])
  }

  @Test func aFavoriteCounts() {
    let pinID = window.host.addPin(url: "https://calendar.example/", title: "Calendar", inSpace: nil)
    window.browser.addTab(title: "News")
    window.browser.openPin(pinID)
    window.browser.addTab(title: "Docs")
    #expect(recents == ["Docs", "Calendar", "News"])
  }

  /// A tab and its Peek are one entry (peek spec, "Ctrl+Tab across a Peek").
  @Test func aPeekCountsAsItsParent() throws {
    window.browser.addTab(title: "Docs")
    let mail = window.browser.addTab(title: "Mail")
    let peek = try #require(window.browser.openPeek(of: mail.tabID, title: "Peek"))
    window.browser.activate(tab: peek.tabID)
    #expect(recents == ["Mail", "Docs"])
    #expect(window.controller.recents.ids.first == mail.tabID)
  }

  /// A split is one entry, through its leading pane (split-view spec).
  @Test func aSplitCountsOnce() {
    let docs = window.browser.addTab(title: "Docs")
    let news = window.browser.addTab(title: "News")
    let mail = window.browser.addTab(title: "Mail")
    window.browser.split(tab: news.tabID, with: docs.tabID, side: .trailing)
    window.browser.activate(tab: news.tabID)
    window.browser.activate(tab: mail.tabID)
    window.browser.activate(tab: docs.tabID)
    #expect(window.controller.recentTabIDs == [news.tabID, mail.tabID])
  }

  @Test func aClosedTabLeaves() {
    let mail = window.browser.addTab(title: "Mail")
    window.browser.addTab(title: "Docs")
    window.browser.closeTabNow(mail.tabID)
    #expect(recents == ["Docs"])
  }

  /// The still's placeholder is in no Space, and never enters the list.
  @Test func theStillsPlaceholderNeverEnters() {
    let w = SharedWindows()
    w.a.activate(tab: w.notes.tabID)
    w.a.activate(tab: w.docs.tabID)
    w.b.activate(tab: w.docs.tabID)
    #expect(w.controllerA.model.isShowingStill)
    #expect(w.controllerA.recentTabIDs == [w.docs.tabID, w.notes.tabID])
  }

  /// The incoming window of a profile swap takes the outgoing one's list.
  @Test func theIncomingWindowTakesTheList() {
    let mail = window.browser.addTab(title: "Mail")
    let docs = window.browser.addTab(title: "Docs")
    let other = FakeBrowser(host: window.host)
    let incoming = BrowserWindowController(browser: other, spaces: other.spaces)
    other.clairWindow = incoming
    incoming.shownSpaceDidChange(
      window.browser.shownSpaceID, from: window.browser.shownSpaceID, swappedInFor: window.browser.browserID)
    #expect(incoming.recentTabIDs.prefix(2) == [docs.tabID, mail.tabID])
  }

  @Test func rowsResolveFromThePeekAndTheTrailingPane() {
    let parent = FakeTab(id: 1, title: "Parent", peekID: 2)
    let peek = FakeTab(id: 2, title: "Peek", peekParentID: 1)
    let lead = FakeTab(id: 3, title: "Lead", splitPartnerID: 4, isLeadingPane: true)
    let trail = FakeTab(id: 4, title: "Trail", splitPartnerID: 3)
    let tabs: [TabID: any ClairTab] = [1: parent, 2: peek, 3: lead, 4: trail]
    #expect(RecentTabs.row(of: 2, in: tabs) == 1)
    #expect(RecentTabs.row(of: 4, in: tabs) == 3)
    #expect(RecentTabs.row(of: 3, in: tabs) == 3)
    #expect(RecentTabs.row(of: 9, in: tabs) == nil)
    var recents = RecentTabs([4, 1, 3, 9])
    recents.prune(in: tabs)
    #expect(recents.ids == [3, 1])
    let unknown = recents.show(9, in: tabs)
    #expect(!unknown)
    let fromPeek = recents.show(2, in: tabs)
    #expect(fromPeek)
    #expect(recents.ids == [1, 3])
  }
}

// MARK: The switcher's state (design D2, D3)

struct SwitcherStateTests {
  let t0 = ContinuousClock.now
  let recents: [TabID] = [1, 2, 3, 4, 5, 6, 7]

  /// tab-switcher, "Seven recent tabs".
  @Test func ctrlTabOpensOnTheFirstFiveWithTheSecondSelected() {
    var state = SwitcherState()
    let r1 = state.open(recents: recents, forward: true, at: t0)
    #expect(r1)
    #expect(state.entries == [1, 2, 3, 4, 5])
    #expect(state.selectedTab == 2)
  }

  /// "Backwards".
  @Test func ctrlShiftTabSelectsTheLast() {
    var state = SwitcherState()
    state.open(recents: recents, forward: false, at: t0)
    #expect(state.selectedTab == 5)
  }

  /// "Two recent tabs" and "One tab".
  @Test func itNeedsTwoRecentTabs() {
    var state = SwitcherState()
    state.open(recents: [1, 2], forward: true, at: t0)
    #expect(state.entries == [1, 2] && state.selectedTab == 2)
    state.cancel()
    let r2 = state.open(recents: [1], forward: true, at: t0)
    #expect(!r2)
    let r3 = state.open(recents: [], forward: true, at: t0)
    #expect(!r3)
    #expect(!state.isOpen)
  }

  /// "Moving the selection": "Stepping" and "Wrapping".
  @Test func tabStepsAndWraps() {
    var state = SwitcherState()
    state.open(recents: recents, forward: true, at: t0)
    state.step(forward: true)
    #expect(state.selectedTab == 3)
    state.step(forward: true)
    state.step(forward: true)
    #expect(state.selectedTab == 5)
    state.step(forward: true)
    #expect(state.selectedTab == 1)
    state.step(forward: false)
    #expect(state.selectedTab == 5)
  }

  /// "Choosing a tab": the selected tab, and nothing for the shown one.
  @Test func releasingCtrlChoosesTheSelectedTab() {
    var state = SwitcherState()
    state.open(recents: recents, forward: true, at: t0)
    state.step(forward: true)
    let r4 = state.commit()
    #expect(r4 == 3)
    #expect(!state.isOpen)
    state.open(recents: recents, forward: true, at: t0)
    state.step(forward: false)
    let r5 = state.commit()
    #expect(r5 == nil)
    let r6 = state.commit()
    #expect(r6 == nil)
  }

  @Test func aCardChosenWithThePointerWins() {
    var state = SwitcherState()
    state.open(recents: recents, forward: true, at: t0)
    let r7 = state.commit(card: 3)
    #expect(r7 == 4)
  }

  /// "Cancelling the switcher".
  @Test func escChoosesNothing() {
    var state = SwitcherState()
    state.open(recents: recents, forward: true, at: t0)
    state.cancel()
    let afterCancel = state.commit()
    #expect(!state.isOpen && afterCancel == nil)
  }

  /// "A quick Ctrl+Tab shows no panel", "Holding Ctrl" and "Two quick Tabs".
  @Test func thePanelWaitsAHundredMilliseconds() {
    var state = SwitcherState()
    state.open(recents: recents, forward: true, at: t0)
    #expect(!state.isPanelShown)
    #expect(state.panelDeadline == t0.advanced(by: .milliseconds(100)))
    state.update(at: t0.advanced(by: .milliseconds(99)))
    #expect(!state.isPanelShown)
    state.update(at: t0.advanced(by: .milliseconds(100)))
    #expect(state.isPanelShown)
    #expect(state.panelDeadline == nil)
    // A quick tap: released before the panel is due.
    state.open(recents: recents, forward: true, at: t0)
    let r8 = state.commit()
    #expect(r8 == 2)
    #expect(!state.isPanelShown)
    // A second Tab within the delay shows it at once, on the third card.
    state.open(recents: recents, forward: true, at: t0)
    state.step(forward: true)
    #expect(state.isPanelShown && state.selectedTab == 3)
  }
}

// MARK: The keys and the pointer (design D2)

/// A window the switcher sits over, standing in for the controller.
@MainActor
final class StubSwitcherHost: TabSwitcherHost {
  let switcherWindow = NSWindow(
    contentRect: CGRect(x: 100, y: 100, width: 1000, height: 700), styleMask: [.titled], backing: .buffered,
    defer: true)
  var switcherMayAct = true
  var recentTabIDs: [TabID] = [1, 2, 3, 4]
  private(set) var shown: [TabID] = []
  private(set) var previewRequests: [TabID] = []
  /// When set, previews wait here instead of arriving at once.
  var holdsPreviews = false
  var heldPreviews: [(TabID, (NSImage?) -> Void)] = []

  init() {
    switcherWindow.isReleasedWhenClosed = false
  }

  func switcherCards(for entries: [TabID]) -> [SwitcherCard] {
    entries.map { SwitcherCard(id: $0, paneIDs: [$0], title: "Tab \($0)", favicons: [nil], label: "Tab \($0)") }
  }

  func requestSwitcherPreview(of tabID: TabID, size: NSSize, completion: @escaping (NSImage?) -> Void) {
    previewRequests.append(tabID)
    if holdsPreviews {
      heldPreviews.append((tabID, completion))
    } else {
      completion(NSImage(size: size))
    }
  }

  func showFromSwitcher(_ tabID: TabID) {
    shown.append(tabID)
  }
}

@MainActor
struct TabSwitcherKeyTests {
  let host = StubSwitcherHost()
  let switcher: TabSwitcher

  init() {
    switcher = TabSwitcher(host: host)
    // The panel's delay never ends on its own here; a second Tab shows it.
    switcher.wait = { _ in try? await Task.sleep(for: .seconds(3600)) }
  }

  private func key(
    _ code: UInt16, _ flags: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown, repeat: Bool = false
  ) -> NSEvent {
    let characters = code == 48 ? "\t" : (code == 53 ? "\u{1b}" : "a")
    return NSEvent.keyEvent(
      with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
      characters: characters, charactersIgnoringModifiers: characters, isARepeat: `repeat`, keyCode: code)!
  }

  private func flags(_ flags: NSEvent.ModifierFlags) -> NSEvent {
    NSEvent.keyEvent(
      with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
      characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 59)!
  }

  @Test func ctrlTabIsTakenAndOtherKeysPassWhileClosed() {
    #expect(!switcher.handle(key(48)))
    #expect(!switcher.handle(key(0, .control)))
    #expect(!switcher.handle(key(48, [.control, .command])))
    #expect(!switcher.state.isOpen)
    #expect(switcher.handle(key(48, .control)))
    #expect(switcher.state.isOpen)
    // Its key-up goes no further either.
    #expect(switcher.handle(key(48, .control, type: .keyUp)))
    #expect(switcher.state.entries == [1, 2, 3, 4])
    #expect(host.previewRequests == [1, 2, 3, 4])
    switcher.cancel()
  }

  @Test func aPreviewFromAnEarlierOpeningIsDropped() {
    host.holdsPreviews = true
    switcher.handle(key(48, .control))
    let earlier = host.heldPreviews
    switcher.handle(key(53, .control))
    switcher.handle(flags([]))
    switcher.handle(key(48, .control))
    for (_, completion) in earlier {
      completion(NSImage(size: NSSize(width: 1, height: 1)))
    }
    #expect(switcher.panelModel.previews.isEmpty)
    let current = host.heldPreviews.dropFirst(earlier.count)
    for (_, completion) in current {
      completion(NSImage(size: NSSize(width: 2, height: 2)))
    }
    #expect(switcher.panelModel.previews.count == 4)
    #expect(switcher.panelModel.previews.values.allSatisfy { $0.size.width == 2 })
    switcher.cancel()
  }

  @Test func releasingCtrlShowsTheSelectedTab() {
    #expect(switcher.handle(key(48, .control)))
    #expect(!switcher.state.isPanelShown)
    #expect(!switcher.handle(flags([])))
    #expect(host.shown == [2])
    #expect(!switcher.state.isOpen)
  }

  @Test func tabStepsAndEscCancels() {
    switcher.handle(key(48, .control))
    #expect(switcher.handle(key(48, .control)))
    #expect(switcher.state.isPanelShown && switcher.state.selectedTab == 3)
    #expect(switcher.handle(key(48, [.control, .shift])))
    #expect(switcher.state.selectedTab == 2)
    // Any other key is swallowed while it's open.
    #expect(switcher.handle(key(0, .control)))
    #expect(switcher.handle(key(53, .control)))
    #expect(!switcher.state.isOpen)
    switcher.handle(flags([]))
    #expect(host.shown.isEmpty)
  }

  @Test func clickingACardShowsItsTab() {
    switcher.handle(key(48, .control))
    switcher.handle(key(48, .control))
    let card = SwitcherLayout.cardFrame(3)
    // From the panel's bottom left.
    #expect(switcher.click(at: CGPoint(x: card.midX, y: SwitcherLayout.height - card.midY)))
    #expect(host.shown == [4])
    // Releasing Ctrl then changes nothing.
    switcher.handle(flags([]))
    #expect(host.shown == [4])
    #expect(!switcher.click(at: CGPoint(x: card.midX, y: 10)))
  }

  /// A key held down before the switcher opened keeps its release: the
  /// switcher swallows its repeats, but its key-up goes on to the page.
  @Test func aKeyPressedBeforeKeepsItsRelease() {
    switcher.handle(key(48, .control))
    #expect(switcher.handle(key(125, .control, repeat: true)))
    switcher.handle(key(53, .control))
    #expect(!switcher.handle(key(125, type: .keyUp)))
    // Esc, pressed inside the switcher, has its release taken.
    #expect(switcher.handle(key(53, type: .keyUp)))
  }

  @Test func nothingHappensWhileADialogIsUp() {
    host.switcherMayAct = false
    #expect(!switcher.handle(key(48, .control)))
    #expect(!switcher.state.isOpen)
  }

  @Test func oneRecentTabOpensNothingButCtrlTabIsStillTaken() {
    host.recentTabIDs = [1]
    #expect(switcher.handle(key(48, .control)))
    #expect(!switcher.state.isOpen)
  }

  @Test func theShownTabClosingCancels() {
    switcher.handle(key(48, .control))
    switcher.tabsDidChange(open: [2, 3, 4])
    #expect(!switcher.state.isOpen)
  }
}

// MARK: The panel's layout (design D3)

struct SwitcherLayoutTests {
  /// tab-switcher, "Five cards": about 938 by 189 points.
  @Test(arguments: [(1, 211.5), (2, 393.0), (3, 574.5), (4, 756.0), (5, 937.5)])
  func thePanelFitsItsCards(cards: Int, width: Double) {
    #expect(SwitcherLayout.panelSize(cards: cards) == CGSize(width: width, height: 189))
  }

  @Test func eachCardsHighlightIsTwelvePointsAroundItsPreview() {
    #expect(SwitcherLayout.cardFrame(0) == CGRect(x: 15, y: 15, width: 181.5, height: 157.5))
    #expect(SwitcherLayout.cardFrame(2).minX == 15 + 2 * 181.5)
    #expect(SwitcherLayout.card(at: CGPoint(x: 20, y: 100), cards: 5) == 0)
    #expect(SwitcherLayout.card(at: CGPoint(x: 200, y: 100), cards: 5) == 1)
    #expect(SwitcherLayout.card(at: CGPoint(x: 5, y: 100), cards: 5) == nil)
    #expect(SwitcherLayout.card(at: CGPoint(x: 200, y: 180), cards: 5) == nil)
  }

  @Test func itsCentredOnTheWindow() {
    let window = CGRect(x: 0, y: 30, width: 1400, height: 976)
    let frame = SwitcherLayout.panelFrame(cards: 5, window: window, visible: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    #expect(frame.midX == window.midX && frame.midY == window.midY)
  }

  /// Kept on screen: a five-card panel over a narrow window at the screen's
  /// edge moves inside the visible frame.
  @Test func itStaysOnScreen() {
    let visible = CGRect(x: 0, y: 0, width: 1920, height: 1050)
    let left = SwitcherLayout.panelFrame(cards: 5, window: CGRect(x: 0, y: 30, width: 600, height: 976), visible: visible)
    #expect(left.minX == 0)
    let right = SwitcherLayout.panelFrame(
      cards: 5, window: CGRect(x: 1500, y: 0, width: 420, height: 300), visible: visible)
    #expect(right.maxX == 1920)
    #expect(right.midY == 150)
    let low = SwitcherLayout.panelFrame(cards: 2, window: CGRect(x: 0, y: -50, width: 600, height: 100), visible: visible)
    #expect(low.minY == 0)
    // Wider than the screen: its leading edge stays on it.
    let narrow = SwitcherLayout.panelFrame(
      cards: 5, window: CGRect(x: 0, y: 0, width: 800, height: 600), visible: CGRect(x: 0, y: 0, width: 800, height: 600))
    #expect(narrow.minX == 0)
  }
}

// MARK: Cards (tab-switcher, "Cards")

struct SwitcherCardTests {
  @Test func aRenamedTabReadsItsName() {
    let mail = FakeTab(id: 1, title: "Mail", name: "Inbox")
    let card = SwitcherCard.make(1, in: [1: mail])
    #expect(card?.title == "Inbox")
  }

  @Test func aSplitShowsBothPagesInPaneOrderWithNoTitle() {
    let news = FakeTab(id: 1, title: "News", splitPartnerID: 2, isLeadingPane: true)
    let docs = FakeTab(id: 2, title: "Docs", splitPartnerID: 1)
    let card = SwitcherCard.make(1, in: [1: news, 2: docs])
    #expect(card?.paneIDs == [1, 2])
    #expect(card?.title == "")
    #expect(card?.favicons.count == 2)
    #expect(card?.label == "News, Docs")
  }
}
