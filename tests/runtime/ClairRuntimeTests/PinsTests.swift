// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import XCTest

extension Browser {
  /// The pinned rows' titles, from one snapshot of the window.
  var pinTitles: [String] { titles(of: "clair.pinRow") }
  /// The favorite tiles' titles.
  var favoriteTitles: [String] { titles(of: "clair.favoriteTile") }

  func titles(of identifier: String) -> [String] {
    guard let window = try? nativeWindow.snapshot() else { return [] }
    var titles: [String] = []
    func collect(_ element: any XCUIElementSnapshot) {
      if element.identifier == identifier {
        titles.append(element.label)
      }
      element.children.forEach(collect)
    }
    collect(window)
    return titles
  }

  func pinRow(_ title: String) -> XCUIElement {
    nativeWindow.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == 'clair.pinRow' AND label == %@", title)).firstMatch
  }

  func favoriteTile(_ title: String) -> XCUIElement {
    nativeWindow.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == 'clair.favoriteTile' AND label == %@", title)).firstMatch
  }

  func waitForPins(_ seconds: TimeInterval = 15, _ condition: @escaping ([String]) -> Bool) async -> Bool {
    await Harness.wait(for: seconds) { condition(self.pinTitles) }
  }

  func waitForFavorites(_ seconds: TimeInterval = 15, _ condition: @escaping ([String]) -> Bool) async -> Bool {
    await Harness.wait(for: seconds) { condition(self.favoriteTitles) }
  }

  var tabMenu: XCUIElement { ui.menuBars.menuBarItems["Tab"] }

  /// A Tab menu item, opened and read; Esc closes the menu again.
  func tabMenuItem(_ title: String) throws -> XCUIElement {
    try require(tabMenu.waitForExistence(timeout: 30), "The menu bar has no Tab menu")
    tabMenu.click()
    let item = tabMenu.menuItems[title]
    try require(item.waitForExistence(timeout: 5), "The Tab menu has no \(title)")
    return item
  }

  /// Chooses an item of a row's context menu.
  func choose(_ title: String, inMenuOf row: XCUIElement) throws {
    row.rightClick()
    let item = ui.menuItems[title]
    try require(item.waitForExistence(timeout: 5), "The menu has no \(title)")
    item.click()
  }
}

/// Pinned tabs, favorites and tab names (add-pinned-tabs-and-favorites task
/// 3.12), driven through the sidebar, the menu bar and the keyboard, with a
/// page that links within its site (localhost) and to another (127.0.0.1).
@MainActor
final class PinsTests: NativeWindowTestCase {
  let pinsTitle = "Clair pins page"

  /// Starts with the pins page, active, and pins it with Cmd+D.
  func startPinned() async throws -> (Browser, DevToolsSession) {
    let (browser, tab) = try await startWithPage("pins.html")
    _ = await browser.waitForActiveRow(pinsTitle)
    browser.ui.typeKey("d", modifierFlags: .command)
    let pinned = await browser.waitForPins { $0 == [self.pinsTitle] }
    try require(pinned, "Cmd+D didn't pin the tab: \(browser.pinTitles)")
    return (browser, tab)
  }

  func testPinningAndUnpinning() async throws {
    let (browser, tab) = try await startPinned()
    defer { tab.close() }
    XCTAssertFalse(browser.tabTitles.contains(pinsTitle), "The pinned tab stayed among the Today tabs")
    let open = try await browser.target(endingWith: "pins.html")
    XCTAssertNotNil(open, "Pinning closed the page")
    let unpin = try browser.tabMenuItem("Unpin Tab")
    XCTAssertTrue(unpin.isEnabled, "Tab › Unpin Tab is off on a pinned tab")
    browser.ui.typeKey(.escape, modifierFlags: [])
    browser.ui.typeKey("d", modifierFlags: .command)
    let unpinned = await browser.waitForTabs { $0.first == self.pinsTitle }
    XCTAssertTrue(unpinned, "Cmd+D didn't unpin to the top of Today: \(browser.tabTitles)")
    XCTAssertTrue(browser.pinTitles.isEmpty, "The pin stayed")

    // Pin to Favorites keeps the page and leaves the Today tabs.
    try browser.choose("Pin to Favorites", inMenuOf: try XCTUnwrap(browser.tabRow(pinsTitle)))
    let favorite = await browser.waitForFavorites { $0 == [self.pinsTitle] }
    XCTAssertTrue(favorite, "Pin to Favorites didn't add a tile: \(browser.favoriteTitles)")
    XCTAssertFalse(browser.tabTitles.contains(pinsTitle), "The favorite stayed among the Today tabs")
    let stillOpen = try await browser.target(endingWith: "pins.html")
    XCTAssertNotNil(stillOpen, "Pin to Favorites closed the page")
  }

  func testClosingAndRemovingPins() async throws {
    let (browser, tab) = try await startPinned()
    defer { tab.close() }
    let news = try await browser.open(url("counter.html?news"))
    defer { news.close() }
    _ = await browser.waitForActiveRow("Counter news")
    browser.pinRow(pinsTitle).click()
    try await Task.sleep(for: .seconds(1))
    // Cmd+W on the selected pinned tab keeps it, and shows News.
    browser.ui.typeKey("w", modifierFlags: .command)
    let closed = await browser.waitForTarget("pins.html", open: false)
    XCTAssertTrue(closed, "Cmd+W didn't close the pinned tab's page")
    XCTAssertEqual(browser.pinTitles, [pinsTitle], "Cmd+W removed the pin")
    let back = await browser.waitForActiveRow("Counter news")
    XCTAssertTrue(back, "Cmd+W didn't show the tab the pin was selected from")

    // × on it, unselected and closed, removes it; Restore Last Closed Tab
    // brings it back, still closed.
    browser.pinRow(pinsTitle).hover()
    let remove = browser.element("clair.pinRemove")
    try require(remove.waitForExistence(timeout: 5), "The unselected pin shows no ×")
    remove.click()
    let removed = await browser.waitForPins { $0.isEmpty }
    XCTAssertTrue(removed, "× didn't remove the pin")
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    let restored = await browser.waitForPins { $0 == [self.pinsTitle] }
    XCTAssertTrue(restored, "Restore Last Closed Tab didn't bring the pin back")

    // Open, then × again: its page closes, and comes back with the pin.
    browser.pinRow(pinsTitle).click()
    let opened = await browser.waitForTarget("pins.html")
    try require(opened, "Clicking the pin didn't open its page")
    browser.tabRow("Counter news")?.click()
    browser.pinRow(pinsTitle).hover()
    try require(remove.waitForExistence(timeout: 5), "The open, unselected pin shows no ×")
    remove.click()
    let gone = await browser.waitForTarget("pins.html", open: false)
    XCTAssertTrue(gone, "× didn't close the pin's page")
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    let both = await browser.waitForPins { $0 == [self.pinsTitle] }
    let reopened = await browser.waitForTarget("pins.html")
    XCTAssertTrue(both && reopened, "Restore Last Closed Tab didn't bring the pin back with its page")
  }

  func testClearTodayAndCommandNumbers() async throws {
    let (browser, tab) = try await startPinned()
    defer { tab.close() }
    let a = try await browser.open(url("counter.html?a"))
    let b = try await browser.open(url("counter.html?b"))
    defer {
      a.close()
      b.close()
    }
    _ = await browser.waitForTabs { $0.contains("Counter b") }
    // Cmd+1 counts the pinned tab first.
    browser.ui.typeKey("1", modifierFlags: .command)
    try await Task.sleep(for: .seconds(1))
    XCTAssertTrue(browser.pinRow(pinsTitle).isSelected, "Cmd+1 didn't select the pinned tab")
    browser.ui.typeKey("w", modifierFlags: .command)
    _ = await browser.waitForTarget("pins.html", open: false)
    // Cmd+1 on the pin without a page opens it.
    browser.ui.typeKey("1", modifierFlags: .command)
    let opened = await browser.waitForTarget("pins.html")
    XCTAssertTrue(opened, "Cmd+1 didn't open the pinned tab")

    let clear = try browser.tabMenuItem("Clear Today")
    XCTAssertTrue(clear.isEnabled, "Clear Today is off with Today tabs")
    clear.click()
    let cleared = await browser.waitForTabs { !$0.contains("Counter a") && !$0.contains("Counter b") }
    XCTAssertTrue(cleared, "Clear Today left Today tabs: \(browser.tabTitles)")
    XCTAssertEqual(browser.pinTitles, [pinsTitle], "Clear Today touched the pinned tab")
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    let one = await browser.waitForTabs { $0.contains("Counter a") || $0.contains("Counter b") }
    XCTAssertTrue(one, "Restore Last Closed Tab didn't bring back a Today tab")
  }

  func testBackToPinnedURLAndEditingIt() async throws {
    let (browser, tab) = try await startPinned()
    defer { tab.close() }
    // A same-site link navigates the pinned tab.
    try await tab.click("same")
    let navigated = await Harness.wait(for: 15) {
      try await tab.evaluate("location.pathname") as? String == "/pages/pins-same.html"
    }
    try require(navigated, "A link within the site didn't navigate the pinned tab")
    let shown = await browser.waitForPins { $0 == ["Clair pins guide"] }
    XCTAssertTrue(shown, "The navigated row doesn't show the page's title: \(browser.pinTitles)")
    XCTAssertTrue(browser.element("clair.backToPinnedURL").waitForExistence(timeout: 5), "No Back to Pinned URL")
    let history = try await tab.evaluate("history.length") as? Int ?? 0
    try browser.tabMenuItem("Back to Pinned URL").click()
    let returned = await Harness.wait(for: 15) {
      try await tab.evaluate("location.pathname") as? String == "/pages/pins.html"
    }
    XCTAssertTrue(returned, "Back to Pinned URL didn't load the pinned URL")
    let longer = try await tab.evaluate("history.length") as? Int ?? 0
    XCTAssertGreaterThan(longer, history, "Back to Pinned URL added no history entry")
    _ = try await tab.evaluate("history.back(); 1")
    let backAgain = await Harness.wait(for: 15) {
      try await tab.evaluate("location.pathname") as? String == "/pages/pins-same.html"
    }
    XCTAssertTrue(backAgain, "Back didn't return to the page before Back to Pinned URL")

    // Replace Pinned URL with Current makes it the pinned URL.
    let row = browser.pinRow("Clair pins guide")
    row.rightClick()
    browser.ui.menuItems["Edit Pinned Page"].hover()
    let replace = browser.ui.menuItems["Replace Pinned URL with Current"]
    try require(replace.waitForExistence(timeout: 5), "No Replace Pinned URL with Current")
    replace.click()
    let plain = await Harness.wait(for: 10) { !browser.element("clair.backToPinnedURL").exists }
    XCTAssertTrue(plain, "The row still shows it navigated away")

    // Edit… sets another, which Back to Pinned URL then loads.
    browser.pinRow("Clair pins guide").rightClick()
    browser.ui.menuItems["Edit Pinned Page"].hover()
    browser.ui.menuItems["Edit…"].click()
    let field = browser.ui.textFields["clair.pinnedURLField"]
    try require(field.waitForExistence(timeout: 10), "Edit… opened no URL field")
    field.typeKey("a", modifierFlags: .command)
    field.typeText("not a url")
    XCTAssertFalse(browser.ui.buttons["clair.dialogDefault"].isEnabled, "Save is on without a URL")
    field.typeKey("a", modifierFlags: .command)
    field.typeText(url("pins.html?edited"))
    browser.ui.buttons["clair.dialogDefault"].click()
    try await Task.sleep(for: .seconds(1))
    try browser.tabMenuItem("Back to Pinned URL").click()
    let edited = await browser.waitForTarget("pins.html?edited")
    XCTAssertTrue(edited, "Back to Pinned URL didn't load the edited URL")
  }

  func testLinksToOtherSitesPeek() async throws {
    let (browser, tab) = try await startPinned()
    defer { tab.close() }
    // From the pinned tab: another site opens in a Peek, and the tab stays.
    try await tab.click("other")
    XCTAssertTrue(browser.peek.waitForExistence(timeout: 15), "A link to another site opened no Peek")
    let stayed = try await tab.evaluate("location.pathname") as? String
    XCTAssertEqual(stayed, "/pages/pins.html", "The pinned tab navigated")
    // Expanding it puts a Today tab at the top.
    browser.peekExpand.click()
    let expanded = await browser.waitForTabs { $0.first?.hasPrefix("Clair Peek") == true || $0.first == "Clair Peek target" }
    XCTAssertTrue(expanded, "The expanded Peek isn't the first Today tab: \(browser.tabTitles)")
    XCTAssertEqual(browser.pinTitles, [pinsTitle], "Expanding the Peek unpinned the tab")

    // A script without a click navigates the tab.
    browser.pinRow(pinsTitle).click()
    try await Task.sleep(for: .seconds(1))
    _ = try await tab.send("Runtime.evaluate", ["expression": "goElsewhere()", "userGesture": false])
    let scripted = await Harness.wait(for: 15) {
      try await browser.target(endingWith: "?script") != nil
    }
    XCTAssertTrue(scripted, "A scripted navigation didn't navigate the pinned tab")
  }

  func testNoPeekFromTodayOrWithTheToggleOff() async throws {
    try Harness.run("/usr/bin/defaults", ["write", Harness.bundleID, "ClairPeekForOtherSites", "-bool", "NO"])
    let (browser, tab) = try await startPinned()
    defer { tab.close() }
    try await tab.click("other")
    let navigated = await browser.waitForTarget("?other")
    XCTAssertTrue(navigated, "With the toggle off, the pinned tab didn't navigate")
    XCTAssertFalse(browser.peek.exists, "A Peek opened with the toggle off")
    // A Today tab never peeks.
    let today = try await browser.open(url("pins.html?today"))
    defer { today.close() }
    try await today.click("other")
    let todayNavigated = await Harness.wait(for: 15) {
      try await today.evaluate("location.host") as? String == "127.0.0.1:8123"
    }
    XCTAssertTrue(todayNavigated, "A Today tab's link to another site didn't navigate")
    XCTAssertFalse(browser.peek.exists, "A Today tab's link opened a Peek")
  }

  func testRenaming() async throws {
    let (browser, tab) = try await startWithPage("counter.html?name")
    defer { tab.close() }
    let row = try XCTUnwrap(browser.tabRow("Counter name"))
    try browser.choose("Rename…", inMenuOf: row)
    let field = browser.element("clair.renameField")
    try require(field.waitForExistence(timeout: 5), "Rename… opened no field")
    field.typeText("Fruit Co\r")
    let renamed = await browser.waitForTabs { $0.contains("Fruit Co") }
    XCTAssertTrue(renamed, "Return didn't name the row: \(browser.tabTitles)")
    let titled = await Harness.wait(for: 10) { browser.nativeWindow.title == "Fruit Co" }
    XCTAssertTrue(titled, "The window's title isn't the name: \(browser.nativeWindow.title)")

    // Esc cancels.
    try browser.choose("Rename…", inMenuOf: try XCTUnwrap(browser.tabRow("Fruit Co")))
    try require(field.waitForExistence(timeout: 5), "Rename… opened no field")
    field.typeText("Other")
    browser.ui.typeKey(.escape, modifierFlags: [])
    try await Task.sleep(for: .seconds(1))
    XCTAssertTrue(browser.tabTitles.contains("Fruit Co"), "Esc didn't keep the name")

    // The name survives navigation and pinning.
    try await tab.navigate(to: url("counter.html?other"))
    try await Task.sleep(for: .seconds(1))
    XCTAssertTrue(browser.tabTitles.contains("Fruit Co"), "Navigating lost the name")
    browser.tabRow("Fruit Co")?.click()
    browser.ui.typeKey("d", modifierFlags: .command)
    let pinned = await browser.waitForPins { $0 == ["Fruit Co"] }
    XCTAssertTrue(pinned, "Pinning lost the name: \(browser.pinTitles)")
    browser.ui.typeKey("d", modifierFlags: .command)
    let unpinned = await browser.waitForTabs { $0.contains("Fruit Co") }
    XCTAssertTrue(unpinned, "Unpinning lost the name")

    // An empty name brings back the page's title.
    try browser.choose("Rename…", inMenuOf: try XCTUnwrap(browser.tabRow("Fruit Co")))
    try require(field.waitForExistence(timeout: 5), "Rename… opened no field")
    field.typeKey("a", modifierFlags: .command)
    field.typeKey(.delete, modifierFlags: [])
    field.typeText("\r")
    let cleared = await browser.waitForTabs { $0.contains("Counter other") }
    XCTAssertTrue(cleared, "An empty name didn't bring back the title: \(browser.tabTitles)")
  }

  func testRelaunchKeepsPinsFavoritesAndNames() async throws {
    let (browser, tab) = try await startPinned()
    let fav = try await browser.open(url("counter.html?fav"))
    _ = await browser.waitForActiveRow("Counter fav")
    try browser.choose("Pin to Favorites", inMenuOf: try XCTUnwrap(browser.tabRow("Counter fav")))
    _ = await browser.waitForFavorites { $0 == ["Counter fav"] }
    let closed = try await browser.open(url("counter.html?closed"))
    _ = await browser.waitForActiveRow("Counter closed")
    browser.ui.typeKey("d", modifierFlags: .command)
    _ = await browser.waitForPins { $0.count == 2 }
    browser.ui.typeKey("w", modifierFlags: .command)
    _ = await browser.waitForTarget("?closed", open: false)
    let named = try await browser.open(url("counter.html?named"))
    _ = await browser.waitForActiveRow("Counter named")
    try browser.choose("Rename…", inMenuOf: try XCTUnwrap(browser.tabRow("Counter named")))
    let field = browser.element("clair.renameField")
    try require(field.waitForExistence(timeout: 5), "Rename… opened no field")
    try await Task.sleep(for: .seconds(0.5))
    field.typeText("Fruit Co\r")
    _ = await browser.waitForTabs { $0.contains("Fruit Co") }
    // The pinned tab navigated away from its pinned URL.
    try await tab.click("same")
    _ = await browser.waitForPins { $0.contains("Clair pins guide") }
    // "Open the New Tab page", set as the settings page would.
    let settings = try await browser.open("chrome://settings")
    _ = try await settings.evaluate(
      "(async () => { await chrome.settingsPrivate.setPref('session.restore_on_startup', 5); return 1; })()")
    // The sections, searched for through every shadow root once the page
    // has drawn them.
    let sections = """
      (() => { const find = (root, selector) => { const hit = root.querySelector(selector); if (hit) return hit;
        for (const element of root.querySelectorAll('*')) { if (element.shadowRoot) {
          const found = find(element.shadowRoot, selector); if (found) return found; } } return null; };
        const shown = (s) => { const a = find(document, s); return !!a && !a.hidden; };
        return [shown('a[href="/appearance"]'), shown('a[href="/onStartup"]')]; })()
      """
    var onStartup: [Bool]?
    _ = await Harness.wait(for: 15) {
      onStartup = try await settings.evaluate(sections) as? [Bool]
      return onStartup?.first == true
    }
    XCTAssertEqual(onStartup?.first, true, "Couldn't read chrome://settings' sections")
    XCTAssertEqual(onStartup?.last, false, "chrome://settings shows On startup")
    settings.close()
    try await Task.sleep(for: .seconds(3))
    [tab, fav, closed, named].forEach { $0.close() }
    try await browser.quit()
    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back")
    let pins = await browser.waitForPins(60) { $0 == ["Clair pins guide", "Counter closed"] }
    XCTAssertTrue(pins, "The pinned tabs didn't come back in order: \(browser.pinTitles)")
    let favorites = await browser.waitForFavorites { $0 == ["Counter fav"] }
    XCTAssertTrue(favorites, "The favorite didn't come back: \(browser.favoriteTitles)")
    let open = await browser.waitForTarget("pins-same.html", seconds: 30)
    XCTAssertTrue(open, "The open pinned tab didn't come back at the URL it showed")
    let favoriteOpen = await browser.waitForTarget("?fav")
    XCTAssertTrue(favoriteOpen, "The open favorite didn't come back open")
    let stillClosed = try await browser.target(endingWith: "?closed")
    XCTAssertNil(stillClosed, "A pinned tab without a page came back open")
    let name = await browser.waitForTabs { $0.contains("Fruit Co") }
    XCTAssertTrue(name, "The name didn't come back: \(browser.tabTitles)")
  }

  func testIncognitoHasNoPins() async throws {
    let (browser, tab) = try await startPinned()
    defer { tab.close() }
    browser.ui.typeKey("n", modifierFlags: [.command, .shift])
    let incognito = browser.ui.windows.containing(.any, identifier: "clair.sidebar")
      .matching(NSPredicate(format: "title CONTAINS[c] 'incognito' OR title == ''")).firstMatch
    try await Task.sleep(for: .seconds(3))
    _ = incognito
    let window = browser.ui.windows.firstMatch
    let pinRows = window.descendants(matching: .any).matching(identifier: "clair.pinRow").count
    XCTAssertEqual(pinRows, 0, "The incognito window shows pinned tabs")
    browser.ui.typeKey("d", modifierFlags: .command)
    try await Task.sleep(for: .seconds(1))
    let favorites = window.descendants(matching: .any).matching(identifier: "clair.favoriteTile").count
    XCTAssertEqual(favorites, 0, "Cmd+D in incognito made a favorite or pin show")
    let pin = try browser.tabMenuItem("Pin Tab")
    XCTAssertFalse(pin.isEnabled, "Tab › Pin Tab is on in incognito")
    browser.ui.typeKey(.escape, modifierFlags: [])
  }

  /// Creates a Space from the Spaces menu and closes the command bar it
  /// opens with.
  func createSpace(_ name: String, in browser: Browser) async throws {
    try browser.chooseSpacesItem("New Space…")
    let field = browser.element("clair.newSpaceName")
    try require(field.waitForExistence(timeout: 10), "The New Space form didn't open")
    field.click()
    field.typeText(name)
    browser.element("clair.createSpace").click()
    let shown = await browser.waitForSpace(name)
    try require(shown, "The window doesn't show \(name)")
    browser.ui.typeKey(.escape, modifierFlags: [])
  }

  func testFavoritesAcrossSpacesAndLeavingTheirSite() async throws {
    let (browser, tab) = try await startWithPage("pins.html")
    defer { tab.close() }
    _ = await browser.waitForActiveRow(pinsTitle)
    try browser.choose("Pin to Favorites", inMenuOf: try XCTUnwrap(browser.tabRow(pinsTitle)))
    _ = await browser.waitForFavorites { $0 == [self.pinsTitle] }
    try await createSpace("Travel", in: browser)
    XCTAssertEqual(browser.favoriteTitles, [pinsTitle], "Another Space of the profile doesn't show the favorite")
    // The same page, in the other Space.
    let before = try await browser.pageTargets().count
    browser.favoriteTile(pinsTitle).click()
    try await Task.sleep(for: .seconds(1))
    let after = try await browser.pageTargets().count
    XCTAssertEqual(before, after, "Selecting the favorite in another Space opened another page")
    XCTAssertEqual(browser.spaceName, "Travel", "Selecting the favorite left the Space")

    // A URL to another site from the favorite opens a Today tab.
    browser.ui.typeKey("l", modifierFlags: .command)
    try await Task.sleep(for: .seconds(1))
    browser.ui.typeKey("a", modifierFlags: .command)
    browser.ui.typeText("http://127.0.0.1:8123/pages/counter.html?typed\r")
    let today = await browser.waitForTabs { $0.first == "Counter typed" }
    XCTAssertTrue(today, "The URL didn't open as a Today tab: \(browser.tabTitles)")
    let kept = try await tab.evaluate("location.pathname") as? String
    XCTAssertEqual(kept, "/pages/pins.html", "The favorite navigated to another site")

    // A Cmd-click from the favorite opens a tab, not a Peek.
    browser.favoriteTile(pinsTitle).click()
    try await Task.sleep(for: .seconds(1))
    try await tab.click("other", modifiers: 4)
    let opened = await browser.waitForTarget("?other")
    XCTAssertTrue(opened, "Cmd-click didn't open the link")
    XCTAssertFalse(browser.peek.exists, "Cmd-click opened a Peek")
  }

  func testDeletingASpaceRemovesItsPins() async throws {
    let (browser, tab) = try await startWithPage("counter.html?home")
    defer { tab.close() }
    try await createSpace("Work", in: browser)
    let work = try await browser.open(url("pins.html?work"))
    defer { work.close() }
    _ = await browser.waitForActiveRow(pinsTitle)
    browser.ui.typeKey("d", modifierFlags: .command)
    _ = await browser.waitForPins { $0 == [self.pinsTitle] }
    browser.ui.typeKey("w", modifierFlags: .command)
    _ = await browser.waitForTarget("?work", open: false)
    // Delete Space counts the pinned tab and asks.
    let header = browser.element("clair.spaceHeader")
    header.rightClick()
    let delete = browser.ui.menuItems["Delete Space"]
    try require(delete.waitForExistence(timeout: 5), "The header's menu has no Delete Space")
    delete.click()
    let confirm = browser.ui.buttons["clair.dialogDefault"]
    try require(confirm.waitForExistence(timeout: 10), "Deleting a Space with a pinned tab didn't ask")
    confirm.click()
    let home = await browser.waitForSpace("Home")
    try require(home, "The window didn't go back to Home")
    XCTAssertTrue(browser.pinTitles.isEmpty, "Home shows Work's pinned tab")
    try await Task.sleep(for: .seconds(3))
    try await browser.quit()
    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back")
    try await Task.sleep(for: .seconds(3))
    XCTAssertTrue(browser.pinTitles.isEmpty, "The deleted Space's pin came back")
  }
}
