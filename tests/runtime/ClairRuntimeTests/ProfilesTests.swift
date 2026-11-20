// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import XCTest

extension Browser {
  /// Opens Settings on its Profiles page.
  func openProfilesPage() throws {
    ui.typeKey(",", modifierFlags: .command)
    let page = ui.toolbars.buttons["Profiles"]
    try require(page.waitForExistence(timeout: 15), "Settings has no Profiles page")
    page.click()
    try require(ui.windows["Profiles"].waitForExistence(timeout: 10), "The Profiles page didn't open")
  }

  /// The Profiles list's rows, in order, as "name" or "name, 2 Spaces".
  var profileRows: [XCUIElement] {
    ui.windows["Profiles"].descendants(matching: .any).matching(identifier: "clair.profileRow").allElementsBoundByIndex
  }

  func profileRow(_ name: String) -> XCUIElement? {
    profileRows.first { $0.label.hasPrefix(name) }
  }

  func settingsElement(_ identifier: String) -> XCUIElement {
    ui.windows["Profiles"].descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// A part of the dialog on any window (DialogTests' `dialog`).
  func dialogElement(_ identifier: String) -> XCUIElement {
    dialog.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// The menu item titled `title` in the menu that's open, not one of the
  /// same title in a closed menu, such as Spaces › Change Profile's.
  func openMenuItem(_ title: String) async throws -> XCUIElement {
    var found: XCUIElement?
    let shown = await Harness.wait(for: 5) {
      found = self.ui.menuItems.matching(NSPredicate(format: "title == %@", title)).allElementsBoundByIndex
        .first(where: \.isHittable)
      return found != nil
    }
    try require(shown, "No open menu has \(title)")
    return found!
  }

  /// Types `name` into the open dialog's field and presses its default
  /// button.
  func answerDialog(field: String, with name: String) throws {
    let input = dialogElement(field)
    try require(input.waitForExistence(timeout: 10), "The dialog has no field \(field)")
    input.click()
    input.typeKey("a", modifierFlags: .command)
    input.typeText(name)
    dialogElement("clair.dialogDefault").click()
  }

  /// Adds a profile from Settings › Profiles, which must be open.
  func addProfile(_ name: String) async throws {
    settingsElement("clair.profilesAdd").click()
    try require(dialog.waitForExistence(timeout: 10), "Add didn't ask for a name")
    let create = dialogElement("clair.dialogDefault")
    XCTAssertFalse(create.isEnabled, "Create Profile is on before a name is typed")
    try answerDialog(field: "clair.newProfileName", with: name)
    let listed = await Harness.wait(for: 30) { self.profileRow(name) != nil }
    try require(listed, "\(name) isn't in the Profiles list")
  }

  /// Creates a Space from the Spaces menu on `profile`, chosen in the form's
  /// popup, and waits for the window to show it.
  func createSpace(_ name: String, profile: String? = nil) async throws {
    try chooseSpacesItem("New Space…")
    let field = element("clair.newSpaceName")
    try require(field.waitForExistence(timeout: 10), "The New Space form didn't open")
    field.click()
    field.typeText(name)
    if let profile {
      let popup = element("clair.profilePopup")
      try require(popup.waitForExistence(timeout: 5), "The form has no profile popup")
      popup.click()
      try await openMenuItem(profile).click()
    }
    element("clair.createSpace").click()
    let shown = await waitForSpace(name, seconds: 30)
    try require(shown, "The window doesn't show the new Space \(name): \(spaceName)")
    ui.typeKey(.escape, modifierFlags: [])
  }

  /// Chooses `profile` in the Space header's Set Profile menu.
  func setProfileFromHeader(_ profile: String) async throws {
    element("clair.spaceHeader").rightClick()
    let menu = try await openMenuItem("Set Profile")
    menu.hover()
    try await openMenuItem(profile).click()
  }

  /// Whether `tab`'s page sees the cookie the cookie page sets.
  func hasCookie(_ tab: DevToolsSession) async throws -> Bool {
    try await tab.evaluate("window.hasCookie()") as? Bool ?? false
  }

  /// The native windows on screen.
  var visibleNativeWindowCount: Int {
    ui.windows.containing(.any, identifier: "clair.sidebar").count
  }
}

/// Profiles (add-profiles task 3.9), driven through Settings, the Space
/// menus and the New Space form, with the counter page, whose state shows
/// that a tab kept its page, and the cookie page, whose cookie shows which
/// profile a page uses.
@MainActor
final class ProfilesTests: NativeWindowTestCase {
  /// Chromium's name for the first profile.
  static let defaultProfile = "Your Clair"

  func counter(_ name: String) -> String { url("counter.html?\(name)") }
  func cookie(_ name: String) -> String { url("cookie.html?\(name)") }

  /// Starts with Home on the default profile, a "Work" profile and a Space
  /// "Work" using it, shown.
  func startWithWorkProfile(arguments: [String] = []) async throws -> (Browser, DevToolsSession) {
    try Harness.setRestoreWindows(false)
    let (browser, tab) = try await startWithPage("counter.html?home", arguments: arguments)
    try browser.openProfilesPage()
    try await browser.addProfile("Work")
    browser.ui.windows["Profiles"].typeKey("w", modifierFlags: .command)
    browser.nativeWindow.click()
    try await browser.createSpace("Work", profile: "Work")
    return (browser, tab)
  }

  func testProfilesInSettingsAndTheMenuBar() async throws {
    try Harness.setRestoreWindows(false)
    let (browser, tab) = try await startWithPage("counter.html?a")
    defer { tab.close() }
    // The menu bar has no Profiles menu, and the Clair menu no "Warn Before
    // Quitting".
    XCTAssertFalse(browser.ui.menuBars.menuBarItems["Profiles"].exists, "The menu bar has a Profiles menu")
    browser.ui.menuBars.menuBarItems["Clair"].click()
    XCTAssertFalse(
      browser.ui.menuBars.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", "Warn Before Quitting"))
        .firstMatch.exists,
      "The Clair menu has Warn Before Quitting")
    browser.ui.typeKey(.escape, modifierFlags: [])

    // The Profiles page adds, renames and removes profiles in the engine;
    // the unit tests check its dialogs.
    try browser.openProfilesPage()
    XCTAssertEqual(browser.profileRows.count, 1, "There isn't one profile at first")
    try await browser.addProfile("Client")

    // Rename.
    browser.settingsElement("clair.profilesRename").click()
    try require(browser.dialog.waitForExistence(timeout: 10), "Rename didn't open its dialog")
    try browser.answerDialog(field: "clair.renameProfileName", with: "Office")
    let renamed = await Harness.wait(for: 15) { browser.profileRow("Office") != nil }
    XCTAssertTrue(renamed, "The profile wasn't renamed")

    // Remove, after typing the name.
    let folders = try FileManager.default.contentsOfDirectory(atPath: browser.dataDirectory.path)
    browser.profileRow("Office")?.click()
    browser.settingsElement("clair.profilesRemove").click()
    try require(browser.dialog.waitForExistence(timeout: 10), "Remove didn't ask")
    let field = browser.dialogElement("clair.deleteProfileName")
    field.click()
    field.typeText("Office")
    browser.dialogElement("clair.dialogDefault").click()
    let removed = await Harness.wait(for: 30) { browser.profileRow("Office") == nil }
    XCTAssertTrue(removed, "The profile wasn't removed")
    let created = folders.filter { $0.hasPrefix("Profile ") }
    let gone = await Harness.wait(for: 60) {
      let now = try FileManager.default.contentsOfDirectory(atPath: browser.dataDirectory.path)
      return created.allSatisfy { !now.contains($0) }
    }
    XCTAssertTrue(gone, "The removed profile's data folder is still there")
  }

  func testIsolationAndSwitching() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    let frame = browser.nativeWindow.frame
    let sidebarWidth = browser.sidebar.frame.width

    // Home sets a cookie.
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let setter = try await browser.open(cookie("set"))
    defer { setter.close() }
    let set = await Harness.wait(for: 15) { try await browser.hasCookie(setter) }
    try require(set, "The cookie page didn't set its cookie")

    // Work, of another profile, doesn't see it, in the same window.
    browser.ui.typeKey("2", modifierFlags: .control)
    let work = await browser.waitForSpace("Work")
    try require(work, "Ctrl+2 didn't show Work")
    XCTAssertEqual(browser.visibleNativeWindowCount, 1, "Switching profile showed a second window")
    XCTAssertEqual(browser.nativeWindow.frame, frame, "Switching profile changed the window's frame")
    XCTAssertEqual(browser.sidebar.frame.width, sidebarWidth, "Switching profile changed the sidebar's width")
    let other = try await browser.open(cookie("work"))
    defer { other.close() }
    let leaked = try await browser.hasCookie(other)
    XCTAssertFalse(leaked, "A Space of another profile sees the cookie")

    // A third Space on the default profile sees it.
    try await browser.createSpace("Errands", profile: Self.defaultProfile)
    let same = try await browser.open(cookie("errands"))
    defer { same.close() }
    let seen = await Harness.wait(for: 15) { try await browser.hasCookie(same) }
    XCTAssertTrue(seen, "Another Space of the same profile doesn't see the cookie")
    XCTAssertEqual(browser.visibleNativeWindowCount, 1, "Switching back showed a second window")
  }

  /// Setting a Space's profile asks when the Space has tabs and reopens them
  /// in order; then closing the new tab page of an emptied Space closes the
  /// window (design D13).
  func testSettingASpacesProfileAndEmptyingIt() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    // Work shows a new tab page, so it asks; Cancel changes nothing.
    try await browser.setProfileFromHeader(Self.defaultProfile)
    try require(browser.dialog.waitForExistence(timeout: 10), "A Space with a tab didn't ask")
    browser.dialogElement("clair.dialogCancel").click()
    XCTAssertEqual(browser.tabTitles.count, 1, "Cancel changed Work's tabs")

    // Home, with tabs, one of which asks before leaving: confirming reopens
    // them in Work, in order, without the page asking.
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let asks = try await browser.open(url("beforeunload.html"))
    // The page asks only after a click.
    _ = try await asks.evaluate("document.body.id = 'body'; 1")
    try await asks.click("body")
    let checker = try await browser.open(cookie("check"))
    let before = browser.tabTitles
    asks.close()
    checker.close()
    try await browser.setProfileFromHeader("Work")
    try require(browser.dialog.waitForExistence(timeout: 10), "A Space with tabs didn't ask")
    browser.dialogElement("clair.dialogDefault").click()
    let reopened = await browser.waitForTabs(30) { $0 == before }
    XCTAssertTrue(reopened, "Home doesn't list the same tabs in order: \(browser.tabTitles) vs \(before)")
    XCTAssertFalse(browser.dialog.exists, "A page asked before leaving")
    XCTAssertEqual(browser.spaceName, "Home", "The window left Home")
    let moved = try await browser.target(endingWith: "?check")
    try require(moved != nil, "The cookie page didn't come back")
    let session = try await browser.session(onTarget: moved!.id)
    defer { session.close() }
    let counter = try await browser.target(endingWith: "?home")
    XCTAssertNotNil(counter, "The counter page didn't come back")

    // Work's only row is a new tab page: closing it closes the window.
    browser.ui.typeKey("2", modifierFlags: .control)
    let work = await browser.waitForSpace("Work")
    try require(work, "Ctrl+2 didn't show Work")
    let emptied = await browser.waitForTabs { $0.count == 1 }
    try require(emptied, "Work doesn't list its new tab page alone: \(browser.tabTitles)")
    let windowsBefore = try await browser.windowCount()
    browser.ui.typeKey("w", modifierFlags: .command)
    let closed = await Harness.wait(for: 30) { try await browser.windowCount() < windowsBefore }
    XCTAssertTrue(closed, "Closing an emptied Space's new tab page didn't close the window")
  }

  /// Move to Space within a profile keeps the page; across profiles it
  /// reopens it. Moving the active tab takes the window with it (design D9);
  /// moving another leaves a notice.
  func testMoveToSpace() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    try await browser.createSpace("Errands", profile: Self.defaultProfile)
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let moving = try await browser.open(counter("moving"))
    let staying = try await browser.open(counter("staying"))
    defer {
      moving.close()
      staying.close()
    }
    _ = try await moving.evaluate("window.counter = 5; 1")

    // The active tab, within the profile: the window follows it to Errands,
    // the tab still active, its page kept.
    browser.tabRow("Counter moving")?.click()
    let selected = await browser.waitForActiveRow("Counter moving")
    try require(selected, "The tab to move isn't active")
    try await moveRow("Counter moving", to: "Errands", in: browser)
    var shown = await browser.waitForSpace("Errands")
    XCTAssertTrue(shown, "Moving the active tab didn't show Errands: \(browser.spaceName)")
    var active = await browser.waitForActiveRow("Counter moving")
    XCTAssertTrue(active, "The moved tab isn't active in Errands: \(browser.activeRow ?? "none")")
    XCTAssertEqual(browser.tabTitles.first, "Counter moving", "The moved tab isn't first in Errands")
    let kept = try await moving.evaluate("window.counter") as? Double
    XCTAssertEqual(kept, 5, "Moving the tab within its profile reloaded its page")
    browser.ui.typeKey("1", modifierFlags: .control)
    shown = await browser.waitForSpace("Home")
    try require(shown, "Ctrl+1 didn't show Home")
    let gone = await browser.waitForTabs { !$0.contains("Counter moving") }
    XCTAssertTrue(gone, "The moved tab is still in Home")

    // Another tab, across profiles: the window stays, and a notice says
    // where it went.
    browser.tabRow("Counter staying")?.click()
    _ = await browser.waitForActiveRow("Counter staying")
    try await moveRow("Counter home", to: "Work", in: browser)
    let notice = browser.element("clair.tabMoved")
    XCTAssertTrue(notice.waitForExistence(timeout: 10), "Moving another tab showed no notice")
    XCTAssertEqual(notice.value as? String, "Tab was moved to Work", "The notice doesn't name Work")
    XCTAssertEqual(browser.spaceName, "Home", "Moving another tab left Home")

    // The active tab, across profiles: the window follows it, reopened at
    // the top of Work.
    browser.ui.typeKey("3", modifierFlags: .control)
    shown = await browser.waitForSpace("Errands")
    try require(shown, "Ctrl+3 didn't show Errands")
    browser.tabRow("Counter moving")?.click()
    _ = await browser.waitForActiveRow("Counter moving")
    try await moveRow("Counter moving", to: "Work", in: browser)
    let followed = await browser.waitForSpace("Work", seconds: 30)
    XCTAssertTrue(followed, "Moving the active tab didn't show Work")
    active = await browser.waitForActiveRow("Counter moving")
    XCTAssertTrue(active, "The moved tab isn't active in Work: \(browser.activeRow ?? "none")")
    XCTAssertEqual(browser.tabTitles.first, "Counter moving", "The moved tab isn't at the top of Work")
    let target = try await browser.target(endingWith: "?moving")
    try require(target != nil, "The moved tab isn't open")
    let reopened = try await browser.session(onTarget: target!.id)
    defer { reopened.close() }
    let count = try await reopened.evaluate("window.counter") as? Double
    XCTAssertEqual(count, 0, "The tab kept its page across profiles")
  }

  func moveRow(_ title: String, to space: String, in browser: Browser) async throws {
    browser.tabRow(title)?.rightClick()
    let move = browser.ui.menuItems["Move to Space"]
    try require(move.waitForExistence(timeout: 5), "\(title) has no Move to Space")
    move.hover()
    // The submenu's own item: the Spaces menu has one of the same title.
    let item = move.menuItems[space]
    try require(item.waitForExistence(timeout: 5), "Move to Space doesn't list \(space)")
    item.click()
  }

  /// Changing the profile of a Space two windows show swaps both, including
  /// the one that only shows a still of its tab (design D9).
  func testSettingTheProfileOfASpaceTwoWindowsShow() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let second = try await browser.open(counter("second"), newWindow: true)
    defer { second.close() }
    let windows = try await browser.waitForNativeWindows(2)
    // Both show Home; the second takes Counter home, so the first shows a
    // still of it and holds no tab it shows.
    guard let taker = windows.first(where: { $0.activeRow == "Counter second" }),
      let other = windows.first(where: { $0.frame != taker.frame })
    else {
      throw HarnessError("No window shows Counter second: \(windows.map(\.activeRow))")
    }
    try require(other.spaceName == "Home" && taker.spaceName == "Home", "The windows don't both show Home")
    taker.tabRow("Counter home")?.click()
    let still = await other.waitForStill()
    try require(still, "The other window doesn't show a still of Counter home")
    let before = taker.tabTitles
    try await browser.setProfileFromHeader("Work")
    try require(browser.dialog.waitForExistence(timeout: 10), "A Space with tabs didn't ask")
    browser.dialogElement("clair.dialogDefault").click()
    // Both windows show Home in Work's profile and list its rows alike: the
    // reopened ones, and one new tab page for the window that showed the
    // still (D9). A window left on the old profile would list a new tab page
    // of its own as well.
    let after = try await browser.waitForNativeWindows(2)
    let same = await Harness.wait(for: 30) {
      let titles = after.map(\.tabTitles)
      return titles.count == 2 && titles[0].sorted() == titles[1].sorted()
        && titles[0].sorted() == (before + ["New Tab"]).sorted()
    }
    XCTAssertTrue(same, "The windows don't list Home's tabs as expected: \(after.map(\.tabTitles)) from \(before)")
    XCTAssertTrue(after.allSatisfy { $0.spaceName == "Home" }, "A window left Home")
  }

  /// In full screen, Work covers Home's full-screen window. When Home's
  /// window closes under it, as its only tab closes from outside Clair,
  /// Work's window stays, as a window of its own (design D4).
  func testTheCoverStaysWhenTheFullScreenWindowCloses() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    // Work holds a page of its own, so that only Home's tabs are new tab
    // pages and Counter home.
    let work = try await browser.open(counter("work"))
    defer { work.close() }
    _ = await browser.waitForTabs { $0.contains("Counter work") }
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    browser.ui.typeKey("f", modifierFlags: [.control, .command])
    let screen = NSScreen.main?.frame.size ?? .zero
    let full = await Harness.wait(for: 30) { browser.nativeWindow.frame.size == screen }
    try require(full, "The window didn't go full screen: \(browser.nativeWindow.frame)")
    try await Task.sleep(for: .seconds(1))
    browser.ui.typeKey("2", modifierFlags: .control)
    let onWork = await browser.waitForSpace("Work", seconds: 30)
    try require(onWork, "Ctrl+2 didn't show Work in full screen")
    browser.tabRow("Counter work")?.click()
    _ = await browser.waitForActiveRow("Counter work")
    // Every tab of Home's full-screen window closes from outside Clair, and
    // the window with them.
    let session = try await browser.browserSession()
    for target in try await browser.pageTargets()
    where target.url.hasSuffix("?home") || target.url.hasPrefix("chrome://newtab") {
      _ = try? await session.send("Target.closeTarget", ["targetId": target.id])
    }
    session.close()
    let gone = await browser.waitForTarget("?home", open: false, seconds: 30)
    try require(gone, "Counter home didn't close")
    let alone = await Harness.wait(for: 15) { browser.visibleNativeWindowCount == 1 }
    XCTAssertTrue(alone, "Work's window didn't stay alone: \(browser.visibleNativeWindowCount)")
    XCTAssertEqual(browser.spaceName, "Work", "The window doesn't show Work")
    let controls = await Harness.wait(for: 10) {
      browser.nativeWindow.buttons[XCUIIdentifierCloseWindow].exists
    }
    XCTAssertTrue(controls, "The window kept the cover's hidden controls")
  }

  /// What an extension asks of the window of a profile the window doesn't
  /// show leaves it hidden, and leaves the group's full screen as it is.
  func testAnExtensionLeavesAHiddenProfilesWindowHidden() async throws {
    let extensionPath = Fixture.directory.appending(path: "extensions/popup-badge").path
    let (browser, home) = try await startWithWorkProfile(arguments: ["--load-extension=\(extensionPath)"])
    defer { home.close() }
    // The extension is the default profile's: its one window is Home's, which
    // the window hides while it shows Work.
    let worker = try await extensionWorker(browser, named: "Clair Test Action")
    defer { worker.close() }
    let ids = try await worker.evaluate("chrome.windows.getAll().then(all => all.map(w => w.id))") as? [Int] ?? []
    try require(ids.count == 1, "The default profile has \(ids.count) windows")
    func update(_ info: String) async throws -> String? {
      try await worker.evaluate(
        "chrome.windows.update(\(ids[0]), \(info)).then(() => 'done', error => error.message)") as? String
    }
    let frame = browser.nativeWindow.frame
    for info in [
      "{focused: false}", "{state: 'minimized'}", "{state: 'maximized'}", "{state: 'fullscreen'}",
      "{state: 'normal'}", "{left: 40, top: 60, width: 500, height: 400}",
    ] {
      let result = try await update(info)
      XCTAssertEqual(result, "done", "chrome.windows.update(\(info)) failed")
      try await Task.sleep(for: .seconds(2))
      XCTAssertEqual(browser.visibleNativeWindowCount, 1, "\(info) showed Home's window")
      XCTAssertEqual(browser.spaceName, "Work", "\(info) took the window away from Work")
      XCTAssertEqual(browser.nativeWindow.frame, frame, "\(info) changed the window's frame")
    }
    browser.ui.typeKey("1", modifierFlags: .control)
    let onHome = await browser.waitForSpace("Home")
    try require(onHome, "Ctrl+1 didn't show Home")
    XCTAssertEqual(browser.visibleNativeWindowCount, 1, "Switching to Home showed a second window")
    XCTAssertEqual(browser.nativeWindow.frame, frame, "Home came back at another frame")

    // Home goes full screen at the extension's request, which it leaves at
    // the extension's request too, and Work covers it.
    let entered = try await update("{state: 'fullscreen'}")
    try require(entered == "done", "Home didn't take the extension's full screen: \(entered ?? "nil")")
    let screen = NSScreen.main?.frame.size ?? .zero
    let full = await Harness.wait(for: 30) { browser.nativeWindow.frame.size == screen }
    try require(full, "The window didn't go full screen: \(browser.nativeWindow.frame)")
    try await Task.sleep(for: .seconds(1))
    browser.ui.typeKey("2", modifierFlags: .control)
    let onWork = await browser.waitForSpace("Work", seconds: 30)
    try require(onWork, "Ctrl+2 didn't show Work in full screen")
    let left = try await update("{state: 'normal'}")
    XCTAssertEqual(left, "done", "chrome.windows.update({state: 'normal'}) failed")
    try await Task.sleep(for: .seconds(3))
    XCTAssertEqual(browser.spaceName, "Work", "The window doesn't show Work")
    // Home's window, under Work's, kept the full screen Work shows.
    browser.ui.typeKey("1", modifierFlags: .control)
    let back = await browser.waitForSpace("Home", seconds: 30)
    try require(back, "Ctrl+1 didn't show Home")
    let stillFull = await Harness.wait(for: 10) { browser.nativeWindow.frame.size == screen }
    XCTAssertTrue(stillFull, "Home's window left full screen under Work's: \(browser.nativeWindow.frame)")
  }

  /// A window of a profile the group doesn't show hears of its extensions'
  /// changes when it shows again.
  func testAHiddenProfilesWindowShowsItsActionsLatestBadge() async throws {
    let extensionPath = Fixture.directory.appending(path: "extensions/popup-badge").path
    let (browser, home) = try await startWithWorkProfile(arguments: ["--load-extension=\(extensionPath)"])
    defer { home.close() }
    browser.ui.typeKey("1", modifierFlags: .control)
    let onHome = await browser.waitForSpace("Home")
    try require(onHome, "Ctrl+1 didn't show Home")
    let pinned = try browser.pinExtensionFromSiteControls()
    let badge = await Harness.wait(for: 15) { (pinned.value as? String) == "3" }
    try require(badge, "The pinned action doesn't show its badge")

    browser.ui.typeKey("2", modifierFlags: .control)
    let onWork = await browser.waitForSpace("Work")
    try require(onWork, "Ctrl+2 didn't show Work")
    let worker = try await extensionWorker(browser, named: "Clair Test Action")
    defer { worker.close() }
    let set = try await worker.evaluate(
      "chrome.action.setBadgeText({text: '7'}).then(() => 'done', error => error.message)") as? String
    try require(set == "done", "chrome.action.setBadgeText failed: \(set ?? "nil")")
    try await Task.sleep(for: .seconds(2))

    browser.ui.typeKey("1", modifierFlags: .control)
    let back = await browser.waitForSpace("Home")
    try require(back, "Ctrl+1 didn't show Home again")
    let shown = browser.element("clair.extensionAction")
    let updated = await Harness.wait(for: 5) { (shown.value as? String) == "7" }
    XCTAssertTrue(updated, "Home's pinned action shows \(shown.value ?? "nothing"), not the badge it got while hidden")
  }

  /// Taking a tab of another profile between windows keeps its page and
  /// leaves a still; closing a window with tabs of two profiles keeps them
  /// all, without a reload or a page asking (design D5). Closing the last
  /// window closes its tabs, and Reopen Closed Window brings them back.
  func testSharedTabsAndClosingWindowsAcrossProfiles() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    _ = try await home.evaluate("window.counter = 9; 1")
    // Window A, on Work, holds Counter w; Counter home, of the default
    // profile, is in its hidden member.
    let w = try await browser.open(counter("w"))
    defer { w.close() }
    _ = await browser.waitForTabs { $0.contains("Counter w") }
    _ = try await w.evaluate("window.counter = 5; 1")
    let b = try await browser.open(counter("b"), newWindow: true)
    defer { b.close() }
    _ = try await browser.waitForNativeWindows(2)
    try await tile([w, b], in: browser)
    try await Task.sleep(for: .seconds(1))
    let windows = try await browser.waitForNativeWindows(2).sorted { $0.frame.minX < $1.frame.minX }
    let windowA = windows[0], windowB = windows[1]

    // B shows Home and takes Counter home, which no window shows.
    windowB.click()
    browser.ui.typeKey("1", modifierFlags: .control)
    let bOnHome = await Harness.wait(for: 15) { windowB.spaceName == "Home" }
    try require(bOnHome, "B didn't switch to Home")
    windowB.tabRow("Counter home")?.click()
    let tookHome = await windowB.waitForActiveRow("Counter home")
    try require(tookHome, "B didn't show Counter home: \(windowB.activeRow ?? "none")")

    // B switches to Work and takes Counter w from A.
    browser.ui.typeKey("2", modifierFlags: .control)
    let bOnWork = await Harness.wait(for: 15) { windowB.spaceName == "Work" }
    try require(bOnWork, "B didn't switch to Work")
    windowB.tabRow("Counter w")?.click()
    let taken = await windowB.waitForActiveRow("Counter w")
    try require(taken, "B didn't show Counter w: \(windowB.activeRow ?? "none")")
    let takenCount = try await w.evaluate("window.counter") as? Double
    XCTAssertEqual(takenCount, 5, "Taking the tab reloaded its page")
    let still = await windowA.waitForStill()
    XCTAssertTrue(still, "A shows no still of the tab B took")

    // B also holds a page that asks before it closes, armed by a click.
    let asking = try await browser.open(url("beforeunload.html"))
    defer { asking.close() }
    _ = try await asking.evaluate("document.body.id = 'body'; 1")
    try await asking.click("body")

    // Closing B keeps its tabs, of two profiles, in A, without asking.
    windowB.click()
    browser.ui.typeKey("w", modifierFlags: [.command, .shift])
    _ = try await browser.waitForNativeWindows(1)
    XCTAssertFalse(browser.ui.buttons["Leave"].waitForExistence(timeout: 3), "Closing B asked about a page")
    let workKept = await browser.waitForTabs { $0.contains("Counter w") }
    XCTAssertTrue(workKept, "A's Work doesn't list Counter w: \(browser.tabTitles)")
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let homeKept = await browser.waitForTabs { $0.contains("Counter home") }
    XCTAssertTrue(homeKept, "A's Home doesn't list Counter home: \(browser.tabTitles)")
    let wCount = try await w.evaluate("window.counter") as? Double
    let homeCount = try await home.evaluate("window.counter") as? Double
    XCTAssertEqual(wCount, 5, "Counter w reloaded")
    XCTAssertEqual(homeCount, 9, "Counter home reloaded")
    let askingKept = try await browser.target(endingWith: "beforeunload.html")
    XCTAssertNotNil(askingKept, "Closing B closed the page that asks")

    // Closing the last window closes its tabs; Reopen Closed Window brings
    // them back.
    browser.ui.typeKey("w", modifierFlags: [.command, .shift])
    let leave = browser.ui.buttons["Leave"]
    if leave.waitForExistence(timeout: 10) {
      leave.click()
    }
    let closed = await browser.waitForTarget("?w", open: false, seconds: 30)
    try require(closed, "Closing the last window didn't close its tabs")
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    let back = await browser.waitForTarget("?w", seconds: 30)
    XCTAssertTrue(back, "Reopen Closed Window didn't bring the tabs back")
  }

  /// A data folder from before profiles, whose Spaces name no profile, loads
  /// with every Space on the default profile (design D2).
  func testAnOldDataFolderLoadsOnTheDefaultProfile() async throws {
    let (browser, home) = try await startWithWorkProfile()
    home.close()
    try await Task.sleep(for: .seconds(3))
    try await browser.quit()
    let localState = browser.dataDirectory.appending(path: "Local State")
    guard var state = try JSONSerialization.jsonObject(with: Data(contentsOf: localState)) as? [String: Any],
      var clair = state["clair"] as? [String: Any],
      var store = clair["spaces"] as? [String: Any],
      var entries = store["spaces"] as? [String: [String: Any]]
    else {
      throw HarnessError("Local State has no clair.spaces")
    }
    for id in entries.keys {
      entries[id]?.removeValue(forKey: "profile")
    }
    store["spaces"] = entries
    clair["spaces"] = store
    state["clair"] = clair
    try JSONSerialization.data(withJSONObject: state).write(to: localState)

    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back")
    try browser.openProfilesPage()
    let labels = await Harness.wait(for: 15) {
      browser.profileRows.map(\.label) == ["\(Self.defaultProfile), 2 Spaces", "Work"]
    }
    XCTAssertTrue(labels, "Both Spaces aren't on the default profile: \(browser.profileRows.map(\.label))")
  }

  /// A Settings link for a profile opens with no window open: a new window,
  /// on a Space of that profile (design D7).
  func testASettingsLinkWithNoWindowOpen() async throws {
    let (browser, home) = try await startWithWorkProfile()
    home.close()
    // The window's two members, Home's hidden one first, close with it
    // (#147).
    browser.nativeWindow.buttons[XCUIIdentifierCloseWindow].click()
    let closed = await Harness.wait(for: 30) { try await browser.pageTargets().isEmpty }
    try require(closed, "The window didn't close: \(try await browser.pageTargets().map(\.url))")
    try browser.openProfilesPage()
    browser.profileRow("Work")?.click()
    let links = browser.ui.windows["Profiles"].descendants(matching: .any).matching(identifier: "clair.profileLink")
      .allElementsBoundByIndex
    try require(links.count == 4, "The page doesn't have four link rows")
    links[1].click()
    let opened = await browser.waitForTarget("chrome://settings/privacy", seconds: 30)
    XCTAssertTrue(opened, "Privacy and Security didn't open chrome://settings/privacy")
    let window = await Harness.wait(for: 30) { browser.visibleNativeWindowCount == 1 }
    XCTAssertTrue(window, "No window opened for the link")
    let shown = await browser.waitForSpace("Work", seconds: 15)
    XCTAssertTrue(shown, "The settings page isn't in a Space of Work: \(browser.spaceName)")
  }

  /// Staying on a page that asks stops the window's close, and every member
  /// stays; closing again, and leaving, closes all of it (design D5, #147).
  func testStayingOnAPageStopsTheWindowsClose() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    // Home's member, hidden behind Work's, holds a page that asks.
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let asking = try await browser.open(url("beforeunload.html"))
    defer { asking.close() }
    // The page asks only after a click.
    _ = try await asking.evaluate("document.body.id = 'body'; 1")
    try await asking.click("body")
    browser.ui.typeKey("2", modifierFlags: .control)
    let work = await browser.waitForSpace("Work")
    try require(work, "The window doesn't show Work: \(browser.spaceName)")

    browser.nativeWindow.buttons[XCUIIdentifierCloseWindow].click()
    let cancel = browser.ui.buttons["Cancel"]
    try require(cancel.waitForExistence(timeout: 15), "Closing the window didn't ask about Home's page")
    cancel.click()
    try await Task.sleep(for: .seconds(2))
    let urls = try await browser.pageTargets().map(\.url)
    XCTAssertTrue(urls.contains { $0.hasSuffix("beforeunload.html") }, "Staying on the page closed it: \(urls)")
    XCTAssertTrue(urls.contains { $0.hasPrefix("chrome://newtab") }, "Staying on the page closed Work's tab: \(urls)")
    XCTAssertEqual(browser.visibleNativeWindowCount, 1, "Staying on the page didn't keep one window")

    browser.nativeWindow.buttons[XCUIIdentifierCloseWindow].click()
    let leave = browser.ui.buttons["Leave"]
    try require(leave.waitForExistence(timeout: 15), "Closing the window again didn't ask about Home's page")
    leave.click()
    let closed = await Harness.wait(for: 30) { try await browser.pageTargets().isEmpty }
    try require(closed, "The window didn't close: \(try await browser.pageTargets().map(\.url))")
  }

  /// Settings act for a profile: Work's download folder applies to Work only,
  /// Search Engine opens Chromium's page in a Space of Work, and Manage
  /// Extensions… opens in the shown Space's profile.
  func testSettingsPagesFollowTheProfile() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    try browser.openProfilesPage()
    browser.profileRow("Work")?.click()
    let popup = browser.settingsElement("clair.downloadLocation")
    try require(popup.waitForExistence(timeout: 10), "The page has no Download location")
    // ungoogled-chromium asks where to save by default: Work saves to its
    // folder instead, and the default profile goes on asking.
    popup.click()
    try await browser.openMenuItem("Downloads").click()
    try await Task.sleep(for: .seconds(1))

    // Search Engine opens Chromium's page in a Space of Work.
    let links = browser.ui.windows["Profiles"].descendants(matching: .any).matching(identifier: "clair.profileLink")
      .allElementsBoundByIndex
    try require(links.count == 4, "The page doesn't have four link rows")
    links[0].click()
    let opened = await browser.waitForTarget("chrome://settings/search", seconds: 30)
    XCTAssertTrue(opened, "Search Engine didn't open chrome://settings/search")
    let shown = await browser.waitForSpace("Work", seconds: 15)
    XCTAssertTrue(shown, "The settings page isn't in a Space of Work: \(browser.spaceName)")
    XCTAssertFalse(browser.ui.windows["Profiles"].exists, "Settings didn't close")

    // Asking applies to Work only.
    let searchTarget = try await browser.target(endingWith: "/search")
    try require(searchTarget != nil, "The settings tab isn't open")
    let workSettings = try await browser.session(onTarget: searchTarget!.id)
    defer { workSettings.close() }
    let asks = try await workSettings.evaluate(
      "(async () => (await new Promise(r => chrome.settingsPrivate.getPref('download.prompt_for_download', r))).value)()")
    XCTAssertEqual(asks as? Bool, false, "Choosing the folder didn't apply to Work")
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let homeSettings = try await browser.open("chrome://settings/downloads")
    defer { homeSettings.close() }
    try await Task.sleep(for: .seconds(2))
    let homeAsks = try await homeSettings.evaluate(
      "(async () => (await new Promise(r => chrome.settingsPrivate.getPref('download.prompt_for_download', r))).value)()")
    XCTAssertEqual(homeAsks as? Bool, true, "Work's folder applied to the default profile")

    // The Extensions menu acts for the shown Space's profile.
    func manageExtensions() {
      browser.ui.menuBars.menuBarItems["Extensions"].click()
      browser.ui.menuItems["Manage Extensions…"].click()
    }
    browser.ui.typeKey("2", modifierFlags: .control)
    _ = await browser.waitForSpace("Work")
    manageExtensions()
    let inWork = await browser.waitForTabs(30) { $0.contains("Extensions") }
    XCTAssertTrue(inWork, "Manage Extensions… didn't open in Work: \(browser.tabTitles)")
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    manageExtensions()
    let inHome = await browser.waitForTabs(30) { $0.contains("Extensions") }
    XCTAssertTrue(inHome, "Manage Extensions… didn't open in Home: \(browser.tabTitles)")
    // One page per profile: within one profile Chromium would reuse its tab.
    let pages = try await browser.pageTargets().filter { $0.url.hasPrefix("chrome://extensions") }
    XCTAssertEqual(pages.count, 2, "The two Spaces' profiles share an extensions page")
  }

  /// native-quit-confirmation: Cmd+Q and Clair › Quit Clair ask in Dia's
  /// dialog; Cancel keeps Clair running, and "Always quit" quits and turns
  /// the warning off, so after a relaunch Cmd+Q quits at once.
  func testWarnBeforeQuitting() async throws {
    try Harness.setRestoreWindows(false)
    let (browser, tab) = try await startWithPage("counter.html?a")
    tab.close()
    browser.nativeWindow.click()
    browser.ui.typeKey("q", modifierFlags: .command)
    try require(browser.dialog.waitForExistence(timeout: 10), "Cmd+Q didn't ask before quitting")
    XCTAssertTrue(
      browser.dialog.staticTexts["Are you sure you want to quit Clair?"].exists, "The dialog isn't the quit dialog")
    XCTAssertTrue(browser.dialogButton("clair.dialogLeading").exists, "The dialog has no Always quit button")
    XCTAssertTrue(browser.dialogButton("clair.dialogDefault").exists, "The dialog has no Quit button")
    browser.dialogButton("clair.dialogCancel").click()
    try await Task.sleep(for: .seconds(2))
    XCTAssertNotNil(try browser.runningProcessID(), "Cancel quit Clair")
    XCTAssertFalse(browser.dialog.exists, "Cancel left the dialog open")

    let clair = browser.ui.menuBars.menuBarItems["Clair"]
    try require(clair.waitForExistence(timeout: 10), "There's no Clair menu")
    clair.click()
    let quitItem = browser.clairMenuItem(titled: "Quit Clair")
    try require(quitItem.waitForExistence(timeout: 10), "The Clair menu has no Quit Clair item")
    quitItem.click()
    try require(browser.dialog.waitForExistence(timeout: 10), "Quit Clair didn't ask before quitting")
    browser.dialogButton("clair.dialogLeading").click()
    let quit = await Harness.wait(for: 30) { try browser.runningProcessID() == nil }
    try require(quit, "Always quit didn't quit")

    let localState = browser.dataDirectory.appending(path: "Local State")
    let state = try JSONSerialization.jsonObject(with: Data(contentsOf: localState)) as? [String: Any]
    let warns = (state?["browser"] as? [String: Any])?["confirm_to_quit"] as? Bool
    XCTAssertEqual(warns, false, "Always quit didn't turn Warn before quitting off")

    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back")
    browser.nativeWindow.click()
    browser.ui.typeKey("q", modifierFlags: .command)
    let quitAtOnce = await Harness.wait(for: 15) { try browser.runningProcessID() == nil }
    XCTAssertTrue(quitAtOnce, "Cmd+Q didn't quit at once with the warning off")
  }
}
