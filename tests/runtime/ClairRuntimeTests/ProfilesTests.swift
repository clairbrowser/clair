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
  func startWithWorkProfile() async throws -> (Browser, DevToolsSession) {
    try Harness.setRestoreWindows(false)
    let (browser, tab) = try await startWithPage("counter.html?home")
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

    try browser.openProfilesPage()
    XCTAssertEqual(browser.profileRows.count, 1, "There isn't one profile at first")
    // The only profile, which Home uses, can't be removed.
    XCTAssertFalse(browser.settingsElement("clair.profilesRemove").isEnabled, "Remove is on for the last profile")

    try await browser.addProfile("Client")
    XCTAssertTrue(browser.profileRow("Client")?.isSelected == true, "The new profile isn't selected")
    XCTAssertTrue(browser.settingsElement("clair.profilesRemove").isEnabled, "Remove is off for a profile no Space uses")
    XCTAssertTrue(
      browser.settingsElement("clair.profileLinksNote").exists, "The link rows aren't explained for a profile without a Space")

    // Rename.
    browser.settingsElement("clair.profilesRename").click()
    try require(browser.dialog.waitForExistence(timeout: 10), "Rename didn't open its dialog")
    try browser.answerDialog(field: "clair.renameProfileName", with: "Office")
    let renamed = await Harness.wait(for: 15) { browser.profileRow("Office") != nil }
    XCTAssertTrue(renamed, "The profile wasn't renamed")

    // The default profile, which Home uses, can't be removed.
    browser.profileRows.first?.click()
    XCTAssertFalse(browser.settingsElement("clair.profilesRemove").isEnabled, "Remove is on for a profile a Space uses")

    // Remove, after typing the name.
    let folders = try FileManager.default.contentsOfDirectory(atPath: browser.dataDirectory.path)
    browser.profileRow("Office")?.click()
    browser.settingsElement("clair.profilesRemove").click()
    try require(browser.dialog.waitForExistence(timeout: 10), "Remove didn't ask")
    let field = browser.dialogElement("clair.deleteProfileName")
    field.click()
    field.typeText("office 2")
    XCTAssertFalse(browser.dialogElement("clair.dialogDefault").isEnabled, "Delete is on for a wrong name")
    field.typeKey("a", modifierFlags: .command)
    field.typeText("Office")
    XCTAssertTrue(browser.dialogElement("clair.dialogDefault").isEnabled, "Delete is off for the name")
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

  func testNoProfilePickerWithTwoProfiles() async throws {
    let (browser, tab) = try await startWithWorkProfile()
    tab.close()
    try await Task.sleep(for: .seconds(3))
    try await browser.quit()
    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "No browser window opened with two profiles")
    let picker = try await browser.pageTargets().contains { $0.url.hasPrefix("chrome://profile-picker") }
    XCTAssertFalse(picker, "Chromium's profile picker showed at launch")
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

  func testSettingASpacesProfile() async throws {
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
  }

  func testManageSpacesStaysOpenWhenTheShownSpaceChangesProfile() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    try browser.chooseSpacesItem("Manage Spaces…")
    try require(browser.dialog.waitForExistence(timeout: 10), "Manage Spaces didn't open")
    let popup = browser.dialogElement("clair.profilePopup")
    popup.click()
    try await browser.openMenuItem("Work").click()
    try require(
      browser.dialogElement("clair.dialogDefault").waitForExistence(timeout: 10), "Changing Home's profile didn't ask")
    browser.dialogElement("clair.dialogDefault").click()
    let back = await Harness.wait(for: 15) { browser.dialog.exists && browser.dialogElement("clair.manageSpacesList").exists }
    XCTAssertTrue(back, "Manage Spaces didn't stay open")

    // A Space Manage Spaces adds has no tab: its profile changes at once.
    browser.dialogElement("clair.manageSpacesAdd").click()
    let added = await Harness.wait(for: 10) {
      browser.dialog.descendants(matching: .any).matching(identifier: "clair.manageSpacesRow").count == 3
    }
    try require(added, "Add didn't add a Space")
    browser.dialogElement("clair.profilePopup").click()
    try await browser.openMenuItem(Self.defaultProfile).click()
    let asked = browser.dialogElement("clair.manageSpacesList").waitForExistence(timeout: 3)
    XCTAssertTrue(asked, "Changing an empty Space's profile asked")
    browser.ui.typeKey(.escape, modifierFlags: [])
  }

  func testMoveToSpaceAcrossProfiles() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let moving = try await browser.open(counter("moving"))
    let staying = try await browser.open(counter("staying"))
    defer {
      moving.close()
      staying.close()
    }
    _ = try await moving.evaluate("window.counter = 5; 1")

    // Another tab: the window stays, and a notice says where it went.
    browser.tabRow("Counter staying")?.click()
    _ = await browser.waitForActiveRow("Counter staying")
    try await moveRow("Counter home", to: "Work", in: browser)
    let notice = browser.element("clair.tabMoved")
    XCTAssertTrue(notice.waitForExistence(timeout: 10), "Moving another tab showed no notice")
    XCTAssertEqual(notice.value as? String, "Tab was moved to Work", "The notice doesn't name Work")
    XCTAssertEqual(browser.spaceName, "Home", "Moving another tab left Home")

    // The active tab: the window follows it, reopened at the top of Work.
    browser.tabRow("Counter moving")?.click()
    _ = await browser.waitForActiveRow("Counter moving")
    try await moveRow("Counter moving", to: "Work", in: browser)
    let followed = await browser.waitForSpace("Work", seconds: 30)
    XCTAssertTrue(followed, "Moving the active tab didn't show Work")
    let active = await browser.waitForActiveRow("Counter moving")
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

  func testTheEmptiedSpace() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    // Work's only row is a new tab page: closing it closes the window.
    let windowsBefore = try await browser.windowCount()
    browser.ui.typeKey("w", modifierFlags: .command)
    let closed = await Harness.wait(for: 30) { try await browser.windowCount() < windowsBefore }
    XCTAssertTrue(closed, "Closing an emptied Space's new tab page didn't close the window")
  }

  func testRelaunchWithRestoringOff() async throws {
    let (browser, home) = try await startWithWorkProfile()
    let work = try await browser.open(counter("work"))
    // A second window, last active, on Home.
    let other = try await browser.open(counter("other"), newWindow: true)
    _ = await Harness.wait(for: 30) { browser.visibleNativeWindowCount == 2 }
    browser.ui.typeKey("1", modifierFlags: .control)
    try await Task.sleep(for: .seconds(3))
    [home, work, other].forEach { $0.close() }
    try await browser.quit()
    try Harness.setRestoreWindows(false)
    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back")
    let one = await Harness.wait(for: 30) { browser.visibleNativeWindowCount == 1 }
    XCTAssertTrue(one, "Clair didn't come back as one window: \(browser.visibleNativeWindowCount)")
    let onHome = await browser.waitForSpace("Home", seconds: 30)
    XCTAssertTrue(onHome, "The window doesn't show the Space last shown: \(browser.spaceName)")
    let listed = await browser.waitForTabs(30) { $0.contains("Counter home") }
    XCTAssertTrue(listed, "Home doesn't list its tabs: \(browser.tabTitles)")
    XCTAssertTrue(
      browser.element("clair.commandBarField").waitForExistence(timeout: 10), "The window didn't open the command bar")
    browser.ui.typeKey(.escape, modifierFlags: [])
    browser.ui.typeKey("2", modifierFlags: .control)
    // The second window opened on Work, the Space shown then.
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

  func testRelaunchWithRestoringOn() async throws {
    let (browser, home) = try await startWithWorkProfile()
    let work = try await browser.open(counter("work"))
    browser.tabRow("Counter work")?.click()
    _ = await browser.waitForActiveRow("Counter work")
    let other = try await browser.open(counter("other"), newWindow: true)
    _ = await Harness.wait(for: 30) { browser.visibleNativeWindowCount == 2 }
    try await Task.sleep(for: .seconds(3))
    [home, work, other].forEach { $0.close() }
    try await browser.quit()
    try Harness.setRestoreWindows(true)
    try await browser.start()
    let two = await Harness.wait(for: 60) { browser.visibleNativeWindowCount == 2 }
    XCTAssertTrue(two, "Both windows didn't come back: \(browser.visibleNativeWindowCount)")
    let windows = browser.nativeWindows
    let rows = windows.map { $0.activeRow ?? "" }.sorted()
    XCTAssertEqual(rows, ["Counter other", "Counter work"], "The windows don't show their tabs: \(rows)")
  }

  /// A window of two profiles comes back as one window on every relaunch:
  /// the browser a later profile restores joins the group, and its tabs'
  /// session tags follow it (design D6).
  func testRestoringOnKeepsTheGroupAcrossTwoRelaunches() async throws {
    let (browser, home) = try await startWithWorkProfile()
    let work = try await browser.open(counter("work"))
    _ = await browser.waitForTabs { $0.contains("Counter work") }
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    try await Task.sleep(for: .seconds(3))
    [home, work].forEach { $0.close() }
    try await browser.quit()
    try Harness.setRestoreWindows(true)
    for launch in ["first", "second"] {
      try await browser.start()
      try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back (\(launch))")
      // Each profile restores in turn; give the later one time to join.
      try await Task.sleep(for: .seconds(5))
      XCTAssertEqual(browser.visibleNativeWindowCount, 1, "The window came back split (\(launch) relaunch)")
      if launch == "first" {
        try await browser.quit()
      }
    }
    browser.ui.typeKey("2", modifierFlags: .control)
    let onWork = await browser.waitForTabs(30) { $0.contains("Counter work") }
    XCTAssertTrue(onWork, "Work doesn't list its tab: \(browser.tabTitles)")
    XCTAssertEqual(browser.visibleNativeWindowCount, 1, "Switching to Work showed a second window")
  }

  /// With restoring on, a window last on a new tab page comes back on one,
  /// though new tab pages themselves aren't restored (design D6).
  func testRestoringOnASelectedNewTabPage() async throws {
    try Harness.setRestoreWindows(true)
    let (browser, home) = try await startWithPage("counter.html?home")
    let newTab = try await browser.open("chrome://newtab/")
    let selected = await browser.waitForActiveRow("New Tab")
    try require(selected, "The new tab page isn't the active row: \(browser.activeRow ?? "none")")
    try await Task.sleep(for: .seconds(3))
    [home, newTab].forEach { $0.close() }
    try await browser.quit()
    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back")
    let listed = await browser.waitForTabs(30) { $0.contains("Counter home") }
    XCTAssertTrue(listed, "Home doesn't list its tab: \(browser.tabTitles)")
    let onNewTab = await browser.waitForActiveRow("New Tab", seconds: 30)
    XCTAssertTrue(onNewTab, "The window came back on \(browser.activeRow ?? "none"), not a new tab page")
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

  /// The Extensions menu acts for the shown Space's profile: Manage
  /// Extensions… opens Chromium's page in that profile, in its Space.
  func testTheExtensionsMenuFollowsTheProfile() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    try require(browser.spaceName == "Work", "The window doesn't show Work")
    func manageExtensions() {
      browser.ui.menuBars.menuBarItems["Extensions"].click()
      browser.ui.menuItems["Manage Extensions…"].click()
    }
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

  /// Taking a tab of another profile between windows keeps its page and
  /// leaves a still; closing a window with tabs of two profiles keeps them
  /// all, without a reload (design D5).
  func testSharedTabsAcrossProfiles() async throws {
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

    // Closing B keeps both its tabs, of two profiles, in A.
    windowB.click()
    browser.ui.typeKey("w", modifierFlags: [.command, .shift])
    _ = try await browser.waitForNativeWindows(1)
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

  /// A link from another app opens as a tab in a window already open, not
  /// in a window of its own (design D8).
  func testALinkFromAnotherAppOpensInAWindowAlreadyOpen() async throws {
    let (browser, home) = try await startWithWorkProfile()
    defer { home.close() }
    let session = try await browser.browserSession()
    defer { session.close() }
    func windowOf(_ target: Browser.Target) async throws -> Int? {
      let window = try await session.send("Browser.getWindowForTarget", ["targetId": target.id])
      return window["windowId"] as? Int
    }
    var windows: Set<Int> = []
    for target in try await browser.pageTargets() {
      if let window = try await windowOf(target) {
        windows.insert(window)
      }
    }
    // As a link from outside reaches the running Clair: a second launch on
    // its data folder hands the URL over and exits. XCUITest loses track of
    // the app after it, so what follows goes through DevTools alone.
    let launch = Process()
    launch.executableURL = browser.appPath.appending(path: "Contents/MacOS/Clair")
    launch.arguments = [
      "--user-data-dir=\(browser.dataDirectory.path)", "--use-mock-keychain", url("counter.html?external"),
    ]
    try launch.run()
    let opened = await browser.waitForTarget("?external", seconds: 30)
    try require(opened, "The link didn't open")
    guard let target = try await browser.target(endingWith: "?external") else {
      throw HarnessError("The link's tab is gone")
    }
    let window = try await windowOf(target)
    XCTAssertTrue(window.map(windows.contains) == true, "The link opened in a window of its own")
  }

  func testDownloadSettingsAndLinksPerProfile() async throws {
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
  }

  func testWarnBeforeQuittingOff() async throws {
    try Harness.setRestoreWindows(false)
    let (browser, tab) = try await startWithPage("counter.html?a")
    tab.close()
    browser.ui.typeKey(",", modifierFlags: .command)
    let advanced = browser.ui.toolbars.buttons["Advanced"]
    try require(advanced.waitForExistence(timeout: 15), "Settings has no Advanced page")
    advanced.click()
    let warn = browser.ui.switches["clair.warnBeforeQuittingToggle"]
    try require(warn.waitForExistence(timeout: 10), "The Advanced page has no Warn before quitting toggle")
    XCTAssertEqual(warn.value as? Int, 1, "Warn before quitting isn't on by default")
    let restore = browser.ui.switches["clair.restoreWindowsToggle"]
    XCTAssertEqual(restore.value as? Int, 0, "Restoring windows isn't off by default")
    warn.click()
    browser.nativeWindow.click()
    browser.ui.typeKey("q", modifierFlags: .command)
    let quit = await Harness.wait(for: 15) { try browser.runningProcessID() == nil }
    XCTAssertTrue(quit, "Cmd+Q didn't quit at once with the warning off")
  }
}
