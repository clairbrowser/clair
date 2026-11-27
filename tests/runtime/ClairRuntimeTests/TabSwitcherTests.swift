// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import XCTest

extension Browser {
  /// Ctrl+Tab's panel, a window of its own over the browser window
  /// (add-tab-switcher-and-tabs-menu D7).
  var tabSwitcher: XCUIElement { ui.descendants(matching: .any)["clair.tabSwitcher"].firstMatch }

  /// The switcher's cards, left to right.
  var switcherCards: [XCUIElement] {
    ui.descendants(matching: .any).matching(identifier: "clair.tabSwitcherCard").allElementsBoundByIndex
  }

  /// A row's context menu's items, "|" for a divider, read and closed again.
  func menuTitles(of row: XCUIElement) -> [String] {
    row.rightClick()
    defer { ui.typeKey(.escape, modifierFlags: []) }
    let menu = ui.menus.containing(NSPredicate(format: "title == 'Copy Link'")).firstMatch
    guard menu.waitForExistence(timeout: 5) else { return [] }
    var titles = menu.children(matching: .menuItem).allElementsBoundByIndex.map { $0.title.isEmpty ? "|" : $0.title }
    // AppKit appends a section of its own to a context menu, whose items
    // are hidden but whose divider XCUITest lists.
    while titles.last == "|" { titles.removeLast() }
    return titles
  }
}

/// Ctrl+Tab's switcher and the tab menus (add-tab-switcher-and-tabs-menu
/// tasks 5.2 to 5.4), driven with Ctrl held through XCUITest.
@MainActor
final class TabSwitcherTests: NativeWindowTestCase {
  func counter(_ name: String) -> String { url("counter.html?\(name)") }

  /// What the switcher shows while Ctrl is held after `tabs` Tabs: whether it
  /// appeared, its cards' labels, and the selected card's index. `then`
  /// runs before Ctrl is let go; a key it types must say Control too.
  func holdingCtrl(
    _ browser: Browser, tabs: Int = 1, then: (Browser) -> Void = { _ in }
  ) -> (appeared: Bool, labels: [String], selected: Int?) {
    var result: (appeared: Bool, labels: [String], selected: Int?) = (false, [], nil)
    XCUIElement.perform(withKeyModifiers: .control) {
      // Each key says Control itself: inside the block, a key typed with
      // no modifiers lets go of Control first, which chooses the card.
      for _ in 0..<tabs {
        browser.ui.typeKey(.tab, modifierFlags: .control)
      }
      result.appeared = browser.tabSwitcher.waitForExistence(timeout: 5)
      let cards = browser.switcherCards
      result.labels = cards.map(\.label)
      result.selected = cards.firstIndex(where: \.isSelected)
      then(browser)
    }
    return result
  }

  /// tab-switcher: a quick Ctrl+Tab goes back with no panel; held, the panel
  /// lists the recent tabs, the second selected; releasing Ctrl, Esc and a
  /// click choose or keep a tab; Opt+Cmd+Down still steps through the rows,
  /// and Close Tabs Below and Cmd+number still work.
  func testCtrlTabGoesBackToRecentTabs() async throws {
    let (browser, a) = try await startWithPage("counter.html?a")
    let b = try await browser.open(counter("b"))
    let c = try await browser.open(counter("c"))
    defer {
      a.close()
      b.close()
      c.close()
    }
    var shown = await browser.waitForActiveRow("Counter c")
    try require(shown, "Counter c isn't active: \(browser.activeRow ?? "none")")

    // A quick Ctrl+Tab shows the previous tab, and no panel stays.
    browser.ui.typeKey(.tab, modifierFlags: .control)
    shown = await browser.waitForActiveRow("Counter b")
    XCTAssertTrue(shown, "A quick Ctrl+Tab didn't show the previous tab: \(browser.activeRow ?? "none")")
    XCTAssertFalse(browser.tabSwitcher.exists, "A quick Ctrl+Tab left the switcher open")
    browser.ui.typeKey(.tab, modifierFlags: .control)
    shown = await browser.waitForActiveRow("Counter c")
    XCTAssertTrue(shown, "A second Ctrl+Tab didn't go back again")

    // Held: the recent tabs, the shown one first, the second selected;
    // releasing Ctrl shows it.
    let held = holdingCtrl(browser)
    XCTAssertTrue(held.appeared, "Holding Ctrl showed no switcher")
    XCTAssertEqual(Array(held.labels.prefix(3)), ["Counter c", "Counter b", "Counter a"], "The cards aren't the recent tabs")
    XCTAssertEqual(held.selected, 1, "The second card isn't selected")
    shown = await browser.waitForActiveRow("Counter b")
    XCTAssertTrue(shown, "Releasing Ctrl didn't show the selected tab")
    let closed = await Harness.wait(for: 5) { !browser.tabSwitcher.exists }
    XCTAssertTrue(closed, "The switcher stayed after Ctrl was let go")

    // Esc keeps the tab, Ctrl still held.
    let escaped = holdingCtrl(browser, tabs: 2) { $0.ui.typeKey(.escape, modifierFlags: .control) }
    XCTAssertEqual(escaped.selected, 2, "A second Tab didn't select the third card")
    try await Task.sleep(for: .seconds(1))
    XCTAssertEqual(browser.activeRow, "Counter b", "Esc switched tabs")
    XCTAssertFalse(browser.tabSwitcher.exists, "Esc left the switcher open")

    // A click on a card, Ctrl held, shows its tab.
    _ = holdingCtrl(browser) { browser in
      let cards = browser.switcherCards
      if cards.count > 2 { cards[2].click() }
    }
    shown = await browser.waitForActiveRow("Counter a")
    XCTAssertTrue(shown, "Clicking a card didn't show its tab: \(browser.activeRow ?? "none")")

    // Opt+Cmd+Down still steps through the rows (c, b, a top down), and the
    // tab it shows becomes the most recent.
    browser.tabRow("Counter c")?.click()
    _ = await browser.waitForActiveRow("Counter c")
    browser.ui.typeKey(.downArrow, modifierFlags: [.command, .option])
    shown = await browser.waitForActiveRow("Counter b")
    XCTAssertTrue(shown, "Opt+Cmd+Down didn't select the next row")
    browser.ui.typeKey(.upArrow, modifierFlags: [.command, .option])
    shown = await browser.waitForActiveRow("Counter c")
    XCTAssertTrue(shown, "Opt+Cmd+Up didn't select the previous row")
    browser.ui.typeKey(.tab, modifierFlags: .control)
    shown = await browser.waitForActiveRow("Counter b")
    XCTAssertTrue(shown, "Ctrl+Tab after Opt+Cmd+Up didn't go back to the row Next Tab showed")
    browser.ui.typeKey("1", modifierFlags: .command)
    shown = await browser.waitForActiveRow("Counter c")
    XCTAssertTrue(shown, "Cmd+1 didn't select the first row")

    // Close Tabs Below, from the row's menu, still closes the rows below.
    try browser.chooseOnScreen("Close Tabs Below", inMenuOf: try XCTUnwrap(browser.tabRow("Counter b")))
    let below = await browser.waitForTabs { !$0.contains("Counter a") }
    XCTAssertTrue(below, "Close Tabs Below left Counter a: \(browser.tabTitles)")
  }

  /// tab-switcher, "Another Space": a tab shown in another Space comes back
  /// with Ctrl+Tab, and the window shows its Space.
  func testCtrlTabGoesBackToAnotherSpace() async throws {
    let (browser, home) = try await startWithPage("counter.html?home")
    defer { home.close() }
    _ = await browser.waitForActiveRow("Counter home")
    try await createSpace("Work", in: browser)
    let work = try await browser.open(counter("work"))
    defer { work.close() }
    _ = await browser.waitForActiveRow("Counter work")
    // Work's new tab page goes, leaving Counter work and then Counter home.
    browser.tabRow("New Tab")?.click()
    if browser.tabTitles.contains("New Tab") {
      browser.ui.typeKey("w", modifierFlags: .command)
    }
    let alone = await browser.waitForTabs { $0 == ["Counter work"] }
    try require(alone, "Work doesn't list its one tab: \(browser.tabTitles)")
    _ = await browser.waitForActiveRow("Counter work")

    browser.ui.typeKey(.tab, modifierFlags: .control)
    let atHome = await browser.waitForSpace("Home")
    XCTAssertTrue(atHome, "Ctrl+Tab didn't switch the window to Home: \(browser.spaceName)")
    let shown = await browser.waitForActiveRow("Counter home")
    XCTAssertTrue(shown, "Ctrl+Tab didn't show Counter home: \(browser.activeRow ?? "none")")
    browser.ui.typeKey(.tab, modifierFlags: .control)
    let back = await browser.waitForSpace("Work")
    XCTAssertTrue(back, "A second Ctrl+Tab didn't go back to Work")
  }

  /// sidebar, "Today tab's menu", and pinned-tabs, "From its menu": the
  /// menus' groups in order, and a pinned tab's Close Tab keeps its row.
  func testTabMenusAndClosingAPinnedTab() async throws {
    let (browser, a) = try await startWithPage("counter.html?a")
    let b = try await browser.open(counter("b"))
    defer {
      a.close()
      b.close()
    }
    _ = await browser.waitForActiveRow("Counter b")
    let today = try XCTUnwrap(browser.tabRow("Counter a"), "No row for Counter a")
    XCTAssertEqual(
      browser.menuTitles(of: today),
      [
        "Pin Tab", "Pin to Favorites", "|", "Copy Link", "Duplicate", "|", "Split with Tab", "|", "Rename…", "Mute",
        "|", "Close Tab", "Close Tabs Below",
      ],
      "The Today tab's menu isn't in its groups")

    // Pinned, open and not shown, its menu ends with Close Tab, which closes
    // its page and keeps its row.
    try browser.chooseOnScreen("Pin Tab", inMenuOf: today)
    let pinned = await browser.waitForPins { $0 == ["Counter a"] }
    try require(pinned, "Pin Tab didn't pin Counter a: \(browser.pinTitles)")
    browser.tabRow("Counter b")?.click()
    _ = await browser.waitForActiveRow("Counter b")
    let pin = browser.pinRow("Counter a")
    XCTAssertEqual(
      browser.menuTitles(of: pin),
      [
        "Unpin Tab", "Pin to Favorites", "|", "Copy Link", "Duplicate", "|", "Split with Tab", "|", "Rename…", "Mute",
        "Edit Pinned Page", "|", "Close Tab",
      ],
      "The pinned tab's menu isn't in its groups")
    try browser.chooseOnScreen("Close Tab", inMenuOf: pin)
    let closed = await browser.waitForTarget("counter.html?a", open: false)
    XCTAssertTrue(closed, "Close Tab didn't close the pinned tab's page")
    XCTAssertEqual(browser.pinTitles, ["Counter a"], "Close Tab removed the pin")
    XCTAssertEqual(browser.activeRow, "Counter b", "Closing a pinned tab that isn't shown changed the tab")
  }
}
