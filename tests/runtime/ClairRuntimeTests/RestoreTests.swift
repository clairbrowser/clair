// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import XCTest

/// Quitting and relaunching, with "When opening Clair, restore windows from
/// previous session" on and off (add-spaces D11, add-profiles D6). Each test
/// sets up everything one relaunch checks, since the relaunch is what takes
/// the time; its steps check separate state, so a failure names what didn't
/// come back.
@MainActor
final class RestoreTests: NativeWindowTestCase {
  func counter(_ name: String) -> String { url("counter.html?\(name)") }

  /// Adds a "Work" profile from Settings and a Space "Work" using it, and
  /// shows that Space.
  func addWorkSpace(_ browser: Browser) async throws {
    try browser.openProfilesPage()
    try await browser.addProfile("Work")
    browser.ui.windows["Profiles"].typeKey("w", modifierFlags: .command)
    browser.nativeWindow.click()
    try await browser.createSpace("Work", profile: "Work")
  }

  /// Moves and sizes the window that shows `tab`.
  func setBounds(of tab: DevToolsSession, in browser: Browser, _ bounds: [String: Int]) async throws {
    let session = try await browser.browserSession()
    defer { session.close() }
    let id = try await tab.targetID(in: browser) ?? ""
    let window = try await session.send("Browser.getWindowForTarget", ["targetId": id])
    try await session.send("Browser.setWindowBounds", ["windowId": window["windowId"] as? Int ?? 0, "bounds": bounds])
  }

  /// The native windows, left to right.
  func windowsLeftToRight(_ browser: Browser, count: Int, seconds: TimeInterval = 30) async throws -> [NativeWindow] {
    try await browser.waitForNativeWindows(count, seconds: seconds).sorted { $0.frame.minX < $1.frame.minX }
  }

  /// With restoring on, both windows come back where they were, at their
  /// size, each on the Space and tab it showed: A, a window of two profiles,
  /// on Work's tabs in order; B on a new tab page in Home, though new tab
  /// pages themselves aren't restored. A comes back as one window on a second
  /// relaunch too, and Restore Last Closed Tab returns a tab to its Space.
  func testRelaunchWithRestoringOn() async throws {
    try Harness.setRestoreWindows(true)
    let (browser, h1) = try await startWithPage("counter.html?h1")
    let h2 = try await browser.open(counter("h2"))
    try await addWorkSpace(browser)
    var work: [DevToolsSession] = []
    for name in ["w1", "w2", "w3"] {
      work.append(try await browser.open(counter(name)))
    }
    // Leave Work with its three tabs: close the new tab page it opened with.
    browser.tabRow("New Tab")?.click()
    if browser.tabTitles.count > 3 {
      browser.ui.typeKey("w", modifierFlags: .command)
    }
    let listed = await browser.waitForTabs { $0 == ["Counter w3", "Counter w2", "Counter w1"] }
    try require(listed, "Work doesn't list its three tabs: \(browser.tabTitles)")
    // A on the left, B on the right, at different sizes. Both fit the hosted
    // runner's 1024×768 screen, which would clamp them, and A's sidebar
    // stays clear of B.
    try await setBounds(of: work[1], in: browser, ["left": 0, "top": 40, "width": 600, "height": 560])

    // B opens on Work, then shows a new tab page in Home.
    let other = try await browser.open(counter("other"), newWindow: true)
    _ = try await browser.waitForNativeWindows(2)
    try await setBounds(of: other, in: browser, ["left": 420, "top": 40, "width": 600, "height": 640])
    try await Task.sleep(for: .seconds(1))
    let windows = try await windowsLeftToRight(browser, count: 2)
    let windowA = windows[0], windowB = windows[1]
    let onWork = await windowB.waitForActiveRow("Counter other")
    try require(onWork, "B doesn't show Counter other: \(windowB.activeRow ?? "none")")
    browser.ui.typeKey("1", modifierFlags: .control)
    let bOnHome = await Harness.wait(for: 15) { windowB.spaceName == "Home" }
    try require(bOnHome, "B didn't switch to Home")
    let newTab = try await browser.open("chrome://newtab/")
    let onNewTab = await windowB.waitForActiveRow("New Tab")
    try require(onNewTab, "B isn't on its new tab page: \(windowB.activeRow ?? "none")")
    let homeRows = windowB.tabTitles.filter { $0 != "New Tab" }

    // A shows w2.
    windowA.click()
    windowA.tabRow("Counter w2")?.click()
    let onW2 = await windowA.waitForActiveRow("Counter w2")
    try require(onW2, "A doesn't show Counter w2: \(windowA.activeRow ?? "none")")
    let workRows = windowA.tabTitles
    let framesBefore = [windowA.frame, windowB.frame]

    // Let session restore write the tabs and the windows' bounds.
    try await Task.sleep(for: .seconds(3))
    ([h1, h2, other, newTab] + work).forEach { $0.close() }
    try await browser.quit()
    try await browser.start()

    let back = await Harness.wait(for: 60) { browser.visibleNativeWindowCount == 2 }
    try require(back, "Both windows didn't come back: \(browser.visibleNativeWindowCount)")
    // Each profile restores in turn; give the later one time to join.
    try await Task.sleep(for: .seconds(5))
    let restored = try await windowsLeftToRight(browser, count: 2)
    let restoredA = restored[0], restoredB = restored[1]
    for (before, after) in zip(framesBefore, [restoredA.frame, restoredB.frame]) {
      XCTAssertEqual(after.minX, before.minX, accuracy: 2, "A window came back elsewhere: \(after) vs \(before)")
      XCTAssertEqual(after.minY, before.minY, accuracy: 2, "A window came back elsewhere: \(after) vs \(before)")
      XCTAssertEqual(after.width, before.width, accuracy: 2, "A window came back at another width: \(after) vs \(before)")
      XCTAssertEqual(after.height, before.height, accuracy: 2, "A window came back at another height: \(after) vs \(before)")
    }
    XCTAssertEqual(restoredA.spaceName, "Work", "A doesn't show the Space it showed")
    let aRows = await restoredA.waitForTabs(60) { $0 == workRows }
    XCTAssertTrue(aRows, "Work's tabs didn't come back in order: \(restoredA.tabTitles) vs \(workRows)")
    let aActive = await restoredA.waitForActiveRow("Counter w2", seconds: 30)
    XCTAssertTrue(aActive, "A came back on \(restoredA.activeRow ?? "none"), not Counter w2")
    XCTAssertEqual(restoredB.spaceName, "Home", "B doesn't show the Space it showed")
    let bActive = await restoredB.waitForActiveRow("New Tab", seconds: 30)
    XCTAssertTrue(bActive, "B came back on \(restoredB.activeRow ?? "none"), not a new tab page")
    let bRows = await restoredB.waitForTabs(30) { $0.filter { $0 != "New Tab" } == homeRows }
    XCTAssertTrue(bRows, "Home's tabs didn't come back: \(restoredB.tabTitles) vs \(homeRows)")

    // A window of two profiles comes back as one window on a second
    // relaunch too: the browser a later profile restores joins the group.
    try await Task.sleep(for: .seconds(3))
    try await browser.quit()
    try await browser.start()
    let again = await Harness.wait(for: 60) { browser.visibleNativeWindowCount >= 2 }
    try require(again, "The windows didn't come back a second time")
    try await Task.sleep(for: .seconds(5))
    XCTAssertEqual(browser.visibleNativeWindowCount, 2, "A window came back split on the second relaunch")

    // Restore Last Closed Tab returns a tab to its Space and shows it.
    let windowsAgain = try await windowsLeftToRight(browser, count: 2)
    let a = windowsAgain[0]
    a.click()
    a.tabRow("Counter w2")?.click()
    _ = await a.waitForActiveRow("Counter w2")
    browser.ui.typeKey("w", modifierFlags: .command)
    let closed = await a.waitForTabs { !$0.contains("Counter w2") }
    try require(closed, "Cmd+W didn't close w2")
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await Harness.wait(for: 15) { a.spaceName == "Home" }
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    let toWork = await Harness.wait(for: 15) { a.spaceName == "Work" }
    XCTAssertTrue(toWork, "Restoring the tab didn't show its Space")
    let inWork = await a.waitForTabs { $0.contains("Counter w2") }
    XCTAssertTrue(inWork, "The restored tab isn't in Work: \(a.tabTitles)")
  }

  /// With restoring off, pinned tabs, favorites and names come back with one
  /// window, on the Space last shown, with the command bar; the second
  /// window's tabs are in the Space it showed; two profiles show no profile
  /// picker; and a second relaunch lists one new tab page, not two.
  func testRelaunchWithRestoringOff() async throws {
    try Harness.setRestoreWindows(false)
    let pinsTitle = "Clair pins page"
    let (browser, tab) = try await startWithPage("pins.html")
    _ = await browser.waitForActiveRow(pinsTitle)
    browser.ui.typeKey("d", modifierFlags: .command)
    let pinned = await browser.waitForPins { $0 == [pinsTitle] }
    try require(pinned, "Cmd+D didn't pin the tab: \(browser.pinTitles)")
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

    // Work, of another profile, holds a tab; a second window opens on Work
    // and, last active, shows Home.
    try await addWorkSpace(browser)
    let work = try await browser.open(counter("work"))
    let other = try await browser.open(counter("other"), newWindow: true)
    _ = await Harness.wait(for: 30) { browser.visibleNativeWindowCount == 2 }
    browser.ui.typeKey("1", modifierFlags: .control)
    try await Task.sleep(for: .seconds(3))
    [tab, fav, closed, named, work, other].forEach { $0.close() }
    try await browser.quit()
    try await browser.start()

    try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back")
    let one = await Harness.wait(for: 30) { browser.visibleNativeWindowCount == 1 }
    XCTAssertTrue(one, "Clair didn't come back as one window: \(browser.visibleNativeWindowCount)")
    let picker = try await browser.pageTargets().contains { $0.url.hasPrefix("chrome://profile-picker") }
    XCTAssertFalse(picker, "Chromium's profile picker showed at launch")
    let onHome = await browser.waitForSpace("Home", seconds: 30)
    XCTAssertTrue(onHome, "The window doesn't show the Space last shown: \(browser.spaceName)")
    XCTAssertTrue(
      browser.element("clair.commandBarField").waitForExistence(timeout: 10), "The window didn't open the command bar")
    browser.ui.typeKey(.escape, modifierFlags: [])

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

    // The second window opened on Work, the Space shown then.
    browser.ui.typeKey("2", modifierFlags: .control)
    let workBack = await browser.waitForTabs(30) { $0.contains("Counter work") && $0.contains("Counter other") }
    XCTAssertTrue(workBack, "Work doesn't list its tabs: \(browser.tabTitles)")

    // A second launch lists one new tab page, not two.
    browser.ui.typeKey("1", modifierFlags: .control)
    try await Task.sleep(for: .seconds(3))
    try await browser.quit()
    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back again")
    _ = await browser.waitForSpace("Home", seconds: 30)
    let newTabPages = await Harness.wait(for: 30) {
      try await browser.pageTargets().filter { $0.url.hasPrefix("chrome://newtab") }.count == 1
    }
    XCTAssertTrue(newTabPages, "New tab pages left open at quit came back")
  }
}
