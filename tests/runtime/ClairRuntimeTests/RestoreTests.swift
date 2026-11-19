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

  /// Checks `window`'s frame against `expected`, naming `when`.
  func assertFrame(_ window: NativeWindow, _ expected: CGRect, _ when: String) {
    let frame = window.frame
    XCTAssertEqual(frame.minX, expected.minX, accuracy: 2, "A window came back elsewhere \(when): \(frame) vs \(expected)")
    XCTAssertEqual(frame.minY, expected.minY, accuracy: 2, "A window came back elsewhere \(when): \(frame) vs \(expected)")
    XCTAssertEqual(frame.width, expected.width, accuracy: 2, "A window came back at another width \(when): \(frame) vs \(expected)")
    XCTAssertEqual(frame.height, expected.height, accuracy: 2, "A window came back at another height \(when): \(frame) vs \(expected)")
  }

  /// With restoring on, one window of one profile comes back on the Space
  /// and tab it showed, both Spaces' tabs in order and a new tab page left
  /// in Home gone; Restore Last Closed Tab returns a tab to its Space and
  /// shows it.
  func testRestoringOnKeepsSpacesAndClosedTabs() async throws {
    try Harness.setRestoreWindows(true)
    let (browser, h1) = try await startWithPage("counter.html?h1")
    let h2 = try await browser.open(counter("h2"))
    try await browser.createSpace("Work")
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
    let workRows = browser.tabTitles
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    // A new tab page left open at quit doesn't come back (add-profiles D6).
    let homeRows = browser.tabTitles.filter { $0 != "New Tab" }
    browser.ui.typeKey("2", modifierFlags: .control)
    _ = await browser.waitForSpace("Work")
    browser.tabRow("Counter w2")?.click()
    _ = await browser.waitForActiveRow("Counter w2")

    // Let session restore write the tabs.
    try await Task.sleep(for: .seconds(3))
    ([h1, h2] + work).forEach { $0.close() }
    try await browser.quit()
    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back")
    let restored = await browser.waitForSpace("Work", seconds: 60)
    try require(restored, "The window doesn't show the Space it showed: \(browser.spaceName)")
    let rowsBack = await browser.waitForTabs(60) { $0 == workRows }
    XCTAssertTrue(rowsBack, "Work's tabs didn't come back in order: \(browser.tabTitles) vs \(workRows)")
    let active = await browser.waitForActiveRow("Counter w2", seconds: 30)
    XCTAssertTrue(active, "The window came back on \(browser.activeRow ?? "none"), not Counter w2")
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let homeBack = await browser.waitForTabs { $0 == homeRows }
    XCTAssertTrue(homeBack, "Home's tabs didn't come back: \(browser.tabTitles) vs \(homeRows)")

    // Restore Last Closed Tab returns a tab to its Space and shows it.
    browser.ui.typeKey("2", modifierFlags: .control)
    _ = await browser.waitForSpace("Work")
    browser.tabRow("Counter w2")?.click()
    _ = await browser.waitForActiveRow("Counter w2")
    browser.ui.typeKey("w", modifierFlags: .command)
    let closed = await browser.waitForTabs { !$0.contains("Counter w2") }
    try require(closed, "Cmd+W didn't close w2")
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    let back = await browser.waitForSpace("Work")
    XCTAssertTrue(back, "Restoring the tab didn't show its Space")
    let inWork = await browser.waitForTabs { $0.contains("Counter w2") }
    XCTAssertTrue(inWork, "The restored tab isn't in Work: \(browser.tabTitles)")
  }

  /// With restoring on, two windows of one profile come back where they
  /// were, at their size, on two relaunches: A on the tab it showed, B on a
  /// new tab page, though new tab pages themselves aren't restored, and the
  /// Space's tabs, opened in both, in order.
  func testRestoringOnKeepsTwoWindows() async throws {
    try Harness.setRestoreWindows(true)
    let (browser, h1) = try await startWithPage("counter.html?h1")
    let h2 = try await browser.open(counter("h2"))
    // A on the left, B on the right, at different sizes. Both fit the hosted
    // runner's 1024×768 screen, which would clamp them, and A's sidebar
    // stays clear of B.
    try await setBounds(of: h2, in: browser, ["left": 0, "top": 40, "width": 600, "height": 560])
    let bHome = try await browser.open(counter("b-home"), newWindow: true)
    _ = try await browser.waitForNativeWindows(2)
    try await setBounds(of: bHome, in: browser, ["left": 420, "top": 40, "width": 600, "height": 640])
    // B ends on a new tab page.
    let newTab = try await browser.open("chrome://newtab/")
    try await Task.sleep(for: .seconds(1))
    let windows = try await windowsLeftToRight(browser, count: 2)
    let onNewTab = await windows[1].waitForActiveRow("New Tab")
    try require(onNewTab, "B isn't on its new tab page: \(windows[1].activeRow ?? "none")")
    let onH2 = await windows[0].waitForActiveRow("Counter h2")
    try require(onH2, "A doesn't show Counter h2: \(windows[0].activeRow ?? "none")")
    let homeRows = windows[1].tabTitles.filter { $0 != "New Tab" }
    let frames = windows.map(\.frame)

    // Let session restore write the tabs and the windows' bounds.
    try await Task.sleep(for: .seconds(3))
    [h1, h2, bHome, newTab].forEach { $0.close() }
    for launch in ["first", "second"] {
      try await browser.quit()
      try await browser.start()
      let back = await Harness.wait(for: 60) { browser.visibleNativeWindowCount == 2 }
      try require(back, "Both windows didn't come back (\(launch) relaunch): \(browser.visibleNativeWindowCount)")
      try await Task.sleep(for: .seconds(3))
      let restored = try await windowsLeftToRight(browser, count: 2)
      for (window, frame) in zip(restored, frames) {
        assertFrame(window, frame, "(\(launch) relaunch)")
      }
      let aActive = await restored[0].waitForActiveRow("Counter h2", seconds: 30)
      XCTAssertTrue(aActive, "A came back on \(restored[0].activeRow ?? "none") (\(launch) relaunch)")
      let bActive = await restored[1].waitForActiveRow("New Tab", seconds: 30)
      XCTAssertTrue(bActive, "B came back on \(restored[1].activeRow ?? "none") (\(launch) relaunch)")
      let rows = await restored[1].waitForTabs(30) { $0.filter { $0 != "New Tab" } == homeRows }
      XCTAssertTrue(rows, "Home's tabs didn't come back in order (\(launch) relaunch): \(restored[1].tabTitles) vs \(homeRows)")
      // Let session restore write the restored windows before quitting again.
      try await Task.sleep(for: .seconds(3))
    }
  }

  /// With restoring on, a window of two profiles, resized and quit while it
  /// shows Work, of the second profile, comes back as one window at its
  /// frame, on Work's tab, on two relaunches (add-profiles D6, #192); then
  /// Restore Last Closed Tab, chosen in Home, brings back a tab Work closed.
  func testRestoringOnKeepsAWindowOfTwoProfiles() async throws {
    try Harness.setRestoreWindows(true)
    let (browser, h1) = try await startWithPage("counter.html?h1")
    let h2 = try await browser.open(counter("h2"))
    try await addWorkSpace(browser)
    var work: [DevToolsSession] = []
    for name in ["w1", "w2", "w3"] {
      work.append(try await browser.open(counter(name)))
    }
    browser.tabRow("New Tab")?.click()
    if browser.tabTitles.count > 3 {
      browser.ui.typeKey("w", modifierFlags: .command)
    }
    let listed = await browser.waitForTabs { $0 == ["Counter w3", "Counter w2", "Counter w1"] }
    try require(listed, "Work doesn't list its three tabs: \(browser.tabTitles)")
    let workRows = browser.tabTitles
    browser.tabRow("Counter w2")?.click()
    _ = await browser.waitForActiveRow("Counter w2")
    // Resized while it shows Work.
    try await setBounds(of: work[1], in: browser, ["left": 0, "top": 40, "width": 600, "height": 560])
    try await Task.sleep(for: .seconds(1))
    let frame = try await windowsLeftToRight(browser, count: 1)[0].frame

    try await Task.sleep(for: .seconds(3))
    ([h1, h2] + work).forEach { $0.close() }
    for launch in ["first", "second"] {
      try await browser.quit()
      try await browser.start()
      try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back (\(launch) relaunch)")
      // Each profile restores in turn; give the later one time to join.
      try await Task.sleep(for: .seconds(5))
      XCTAssertEqual(browser.visibleNativeWindowCount, 1, "The window came back split (\(launch) relaunch)")
      let window = try await windowsLeftToRight(browser, count: 1)[0]
      assertFrame(window, frame, "(\(launch) relaunch)")
      let onWork = await browser.waitForSpace("Work", seconds: 30)
      XCTAssertTrue(onWork, "The window doesn't show Work (\(launch) relaunch): \(browser.spaceName)")
      let rows = await browser.waitForTabs(30) { $0 == workRows }
      XCTAssertTrue(rows, "Work's tabs didn't come back in order (\(launch) relaunch): \(browser.tabTitles)")
      let active = await browser.waitForActiveRow("Counter w2", seconds: 30)
      XCTAssertTrue(active, "The window came back on \(browser.activeRow ?? "none") (\(launch) relaunch)")
      try await Task.sleep(for: .seconds(3))
    }

    // Restore Last Closed Tab, chosen while Home shows, brings back Work's
    // tab in Work, in the same window.
    browser.ui.typeKey("w", modifierFlags: .command)
    let closed = await browser.waitForTabs { !$0.contains("Counter w2") }
    try require(closed, "Cmd+W didn't close w2")
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    let toWork = await browser.waitForSpace("Work")
    XCTAssertTrue(toWork, "Restoring the tab didn't show its Space: \(browser.spaceName)")
    let inWork = await browser.waitForTabs { $0.contains("Counter w2") }
    XCTAssertTrue(inWork, "The restored tab isn't in Work: \(browser.tabTitles)")
    try await Task.sleep(for: .seconds(1))
    XCTAssertEqual(browser.visibleNativeWindowCount, 1, "Restoring the tab opened another window")
  }

  /// With restoring on, two windows showing tabs of Work, of the second
  /// profile, both come back on their tabs.
  func testRestoringOnKeepsTwoWindowsOfAnotherProfile() async throws {
    try Harness.setRestoreWindows(true)
    let (browser, home) = try await startWithPage("counter.html?home")
    try await addWorkSpace(browser)
    let work = try await browser.open(counter("work"))
    browser.tabRow("Counter work")?.click()
    _ = await browser.waitForActiveRow("Counter work")
    let other = try await browser.open(counter("other"), newWindow: true)
    _ = await Harness.wait(for: 30) { browser.visibleNativeWindowCount == 2 }
    try await Task.sleep(for: .seconds(3))
    [home, work, other].forEach { $0.close() }
    try await browser.quit()
    try await browser.start()
    let two = await Harness.wait(for: 60) { browser.visibleNativeWindowCount == 2 }
    XCTAssertTrue(two, "Both windows didn't come back: \(browser.visibleNativeWindowCount)")
    try await Task.sleep(for: .seconds(3))
    let rows = browser.nativeWindows.map { $0.activeRow ?? "" }.sorted()
    XCTAssertEqual(rows, ["Counter other", "Counter work"], "The windows don't show their tabs: \(rows)")
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
