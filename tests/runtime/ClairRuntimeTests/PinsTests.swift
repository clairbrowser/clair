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

  /// Clair's Tabs menu (add-tab-switcher-and-tabs-menu D5).
  var tabMenu: XCUIElement { ui.menuBars.menuBarItems["Tabs"] }

  /// A Tabs menu item, opened and read; Esc closes the menu again.
  func tabMenuItem(_ title: String) throws -> XCUIElement {
    try require(tabMenu.waitForExistence(timeout: 30), "The menu bar has no Tabs menu")
    tabMenu.click()
    let item = tabMenu.menuItems[title]
    try require(item.waitForExistence(timeout: 5), "The Tabs menu has no \(title)")
    return item
  }

  /// Chooses an item of a row's context menu, the one on screen: the Tabs
  /// menu has items of the same titles, as Pin to Favorites.
  func choose(_ title: String, inMenuOf row: XCUIElement) throws {
    try chooseOnScreen(title, inMenuOf: row)
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

  /// A pin's life: pinning keeps the page; Cmd+1 counts the pin first and
  /// opens it when closed; Cmd+W closes its page and keeps it; Clear
  /// Unpinned Tabs leaves it; × removes it, open or closed, and Restore Last Closed Tab
  /// brings it back as it was; a tab's name survives navigation and pinning;
  /// and unpinning and Pin to Favorites keep the page.
  func testPinLifecycle() async throws {
    let (browser, tab) = try await startPinned()
    tab.close()
    XCTAssertFalse(browser.tabTitles.contains(pinsTitle), "The pinned tab stayed among the Today tabs")
    let open = try await browser.target(endingWith: "pins.html")
    XCTAssertNotNil(open, "Pinning closed the page")
    // tabs-menu, "The menu bar": Clair's Tabs menu, and no Chromium Tab menu.
    let unpin = try browser.tabMenuItem("Unpin Tab")
    XCTAssertTrue(unpin.isEnabled, "Tabs › Unpin Tab is off on a pinned tab")
    browser.ui.typeKey(.escape, modifierFlags: [])
    XCTAssertFalse(browser.ui.menuBars.menuBarItems["Tab"].exists, "The menu bar still has Chromium's Tab menu")

    // Cmd+1 counts the pinned tab first; Cmd+W closes its page, keeps the pin
    // and shows the tab it was selected from; Cmd+1 then opens it again.
    let a = try await browser.open(url("counter.html?a"))
    let b = try await browser.open(url("counter.html?b"))
    defer {
      a.close()
      b.close()
    }
    let shown = await browser.waitForActiveRow("Counter b")
    try require(shown, "Counter b isn't active: \(browser.activeRow ?? "none")")
    browser.ui.typeKey("1", modifierFlags: .command)
    try await Task.sleep(for: .seconds(1))
    XCTAssertTrue(browser.pinRow(pinsTitle).isSelected, "Cmd+1 didn't select the pinned tab")
    browser.ui.typeKey("w", modifierFlags: .command)
    let closed = await browser.waitForTarget("pins.html", open: false)
    XCTAssertTrue(closed, "Cmd+W didn't close the pinned tab's page")
    XCTAssertEqual(browser.pinTitles, [pinsTitle], "Cmd+W removed the pin")
    let back = await browser.waitForActiveRow("Counter b")
    XCTAssertTrue(back, "Cmd+W didn't show the tab the pin was selected from")
    browser.ui.typeKey("1", modifierFlags: .command)
    let opened = await browser.waitForTarget("pins.html")
    XCTAssertTrue(opened, "Cmd+1 didn't open the pinned tab")

    // Clear Unpinned Tabs closes the Today tabs only.
    let clear = try browser.tabMenuItem("Clear Unpinned Tabs")
    XCTAssertTrue(clear.isEnabled, "Clear Unpinned Tabs is off with Today tabs")
    clear.click()
    let cleared = await browser.waitForTabs { !$0.contains("Counter a") && !$0.contains("Counter b") }
    XCTAssertTrue(cleared, "Clear Unpinned Tabs left Today tabs: \(browser.tabTitles)")
    XCTAssertEqual(browser.pinTitles, [pinsTitle], "Clear Unpinned Tabs touched the pinned tab")
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    let one = await browser.waitForTabs { $0.contains("Counter a") || $0.contains("Counter b") }
    try require(one, "Restore Last Closed Tab didn't bring back a Today tab")
    let today = try XCTUnwrap(browser.tabTitles.first { $0.hasPrefix("Counter") })

    // × on the open, unselected pin closes its page; Restore Last Closed Tab
    // brings both back.
    browser.tabRow(today)?.click()
    _ = await browser.waitForActiveRow(today)
    browser.pinRow(pinsTitle).hover()
    let remove = browser.element("clair.pinRemove")
    try require(remove.waitForExistence(timeout: 5), "The open, unselected pin shows no ×")
    remove.click()
    let gone = await browser.waitForTarget("pins.html", open: false)
    let removed = await browser.waitForPins { $0.isEmpty }
    XCTAssertTrue(gone && removed, "× didn't remove the pin and close its page")
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    let both = await browser.waitForPins { $0 == [self.pinsTitle] }
    let reopened = await browser.waitForTarget("pins.html")
    try require(both && reopened, "Restore Last Closed Tab didn't bring the pin back with its page")

    // × on the closed pin removes it; it comes back still closed.
    browser.pinRow(pinsTitle).click()
    try await Task.sleep(for: .seconds(1))
    browser.ui.typeKey("w", modifierFlags: .command)
    _ = await browser.waitForTarget("pins.html", open: false)
    _ = await browser.waitForActiveRow(today)
    browser.pinRow(pinsTitle).hover()
    try require(remove.waitForExistence(timeout: 5), "The unselected pin shows no ×")
    remove.click()
    let removedClosed = await browser.waitForPins { $0.isEmpty }
    XCTAssertTrue(removedClosed, "× didn't remove the closed pin")
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    let restored = await browser.waitForPins { $0 == [self.pinsTitle] }
    XCTAssertTrue(restored, "Restore Last Closed Tab didn't bring the pin back")
    let stillClosed = try await browser.target(endingWith: "pins.html")
    XCTAssertNil(stillClosed, "The closed pin came back open")

    // A tab's name survives navigation and pinning.
    let named = try await browser.open(url("counter.html?name"))
    defer { named.close() }
    _ = await browser.waitForActiveRow("Counter name")
    try browser.choose("Rename…", inMenuOf: try XCTUnwrap(browser.tabRow("Counter name")))
    let field = browser.element("clair.renameField")
    try require(field.waitForExistence(timeout: 5), "Rename… opened no field")
    field.typeText("Fruit Co\r")
    let renamed = await browser.waitForTabs { $0.contains("Fruit Co") }
    try require(renamed, "Return didn't name the row: \(browser.tabTitles)")
    try await named.navigate(to: url("counter.html?other"))
    try await Task.sleep(for: .seconds(1))
    XCTAssertTrue(browser.tabTitles.contains("Fruit Co"), "Navigating lost the name")
    browser.tabRow("Fruit Co")?.click()
    browser.ui.typeKey("d", modifierFlags: .command)
    let pinnedName = await browser.waitForPins { $0.contains("Fruit Co") }
    XCTAssertTrue(pinnedName, "Pinning lost the name: \(browser.pinTitles)")
    browser.ui.typeKey("d", modifierFlags: .command)
    let unpinnedName = await browser.waitForTabs { $0.contains("Fruit Co") }
    XCTAssertTrue(unpinnedName, "Unpinning lost the name")

    // Unpinning puts the tab at the top of Today with its page.
    browser.pinRow(pinsTitle).click()
    let pinOpen = await browser.waitForTarget("pins.html")
    try require(pinOpen, "Clicking the pin didn't open its page")
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

  /// The pinned URL: another query is still it, a same-site link navigates,
  /// Back to Pinned URL returns, and Replace and Edit… change it. Links to
  /// other sites open a Peek (clair_pinned_link_throttle.mm decides), but not
  /// from a Today tab, from a script, or with the toggle off.
  func testPinnedURLAndPeeks() async throws {
    let (browser, tab) = try await startPinned()
    defer { tab.close() }
    // Another query is still the pinned URL, as in Arc.
    try await tab.click("query")
    let queried = await Harness.wait(for: 15) {
      try await tab.evaluate("location.search") as? String == "?query"
    }
    try require(queried, "A link to another query didn't navigate the pinned tab")
    XCTAssertFalse(
      browser.element("clair.backToPinnedURL").waitForExistence(timeout: 3),
      "Another query shows the pinned tab navigated away")
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
    // The row's icon.
    browser.element("clair.backToPinnedURL").click()
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
    // Edit Pinned Page › Back to Pinned URL (add-tab-switcher-and-tabs-menu
    // D6).
    browser.pinRow("Clair pins guide").rightClick()
    browser.ui.menuItems["Edit Pinned Page"].hover()
    let backItem = browser.ui.menuItems["Back to Pinned URL"]
    try require(backItem.waitForExistence(timeout: 5), "Edit Pinned Page has no Back to Pinned URL")
    XCTAssertTrue(backItem.isEnabled, "Back to Pinned URL is off on a page away from its pinned URL")
    backItem.click()
    let edited = await browser.waitForTarget("pins.html?edited")
    try require(edited, "Back to Pinned URL didn't load the edited URL")

    // From the pinned tab, another subdomain is another site, as in Arc.
    try await tab.click("sub")
    XCTAssertTrue(browser.peek.waitForExistence(timeout: 15), "A link to a subdomain opened no Peek")
    browser.peekClose.click()
    let peekClosed = await Harness.wait(for: 10) { !browser.peek.exists }
    try require(peekClosed, "The subdomain's Peek didn't close")
    // Another site opens in a Peek, and the tab stays.
    try await tab.click("other")
    XCTAssertTrue(browser.peek.waitForExistence(timeout: 15), "A link to another site opened no Peek")
    let stayed = try await tab.evaluate("location.pathname") as? String
    XCTAssertEqual(stayed, "/pages/pins.html", "The pinned tab navigated")
    // Expanding it puts a Today tab at the top.
    browser.peekExpand.click()
    let expanded = await browser.waitForTabs { $0.first?.hasPrefix("Clair Peek") == true || $0.first == "Clair Peek target" }
    XCTAssertTrue(expanded, "The expanded Peek isn't the first Today tab: \(browser.tabTitles)")
    XCTAssertEqual(browser.pinTitles, [pinsTitle], "Expanding the Peek unpinned the tab")

    // A Today tab never peeks.
    let today = try await browser.open(url("pins.html?today"))
    defer { today.close() }
    try await today.click("other")
    let todayNavigated = await Harness.wait(for: 15) {
      try await today.evaluate("location.host") as? String == "127.0.0.1:8123"
    }
    XCTAssertTrue(todayNavigated, "A Today tab's link to another site didn't navigate")
    XCTAssertFalse(browser.peek.exists, "A Today tab's link opened a Peek")

    // A script without a click navigates the tab. The page keeps a user
    // gesture for 5 seconds, and the clicks and evaluations above, which run
    // as gestures, would make the script's navigation a click's: wait it out.
    browser.pinRow(pinsTitle).click()
    try await Task.sleep(for: .seconds(6))
    _ = try await tab.send("Runtime.evaluate", ["expression": "goElsewhere()", "userGesture": false])
    let scripted = await Harness.wait(for: 15) {
      try await tab.evaluate("location.search") as? String == "?script"
    }
    XCTAssertTrue(scripted, "A scripted navigation didn't navigate the pinned tab")
    XCTAssertFalse(browser.peek.exists, "A scripted navigation opened a Peek")

    // With the toggle off on Settings' Links page, the pinned tab navigates.
    let away = browser.element("clair.backToPinnedURL")
    try require(away.waitForExistence(timeout: 10), "The navigated pinned tab shows no Back to Pinned URL")
    away.click()
    let returnedAgain = await Harness.wait(for: 15) {
      try await tab.evaluate("location.search") as? String == "?edited"
    }
    try require(returnedAgain, "Back to Pinned URL didn't load the pinned URL again")
    browser.ui.typeKey(",", modifierFlags: .command)
    let linksPage = browser.ui.toolbars.buttons["Links"]
    try require(linksPage.waitForExistence(timeout: 15), "Settings has no Links page")
    linksPage.click()
    let toggle = browser.ui.switches["clair.peekOtherSitesToggle"]
    try require(toggle.waitForExistence(timeout: 10), "The Links page has no toggle for other sites")
    toggle.click()
    browser.ui.typeKey("w", modifierFlags: .command)
    try await tab.click("other")
    let navigatedOff = await Harness.wait(for: 15) {
      try await tab.evaluate("location.search") as? String == "?other"
    }
    XCTAssertTrue(navigatedOff, "With the toggle off, the pinned tab didn't navigate")
    XCTAssertFalse(browser.peek.exists, "A Peek opened with the toggle off")
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
}
