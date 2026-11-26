// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import XCTest

extension Browser {
  /// The split rows' labels, each "leading, trailing", from one snapshot.
  var splitRows: [String] { titles(of: "clair.splitRow") }

  func splitRow(_ label: String) -> XCUIElement {
    nativeWindow.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == 'clair.splitRow' AND label == %@", label)).firstMatch
  }

  func waitForSplitRows(_ seconds: TimeInterval = 15, _ condition: @escaping ([String]) -> Bool) async -> Bool {
    await Harness.wait(for: seconds) { condition(self.splitRows) }
  }

  var viewMenu: XCUIElement { ui.menuBars.menuBarItems["View"] }

  /// Chooses an item of the View menu.
  func chooseViewItem(_ title: String) throws {
    try require(viewMenu.waitForExistence(timeout: 30), "The menu bar has no View menu")
    viewMenu.click()
    let item = viewMenu.menuItems[title]
    try require(item.waitForExistence(timeout: 5), "The View menu has no \(title)")
    item.click()
  }

  /// Chooses `title` in Tabs › Split with Tab ›.
  func splitWithTabFromMenuBar(_ title: String) throws {
    let submenu = try tabMenuItem("Split with Tab")
    try require(submenu.isEnabled, "Tab › Split with Tab is off")
    submenu.hover()
    let item = submenu.menuItems[title]
    try require(item.waitForExistence(timeout: 5), "Tab › Split with Tab has no \(title)")
    item.click()
  }

  /// Chooses `title` in a row's Split with Tab › menu.
  func splitWithTab(_ title: String, inMenuOf row: XCUIElement) throws {
    row.rightClick()
    let submenu = ui.menuItems["Split with Tab"]
    try require(submenu.waitForExistence(timeout: 5), "The row's menu has no Split with Tab")
    submenu.hover()
    let item = submenu.menuItems[title]
    try require(item.waitForExistence(timeout: 5), "Split with Tab has no \(title)")
    item.click()
  }

  /// How many pages are open.
  func pageCount() async throws -> Int {
    try await pageTargets().count
  }
}

extension DevToolsSession {
  /// Option+clicks the element with `id` (CDP's modifier bit 1 is Alt).
  func optionClick(_ id: String) async throws {
    try await click(id, modifiers: 1)
  }

  /// Right-clicks the element with `id`, which opens the page's context menu.
  func rightClick(_ id: String) async throws {
    let center =
      try await evaluate(
        "(() => { const r = document.getElementById('\(id)').getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; })()"
      ) as? [Double] ?? [0, 0]
    for type in ["mousePressed", "mouseReleased"] {
      try await send(
        "Input.dispatchMouseEvent",
        ["type": type, "x": center[0], "y": center[1], "button": "right", "clickCount": 1])
    }
  }

  /// Whether the page has the keyboard.
  func isFocused() async throws -> Bool {
    try await evaluate("document.hasFocus()") as? Bool ?? false
  }
}

/// Split view (add-split-view task 3.12): two tabs side by side as one row,
/// made from the menus and Option+click, focused, rearranged, closed,
/// pinned and restored.
@MainActor
final class SplitViewTests: NativeWindowTestCase {
  static let links = "Clair split links"

  /// Starts Clair with Counter a, then the page of links, which is active.
  func startWithLinks() async throws -> (Browser, DevToolsSession, DevToolsSession) {
    let browser = try await startBrowser()
    let counter = try await browser.open(url("counter.html?a"))
    let links = try await browser.open(url("split.html"))
    browser.ui.activate()
    try require(browser.nativeWindow.waitForExistence(timeout: 30), "Clair shows no native window")
    let active = await browser.waitForActiveRow(Self.links)
    try require(active, "The page of links isn't active: \(browser.activeRow ?? "none")")
    return (browser, links, counter)
  }

  /// A split from the menus: both pages visible, one row, focus by click,
  /// Move Right, "Cannot Add New Pane", Ctrl+Tab, Separate Tabs and Cmd+W
  /// on a pane.
  func testMakingAndRearrangingASplit() async throws {
    let (browser, links, counter) = try await startWithLinks()
    defer {
      links.close()
      counter.close()
    }
    let other = try await browser.open(url("counter.html?other"))
    defer { other.close() }
    browser.tabRow(Self.links)?.click()
    _ = await browser.waitForActiveRow(Self.links)

    // Split with Tab › from the row's menu: the chosen tab trails, focused.
    try browser.splitWithTab("Counter a", inMenuOf: try XCTUnwrap(browser.tabRow(Self.links)))
    let split = "\(Self.links), Counter a"
    var made = await browser.waitForSplitRows { $0 == [split] }
    try require(made, "Split with Tab made no split row: \(browser.splitRows)")
    XCTAssertFalse(browser.tabTitles.contains(Self.links), "The split's tab kept a row of its own")
    XCTAssertTrue(browser.element("clair.pane.0").exists && browser.element("clair.pane.1").exists, "No two panes")
    XCTAssertTrue(browser.element("clair.splitDivider").exists, "The split shows no divider")
    var linksVisibility = try await browser.visibility(of: links)
    var counterVisibility = try await browser.visibility(of: counter)
    XCTAssertEqual(linksVisibility, "visible", "The leading pane's page isn't visible")
    XCTAssertEqual(counterVisibility, "visible", "The trailing pane's page isn't visible")

    // A click in the other pane focuses it.
    browser.element("clair.pane.0").click()
    let focused = await Harness.wait(for: 10) { try await links.isFocused() }
    XCTAssertTrue(focused, "A click in the leading pane didn't focus it")

    // Move Right from the leading pane's split button swaps the panes.
    let header = browser.element("clair.paneToolbar.0")
    let button = browser.element("clair.splitButton", in: header)
    try require(button.waitForExistence(timeout: 5), "The focused pane's header has no split button")
    button.click()
    let moveLeft = button.menuItems["Move Left"]
    try require(moveLeft.waitForExistence(timeout: 5), "The pane's split menu has no Move Left")
    XCTAssertFalse(moveLeft.isEnabled, "Move Left is on in the leading pane")
    button.menuItems["Move Right"].click()
    let swapped = await browser.waitForSplitRows { $0 == ["Counter a, \(Self.links)"] }
    XCTAssertTrue(swapped, "Move Right didn't swap the panes: \(browser.splitRows)")

    // Add Split View while split: a toast, and no third pane.
    let pages = try await browser.pageCount()
    browser.ui.typeKey("=", modifierFlags: [.control, .shift])
    let toast = browser.element("clair.toast")
    XCTAssertTrue(toast.waitForExistence(timeout: 5), "Add Split View showed no toast while split")
    XCTAssertEqual(toast.value as? String, "Cannot Add New Pane")
    let pagesAfter = try await browser.pageCount()
    XCTAssertEqual(pagesAfter, pages, "Add Split View opened a page while split")

    // Ctrl+Tab counts the split as one stop.
    browser.ui.typeKey(.tab, modifierFlags: .control)
    let next = await Harness.wait(for: 15) { try await browser.visibility(of: other) == "visible" }
    XCTAssertTrue(next, "Ctrl+Tab didn't leave the split")
    linksVisibility = try await browser.visibility(of: links)
    counterVisibility = try await browser.visibility(of: counter)
    XCTAssertEqual(linksVisibility, "hidden", "A pane stayed visible behind another tab")
    XCTAssertEqual(counterVisibility, "hidden", "A pane stayed visible behind another tab")
    browser.ui.typeKey(.tab, modifierFlags: .control)
    let back = await Harness.wait(for: 15) {
      let leading = try await browser.visibility(of: links)
      let trailing = try await browser.visibility(of: counter)
      return leading == "visible" && trailing == "visible"
    }
    XCTAssertTrue(back, "Ctrl+Tab didn't come back to the split in one stop")

    // Separate Tabs from the View menu: two rows in pane order.
    try browser.chooseViewItem("Separate Tabs")
    let separated = await browser.waitForSplitRows { $0.isEmpty }
    XCTAssertTrue(separated, "Separate Tabs left a split row")
    let rows = await browser.waitForTabs {
      guard let a = $0.firstIndex(of: "Counter a"), let l = $0.firstIndex(of: Self.links) else { return false }
      return l == a + 1
    }
    XCTAssertTrue(rows, "Separate Tabs didn't leave both rows in pane order: \(browser.tabTitles)")

    // Tabs › Split with Tab ›, then Cmd+W closes the focused pane only.
    browser.tabRow(Self.links)?.click()
    _ = await browser.waitForActiveRow(Self.links)
    try browser.splitWithTabFromMenuBar("Counter a")
    made = await browser.waitForSplitRows { $0 == [split] }
    try require(made, "Tabs › Split with Tab made no split: \(browser.splitRows)")
    let disabled = try browser.tabMenuItem("Split with Tab")
    XCTAssertFalse(disabled.isEnabled, "Tabs › Split with Tab is on while split")
    browser.ui.typeKey(.escape, modifierFlags: [])
    browser.ui.typeKey("w", modifierFlags: .command)
    let closed = await browser.waitForTarget("counter.html?a", open: false)
    XCTAssertTrue(closed, "Cmd+W didn't close the focused pane")
    let kept = await browser.waitForActiveRow(Self.links)
    XCTAssertTrue(kept, "The other pane didn't show alone, active: \(browser.activeRow ?? "none")")
    XCTAssertTrue(browser.splitRows.isEmpty, "Closing a pane left a split row")
  }

  /// Option+click: on a single page it splits with the link; in a split it
  /// loads in the other pane, with Back; from a pinned tab it splits instead
  /// of a Peek; inside a Peek it's a plain click; the context menu's Open
  /// Link in Split View does the same. None downloads.
  func testOptionClickAndTheContextMenu() async throws {
    let (browser, links, counter) = try await startWithLinks()
    defer {
      links.close()
      counter.close()
    }
    let downloads = FileManager.default.temporaryDirectory.appending(path: "clair-split-downloads-\(UUID())")
    let allow = try await browser.allowDownloads(to: downloads)
    defer { allow.close() }

    // A single page: the link opens beside it, trailing and focused.
    var pages = try await browser.pageCount()
    try await links.optionClick("same")
    let opened = await browser.waitForTarget("?split-same")
    try require(opened, "Option+click opened nothing")
    let made = await browser.waitForSplitRows { $0 == ["\(Self.links), Counter split-same"] }
    try require(made, "Option+click made no split: \(browser.splitRows)")
    var pagesAfter = try await browser.pageCount()
    XCTAssertEqual(pagesAfter, pages + 1, "Option+click opened more than one page")

    // In a split: the other pane navigates, no tab opens, and Back returns.
    pages = pagesAfter
    try await links.optionClick("second")
    let loaded = await browser.waitForTarget("?split-second")
    XCTAssertTrue(loaded, "Option+click in a split didn't load the link")
    let gone = await browser.waitForTarget("?split-same", open: false)
    XCTAssertTrue(gone, "Option+click in a split didn't load in the other pane")
    pagesAfter = try await browser.pageCount()
    XCTAssertEqual(pagesAfter, pages, "Option+click in a split opened a tab")
    let partner = try await browser.session(endingWith: "?split-second")
    _ = try await partner.evaluate("history.back(); 1")
    let returned = await browser.waitForTarget("?split-same")
    XCTAssertTrue(returned, "Back in the other pane didn't return")
    partner.close()

    // From the context menu, on a single page.
    try browser.chooseViewItem("Separate Tabs")
    _ = await browser.waitForSplitRows { $0.isEmpty }
    browser.tabRow(Self.links)?.click()
    _ = await browser.waitForActiveRow(Self.links)
    try await links.rightClick("other")
    let item = browser.ui.menuItems["Open Link in Split View"]
    try require(item.waitForExistence(timeout: 10), "The link's context menu has no Open Link in Split View")
    item.click()
    let fromMenu = await browser.waitForTarget("?split-other")
    XCTAssertTrue(fromMenu, "Open Link in Split View opened nothing")
    let menuSplit = await browser.waitForSplitRows { $0.contains { $0.hasPrefix(Self.links) } }
    XCTAssertTrue(menuSplit, "Open Link in Split View made no split: \(browser.splitRows)")
    try browser.chooseViewItem("Separate Tabs")
    _ = await browser.waitForSplitRows { $0.isEmpty }

    // Inside a Peek, Option+click is a plain click.
    let peekTarget = try await browser.open(url("peek.html"))
    defer { peekTarget.close() }
    _ = await browser.waitForActiveRow("Clair Peek links")
    try await peekTarget.shiftClick("plain")
    try require(browser.peek.waitForExistence(timeout: 15), "Shift+click showed no Peek")
    let inPeek = try await browser.session(endingWith: "?plain")
    _ = try await inPeek.evaluate(
      "document.body.insertAdjacentHTML('beforeend', '<a id=\"go\" href=\"/pages/counter.html?in-peek\">go</a>'); 1")
    try await inPeek.optionClick("go")
    let navigated = await browser.waitForTarget("?in-peek")
    XCTAssertTrue(navigated, "Option+click inside a Peek didn't navigate it")
    XCTAssertTrue(browser.peek.exists, "Option+click inside a Peek closed it")
    XCTAssertTrue(browser.splitRows.isEmpty, "Option+click inside a Peek made a split")
    inPeek.close()
    browser.ui.typeKey(.escape, modifierFlags: [])

    // From a pinned tab, a link to another site splits rather than Peeks.
    let pins = try await browser.open(url("pins.html"))
    defer { pins.close() }
    _ = await browser.waitForActiveRow("Clair pins page")
    browser.ui.typeKey("d", modifierFlags: .command)
    let pinned = await browser.waitForPins { $0 == ["Clair pins page"] }
    try require(pinned, "Cmd+D didn't pin the page")
    try await pins.optionClick("other")
    let fromPin = await browser.waitForTarget("?other")
    XCTAssertTrue(fromPin, "Option+click on the pinned tab opened nothing")
    XCTAssertFalse(browser.peek.exists, "Option+click on the pinned tab opened a Peek")
    let pinSplit = await browser.waitForSplitRows { !$0.isEmpty }
    XCTAssertTrue(pinSplit, "Option+click on the pinned tab made no split")

    // Nothing downloaded.
    let files = (try? FileManager.default.contentsOfDirectory(atPath: downloads.path)) ?? []
    XCTAssertTrue(files.isEmpty, "Option+click downloaded \(files)")
  }

  /// Peek's Open in Split View, and no such button on a Peek in a split.
  func testOpenInSplitViewFromAPeek() async throws {
    let browser = try await startBrowser()
    let links = try await browser.open(url("peek.html"))
    defer { links.close() }
    browser.ui.activate()
    try require(browser.nativeWindow.waitForExistence(timeout: 30), "Clair shows no native window")
    _ = await browser.waitForActiveRow("Clair Peek links")
    try await links.shiftClick("plain")
    try require(browser.peek.waitForExistence(timeout: 15), "Shift+click showed no Peek")
    let button = browser.element("clair.peekSplit")
    try require(button.waitForExistence(timeout: 5), "The Peek has no Open in Split View")
    button.click()
    let made = await browser.waitForSplitRows { $0 == ["Clair Peek links, Clair Peek target"] }
    XCTAssertTrue(made, "Open in Split View made no split: \(browser.splitRows)")
    XCTAssertFalse(browser.peek.exists, "The Peek stayed after Open in Split View")
    let peekPage = try await browser.session(endingWith: "?plain")
    defer { peekPage.close() }
    let visible = try await browser.visibility(of: peekPage)
    XCTAssertEqual(visible, "visible", "The Peek's page isn't visible in its pane")

    // A Peek from a pane: no Open in Split View.
    browser.element("clair.pane.0").click()
    try await Task.sleep(for: .seconds(1))
    try await links.shiftClick("blank")
    try require(browser.peek.waitForExistence(timeout: 15), "Shift+click in a pane showed no Peek")
    XCTAssertFalse(browser.element("clair.peekSplit").exists, "A Peek in a split offers Open in Split View")
    // A click in the other pane closes the Peek.
    browser.element("clair.pane.1").click()
    let closed = await browser.waitForTarget("?blank", open: false)
    XCTAssertTrue(closed, "A click in the other pane didn't close the Peek")
  }

  /// A split survives Reopen Closed Window and a relaunch with its ratio;
  /// closing its row and Restore Last Closed Tab bring it back; Move to
  /// Space moves both tabs.
  func testASplitComesBack() async throws {
    try Harness.setRestoreWindows(true)
    let (browser, links, counter) = try await startWithLinks()
    try await links.optionClick("same")
    let split = "\(Self.links), Counter split-same"
    var made = await browser.waitForSplitRows { $0 == [split] }
    try require(made, "Option+click made no split")
    links.close()
    counter.close()

    // Closing the row closes both; Restore Last Closed Tab brings the split
    // back.
    let row = browser.splitRow(split)
    row.hover()
    let close = browser.element("clair.splitClose", in: row)
    try require(close.waitForExistence(timeout: 5), "Hovering the split row shows no ×")
    close.click()
    let closed = await browser.waitForTarget("?split-same", open: false)
    let linksClosed = await browser.waitForTarget("split.html", open: false)
    XCTAssertTrue(closed && linksClosed, "× didn't close both panes")
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    made = await browser.waitForSplitRows { $0 == [split] }
    XCTAssertTrue(made, "Restore Last Closed Tab didn't bring the split back: \(browser.splitRows)")

    // A new ratio, from the divider, if the runner may drag.
    let divider = browser.element("clair.splitDivider")
    try require(divider.waitForExistence(timeout: 10), "The split shows no divider")
    let start = divider.frame
    var dragged = false
    if CGPreflightPostEventAccess() {
      try browser.drag(from: CGPoint(x: start.midX, y: start.midY), to: CGPoint(x: start.midX - 120, y: start.midY))
      dragged = await Harness.wait(for: 10) { browser.element("clair.splitDivider").frame.midX < start.midX - 60 }
      XCTAssertTrue(dragged, "Dragging the divider didn't move it")
    }
    let moved = browser.element("clair.splitDivider").frame

    // Relaunching keeps the split and its ratio.
    try await browser.relaunch()
    made = await browser.waitForSplitRows(30) { $0 == [split] }
    XCTAssertTrue(made, "The split didn't come back after a relaunch: \(browser.splitRows)")
    browser.splitRow(split).click()
    let shown = browser.element("clair.splitDivider")
    XCTAssertTrue(shown.waitForExistence(timeout: 15), "The restored split shows no divider")
    if dragged {
      XCTAssertEqual(shown.frame.midX, moved.midX, accuracy: 3, "The ratio changed across a relaunch")
    }

    // Reopen Closed Window brings it back too.
    let other = try await browser.open(url("counter.html?keep"), newWindow: true)
    defer { other.close() }
    _ = try await browser.waitForNativeWindows(2)
    // The split's window is the first one opened, at the back now.
    browser.nativeWindows.first { $0.element.descendants(matching: .any).matching(identifier: "clair.splitRow").count > 0 }?
      .click()
    browser.ui.typeKey("w", modifierFlags: [.command, .shift])
    _ = await Harness.wait(for: 15) { try await browser.windowCount() == 1 }
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    let reopened = await browser.waitForTarget("?split-same", seconds: 30)
    XCTAssertTrue(reopened, "Reopen Closed Window didn't bring the split's pages back")
  }

  /// A pinned split: Cmd+D pins both as one item, closing one pane takes it
  /// out and Restore brings it back, favoriting and a relaunch keep it, and
  /// Separate Tabs leaves two pins in its place.
  func testPinnedSplits() async throws {
    let (browser, links, counter) = try await startWithLinks()
    defer {
      links.close()
      counter.close()
    }
    try await links.optionClick("same")
    let split = "\(Self.links), Counter split-same"
    let made = await browser.waitForSplitRows { $0 == [split] }
    try require(made, "Option+click made no split")

    // Cmd+D pins the split as one item.
    browser.ui.typeKey("d", modifierFlags: .command)
    let pinned = await Harness.wait(for: 15) { browser.pinTitles.isEmpty && browser.splitRows == [split] }
    XCTAssertTrue(pinned, "Cmd+D didn't pin the split as one row")
    try await browser.relaunch()

    // After the relaunch: the row is back; selecting it opens both pages.
    var back = await browser.waitForSplitRows(30) { $0 == [split] }
    try require(back, "The pinned split didn't come back: \(browser.splitRows)")
    browser.splitRow(split).click()
    let both = await Harness.wait(for: 20) {
      let leading = try await browser.target(endingWith: "split.html")
      let trailing = try await browser.target(endingWith: "?split-same")
      return leading != nil && trailing != nil
    }
    XCTAssertTrue(both, "Selecting the pinned split didn't open both pages")

    // Closing one pane takes its pin out; Restore Last Closed Tab brings the
    // split back.
    browser.element("clair.pane.1").click()
    try await Task.sleep(for: .seconds(1))
    browser.ui.typeKey("w", modifierFlags: .command)
    let out = await Harness.wait(for: 15) { browser.splitRows.isEmpty && browser.pinTitles.count == 1 }
    XCTAssertTrue(out, "Closing a pane didn't leave one pin: \(browser.pinTitles), \(browser.splitRows)")
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    back = await browser.waitForSplitRows { $0 == [split] }
    XCTAssertTrue(back, "Restore Last Closed Tab didn't bring the pinned split back: \(browser.splitRows)")

    // Pin to Favorites makes one tile, which a relaunch keeps.
    try browser.choose("Pin to Favorites", inMenuOf: browser.element("clair.splitChip.0", in: browser.splitRow(split)))
    let tile = browser.element("clair.favoriteSplitTile")
    XCTAssertTrue(tile.waitForExistence(timeout: 15), "Pin to Favorites made no split tile")
    try await browser.relaunch()
    XCTAssertTrue(browser.element("clair.favoriteSplitTile").waitForExistence(timeout: 30), "The tile didn't come back")
    let records = try Array(browser.pinRecords().values)
    let splits = records.filter { $0["kind"] as? String == "split" }
    XCTAssertEqual(splits.count, 1, "Local State holds \(splits.count) split records")
    XCTAssertEqual(
      records.filter { $0["split"] != nil }.count, 2, "Local State's pins don't name their split")

    // Separate Tabs leaves two favorites in its place.
    try browser.choose("Separate Tabs", inMenuOf: browser.element("clair.splitChip.0", in: tile))
    let separated = await browser.waitForFavorites { $0.count == 2 }
    XCTAssertTrue(separated, "Separate Tabs didn't leave two favorites: \(browser.favoriteTitles)")
    XCTAssertFalse(browser.element("clair.favoriteSplitTile").exists, "The split tile stayed")
  }
}
