// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import XCTest

extension Browser {
  var bookmarksMenu: XCUIElement { ui.menuBars.menuBarItems["Bookmarks"] }

  /// Opens the Bookmarks menu and returns its items' titles, "-" for a
  /// divider. The menu stays open; Esc closes it.
  func openBookmarksMenu() throws -> [String] {
    ui.activate()
    try require(bookmarksMenu.waitForExistence(timeout: 30), "The menu bar has no Bookmarks menu")
    bookmarksMenu.click()
    let menu = bookmarksMenu.menus.firstMatch
    try require(menu.waitForExistence(timeout: 5), "The Bookmarks menu didn't open")
    return try menu.snapshot().children.filter { $0.elementType == .menuItem }.map {
      $0.title.isEmpty ? "-" : $0.title
    }
  }

  /// The Bookmarks menu's first item, read with the menu open and closed again.
  func bookmarkPageItemTitle() throws -> String? {
    defer { ui.typeKey(.escape, modifierFlags: []) }
    return try openBookmarksMenu().first
  }

  var dialogTitle: String? {
    let title = dialog.descendants(matching: .any).matching(identifier: "clair.dialogTitle").firstMatch
    return title.exists ? title.label : nil
  }

  func waitForDialog(_ shown: Bool = true, seconds: TimeInterval = 10) async -> Bool {
    await Harness.wait(for: seconds) { self.dialog.exists == shown }
  }

  /// Presses Shift+Cmd+B and waits for the bookmark dialog.
  func pressBookmarkThisPage() async throws {
    ui.typeKey("b", modifierFlags: [.command, .shift])
    let shown = await waitForDialog()
    try require(shown, "Shift+Cmd+B didn't open the bookmark dialog")
  }

  /// The saved bookmarks, for a failure's message.
  var savedDescription: String {
    (try? savedBookmarks()).map { "bar \($0.bar), other \($0.other)" } ?? "unreadable"
  }
}

extension BookmarkNode {
  /// This node and everything under it, depth-first.
  var all: [BookmarkNode] { [self] + children.flatMap(\.all) }
}

extension Array where Element == BookmarkNode {
  var all: [BookmarkNode] { flatMap(\.all) }
  var titles: [String] { map(\.title) }
}

/// The Bookmarks menu, the Bookmarks Bar notice, the bookmark dialog and
/// bookmark suggestions (add-bookmarks-menu tasks 3.4 to 3.6), on a profile
/// whose Bookmarks file the test writes before launch (design D9).
@MainActor
final class BookmarksTests: NativeWindowTestCase {
  static let barExtension = "Clair Test Bookmarks"

  /// Bookmarks of the suite's page server, at addresses the tests never
  /// visit unless they say so.
  func otherBookmarks() -> [BookmarkNode] {
    [
      BookmarkNode(title: "Clair Reading List", url: url("index.html?reading-list")),
      .folder("Reading", [BookmarkNode(title: "Reading Article", url: url("index.html?article"))]),
    ]
  }

  func barBookmarks() -> [BookmarkNode] {
    [
      BookmarkNode(title: "Bar Alpha", url: url("index.html?bar-alpha")),
      BookmarkNode(title: "Bar Beta", url: url("index.html?bar-beta")),
    ]
  }

  /// Starts Clair on a profile with `bar` and `other` bookmarks, showing
  /// `page`.
  func start(
    bar: [BookmarkNode] = [], other: [BookmarkNode] = [], page: String = "index.html", arguments: [String] = []
  ) async throws -> (Browser, DevToolsSession) {
    let browser = try Browser()
    self.browser = browser
    try browser.writeBookmarks(bar: bar, other: other)
    try await browser.start(arguments: arguments)
    let tab = try await browser.open(url(page))
    browser.ui.activate()
    try require(browser.nativeWindow.waitForExistence(timeout: 30), "Clair shows no native window")
    return (browser, tab)
  }

  // MARK: The menu and the Bookmarks Bar (task 3.4)

  /// The seeded Bookmarks Bar moves to the top of Other Bookmarks at launch,
  /// the Heads Up dialog says so once, and the menu lists Other Bookmarks'
  /// contents directly. A bookmark an extension later creates in the bar
  /// moves too, with no dialog, and a relaunch shows none either.
  func testTheBookmarksBarMovesIntoTheMenuWithOneNotice() async throws {
    let extensionPath = Fixture.directory.appending(path: "extensions/bookmarks-bar").path
    let arguments = ["--load-extension=\(extensionPath)"]
    let (browser, tab) = try await start(bar: barBookmarks(), other: otherBookmarks(), arguments: arguments)
    defer { tab.close() }

    let noticed = await browser.waitForDialog(seconds: 30)
    try require(noticed, "No dialog said that the Bookmarks Bar moved")
    XCTAssertEqual(browser.dialogTitle, "Heads Up")
    XCTAssertTrue(
      browser.dialog.staticTexts[
        "Clair doesn't have a bookmarks bar, so bookmarks saved or imported there are moved to the Bookmarks menu."
      ].exists, "The notice's message is wrong")
    browser.ui.typeKey(.return, modifierFlags: [])
    let dismissed = await browser.waitForDialog(false)
    try require(dismissed, "Return didn't close the notice")

    let drained = await browser.waitForSavedBookmarks { bar, other in
      bar.isEmpty && other.titles == ["Bar Alpha", "Bar Beta", "Clair Reading List", "Reading"]
    }
    XCTAssertTrue(drained, "The Bookmarks Bar wasn't moved to the top of Other Bookmarks: \(browser.savedDescription)")

    let titles = try browser.openBookmarksMenu()
    XCTAssertEqual(
      titles,
      ["Bookmark This Page…", "Manage Bookmarks", "-", "Bar Alpha", "Bar Beta", "Clair Reading List", "Reading"])
    browser.bookmarksMenu.menuItems["Reading"].hover()
    XCTAssertTrue(
      browser.bookmarksMenu.menuItems["Reading Article"].waitForExistence(timeout: 5),
      "The Reading submenu doesn't list its bookmark")
    browser.ui.typeKey(.escape, modifierFlags: [])
    browser.ui.typeKey(.escape, modifierFlags: [])

    // An extension's bookmark in the bar moves, and no dialog shows again.
    let worker = try await extensionWorker(browser, named: Self.barExtension)
    defer { worker.close() }
    _ = try await worker.evaluate("createInBar('Extension Bookmark', '\(url("index.html?extension"))')")
    let moved = await Harness.wait(for: 15) {
      let bar = try await worker.evaluate("childTitles('1')") as? [String]
      let other = try await worker.evaluate("childTitles('2')") as? [String]
      return bar == [] && other?.first == "Extension Bookmark"
    }
    XCTAssertTrue(moved, "The extension's bookmark stayed in the Bookmarks Bar")
    try await Task.sleep(for: .seconds(3))
    XCTAssertFalse(browser.dialog.exists, "The notice showed a second time")

    // Nor after a relaunch.
    try await browser.quit()
    try await browser.start(arguments: arguments)
    browser.ui.activate()
    try require(browser.nativeWindow.waitForExistence(timeout: 30), "Clair shows no native window after relaunch")
    try await Task.sleep(for: .seconds(5))
    XCTAssertFalse(browser.dialog.exists, "The notice showed again after a relaunch")
  }

  /// Without bookmarks, the menu holds only its two items; there's no Bookmark
  /// All Tabs or View › Always Show Bookmarks Bar; Option+Cmd+B opens the
  /// bookmark manager.
  func testTheMenuWithoutBookmarksAndManageBookmarks() async throws {
    let (browser, tab) = try await start()
    defer { tab.close() }
    XCTAssertEqual(try browser.openBookmarksMenu(), ["Bookmark This Page…", "Manage Bookmarks"])
    browser.ui.typeKey(.escape, modifierFlags: [])
    try await Task.sleep(for: .seconds(2))
    XCTAssertFalse(browser.dialog.exists, "A profile with no Bookmarks Bar showed the notice")

    browser.ui.menuBars.menuBarItems["View"].click()
    XCTAssertTrue(browser.ui.menuBars.menuItems["Hide Sidebar"].waitForExistence(timeout: 5), "The View menu didn't open")
    XCTAssertFalse(
      browser.ui.menuBars.menuItems["Always Show Bookmarks Bar"].exists, "View offers Always Show Bookmarks Bar")
    browser.ui.typeKey(.escape, modifierFlags: [])

    browser.ui.typeKey("b", modifierFlags: [.command, .option])
    let managed = await Harness.wait(for: 15) {
      try await browser.pageTargets().contains { $0.url.hasPrefix("chrome://bookmarks") }
    }
    XCTAssertTrue(managed, "Option+Cmd+B didn't open chrome://bookmarks")
  }

  /// Choosing a bookmark in the menu loads it in the active tab.
  func testChoosingABookmarkLoadsItInTheActiveTab() async throws {
    let (browser, tab) = try await start(other: otherBookmarks(), page: "index.html?start")
    defer { tab.close() }
    let tabs = try await browser.pageTargets().count
    _ = try browser.openBookmarksMenu()
    browser.bookmarksMenu.menuItems["Clair Reading List"].click()
    let loaded = await Harness.wait(for: 15) {
      let urls = try await browser.pageTargets().map(\.url)
      return urls.contains { $0.hasSuffix("?reading-list") } && !urls.contains { $0.hasSuffix("?start") }
    }
    XCTAssertTrue(loaded, "The bookmark didn't load in the active tab")
    let after = try await browser.pageTargets().count
    XCTAssertEqual(after, tabs, "Choosing the bookmark opened a tab")
  }

  // MARK: The bookmark dialog (task 3.5)

  /// Shift+Cmd+B adds the page and opens "Bookmark Added" with its title
  /// selected; Esc keeps a new name; Edit Bookmark… then moves it to a
  /// folder, adds none, creates a folder, and Remove deletes it; Cmd+D still
  /// pins the tab.
  func testTheBookmarkDialogThroughShiftCmdB() async throws {
    let page = "index.html?dialog"
    let (browser, tab) = try await start(other: otherBookmarks(), page: page)
    defer { tab.close() }
    func pageBookmarks(_ other: [BookmarkNode]) -> [BookmarkNode] {
      other.all.filter { $0.url?.hasSuffix("?dialog") == true }
    }
    XCTAssertEqual(try browser.bookmarkPageItemTitle(), "Bookmark This Page…")

    // Added, with the page's title selected: typing replaces it, and Esc
    // keeps it.
    try await browser.pressBookmarkThisPage()
    XCTAssertEqual(browser.dialogTitle, "Bookmark Added")
    let name = browser.dialogElement("clair.bookmarkName")
    XCTAssertEqual(name.value as? String, "Clair runtime test page")
    browser.ui.typeText("Renamed Page")
    browser.ui.typeKey(.escape, modifierFlags: [])
    var closed = await browser.waitForDialog(false)
    try require(closed, "Esc didn't close the bookmark dialog")
    let renamed = await browser.waitForSavedBookmarks { _, other in
      pageBookmarks(other).map(\.title) == ["Renamed Page"]
    }
    XCTAssertTrue(renamed, "Esc didn't save the name: \(browser.savedDescription)")
    XCTAssertEqual(try browser.bookmarkPageItemTitle(), "Edit Bookmark…")

    // Edit Bookmark: the popup lists Bookmarks and its folder, and no
    // Bookmarks Bar; Reading and Done move it, without adding another.
    try await browser.pressBookmarkThisPage()
    XCTAssertEqual(browser.dialogTitle, "Edit Bookmark")
    let folder = browser.dialogElement("clair.bookmarkFolder")
    try require(folder.waitForExistence(timeout: 5), "The dialog has no Folder popup")
    folder.click()
    let items = folder.menuItems.allElementsBoundByIndex.map(\.title)
    XCTAssertEqual(items.first, "Bookmarks")
    XCTAssertTrue(items.contains("Reading"), "The popup doesn't list Reading: \(items)")
    XCTAssertFalse(
      items.contains { $0.localizedCaseInsensitiveContains("bookmarks bar") }, "The popup lists the Bookmarks Bar")
    folder.menuItems["Reading"].click()
    browser.dialogElement("clair.dialogDefault").click()
    closed = await browser.waitForDialog(false)
    try require(closed, "Done didn't close the bookmark dialog")
    let moved = await browser.waitForSavedBookmarks { _, other in
      other.first { $0.title == "Reading" }?.children.titles == ["Reading Article", "Renamed Page"]
        && pageBookmarks(other).count == 1
    }
    XCTAssertTrue(moved, "Done didn't move the bookmark to Reading: \(browser.savedDescription)")

    // New Folder…: Return creates it, selected, and Return again saves.
    try await browser.pressBookmarkThisPage()
    folder.click()
    folder.menuItems["New Folder…"].click()
    let newFolder = browser.dialogElement("clair.bookmarkNewFolderName")
    try require(newFolder.waitForExistence(timeout: 5), "New Folder… didn't show its field")
    browser.ui.typeText("Recipes\n")
    let selected = await Harness.wait(for: 5) {
      browser.dialogElement("clair.bookmarkFolder").value as? String == "Recipes"
    }
    XCTAssertTrue(selected, "The new folder isn't selected")
    XCTAssertTrue(browser.dialog.exists, "Return in the new folder's field closed the dialog")
    browser.ui.typeKey(.return, modifierFlags: [])
    closed = await browser.waitForDialog(false)
    try require(closed, "Return didn't close the bookmark dialog")
    let filed = await browser.waitForSavedBookmarks { _, other in
      other.first { $0.title == "Recipes" }?.children.titles == ["Renamed Page"]
    }
    XCTAssertTrue(filed, "The bookmark isn't in the new folder: \(browser.savedDescription)")
    XCTAssertTrue(try browser.openBookmarksMenu().contains("Recipes"), "The menu doesn't list the new folder")
    browser.ui.typeKey(.escape, modifierFlags: [])

    // Remove.
    try await browser.pressBookmarkThisPage()
    browser.dialogElement("clair.dialogLeading").click()
    closed = await browser.waitForDialog(false)
    try require(closed, "Remove didn't close the bookmark dialog")
    let removed = await browser.waitForSavedBookmarks { _, other in pageBookmarks(other).isEmpty }
    XCTAssertTrue(removed, "Remove didn't delete the bookmark")
    XCTAssertEqual(try browser.bookmarkPageItemTitle(), "Bookmark This Page…")

    // Cmd+D pins the tab and bookmarks nothing.
    browser.ui.typeKey("d", modifierFlags: .command)
    let pinned = await browser.waitForPins { $0 == ["Clair runtime test page"] }
    XCTAssertTrue(pinned, "Cmd+D didn't pin the tab: \(browser.pinTitles)")
    try await Task.sleep(for: .seconds(3))
    XCTAssertTrue(pageBookmarks(try browser.savedBookmarks().other).isEmpty, "Cmd+D added a bookmark")
    XCTAssertFalse(browser.dialog.exists, "Cmd+D opened a dialog")
  }

  // MARK: Suggestions (task 3.6)

  private func openCommandBar(_ browser: Browser) throws -> XCUIElement {
    browser.ui.typeKey("t", modifierFlags: .command)
    let field = browser.element("clair.commandBarField")
    try require(field.waitForExistence(timeout: 10), "Cmd+T didn't open the command bar")
    return field
  }

  private func suggestions(_ browser: Browser, _ predicate: String) -> [XCUIElement] {
    browser.ui.descendants(matching: .any).matching(
      NSPredicate(format: "identifier == 'clair.suggestion' AND (\(predicate))")
    ).allElementsBoundByIndex
  }

  /// A bookmark never visited is suggested by its title, with the bookmark
  /// icon, and opens; a visited, bookmarked page is listed once with the
  /// bookmark icon; its Switch to Tab row keeps the open tab's icon. A row
  /// with the bookmark icon reads "Bookmark" last.
  func testBookmarkSuggestions() async throws {
    let (browser, tab) = try await start(other: otherBookmarks())
    defer { tab.close() }

    let field = try openCommandBar(browser)
    field.typeText("Clair Reading List")
    let bookmarkRow = "label BEGINSWITH 'Clair Reading List, localhost'"
    let listed = await Harness.wait(for: 15) { !self.suggestions(browser, bookmarkRow).isEmpty }
    try require(listed, "The never-visited bookmark isn't suggested by its title")
    let row = try XCTUnwrap(suggestions(browser, bookmarkRow).first)
    XCTAssertTrue(row.label.hasSuffix(", Bookmark"), "The bookmark's row doesn't show the bookmark icon: \(row.label)")
    row.click()
    let opened = await browser.waitForTarget("?reading-list")
    XCTAssertTrue(opened, "Choosing the bookmark didn't open it")

    // A visited page with a favicon, bookmarked, then left.
    let favicon = try await browser.open(url("favicon.html"))
    defer { favicon.close() }
    let shown = await browser.waitForActiveRow("Clair favicon test page")
    try require(shown, "The favicon page isn't active")
    try await browser.pressBookmarkThisPage()
    browser.ui.typeKey(.escape, modifierFlags: [])
    _ = await browser.waitForDialog(false)
    try await favicon.navigate(to: url("index.html?left"))
    let pageRows = "label BEGINSWITH 'Clair favicon test page'"
    let once = try openCommandBar(browser)
    once.typeText("favicon.html")
    let found = await Harness.wait(for: 15) { !self.suggestions(browser, pageRows).isEmpty }
    try require(found, "The visited, bookmarked page isn't suggested")
    try await Task.sleep(for: .seconds(2))
    let rows = suggestions(browser, pageRows).map(\.label)
    XCTAssertEqual(rows.count, 1, "The page isn't listed once: \(rows)")
    XCTAssertTrue(rows.first?.hasSuffix(", Bookmark") == true, "The bookmarked page's row doesn't show the bookmark icon")
    browser.ui.typeKey(.escape, modifierFlags: [])

    // Open again in a tab that isn't active: its Switch to Tab row keeps the
    // open tab's icon.
    try await favicon.navigate(to: url("favicon.html"))
    let other = try await browser.open(url("index.html?other"))
    defer { other.close() }
    _ = await browser.waitForActiveRow("Clair runtime test page")
    let open = try openCommandBar(browser)
    open.typeText("favicon.html")
    let switchRow = "\(pageRows) AND label CONTAINS 'Switch to Tab'"
    let switchable = await Harness.wait(for: 15) { !self.suggestions(browser, switchRow).isEmpty }
    try require(switchable, "The open page has no Switch to Tab row: \(suggestions(browser, "TRUEPREDICATE").map(\.label))")
    XCTAssertFalse(
      suggestions(browser, switchRow).first?.label.hasSuffix(", Bookmark") == true,
      "The Switch to Tab row shows the bookmark icon")
    browser.ui.typeKey(.escape, modifierFlags: [])
  }
}
