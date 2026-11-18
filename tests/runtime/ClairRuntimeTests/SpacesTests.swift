// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import XCTest

extension Browser {
  /// The Space header's name, which SwiftUI exposes as the text's value.
  /// While the name is a field, as during Rename Space…, there's no name to
  /// read: reading a missing element fails the test, which then hangs.
  var spaceName: String {
    let name = element("clair.spaceName")
    return name.exists ? name.value as? String ?? "" : ""
  }

  /// The footer switcher's items, in order.
  var switcherItems: [XCUIElement] {
    nativeWindow.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier MATCHES 'clair\\\\.space\\\\.[0-9]+'"))
      .allElementsBoundByIndex
  }

  var spacesMenu: XCUIElement { ui.menuBars.menuBarItems["Spaces"] }

  /// The Spaces menu's Space items, in order: its own items after the
  /// commands, without a submenu's such as Change Profile's.
  var spacesMenuSpaces: [String] {
    spacesMenu.click()
    defer { ui.typeKey(.escape, modifierFlags: []) }
    let items = spacesMenu.menus.firstMatch.children(matching: .menuItem).allElementsBoundByIndex
    let commands: Set<String> = [
      "New Space…", "Rename Space", "Change Profile", "Manage Spaces…", "Next Space", "Previous Space", "",
    ]
    return items.map(\.title).filter { !commands.contains($0) }
  }

  func chooseSpacesItem(_ title: String) throws {
    try require(spacesMenu.waitForExistence(timeout: 30), "The menu bar has no Spaces menu")
    spacesMenu.click()
    let item = spacesMenu.menuItems[title]
    try require(item.waitForExistence(timeout: 5), "The Spaces menu has no \(title)")
    item.click()
  }

  /// Waits for the window to show the Space named `name`.
  func waitForSpace(_ name: String, seconds: TimeInterval = 15) async -> Bool {
    await Harness.wait(for: seconds) { self.spaceName == name }
  }

  /// The title of the row the window highlights.
  var activeRow: String? {
    tabRows.first(where: \.isSelected)?.label
  }

  func waitForActiveRow(_ title: String, seconds: TimeInterval = 15) async -> Bool {
    await Harness.wait(for: seconds) { self.activeRow == title }
  }
}

/// Spaces (add-spaces task 3.11), driven through the sidebar, the menu bar
/// and the keyboard, with a counter page whose state shows that a tab kept
/// its page.
@MainActor
final class SpacesTests: NativeWindowTestCase {
  func counter(_ name: String) -> String { url("counter.html?\(name)") }

  /// Creates a Space from the Spaces menu or the footer's plus menu.
  func createSpace(_ name: String, in browser: Browser, fromPlusMenu: Bool = false) async throws {
    if fromPlusMenu {
      let plus = browser.element("clair.footerNew")
      plus.click()
      // The plus menu's own item: the Spaces menu has one of the same title.
      let item = plus.menuItems["New Space…"]
      try require(item.waitForExistence(timeout: 5), "The plus menu has no New Space…")
      item.click()
    } else {
      try browser.chooseSpacesItem("New Space…")
    }
    let field = browser.element("clair.newSpaceName")
    try require(field.waitForExistence(timeout: 10), "The New Space form didn't open")
    let create = browser.element("clair.createSpace")
    XCTAssertFalse(create.isEnabled, "Create Space is on before a name is typed")
    field.click()
    field.typeText(name)
    create.click()
    let shown = await browser.waitForSpace(name)
    try require(shown, "The window doesn't show the new Space \(name): \(browser.spaceName)")
    // The new Space opens on a new tab page with the command bar; close it.
    browser.ui.typeKey(.escape, modifierFlags: [])
  }

  /// The first launch has one Space and no switcher; a Space made from the
  /// plus menu joins the switcher; tab commands stay in the shown Space; and
  /// the switcher, Ctrl+number and Next and Previous Space switch without
  /// moving the window.
  func testSwitchingSpacesAndTabCommands() async throws {
    let (browser, tab) = try await startWithPage("counter.html?home")
    defer { tab.close() }
    XCTAssertEqual(browser.spaceName, "Home", "The first Space isn't Home")
    XCTAssertTrue(browser.switcherItems.isEmpty, "One Space shows a switcher")
    XCTAssertEqual(browser.spacesMenuSpaces, ["Home"], "The Spaces menu doesn't list Home alone")
    try await createSpace("Work", in: browser, fromPlusMenu: true)
    XCTAssertEqual(browser.switcherItems.map(\.label), ["Home", "Work"], "The switcher doesn't list both Spaces")
    // Close Work's new tab page once it has tabs of its own.
    let x = try await browser.open(counter("x"))
    let y = try await browser.open(counter("y"))
    let z = try await browser.open(counter("z"))
    defer {
      x.close()
      y.close()
      z.close()
    }
    let listed = await browser.waitForTabs { $0.starts(with: ["Counter z", "Counter y", "Counter x"]) }
    try require(listed, "New tabs didn't join the shown Space at the top: \(browser.tabTitles)")
    XCTAssertFalse(browser.tabTitles.contains("Counter home"), "Work lists Home's tab")
    browser.tabRow("New Tab")?.click()
    if browser.tabTitles.count > 3 {
      browser.ui.typeKey("w", modifierFlags: .command)
    }
    let three = await browser.waitForTabs { $0 == ["Counter z", "Counter y", "Counter x"] }
    try require(three, "Work doesn't list its three tabs: \(browser.tabTitles)")

    browser.ui.typeKey("2", modifierFlags: .command)
    var active = await browser.waitForActiveRow("Counter y")
    XCTAssertTrue(active, "Cmd+2 didn't select the Space's second row")
    browser.ui.typeKey("3", modifierFlags: .command)
    active = await browser.waitForActiveRow("Counter x")
    XCTAssertTrue(active, "Cmd+3 didn't select the Space's third row")
    // Next Tab at the Space's end goes to its first row, not into Home.
    browser.ui.typeKey(.downArrow, modifierFlags: [.command, .option])
    active = await browser.waitForActiveRow("Counter z")
    XCTAssertTrue(active, "Next Tab didn't wrap within the Space")
    browser.ui.typeKey(.upArrow, modifierFlags: [.command, .option])
    active = await browser.waitForActiveRow("Counter x")
    XCTAssertTrue(active, "Previous Tab didn't wrap within the Space")
    XCTAssertEqual(browser.spaceName, "Work", "A tab command left the Space")

    // Ctrl+Shift+PageUp and PageDown move the active row, stopping at the
    // ends.
    browser.ui.typeKey(.pageUp, modifierFlags: [.control, .shift])
    var moved = await browser.waitForTabs { $0 == ["Counter z", "Counter x", "Counter y"] }
    XCTAssertTrue(moved, "Ctrl+Shift+PageUp didn't move the row up: \(browser.tabTitles)")
    XCTAssertEqual(browser.activeRow, "Counter x", "Moving a row changed the active tab")
    browser.ui.typeKey(.pageDown, modifierFlags: [.control, .shift])
    browser.ui.typeKey(.pageDown, modifierFlags: [.control, .shift])
    moved = await browser.waitForTabs { $0 == ["Counter z", "Counter y", "Counter x"] }
    XCTAssertTrue(moved, "Ctrl+Shift+PageDown didn't move the row down, or went past the end: \(browser.tabTitles)")

    // Switching Spaces keeps the window's frame.
    try await createSpace("Travel", in: browser)
    XCTAssertEqual(browser.switcherItems.map(\.label), ["Home", "Work", "Travel"], "Travel isn't last")
    let frame = browser.nativeWindow.frame
    browser.switcherItems[0].click()
    var shown = await browser.waitForSpace("Home")
    XCTAssertTrue(shown, "Clicking the switcher didn't show Home")
    XCTAssertEqual(browser.activeRow, "Counter home", "Home doesn't show its tab")
    browser.ui.typeKey("3", modifierFlags: .control)
    shown = await browser.waitForSpace("Travel")
    XCTAssertTrue(shown, "Ctrl+3 didn't show the third Space")
    // Next and Previous wrap around at the ends.
    browser.ui.typeKey(.rightArrow, modifierFlags: [.command, .option])
    shown = await browser.waitForSpace("Home")
    XCTAssertTrue(shown, "Opt+Cmd+Right on the last Space didn't show the first")
    browser.ui.typeKey(.leftArrow, modifierFlags: [.command, .option])
    shown = await browser.waitForSpace("Travel")
    XCTAssertTrue(shown, "Opt+Cmd+Left on the first Space didn't show the last")
    XCTAssertEqual(browser.nativeWindow.frame, frame, "Switching Spaces changed the window's frame")
  }

  /// Delete Space on a Space with a page and a pinned tab asks, then closes
  /// both, and the pin doesn't come back after a relaunch. With one Space
  /// left, Delete Space is off.
  func testDeletingASpaceClosesItsTabsAndPins() async throws {
    let (browser, tab) = try await startWithPage("counter.html?a")
    defer { tab.close() }
    try await createSpace("Work", in: browser)
    // A pinned tab without a page still counts.
    let pinned = try await browser.open(url("pins.html?work"))
    defer { pinned.close() }
    _ = await browser.waitForActiveRow("Clair pins page")
    browser.ui.typeKey("d", modifierFlags: .command)
    let pin = await browser.waitForPins { $0 == ["Clair pins page"] }
    try require(pin, "Cmd+D didn't pin the tab: \(browser.pinTitles)")
    browser.ui.typeKey("w", modifierFlags: .command)
    _ = await browser.waitForTarget("?work", open: false)
    let doomed = try await browser.open(counter("doomed"))
    defer { doomed.close() }

    browser.element("clair.spaceHeader").rightClick()
    let delete = browser.ui.menuItems["Delete Space"]
    try require(delete.waitForExistence(timeout: 5), "The header's menu has no Delete Space")
    delete.click()
    try require(browser.dialog.waitForExistence(timeout: 10), "Deleting a Space with tabs didn't ask")
    browser.dialogButton("clair.dialogDefault").click()
    let home = await browser.waitForSpace("Home")
    try require(home, "The window didn't show the Space before the deleted one")
    let closed = await browser.waitForTarget("?doomed", open: false)
    XCTAssertTrue(closed, "The deleted Space's tabs didn't close")
    XCTAssertTrue(browser.switcherItems.isEmpty, "The deleted Space is still in the switcher")
    XCTAssertTrue(browser.pinTitles.isEmpty, "Home shows Work's pinned tab")

    // With one Space, Delete Space is off.
    browser.element("clair.spaceHeader").rightClick()
    XCTAssertFalse(browser.ui.menuItems["Delete Space"].isEnabled, "The only Space can be deleted")
    browser.ui.typeKey(.escape, modifierFlags: [])

    try await Task.sleep(for: .seconds(3))
    try await browser.quit()
    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back")
    try await Task.sleep(for: .seconds(3))
    XCTAssertTrue(browser.pinTitles.isEmpty, "The deleted Space's pin came back")
  }

  /// `arc-reference.md`'s close sequences: the tab the user came from, then
  /// the row above, then the row below.
  func testTheTabShownAfterAClose() async throws {
    let (browser, tab) = try await startWithPage("counter.html?I")
    defer { tab.close() }
    var sessions: [DevToolsSession] = []
    for name in ["A", "B", "C", "D", "E"] {
      sessions.append(try await browser.open(counter(name)))
    }
    defer { sessions.forEach { $0.close() } }
    // Below them, the new tab page a fresh launch opens with.
    let listed = await browser.waitForTabs {
      $0.starts(with: ["Counter E", "Counter D", "Counter C", "Counter B", "Counter A", "Counter I"])
    }
    try require(listed, "The rows aren't E, D, C, B, A, I: \(browser.tabTitles)")

    func close(expecting title: String, _ message: String) async {
      browser.ui.typeKey("w", modifierFlags: .command)
      let shown = await browser.waitForActiveRow(title)
      XCTAssertTrue(shown, "\(message): \(browser.activeRow ?? "none")")
    }
    browser.tabRow("Counter A")?.click()
    browser.tabRow("Counter C")?.click()
    await close(expecting: "Counter A", "Closing C didn't go back to A, where it was selected from")
    await close(expecting: "Counter B", "After a close, closing A didn't show the row above")
    await close(expecting: "Counter D", "Closing B didn't show the row above")
    await close(expecting: "Counter E", "Closing D didn't show the row above")
    await close(expecting: "Counter I", "Closing the top row didn't show the row below")

    // Closing a Space's last page keeps the window on it, on a new tab page
    // (add-profiles D13).
    try await createSpace("Work", in: browser)
    let page = try await browser.open(counter("page"))
    defer { page.close() }
    browser.tabRow("New Tab")?.click()
    browser.ui.typeKey("w", modifierFlags: .command)
    _ = await browser.waitForTabs { $0 == ["Counter page"] }
    browser.ui.typeKey("w", modifierFlags: .command)
    let stays = await browser.waitForTabs { $0.count == 1 && $0 != ["Counter page"] }
    XCTAssertTrue(stays, "Closing Work's only tab didn't leave a new tab page: \(browser.tabTitles)")
    XCTAssertEqual(browser.spaceName, "Work", "Closing Work's only tab left Work")
  }

  /// A page that asks before it closes: Chromium's confirmation makes its
  /// tab active again, so the tab shown after the close is chosen once the
  /// page agrees (add-spaces D4).
  func testClosingATabThatAsks() async throws {
    let (browser, tab) = try await startWithPage("counter.html?I")
    defer { tab.close() }
    let a = try await browser.open(counter("A"))
    let asking = try await browser.open(url("beforeunload.html"))
    let b = try await browser.open(counter("B"))
    defer {
      a.close()
      asking.close()
      b.close()
    }
    let page = "Clair leave page"
    let listed = await browser.waitForTabs { $0.starts(with: ["Counter B", page, "Counter A", "Counter I"]) }
    try require(listed, "The rows aren't B, the page that asks, A, I: \(browser.tabTitles)")
    browser.tabRow("Counter I")?.click()
    browser.tabRow(page)?.click()
    let selected = await browser.waitForActiveRow(page)
    try require(selected, "The page that asks isn't active: \(browser.activeRow ?? "none")")
    // The page asks only after a click.
    _ = try await asking.evaluate("document.body.id = 'body'; 1")
    try await asking.click("body")

    browser.ui.typeKey("w", modifierFlags: .command)
    let cancel = browser.ui.buttons["Cancel"]
    try require(cancel.waitForExistence(timeout: 15), "Closing the tab didn't ask about the page")
    cancel.click()
    try await Task.sleep(for: .seconds(1))
    XCTAssertEqual(browser.activeRow, page, "Staying on the page showed another tab")

    browser.ui.typeKey("w", modifierFlags: .command)
    let leave = browser.ui.buttons["Leave"]
    try require(leave.waitForExistence(timeout: 15), "Closing the tab again didn't ask about the page")
    leave.click()
    let back = await browser.waitForActiveRow("Counter I")
    XCTAssertTrue(back, "Leaving the page didn't go back to I, where it was selected from: \(browser.activeRow ?? "none")")
    let closed = await browser.waitForTabs { $0.starts(with: ["Counter B", "Counter A", "Counter I"]) }
    XCTAssertTrue(closed, "The page that asked didn't close: \(browser.tabTitles)")
    XCTAssertEqual(browser.spaceName, "Home", "The close left the Space")
  }

}
