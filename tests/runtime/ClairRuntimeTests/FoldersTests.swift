// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import XCTest

extension Browser {
  /// The folder rows' names, from one snapshot of the window.
  var folderNames: [String] { titles(of: "clair.folderRow") }

  func folderRow(_ name: String) -> XCUIElement {
    nativeWindow.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == 'clair.folderRow' AND label == %@", name)).firstMatch
  }

  /// The pinned section as the sidebar lists it, from one snapshot: a
  /// folder as "[name]", a tab listed under a folder indented by two spaces.
  var pinnedSection: [String] {
    guard let window = try? nativeWindow.snapshot() else { return [] }
    var rows: [(String, CGFloat)] = []
    var folderX: CGFloat?
    func collect(_ element: any XCUIElementSnapshot) {
      switch element.identifier {
      case "clair.folderRow":
        folderX = folderX ?? element.frame.minX
        rows.append(("[\(element.label)]", element.frame.minX))
      case "clair.pinRow":
        rows.append((element.label, element.frame.minX))
      default:
        element.children.forEach(collect)
      }
    }
    collect(window)
    let leading = rows.map(\.1).min() ?? 0
    return rows.map { title, x in x > leading + 8 ? "  \(title)" : title }
  }

  func waitForPinnedSection(_ seconds: TimeInterval = 15, _ condition: @escaping ([String]) -> Bool) async -> Bool {
    await Harness.wait(for: seconds) { condition(self.pinnedSection) }
  }

  /// Whether a folder's icon says it's open.
  func isFolderOpen(_ name: String) -> Bool {
    folderRow(name).descendants(matching: .any).matching(identifier: "clair.folderIcon").firstMatch.label == "Open"
  }

  /// Drags a row onto the middle of another, as onto a folder's row
  /// (add-tab-folders D5), or onto its top edge, the gap above it: slowly,
  /// and held over the target, so the list and the row's drop view see the
  /// drag arrive.
  func drag(_ row: XCUIElement, onto target: XCUIElement, topEdge: Bool = false) {
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(
        forDuration: 0.5,
        thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: topEdge ? 0.08 : 0.5)),
        withVelocity: .slow, thenHoldForDuration: 0.6)
  }

  /// Local State's "clair" dictionary, read while Clair isn't running.
  func clairState() throws -> [String: Any] {
    let localState = dataDirectory.appending(path: "Local State")
    let state = try JSONSerialization.jsonObject(with: Data(contentsOf: localState)) as? [String: Any]
    return state?["clair"] as? [String: Any] ?? [:]
  }

  /// Changes Local State's "clair" dictionary while Clair isn't running.
  func editClairState(_ change: (inout [String: Any]) -> Void) throws {
    let localState = dataDirectory.appending(path: "Local State")
    var state = try JSONSerialization.jsonObject(with: Data(contentsOf: localState)) as? [String: Any] ?? [:]
    var clair = state["clair"] as? [String: Any] ?? [:]
    change(&clair)
    state["clair"] = clair
    try JSONSerialization.data(withJSONObject: state).write(to: localState)
  }

  /// clair.pins' records, by ID.
  func pinRecords() throws -> [String: [String: Any]] {
    (try clairState()["pins"] as? [String: Any])?["items"] as? [String: [String: Any]] ?? [:]
  }

  /// clair.spaces' records, by ID.
  func spaceRecords() throws -> [String: [String: Any]] {
    (try clairState()["spaces"] as? [String: Any])?["spaces"] as? [String: [String: Any]] ?? [:]
  }

  /// Quits, writing Local State, and runs `body` before starting again.
  func relaunch(between body: () throws -> Void = {}) async throws {
    try await Task.sleep(for: .seconds(3))
    try await quit()
    try body()
    try await start()
    try require(nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back")
    try await Task.sleep(for: .seconds(2))
  }

  /// Chooses an item of a row's context menu, the one on screen when the
  /// menu bar has one of the same title, as Edit › Delete.
  func chooseOnScreen(_ title: String, inMenuOf row: XCUIElement) throws {
    row.rightClick()
    let found = visibleMenuItem(title)
    try require(found != nil, "The menu has no \(title)")
    found?.click()
  }

  func visibleMenuItem(_ title: String) -> XCUIElement? {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
      if let item = ui.menuItems.matching(identifier: title).allElementsBoundByIndex.first(where: \.isHittable)
        ?? ui.menuItems.matching(NSPredicate(format: "title == %@", title)).allElementsBoundByIndex.first(where: \.isHittable)
      {
        return item
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    return nil
  }

  /// Puts the pinned tabs titled `titles`, in that order, into the folder
  /// named `name`, by editing their records while Clair is quit, then
  /// starts it again. XCUITest's drags don't reach the sidebar on every Mac,
  /// so only `testDraggingIntoAndOutOfFolders` drags.
  func fileIntoFolder(_ titles: [String], folder name: String) async throws {
    var missing: [String] = []
    try await relaunch {
      try editClairState { clair in
        var pins = clair["pins"] as? [String: Any] ?? [:]
        var items = pins["items"] as? [String: [String: Any]] ?? [:]
        guard
          let folder = items.first(where: {
            $0.value["kind"] as? String == "folder" && $0.value["name"] as? String == name
          })
        else {
          missing.append(name)
          return
        }
        for (index, title) in titles.enumerated() {
          guard
            let id = items.first(where: { $0.value["kind"] as? String == "pin" && $0.value["title"] as? String == title })?
              .key
          else {
            missing.append(title)
            continue
          }
          items[id]?["folder"] = folder.key
          items[id]?["space"] = folder.value["space"]
          items[id]?["order"] = "a\(index)"
        }
        pins["items"] = items
        clair["pins"] = pins
      }
    }
    try require(missing.isEmpty, "Local State has no \(missing)")
  }

  /// New Folder in the footer's plus menu, named `name` in its field.
  func newFolderFromPlusMenu(_ name: String) throws {
    let plus = element("clair.footerNew")
    plus.click()
    let item = plus.menuItems["New Folder"]
    try require(item.waitForExistence(timeout: 5), "The plus menu has no New Folder")
    item.click()
    let field = element("clair.renameField")
    try require(field.waitForExistence(timeout: 10), "New Folder showed no name field")
    ui.typeText("\(name)\r")
  }

  /// Tabs › New Folder…, named `name` in its dialog.
  func newFolderFromTabMenu(_ name: String) throws {
    try tabMenuItem("New Folder…").click()
    try require(dialog.waitForExistence(timeout: 10), "Tab › New Folder… opened no dialog")
    let field = element("clair.newFolderField", in: dialog)
    try require(field.waitForExistence(timeout: 5), "The New Folder dialog has no field")
    ui.typeText("\(name)\r")
  }

  /// Selects a Today tab and pins it with Cmd+D.
  func pinWithCmdD(_ title: String) async throws {
    tabRow(title)?.click()
    _ = await waitForActiveRow(title)
    ui.typeKey("d", modifierFlags: .command)
    let pinned = await waitForPins { $0.contains(title) }
    try require(pinned, "Cmd+D didn't pin \(title): \(pinTitles)")
  }
}

/// Folders in the pinned section (add-tab-folders task 3.9), driven through
/// the sidebar, the menu bar and the keyboard, and what the stores save, read
/// from Local State after quitting.
@MainActor
final class FoldersTests: NativeWindowTestCase {
  func counter(_ name: String) -> String { url("counter.html?\(name)") }

  /// Opens counter pages, and waits for their rows.
  func openCounters(_ browser: Browser, _ names: [String]) async throws -> [DevToolsSession] {
    var tabs: [DevToolsSession] = []
    for name in names {
      tabs.append(try await browser.open(counter(name)))
    }
    let listed = await browser.waitForTabs { titles in names.allSatisfy { titles.contains("Counter \($0)") } }
    try require(listed, "The counters didn't open: \(browser.tabTitles)")
    return tabs
  }

  /// Creating through the plus menu and Tab › New Folder…, renaming, a drop
  /// on a folder's row, and closing, across a relaunch (tab-folders spec,
  /// "Creating a folder in place", "New Folder dialog", "Opening and closing
  /// a folder", "Folders after a relaunch").
  func testCreatingNamingAndClosingFoldersAcrossARelaunch() async throws {
    executionTimeAllowance = 300
    try Harness.setRestoreWindows(true)
    let (browser, home) = try await startWithPage("counter.html?home")
    defer { home.close() }
    let tabs = try await openCounters(browser, ["spec", "plan"])
    defer { tabs.forEach { $0.close() } }
    try await browser.pinWithCmdD("Counter spec")
    try await browser.pinWithCmdD("Counter plan")
    try await browser.pinWithCmdD("Counter home")
    let order = ["Counter spec", "Counter plan", "Counter home"]
    _ = await browser.waitForPinnedSection { $0 == order }

    try browser.newFolderFromPlusMenu("Trip")
    let trip = await browser.waitForPinnedSection { $0 == order + ["[Trip]"] }
    try require(trip, "New Folder didn't add Trip last: \(browser.pinnedSection)")
    XCTAssertTrue(browser.isFolderOpen("Trip"), "A new folder isn't open")

    try browser.newFolderFromTabMenu("Inbox")
    let inbox = await browser.waitForPinnedSection { $0 == order + ["[Trip]", "[Inbox]"] }
    try require(inbox, "Tab › New Folder… didn't add Inbox last: \(browser.pinnedSection)")

    try browser.choose("Rename…", inMenuOf: browser.folderRow("Inbox"))
    let field = browser.element("clair.renameField")
    try require(field.waitForExistence(timeout: 5), "Rename… opened no field")
    browser.ui.typeText("Docs\r")
    let renamed = await Harness.wait(for: 15) { browser.folderNames == ["Trip", "Docs"] }
    XCTAssertTrue(renamed, "Rename… didn't rename the folder: \(browser.folderNames)")

    // Docs' tabs, as a later launch reads them from their records.
    try await browser.fileIntoFolder(["Counter plan", "Counter spec"], folder: "Docs")
    let filed = await browser.waitForPinnedSection(30) {
      $0 == ["Counter home", "[Trip]", "[Docs]", "  Counter plan", "  Counter spec"]
    }
    try require(filed, "Docs doesn't list its tabs: \(browser.pinnedSection)")

    // Closed, Docs lists only its selected tab, and shows "•••".
    browser.pinRow("Counter spec").click()
    _ = await Harness.wait(for: 10) { browser.pinRow("Counter spec").isSelected }
    browser.folderRow("Docs").click()
    let closed = await browser.waitForPinnedSection { $0.suffix(2) == ["[Docs]", "  Counter spec"] }
    XCTAssertTrue(closed, "The closed folder doesn't list just its selected tab: \(browser.pinnedSection)")
    XCTAssertFalse(browser.isFolderOpen("Docs"), "The folder's row says it's open")

    try await browser.relaunch()
    let back = await browser.waitForPinnedSection(30) { $0.prefix(3) == ["Counter home", "[Trip]", "[Docs]"] }
    XCTAssertTrue(back, "The folders didn't come back in place: \(browser.pinnedSection)")
    XCTAssertFalse(browser.isFolderOpen("Docs"), "Docs came back open")
    XCTAssertTrue(browser.isFolderOpen("Trip"), "Trip came back closed")
    browser.folderRow("Docs").click()
    let both = await browser.waitForPinnedSection {
      $0 == ["Counter home", "[Trip]", "[Docs]", "  Counter plan", "  Counter spec"]
    }
    XCTAssertTrue(both, "Docs' tabs didn't come back in order: \(browser.pinnedSection)")

    try await browser.relaunch()
    let records = try browser.pinRecords()
    let folders = records.filter { $0.value["kind"] as? String == "folder" }
    XCTAssertEqual(Set(folders.values.compactMap { $0["name"] as? String }), ["Trip", "Docs"])
    let closedIDs = try browser.clairState()["closed_folders"] as? [String] ?? []
    XCTAssertTrue(closedIDs.isEmpty, "Docs, opened again, is still in clair.closed_folders: \(closedIDs)")
  }

  /// The tab commands skip a closed folder's tabs and count an open one's
  /// (spaces spec, "Tab commands and folders").
  func testTabCommandsOverClosedAndOpenFolders() async throws {
    try Harness.setRestoreWindows(true)
    let (browser, p) = try await startWithPage("counter.html?p")
    defer { p.close() }
    let tabs = try await openCounters(browser, ["s", "x"])
    defer { tabs.forEach { $0.close() } }
    try await browser.pinWithCmdD("Counter p")
    try await browser.pinWithCmdD("Counter s")
    try browser.newFolderFromPlusMenu("Docs")
    _ = await browser.waitForPinnedSection { $0 == ["Counter p", "Counter s", "[Docs]"] }
    try await browser.fileIntoFolder(["Counter s"], folder: "Docs")
    let filed = await browser.waitForPinnedSection(30) { $0 == ["Counter p", "[Docs]", "  Counter s"] }
    try require(filed, "S isn't in Docs: \(browser.pinnedSection)")
    let x = await browser.waitForTabs(30) { $0.contains("Counter x") }
    try require(x, "X didn't come back: \(browser.tabTitles)")
    browser.folderRow("Docs").click()
    _ = await browser.waitForPinnedSection { $0 == ["Counter p", "[Docs]"] }

    // Closed: from P, the next row is X.
    browser.pinRow("Counter p").click()
    _ = await Harness.wait(for: 10) { browser.pinRow("Counter p").isSelected }
    browser.ui.typeKey(.downArrow, modifierFlags: [.command, .option])
    let next = await browser.waitForActiveRow("Counter x")
    XCTAssertTrue(next, "Opt+Cmd+Down didn't skip the closed folder's tab")
    XCTAssertEqual(browser.pinnedSection, ["Counter p", "[Docs]"], "S showed while its folder is closed")
    // Cmd+2 counts X second.
    browser.ui.typeKey("1", modifierFlags: .command)
    browser.ui.typeKey("2", modifierFlags: .command)
    let second = await browser.waitForActiveRow("Counter x")
    XCTAssertTrue(second, "Cmd+2 counted the closed folder's tab")

    // Open: Cmd+2 is S.
    browser.folderRow("Docs").click()
    _ = await browser.waitForPinnedSection { $0 == ["Counter p", "[Docs]", "  Counter s"] }
    browser.ui.typeKey("2", modifierFlags: .command)
    let s = await Harness.wait(for: 15) { browser.pinRow("Counter s").isSelected }
    XCTAssertTrue(s, "Cmd+2 didn't count the open folder's tab")

    // S, alone in Docs, doesn't move with Ctrl+Shift+PageUp.
    browser.ui.typeKey(.pageUp, modifierFlags: [.control, .shift])
    try await Task.sleep(for: .seconds(1))
    XCTAssertEqual(browser.pinnedSection, ["Counter p", "[Docs]", "  Counter s"], "S left its folder")

    // Closing S, with Docs closed, passes over nothing hidden: P shows.
    browser.folderRow("Docs").click()
    _ = await browser.waitForPinnedSection { $0 == ["Counter p", "[Docs]", "  Counter s"] }
    browser.ui.typeKey("w", modifierFlags: .command)
    let gone = await browser.waitForTarget("?s", open: false)
    XCTAssertTrue(gone, "Cmd+W didn't close S's page")
    let shown = await Harness.wait(for: 15) {
      browser.pinRow("Counter p").isSelected || browser.activeRow == "Counter x"
    }
    XCTAssertTrue(shown, "Closing S showed no next row")
  }

  /// Close This Folder, Duplicate, Delete with its confirmation and Restore
  /// Last Closed Tab, Move to Space and Turn into Space (tab-folders spec).
  func testFolderMenuAndCloseThisFolder() async throws {
    // A relaunch and two Spaces' worth of menus.
    executionTimeAllowance = 300
    try Harness.setRestoreWindows(true)
    let (browser, home) = try await startWithPage("counter.html?home")
    defer { home.close() }
    let tabs = try await openCounters(browser, ["spec", "plan"])
    defer { tabs.forEach { $0.close() } }
    try await browser.pinWithCmdD("Counter spec")
    try await browser.pinWithCmdD("Counter plan")
    try browser.newFolderFromPlusMenu("Docs")
    _ = await browser.waitForPinnedSection { $0.last == "[Docs]" }
    try await browser.fileIntoFolder(["Counter plan", "Counter spec"], folder: "Docs")
    let filled = await browser.waitForPinnedSection(30) { $0 == ["[Docs]", "  Counter plan", "  Counter spec"] }
    try require(filled, "Docs doesn't list both tabs: \(browser.pinnedSection)")
    // Their pages come back with the session.
    let open = await browser.waitForTarget("?spec", seconds: 30)
    try require(open, "Spec's page didn't come back")

    // Close This Folder closes both pages and keeps the tabs.
    browser.folderRow("Docs").hover()
    let minus = browser.element("clair.folderClose")
    try require(minus.waitForExistence(timeout: 10), "Docs shows no Close This Folder")
    minus.click()
    let spec = await browser.waitForTarget("?spec", open: false)
    let plan = await browser.waitForTarget("?plan", open: false)
    XCTAssertTrue(spec && plan, "Close This Folder didn't close the folder's pages")
    XCTAssertEqual(browser.pinnedSection, ["[Docs]", "  Counter plan", "  Counter spec"])

    // Duplicate adds a copy right after, its tabs not open.
    try browser.choose("Duplicate", inMenuOf: browser.folderRow("Docs"))
    let copied = await Harness.wait(for: 15) { browser.folderNames == ["Docs", "Docs"] }
    XCTAssertTrue(copied, "Duplicate didn't add a copy: \(browser.pinnedSection)")

    // Delete asks first, then removes the folder and its tabs; Restore Last
    // Closed Tab brings it back in place, with its page.
    browser.pinRow("Counter spec").click()
    let reopenedSpec = await browser.waitForTarget("?spec")
    try require(reopenedSpec, "Selecting Spec didn't open its page")
    try browser.chooseOnScreen("Delete", inMenuOf: browser.folderRow("Docs"))
    try require(browser.dialog.waitForExistence(timeout: 10), "Deleting a folder with tabs didn't ask")
    browser.dialogButton("clair.dialogDefault").click()
    let deleted = await Harness.wait(for: 15) { browser.folderNames == ["Docs"] }
    XCTAssertTrue(deleted, "Delete Folder didn't remove the folder: \(browser.pinnedSection)")
    let closed = await browser.waitForTarget("?spec", open: false)
    XCTAssertTrue(closed, "Deleting the folder didn't close its tab's page")
    browser.ui.typeKey("t", modifierFlags: [.command, .shift])
    let restored = await Harness.wait(for: 15) { browser.folderNames == ["Docs", "Docs"] }
    XCTAssertTrue(restored, "Restore Last Closed Tab didn't bring the folder back: \(browser.pinnedSection)")
    let reopened = await browser.waitForTarget("?spec")
    XCTAssertTrue(reopened, "Restore Last Closed Tab didn't reopen the folder's page")

    // An empty folder goes at once.
    try browser.newFolderFromPlusMenu("Ideas")
    _ = await Harness.wait(for: 10) { browser.folderNames.contains("Ideas") }
    try browser.chooseOnScreen("Delete", inMenuOf: browser.folderRow("Ideas"))
    let ideasGone = await Harness.wait(for: 10) { !browser.folderNames.contains("Ideas") }
    XCTAssertTrue(ideasGone, "Deleting an empty folder didn't happen at once")
    XCTAssertFalse(browser.dialog.exists, "Deleting an empty folder asked")

    // Move to Space › Work, then Turn into Space there.
    try await browser.createSpace("Work")
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    browser.folderRow("Docs").rightClick()
    let move = browser.ui.menuItems["Move to Space"]
    try require(move.waitForExistence(timeout: 5), "The folder's menu has no Move to Space with two Spaces")
    move.click()
    try require(browser.visibleMenuItem("Work") != nil, "Move to Space has no Work")
    browser.visibleMenuItem("Work")?.click()
    let moved = await Harness.wait(for: 15) { browser.folderNames == ["Docs"] }
    XCTAssertTrue(moved, "Move to Space didn't move one Docs out: \(browser.pinnedSection)")
    browser.ui.typeKey("2", modifierFlags: .control)
    _ = await browser.waitForSpace("Work")
    let there = await Harness.wait(for: 15) { browser.folderNames == ["Docs"] }
    XCTAssertTrue(there, "Work doesn't list the moved folder: \(browser.pinnedSection)")
    try browser.choose("Turn “Docs” into Space", inMenuOf: browser.folderRow("Docs"))
    let turned = await browser.waitForSpace("Docs")
    XCTAssertTrue(turned, "Turn into Space didn't show the new Space")
    let pins = await browser.waitForPinnedSection { $0 == ["Counter plan", "Counter spec"] }
    XCTAssertTrue(pins, "The new Space's pinned tabs aren't the folder's: \(browser.pinnedSection)")
    browser.ui.typeKey("2", modifierFlags: .control)
    _ = await browser.waitForSpace("Work")
    XCTAssertTrue(browser.folderNames.isEmpty, "The folder stayed in Work")
  }

  /// Deleting a Space whose only item is an empty folder asks, and removes
  /// the folder (spaces spec, "Deleting a Space").
  func testDeletingASpaceRemovesItsFolders() async throws {
    let (browser, home) = try await startWithPage("counter.html?home")
    defer { home.close() }
    try await browser.createSpace("Work")
    browser.element("clair.spaceHeader").rightClick()
    let newFolder = browser.ui.menuItems["New Folder"]
    try require(newFolder.waitForExistence(timeout: 5), "The header's menu has no New Folder")
    newFolder.click()
    try require(browser.element("clair.renameField").waitForExistence(timeout: 10), "New Folder showed no field")
    browser.ui.typeText("Ideas\r")
    _ = await Harness.wait(for: 10) { browser.folderNames == ["Ideas"] }
    browser.element("clair.spaceHeader").rightClick()
    browser.ui.menuItems["Delete Space"].click()
    try require(browser.dialog.waitForExistence(timeout: 10), "Deleting a Space with a folder didn't ask")
    browser.dialogButton("clair.dialogDefault").click()
    _ = await browser.waitForSpace("Home")
    try await browser.relaunch()
    let records = try browser.pinRecords()
    XCTAssertFalse(
      records.values.contains { $0["name"] as? String == "Ideas" }, "The deleted Space's folder is still saved")
  }

  /// The stores' records (add-tab-folders D1): sort keys keep twenty pins
  /// placed one after another into the same gap, and twenty at each end, in
  /// order across a relaunch; a move rewrites one record; a folder moving to
  /// another Space rewrites its pins' Space too; and a pinned tab whose
  /// folder is gone lists at its Space's top level. Ctrl+Shift+PageUp places
  /// each pin, one gap at a time.
  func testRecordsAndSortKeys() async throws {
    // Sixty pins, placed one key at a time, and five relaunches.
    executionTimeAllowance = 900
    try Harness.setRestoreWindows(false)
    let (browser, first) = try await startWithPage("counter.html?first")
    defer { first.close() }
    try await browser.pinWithCmdD("Counter first")
    let lastTab = try await browser.open(counter("last"))
    _ = await browser.waitForTabs { $0.contains("Counter last") }
    try await browser.pinWithCmdD("Counter last")
    lastTab.close()

    /// Pins a new counter last, then moves it up `steps` rows.
    func place(_ name: String, up steps: Int, expected: [String]) async throws {
      let tab = try await browser.open(counter(name))
      defer { tab.close() }
      _ = await browser.waitForTabs { $0.contains("Counter \(name)") }
      try await browser.pinWithCmdD("Counter \(name)")
      for _ in 0..<steps {
        browser.ui.typeKey(.pageUp, modifierFlags: [.control, .shift])
      }
      let placed = await browser.waitForPins { $0 == expected }
      try require(placed, "\(name) isn't in place: \(browser.pinTitles)")
    }

    // Twenty at the top, each above the one before.
    var expected = ["Counter first", "Counter last"]
    for round in 1...20 {
      expected.insert("Counter top\(round)", at: 0)
      try await place("top\(round)", up: expected.count - 1, expected: expected)
    }
    // Twenty into the gap after "first", each above the one before.
    let gap = expected.firstIndex(of: "Counter first")! + 1
    for round in 1...20 {
      expected.insert("Counter gap\(round)", at: gap)
      try await place("gap\(round)", up: expected.count - 1 - gap, expected: expected)
    }
    // Twenty at the end.
    for round in 1...20 {
      expected.append("Counter end\(round)")
      try await place("end\(round)", up: 0, expected: expected)
    }
    try await browser.relaunch()
    let kept = await browser.waitForPins(30) { $0 == expected }
    XCTAssertTrue(kept, "The pins' order didn't survive the relaunch: \(browser.pinTitles)")

    // One pin moved up one row: only its record changes.
    let before = try await recordsAfterRelaunch(browser)
    browser.pinRow("Counter last").click()
    _ = await Harness.wait(for: 10) { browser.pinRow("Counter last").isSelected }
    browser.ui.typeKey(.pageUp, modifierFlags: [.control, .shift])
    let index = expected.firstIndex(of: "Counter last")!
    _ = await browser.waitForPins { $0.firstIndex(of: "Counter last") == index - 1 }
    let after = try await recordsAfterRelaunch(browser)
    XCTAssertEqual(changed(before, after).count, 1, "Moving one pin rewrote \(changed(before, after))")

  }

  /// A folder moving to another Space rewrites its record and its pins'
  /// (add-tab-folders D1), and a pinned tab whose folder's record is gone
  /// lists at its Space's top level.
  func testFolderRecords() async throws {
    executionTimeAllowance = 420
    try Harness.setRestoreWindows(false)
    let (browser, first) = try await startWithPage("counter.html?end1")
    defer { first.close() }
    let second = try await browser.open(counter("end2"))
    defer { second.close() }
    _ = await browser.waitForTabs { $0.contains("Counter end2") }
    try await browser.pinWithCmdD("Counter end1")
    try await browser.pinWithCmdD("Counter end2")

    // A folder of two pins moved to another Space: its record and its pins'.
    try browser.newFolderFromPlusMenu("Trip")
    _ = await Harness.wait(for: 10) { browser.folderNames == ["Trip"] }
    try await browser.fileIntoFolder(["Counter end1", "Counter end2"], folder: "Trip")
    _ = await browser.waitForPinnedSection(30) { $0.suffix(3) == ["[Trip]", "  Counter end1", "  Counter end2"] }
    try await browser.createSpace("Work")
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let beforeMove = try await recordsAfterRelaunch(browser)
    browser.folderRow("Trip").rightClick()
    browser.ui.menuItems["Move to Space"].click()
    try require(browser.visibleMenuItem("Work") != nil, "Move to Space has no Work")
    browser.visibleMenuItem("Work")?.click()
    _ = await Harness.wait(for: 10) { browser.folderNames.isEmpty }
    let afterMove = try await recordsAfterRelaunch(browser)
    let moved = changed(beforeMove, afterMove)
    XCTAssertEqual(moved.count, 3, "Moving a folder of two pins rewrote \(moved.count) records")
    let workID = try XCTUnwrap(try browser.spaceRecords().first { $0.value["name"] as? String == "Work" }?.key)
    XCTAssertTrue(moved.allSatisfy { afterMove[$0]?["space"] as? String == workID }, "The moved records don't name Work")

    // A pinned tab whose folder's record is gone lists at its Space's top
    // level.
    try await browser.relaunch {
      try browser.editClairState { clair in
        var pins = clair["pins"] as? [String: Any] ?? [:]
        var items = pins["items"] as? [String: Any] ?? [:]
        for (id, value) in items where (value as? [String: Any])?["kind"] as? String == "folder" {
          items[id] = nil
        }
        pins["items"] = items
        clair["pins"] = pins
      }
    }
    browser.ui.typeKey("2", modifierFlags: .control)
    _ = await browser.waitForSpace("Work")
    let loose = await browser.waitForPinnedSection { $0 == ["Counter end1", "Counter end2"] }
    XCTAssertTrue(loose, "The folder's tabs aren't at Work's top level: \(browser.pinnedSection)")
  }

  /// Relaunches and returns clair.pins' records as saved.
  func recordsAfterRelaunch(_ browser: Browser) async throws -> [String: [String: Any]] {
    var records: [String: [String: Any]] = [:]
    try await browser.relaunch { records = try browser.pinRecords() }
    return records
  }

  /// The records that differ between two reads.
  func changed(_ before: [String: [String: Any]], _ after: [String: [String: Any]]) -> Set<String> {
    Set(after.keys).union(before.keys).filter {
      !NSDictionary(dictionary: before[$0] ?? [:]).isEqual(to: after[$0] ?? [:])
    }
  }

  /// Dragging into, within and out of folders, and reordering folders and
  /// Spaces (tab-folders spec, "Dragging tabs into a folder", "Dragging tabs
  /// out of a folder", "Reordering folders"; add-tab-folders D12). XCUITest's
  /// drags reach the sidebar on the hosted runners.
  func testDraggingIntoAndOutOfFolders() async throws {
    executionTimeAllowance = 300
    let (browser, home) = try await startWithPage("counter.html?home")
    defer { home.close() }
    let tabs = try await openCounters(browser, ["spec", "plan", "note"])
    defer { tabs.forEach { $0.close() } }
    try await browser.pinWithCmdD("Counter home")
    try browser.newFolderFromPlusMenu("Docs")
    _ = await browser.waitForPinnedSection { $0 == ["Counter home", "[Docs]"] }

    // On the row: the folder's first tab, with its page.
    browser.drag(try XCTUnwrap(browser.tabRow("Counter spec")), onto: browser.folderRow("Docs"))
    let onRow = await browser.waitForPinnedSection { $0 == ["Counter home", "[Docs]", "  Counter spec"] }
    try require(onRow, "A drop on Docs' row didn't pin into it: \(browser.pinnedSection)")
    let kept = try await browser.target(endingWith: "?spec")
    XCTAssertNotNil(kept, "Pinning into the folder closed the page")
    browser.drag(try XCTUnwrap(browser.tabRow("Counter plan")), onto: browser.folderRow("Docs"))
    let firstIn = await browser.waitForPinnedSection {
      $0 == ["Counter home", "[Docs]", "  Counter plan", "  Counter spec"]
    }
    XCTAssertTrue(firstIn, "The second drop isn't Docs' first tab: \(browser.pinnedSection)")

    // A drop on a closed folder's row lands in it too.
    browser.folderRow("Docs").click()
    _ = await browser.waitForPinnedSection { $0 == ["Counter home", "[Docs]"] }
    browser.drag(try XCTUnwrap(browser.tabRow("Counter note")), onto: browser.folderRow("Docs"))
    try await Task.sleep(for: .seconds(1))
    browser.folderRow("Docs").click()
    let closedDrop = await browser.waitForPinnedSection {
      $0 == ["Counter home", "[Docs]", "  Counter note", "  Counter plan", "  Counter spec"]
    }
    XCTAssertTrue(closedDrop, "A drop on the closed folder didn't land in it: \(browser.pinnedSection)")

    // A folder's tab dragged above the folder leaves it.
    browser.drag(browser.pinRow("Counter note"), onto: browser.folderRow("Docs"), topEdge: true)
    let out = await browser.waitForPinnedSection {
      $0 == ["Counter home", "Counter note", "[Docs]", "  Counter plan", "  Counter spec"]
    }
    XCTAssertTrue(out, "Dragging Note above Docs didn't take it out: \(browser.pinnedSection)")

    // Into Today, below the divider, it's unpinned with its page.
    browser.drag(browser.pinRow("Counter spec"), onto: browser.element("clair.newTabRow"))
    let today = await browser.waitForTabs { $0.contains("Counter spec") }
    XCTAssertTrue(today, "Dragging Spec into Today didn't unpin it: \(browser.tabTitles)")

    // The folder reorders above Home, with its tabs, and stays put when
    // dropped below the divider.
    browser.drag(browser.folderRow("Docs"), onto: browser.pinRow("Counter home"), topEdge: true)
    let reordered = await browser.waitForPinnedSection { $0.first == "[Docs]" }
    XCTAssertTrue(reordered, "Docs didn't move above Home: \(browser.pinnedSection)")
    let section = browser.pinnedSection
    browser.drag(browser.folderRow("Docs"), onto: try XCTUnwrap(browser.tabRow("Counter spec")))
    try await Task.sleep(for: .seconds(1))
    XCTAssertEqual(browser.pinnedSection, section, "Docs moved below the divider")

    // Reordering Spaces rewrites only the Space that moved.
    try await browser.createSpace("Work")
    let spacesBefore = try await spaceRecordsAfterRelaunch(browser)
    let items = browser.switcherItems
    try require(items.count == 2, "The switcher doesn't show two Spaces")
    items[1].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(
        forDuration: 0.5, thenDragTo: items[0].coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)),
        withVelocity: .slow, thenHoldForDuration: 0.4)
    _ = await Harness.wait(for: 10) { browser.spacesMenuSpaces.first == "Work" }
    let spacesAfter = try await spaceRecordsAfterRelaunch(browser)
    XCTAssertEqual(browser.spacesMenuSpaces, ["Work", "Home"], "The Spaces' order didn't survive the relaunch")
    let workID = try XCTUnwrap(spacesAfter.first { $0.value["name"] as? String == "Work" }?.key)
    XCTAssertEqual(changed(spacesBefore, spacesAfter), [workID], "Reordering rewrote other Spaces")
  }

  /// Relaunches and returns clair.spaces' records as saved.
  func spaceRecordsAfterRelaunch(_ browser: Browser) async throws -> [String: [String: Any]] {
    var records: [String: [String: Any]] = [:]
    try await browser.relaunch { records = try browser.spaceRecords() }
    return records
  }

  /// Profile IDs (add-tab-folders D13): one per profile in clair.profiles,
  /// kept across launches, saved by the Spaces and favorites in place of
  /// directories, dropped with the profile, and an entry for a missing
  /// directory dropped at the next launch.
  func testProfileIDs() async throws {
    // Six relaunches.
    executionTimeAllowance = 420
    try Harness.setRestoreWindows(false)
    let (browser, home) = try await startWithPage("counter.html?home")
    defer { home.close() }
    try browser.openProfilesPage()
    try await browser.addProfile("Work")
    browser.ui.windows["Profiles"].typeKey("w", modifierFlags: .command)
    browser.nativeWindow.click()
    try await browser.createSpace("Work", profile: "Work")
    let fav = try await browser.open(counter("fav"))
    _ = await browser.waitForTabs { $0.contains("Counter fav") }
    try browser.choose("Pin to Favorites", inMenuOf: try XCTUnwrap(browser.tabRow("Counter fav")))
    _ = await browser.waitForFavorites { $0 == ["Counter fav"] }
    fav.close()

    try await browser.relaunch()
    let profiles = try browser.clairState()["profiles"] as? [String: String] ?? [:]
    XCTAssertEqual(profiles.count, 2, "clair.profiles hasn't one entry per profile: \(profiles)")
    let directories = Set(profiles.values)
    XCTAssertTrue(directories.contains("Default"), "The default profile has no ID: \(profiles)")
    let spaces = try browser.spaceRecords()
    for (_, space) in spaces {
      let profile = space["profile"] as? String ?? ""
      XCTAssertNotNil(profiles[profile], "A Space saves \(profile), not a profile ID")
    }
    let favorites = try browser.pinRecords().values.filter { $0["profile"] != nil }
    XCTAssertEqual(favorites.count, 1)
    XCTAssertNotNil(profiles[favorites.first?["profile"] as? String ?? ""], "The favorite doesn't save a profile ID")
    let workDirectory = try XCTUnwrap(profiles.first { $0.value != "Default" }?.value)
    XCTAssertFalse(
      spaces.values.contains { $0["profile"] as? String == workDirectory }, "clair.spaces names a profile directory")

    // Work still uses its profile, and its favorite comes back there.
    try await browser.relaunch()
    browser.ui.typeKey("2", modifierFlags: .control)
    let work = await browser.waitForSpace("Work")
    try require(work, "Ctrl+2 didn't show Work")
    let favoriteBack = await browser.waitForFavorites { $0 == ["Counter fav"] }
    XCTAssertTrue(favoriteBack, "Work's profile's favorite didn't come back: \(browser.favoriteTitles)")
    try await browser.relaunch()
    let again = try browser.clairState()["profiles"] as? [String: String] ?? [:]
    XCTAssertEqual(again, profiles, "The profile IDs changed across a relaunch")

    // An entry for a directory that doesn't exist is dropped at launch.
    try await browser.relaunch {
      try browser.editClairState { clair in
        var profiles = clair["profiles"] as? [String: String] ?? [:]
        profiles["0f0e0d0c-0b0a-4908-8706-050403020100"] = "Profile 99"
        clair["profiles"] = profiles
      }
    }
    try await browser.relaunch()
    let pruned = try browser.clairState()["profiles"] as? [String: String] ?? [:]
    XCTAssertEqual(pruned, profiles, "The entry for a missing directory stayed: \(pruned)")

    // Removing Work's Space and then its profile drops its entry.
    browser.ui.typeKey("2", modifierFlags: .control)
    _ = await browser.waitForSpace("Work")
    browser.element("clair.spaceHeader").rightClick()
    browser.ui.menuItems["Delete Space"].click()
    if browser.dialog.waitForExistence(timeout: 5) {
      browser.dialogButton("clair.dialogDefault").click()
    }
    _ = await browser.waitForSpace("Home")
    try browser.openProfilesPage()
    browser.profileRow("Work")?.click()
    browser.settingsElement("clair.profilesRemove").click()
    try require(browser.dialog.waitForExistence(timeout: 10), "Remove didn't ask")
    let field = browser.dialogElement("clair.deleteProfileName")
    field.click()
    field.typeText("Work")
    browser.dialogElement("clair.dialogDefault").click()
    _ = await Harness.wait(for: 30) { browser.profileRow("Work") == nil }
    try await browser.relaunch()
    let remaining = try browser.clairState()["profiles"] as? [String: String] ?? [:]
    XCTAssertEqual(Array(remaining.values), ["Default"], "The removed profile's entry stayed: \(remaining)")
  }
}
