// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import XCTest

extension Browser {
  /// Clair › Import from Another Browser…, then waits for the dialog.
  func openImportDialog() throws {
    ui.activate()
    let clair = ui.menuBars.menuBarItems["Clair"]
    try require(clair.waitForExistence(timeout: 30), "There's no Clair menu")
    clair.click()
    let item = clairMenuItem(titled: "Import from Another Browser…")
    try require(item.waitForExistence(timeout: 10), "The Clair menu has no Import from Another Browser…")
    item.click()
    try require(dialog.waitForExistence(timeout: 15), "Import from Another Browser… opened no dialog")
  }

  func importElement(_ identifier: String) -> XCUIElement {
    dialog.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  func waitForDialogTitle(_ title: String, seconds: TimeInterval = 15) async -> Bool {
    await Harness.wait(for: seconds) { self.dialogTitle == title }
  }

  /// Selects a browser's card on the first step and continues.
  func chooseImportSource(_ id: String, named name: String) async throws {
    let card = importElement("clair.importSource.\(id)")
    try require(card.waitForExistence(timeout: 10), "The first step has no \(name) card")
    card.click()
    dialogButton("clair.dialogDefault").click()
    let shown = await waitForDialogTitle("Import from \(name)")
    try require(shown, "Continue didn't show \(name)'s step: \(dialogTitle ?? "no title")")
  }

  /// Chooses `title` in a row's "Import into" popup.
  func setImportDestination(row: Int, to title: String) throws {
    let popup = importElement("clair.importDestination.\(row)")
    try require(popup.waitForExistence(timeout: 10), "There's no row \(row)")
    popup.click()
    let item = ui.menuItems.matching(NSPredicate(format: "title == %@", title)).allElementsBoundByIndex
      .first { $0.isHittable }
    try require(item != nil, "Row \(row)'s popup has no \(title)")
    item?.click()
  }

  /// Clicks Import and waits for the summary; returns its counts.
  func runImport(seconds: TimeInterval = 240) async throws -> String {
    let button = dialogButton("clair.dialogDefault")
    try require(button.label == "Import", "The default button reads \(button.label), not Import")
    button.click()
    let done = await waitForDialogTitle("Import Complete", seconds: seconds)
    try require(done, "The import didn't finish: \(dialogTitle ?? "no title")")
    return lines("clair.importCount")
  }

  /// What the summary lists as not imported.
  var importSkipped: String { lines("clair.importSkipped") }

  /// The texts with `identifier` on the dialog, one per line.
  private func lines(_ identifier: String) -> String {
    dialog.descendants(matching: .any).matching(identifier: identifier).allElementsBoundByIndex
      .map { ($0.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? $0.label }.joined(separator: "\n")
  }

  /// Done on the summary.
  func finishImport() async throws {
    dialogButton("clair.dialogDefault").click()
    let closed = await waitForDialog(false)
    try require(closed, "Done didn't close the dialog")
  }

  /// Local State's profiles, by directory.
  func profileNames() throws -> [String: String] {
    let localState = dataDirectory.appending(path: "Local State")
    let state = try JSONSerialization.jsonObject(with: Data(contentsOf: localState)) as? [String: Any]
    let cache = (state?["profile"] as? [String: Any])?["info_cache"] as? [String: [String: Any]] ?? [:]
    return cache.compactMapValues { $0["name"] as? String }
  }

  /// A profile's Other Bookmarks and Bookmarks Bar, from its file.
  func bookmarks(ofProfile directory: String) throws -> (bar: [String], other: [String]) {
    let file = dataDirectory.appending(path: "\(directory)/Bookmarks")
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
    let roots = json?["roots"] as? [String: Any] ?? [:]
    func titles(_ root: String) -> [String] {
      ((roots[root] as? [String: Any])?["children"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "" }
    }
    return (titles("bookmark_bar"), titles("other"))
  }

  /// How many times the suite's server has served a path containing `text`.
  func hits(_ text: String, baseURL: String) async throws -> Int {
    let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    let (data, _) = try await URLSession.shared.data(from: URL(string: "\(baseURL)/hits?\(query)")!)
    return Int(String(decoding: data, as: UTF8.self)) ?? -1
  }
}

/// The per-user temporary directory, where Clair keeps an import's private
/// folder.
private var userTemporaryDirectory: URL {
  var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
  let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
  guard length > 0 else { return FileManager.default.temporaryDirectory }
  let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
  return URL(fileURLWithPath: path, isDirectory: true)
}

/// Importing from another browser (add-browser-import tasks 5.1 to 5.3):
/// fixtures of Arc, Dia, Chrome and Safari data in a fake home that
/// `CLAIR_TEST_IMPORT_ROOT` points Clair at, imported through the dialog, then
/// checked in Local State, the Bookmarks files and menu, the command bar's
/// suggestions, the open tabs and the suite's server log.
@MainActor
final class ImportTests: NativeWindowTestCase {
  var home: ImportHome!

  override func setUp() async throws {
    // Each import reads, writes and installs, some twice.
    executionTimeAllowance = 600
    try await super.setUp()
    home = try ImportHome(baseURL: fixture.baseURL)
  }

  override func tearDown() async throws {
    home?.remove()
    try await super.tearDown()
  }

  private func start() async throws -> Browser {
    let browser = try await startBrowser(environment: home.environment)
    browser.ui.activate()
    try require(browser.nativeWindow.waitForExistence(timeout: 30), "Clair shows no native window")
    return browser
  }

  private func leftoverFolders() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: userTemporaryDirectory.path)) ?? [])
      .filter { $0.hasPrefix("clair-import-") }
  }

  /// Arc's card and the Clair menu's items (task 5.1).
  func testTheMenuOffersClairsImportOnly() async throws {
    try home.addArc()
    let browser = try await start()
    browser.ui.menuBars.menuBarItems["Clair"].click()
    XCTAssertTrue(browser.clairMenuItem(titled: "Import from Another Browser…").waitForExistence(timeout: 10))
    XCTAssertFalse(
      browser.ui.menuBars.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", "Import Bookmarks")).firstMatch
        .exists, "Chromium's Import Bookmarks and Settings… is still in the Clair menu")
    browser.ui.typeKey(.escape, modifierFlags: [])

    try browser.openImportDialog()
    XCTAssertEqual(browser.dialogTitle, "Import from your old browser")
    XCTAssertTrue(browser.importElement("clair.importSource.safari").exists)
    XCTAssertTrue(browser.importElement("clair.importSource.arc").exists)
    XCTAssertFalse(browser.importElement("clair.importSource.dia").exists, "Dia shows without its data")
    // Choosing the item again keeps one dialog.
    try browser.openImportDialog()
    XCTAssertEqual(browser.ui.descendants(matching: .any).matching(identifier: "clair.dialog").count, 1)
    browser.ui.typeKey(.escape, modifierFlags: [])
    let closed = await browser.waitForDialog(false)
    XCTAssertTrue(closed, "Esc didn't close the dialog")
  }

  /// Arc into the shown profile and a new one, then again into the same ones
  /// (task 5.2).
  func testArcImportAndImportingAgain() async throws {
    try home.addArc()
    let browser = try await start()
    try browser.openImportDialog()
    try await browser.chooseImportSource("arc", named: "Arc")
    XCTAssertTrue(browser.importElement("clair.importItem.spaces").exists)
    let counts = try await browser.runImport()
    for count in ["3 Spaces", "3 favorites", "3 pinned tabs", "8 Today tabs", "2 bookmarks", "1 history entry"] {
      XCTAssertTrue(counts.contains(count), "The summary doesn't say \(count): \(counts)")
    }
    XCTAssertTrue(browser.importSkipped.contains("Trip Board"), "The Easel isn't listed as skipped")
    try await browser.finishImport()
    XCTAssertEqual(leftoverFolders(), [], "The import left its private folder")

    // The Today tabs exist, and none loaded its page.
    let targets = try await browser.pageTargets().map(\.url)
    for page in ["wiki/Africa", "wiki/Asia", "wiki/Dog", "news.ycombinator.com", "weather.com"] {
      XCTAssertTrue(targets.contains { $0.contains(page) }, "There's no Today tab of \(page): \(targets)")
    }

    // The history page is suggested in the new profile's Space.
    // Again into the same profiles: nothing new.
    try browser.openImportDialog()
    try await browser.chooseImportSource("arc", named: "Arc")
    try browser.setImportDestination(row: 1, to: "Work")
    let again = try await browser.runImport()
    for count in ["0 Spaces", "0 favorites", "0 pinned tabs", "0 Today tabs", "0 bookmarks", "0 history entries"] {
      XCTAssertTrue(again.contains(count), "The second import says \(again), not \(count)")
    }
    XCTAssertTrue(again.contains("Already in Clair"), "The second import doesn't say what was already in Clair: \(again)")
    try await browser.finishImport()

    try await browser.quit()
    let profiles = try browser.profileNames()
    XCTAssertEqual(profiles.values.filter { $0.hasPrefix("Work") }, ["Work"], "Profiles: \(profiles)")
    let work = try XCTUnwrap(profiles.first { $0.value == "Work" }?.key)
    let spaces = try browser.spaceRecords().values
    XCTAssertEqual(spaces.filter { $0["name"] as? String == "Space 1" }.count, 1)
    XCTAssertEqual(spaces.first { $0["name"] as? String == "Space 2" }?["icon"] as? String, "😀")
    XCTAssertEqual(spaces.filter { $0["name"] as? String == "Space 3" }.count, 1)

    let pins = try browser.pinRecords().values
    let folders = pins.filter { $0["kind"] as? String == "folder" }.compactMap { $0["name"] as? String }.sorted()
    XCTAssertEqual(folders, ["Parent Folder", "Parent Folder / Child Folder"])
    XCTAssertTrue(pins.contains { $0["name"] as? String == "RENAMED TAB" }, "The renamed pin lost its name")
    XCTAssertEqual(pins.filter { $0["kind"] as? String == "split" }.count, 1, "The pinned split isn't one split")
    let favorites = pins.filter { $0["profile"] != nil }.compactMap { $0["url"] as? String }.sorted()
    XCTAssertEqual(favorites, ["https://example.com/", "https://www.wikipedia.org/", "https://www.wiktionary.org/"])
    let closed = (try browser.clairState()["closed_folders"] as? [String]) ?? []
    XCTAssertEqual(closed.count, 2, "The imported folders aren't closed")

    let bookmarks = try browser.bookmarks(ofProfile: work)
    XCTAssertEqual(bookmarks.other, ["Google", "Docs"], "Work's bookmarks aren't as Arc had them")
    XCTAssertEqual(bookmarks.bar, [])
  }

  /// Dia, read with the test secret in place of the keychain (task 5.2).
  func testDiaImport() async throws {
    try home.addDia()
    let browser = try await start()
    try browser.openImportDialog()
    try await browser.chooseImportSource("dia", named: "Dia")
    XCTAssertTrue(browser.importElement("clair.importPrivacyNote").exists, "Dia's step has no privacy note")
    let row = browser.importElement("clair.importRow.0")
    XCTAssertTrue(row.label.contains("Profile 2, Profile 3") || row.staticTexts["Profile 2, Profile 3"].exists)
    try browser.setImportDestination(row: 0, to: "New Profile")
    let counts = try await browser.runImport()
    for count in ["2 Spaces", "1 favorite", "1 pinned tab", "4 Today tabs"] {
      XCTAssertTrue(counts.contains(count), "The summary doesn't say \(count): \(counts)")
    }
    try await browser.finishImport()
    // The new profile's window had no tab: the first Today tab, a split,
    // became its selected tab and loads, as session restore loads each
    // window's selected tab. Nothing else does.
    for page in ["dia-today", "dia-second", "dia-pinned", "dia-favorite"] {
      let loaded = try await browser.hits(page, baseURL: fixture.baseURL)
      XCTAssertEqual(loaded, 0, "\(page) loaded its page")
    }

    try await browser.quit()
    let profiles = try browser.profileNames()
    XCTAssertTrue(profiles.values.contains("Profile 2"), "No profile named after Dia's first: \(profiles)")
    let spaces = try browser.spaceRecords().values.compactMap { $0["name"] as? String }
    XCTAssertTrue(spaces.contains("Profile 2") && spaces.contains("Profile 3"), "Spaces: \(spaces)")
    let pins = try browser.pinRecords().values
    XCTAssertTrue(pins.contains { $0["kind"] as? String == "folder" && $0["name"] as? String == "Outer / Inner" })
    XCTAssertTrue(pins.contains { $0["name"] as? String == "Dia Renamed" })
    XCTAssertEqual(leftoverFolders(), [])
  }

  /// Safari's export, chosen through the file panel (task 5.2).
  func testSafariImport() async throws {
    let zip = try home.safariExport()
    let browser = try await start()
    try browser.openImportDialog()
    try await browser.chooseImportSource("safari", named: "Safari")
    let choose = browser.dialogButton("clair.dialogDefault")
    XCTAssertEqual(choose.label, "Choose File…")
    choose.click()
    let panel = browser.ui.sheets.firstMatch
    try require(panel.waitForExistence(timeout: 10), "Choose File… opened no panel")
    browser.ui.typeKey("g", modifierFlags: [.command, .shift])
    browser.ui.typeText(zip.path + "\n")
    try await Task.sleep(for: .seconds(1))
    browser.ui.typeKey(.return, modifierFlags: [])
    let accepted = await Harness.wait(for: 10) { browser.dialogButton("clair.dialogDefault").label == "Import" }
    try require(accepted, "The export wasn't accepted")
    XCTAssertTrue(browser.importElement("clair.importItem.bookmarks").exists)
    XCTAssertFalse(browser.importElement("clair.importItem.spaces").exists)
    let counts = try await browser.runImport()
    XCTAssertTrue(counts.contains("3 bookmarks"), "Summary: \(counts)")
    XCTAssertTrue(counts.contains("1 history entry"), "Summary: \(counts)")
    try await browser.finishImport()

    // No Heads Up: nothing landed in the Bookmarks Bar.
    try await Task.sleep(for: .seconds(2))
    XCTAssertFalse(browser.dialog.exists, "A dialog showed after the import: \(browser.dialogTitle ?? "")")
    let menu = try browser.openBookmarksMenu()
    browser.ui.typeKey(.escape, modifierFlags: [])
    for title in ["Safari Favorite Page", "Safari News", "Safari Loose Page"] {
      XCTAssertTrue(menu.contains(title), "The Bookmarks menu has no \(title): \(menu)")
    }
    XCTAssertFalse(menu.contains("Safari Read Later"), "The Reading List came over")
    let favoriteIndex = menu.firstIndex(of: "Safari Favorite Page") ?? 0
    let looseIndex = menu.firstIndex(of: "Safari Loose Page") ?? 0
    XCTAssertLessThan(favoriteIndex, looseIndex, "The Favorites bar's contents don't come first")

    // The history page is suggested by its title.
    browser.ui.typeKey("t", modifierFlags: .command)
    let field = browser.element("clair.commandBarField")
    try require(field.waitForExistence(timeout: 10), "Cmd+T didn't open the command bar")
    field.typeText("Clair Safari History")
    let suggested = await Harness.wait(for: 15) {
      !browser.ui.descendants(matching: .any).matching(
        NSPredicate(format: "identifier == 'clair.suggestion' AND label BEGINSWITH 'Clair Safari History Page'")
      ).allElementsBoundByIndex.isEmpty
    }
    XCTAssertTrue(suggested, "The imported history page isn't suggested")
    browser.ui.typeKey(.escape, modifierFlags: [])

    try await browser.quit()
    let pins = try browser.pinRecords().values
    XCTAssertFalse(pins.contains { $0["profile"] != nil }, "Safari's Favorites became Clair favorites")
  }

  /// Chrome's last session (task 5.2, design D13).
  func testChromeImport() async throws {
    try home.addChrome()
    let browser = try await start()
    try browser.openImportDialog()
    try await browser.chooseImportSource("chrome", named: "Chrome")
    XCTAssertFalse(browser.importElement("clair.importItem.favorites").exists)
    try browser.setImportDestination(row: 0, to: "New Profile")
    let counts = try await browser.runImport()
    for count in ["1 Space", "1 pinned tab", "7 Today tabs", "3 bookmarks", "1 history entry"] {
      XCTAssertTrue(counts.contains(count), "The summary doesn't say \(count): \(counts)")
    }
    try await browser.finishImport()
    // Only the new profile's window's selected tab, the first, loads.
    for page in ["chrome-pinned", "chrome-b", "chrome-docs", "chrome-mail", "chrome-d", "chrome-e", "chrome-c"] {
      let loaded = try await browser.hits(page, baseURL: fixture.baseURL)
      XCTAssertEqual(loaded, 0, "\(page) loaded its page")
    }
    let targets = try await browser.pageTargets().map(\.url)
    for page in ["chrome-a", "chrome-b", "chrome-docs", "chrome-mail", "chrome-d", "chrome-e", "chrome-c"] {
      XCTAssertTrue(targets.contains { $0.contains(page) }, "There's no Today tab of \(page)")
    }

    try await browser.quit()
    let profiles = try browser.profileNames()
    let person = try XCTUnwrap(profiles.first { $0.value == "Person 1" }?.key, "Profiles: \(profiles)")
    let spaces = try browser.spaceRecords().values.compactMap { $0["name"] as? String }
    XCTAssertTrue(spaces.contains("Person 1"), "Spaces: \(spaces)")
    let pins = try browser.pinRecords().values
    XCTAssertTrue(pins.contains { ($0["url"] as? String)?.contains("chrome-pinned") == true && $0["space"] != nil })
    XCTAssertFalse(pins.contains { $0["profile"] != nil }, "Chrome's bookmarks bar became favorites")
    let bookmarks = try browser.bookmarks(ofProfile: person)
    XCTAssertEqual(bookmarks.other, ["Chrome Bar Page", "Chrome News", "Chrome Other Page"])
  }

  /// A Web Store extension, turned on and pinned in the source, installs
  /// without a prompt, turned on and pinned (task 5.3).
  func testAStoreExtensionInstallsWithoutAPrompt() async throws {
    // Dark Reader, with the manifest an installed copy keeps: its store
    // public key, and the permissions of its 4.9 releases, with a few more so
    // the store's version asks for no more and the approval holds.
    let darkReader = "eimadpbcbfnmbkopoojfekhnkhdbieeh"
    let key =
      "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqBY2tfTtJYiVMirbII2r3WofqCDaxS2zwPddSsgxUWKRm/MW/ymL2ZaP24MmwnegGIoxHkBVyi4cps4/q76c98ViyijoQvdJjAv3ZtUOwbWlYnZ5pU6gPCeZrScHxoTJdxxJJ30DZpMc6qsc3yJVQJlABG2FQFPrhPEGFLP9sCq/M7pY1xH++KsG+jYLB6cU3ItvZ4zntUXRwG2ZBx+XZelsd6FdkVXbDXj/47TNk2Qq8PAqyiK45GgQ+KJjuISAo89ip1xI4tONLCjSHPinD3nz6HiMikQzwn4L8SsB4Wy7rBhMhPRGIWbwHed+L+W3LXhB05Lhwk0YxuOb7QNWRQIDAQAB"
    try home.addChrome(
      extensions: [
        darkReader: [
          "location": 1, "from_webstore": true, "disable_reasons": [Int](),
          "manifest": [
            "key": key, "name": "Dark Reader", "version": "4.9.135", "manifest_version": 3,
            "background": ["service_worker": "background/index.js"],
            "permissions": ["alarms", "contextMenus", "fontSettings", "scripting", "storage", "tabs"],
            "host_permissions": ["<all_urls>"],
            "optional_permissions": ["contextMenus"],
            "content_scripts": [["matches": ["<all_urls>"], "js": ["inject/index.js"], "all_frames": true]],
          ],
        ]
      ], pinnedExtensions: [darkReader])
    let browser = try await start()
    try browser.openImportDialog()
    try await browser.chooseImportSource("chrome", named: "Chrome")
    let counts = try await browser.runImport(seconds: 300)
    XCTAssertTrue(counts.contains("1 extension"), "Summary: \(counts); skipped: \(browser.importSkipped)")
    XCTAssertFalse(browser.dialogButton("clair.dialogCancel").exists, "A prompt showed")
    try await browser.finishImport()

    let toolbar = browser.element("clair.extensionAction.\(darkReader)")
    let pinned = toolbar.waitForExistence(timeout: 15)
    try await browser.quit()
    let preferences = browser.dataDirectory.appending(path: "Default/Preferences")
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: preferences)) as? [String: Any]
    let extensions = json?["extensions"] as? [String: Any]
    XCTAssertTrue(
      pinned || (extensions?["pinned_extensions"] as? [String] ?? []).contains(darkReader),
      "Dark Reader isn't pinned")
    let secure = try JSONSerialization.jsonObject(
      with: Data(contentsOf: browser.dataDirectory.appending(path: "Default/Secure Preferences"))) as? [String: Any]
    let settings = ((secure?["extensions"] as? [String: Any])?["settings"] as? [String: Any])?[darkReader] as? [String: Any]
    XCTAssertNotNil(settings, "Dark Reader isn't installed")
    XCTAssertEqual((settings?["disable_reasons"] as? [Int]) ?? [], [], "Dark Reader isn't turned on")
  }
}
