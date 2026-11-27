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
  /// (add-tab-folders D5), or onto its top edge, the gap above it, with the
  /// mouse's own events at a hand's speed, as the probe's `drag` does:
  /// XCUITest's synthesized drags never start a drag in the sidebar. Skips
  /// when the runner may not post events.
  func drag(_ row: XCUIElement, onto target: XCUIElement, topEdge: Bool = false) throws {
    try drag(
      from: CGPoint(x: row.frame.midX, y: row.frame.midY),
      to: CGPoint(
        x: target.frame.midX,
        y: topEdge ? target.frame.minY + target.frame.height * 0.08 : target.frame.midY))
  }

  /// Drags between two points on screen with the mouse's own events.
  func drag(from: CGPoint, to: CGPoint) throws {
    guard CGPreflightPostEventAccess() else {
      throw XCTSkip("The test runner may not post mouse events, which drags in the sidebar need")
    }
    func post(_ type: CGEventType, _ point: CGPoint) {
      CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    }
    post(.mouseMoved, from)
    usleep(200_000)
    post(.leftMouseDown, from)
    usleep(300_000)
    let steps = 30
    for step in 1...steps {
      let t = CGFloat(step) / CGFloat(steps)
      post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
      usleep(16_000)
    }
    usleep(600_000)
    post(.leftMouseUp, to)
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
    try require(dialog.waitForExistence(timeout: 10), "Tabs › New Folder… opened no dialog")
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

  /// Creating through the plus menu and Tabs › New Folder…, renaming,
  /// closing, and the tab commands over a closed and an open folder, across
  /// a relaunch (tab-folders spec, "Creating a folder in place", "New Folder
  /// dialog", "Opening and closing a folder", "Folders after a relaunch";
  /// spaces spec, "Tab commands and folders").
  func testCreatingNamingAndClosingFolders() async throws {
    executionTimeAllowance = 300
    try Harness.setRestoreWindows(true)
    let (browser, home) = try await startWithPage("counter.html?home")
    defer { home.close() }
    let tabs = try await openCounters(browser, ["spec", "plan", "x"])
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
    try require(inbox, "Tabs › New Folder… didn't add Inbox last: \(browser.pinnedSection)")

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
    let x = await browser.waitForTabs(30) { $0.contains("Counter x") }
    try require(x, "X didn't come back: \(browser.tabTitles)")

    // Closed, Docs lists only its tabs whose page is open, selected or not,
    // as Arc does, and shows "•••".
    browser.pinRow("Counter plan").click()
    _ = await Harness.wait(for: 10) { browser.pinRow("Counter plan").isSelected }
    browser.ui.typeKey("w", modifierFlags: .command)
    _ = await browser.waitForTarget("?plan", open: false)
    browser.pinRow("Counter spec").click()
    let specOpen = await browser.waitForTarget("?spec")
    try require(specOpen, "Spec's page isn't open")
    browser.pinRow("Counter home").click()
    _ = await Harness.wait(for: 10) { browser.pinRow("Counter home").isSelected }
    browser.folderRow("Docs").click()
    let closed = await browser.waitForPinnedSection { $0.suffix(2) == ["[Docs]", "  Counter spec"] }
    XCTAssertTrue(closed, "The closed folder doesn't list just its open tab: \(browser.pinnedSection)")
    XCTAssertFalse(browser.isFolderOpen("Docs"), "The folder's row says it's open")

    // The tab commands count the rows listed (spaces spec, "Tab commands and
    // folders"): from Home, the next row is Spec, past Plan's hidden one, and
    // Cmd+3 is X, in Today.
    browser.ui.typeKey(.downArrow, modifierFlags: [.command, .option])
    let next = await Harness.wait(for: 15) { browser.pinRow("Counter spec").isSelected }
    XCTAssertTrue(next, "Opt+Cmd+Down didn't go to the closed folder's open tab")
    browser.ui.typeKey("3", modifierFlags: .command)
    let third = await browser.waitForActiveRow("Counter x")
    XCTAssertTrue(third, "Cmd+3 counted the closed folder's hidden tab")

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
    // Open, Docs' tabs count from Cmd+2, and Plan, first in Docs, stays in
    // it on Ctrl+Shift+PageUp.
    browser.ui.typeKey("2", modifierFlags: .command)
    let plan = await Harness.wait(for: 15) { browser.pinRow("Counter plan").isSelected }
    XCTAssertTrue(plan, "Cmd+2 didn't count the open folder's tab")
    browser.ui.typeKey(.pageUp, modifierFlags: [.control, .shift])
    try await Task.sleep(for: .seconds(1))
    XCTAssertEqual(
      browser.pinnedSection, ["Counter home", "[Trip]", "[Docs]", "  Counter plan", "  Counter spec"],
      "Plan left its folder")

    try await browser.relaunch()
    let records = try browser.pinRecords()
    let folders = records.filter { $0.value["kind"] as? String == "folder" }
    XCTAssertEqual(Set(folders.values.compactMap { $0["name"] as? String }), ["Trip", "Docs"])
    let closedIDs = try browser.clairState()["closed_folders"] as? [String] ?? []
    XCTAssertTrue(closedIDs.isEmpty, "Docs, opened again, is still in clair.closed_folders: \(closedIDs)")
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
    // The menu's own item: the Tabs menu has one of the same title.
    let move = try XCTUnwrap(browser.visibleMenuItem("Move to Space"), "The folder's menu has no Move to Space with two Spaces")
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

  /// Each item is its own record (add-tab-folders D1): a pin moving up a row
  /// rewrites only its own record and keeps its place across a relaunch, a
  /// folder moving to another Space rewrites its record and its pins', and a
  /// pinned tab whose folder's record is gone lists at its Space's top level.
  /// Placing keys in any order is scripts/order-key.test.sh's.
  func testFolderRecords() async throws {
    executionTimeAllowance = 420
    try Harness.setRestoreWindows(false)
    let (browser, first) = try await startWithPage("counter.html?end1")
    defer { first.close() }
    let tabs = try await openCounters(browser, ["end2", "end3", "end4"])
    defer { tabs.forEach { $0.close() } }
    for name in ["end1", "end2", "end3", "end4"] {
      try await browser.pinWithCmdD("Counter \(name)")
    }

    // A folder of two pins moved to another Space: its record and its pins'.
    try browser.newFolderFromPlusMenu("Trip")
    _ = await Harness.wait(for: 10) { browser.folderNames == ["Trip"] }
    try await browser.fileIntoFolder(["Counter end1", "Counter end2"], folder: "Trip")
    let filed = await browser.waitForPinnedSection(30) {
      $0 == ["Counter end3", "Counter end4", "[Trip]", "  Counter end1", "  Counter end2"]
    }
    try require(filed, "Trip doesn't hold End 1 and 2: \(browser.pinnedSection)")
    try await browser.createSpace("Work")
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let beforeMove = try await recordsAfterRelaunch(browser)

    // End 4 up a row, then Trip to Work.
    browser.pinRow("Counter end4").click()
    _ = await Harness.wait(for: 10) { browser.pinRow("Counter end4").isSelected }
    browser.ui.typeKey(.pageUp, modifierFlags: [.control, .shift])
    let up = await browser.waitForPinnedSection { $0.prefix(2) == ["Counter end4", "Counter end3"] }
    try require(up, "Ctrl+Shift+PageUp didn't move End 4 up: \(browser.pinnedSection)")
    browser.folderRow("Trip").rightClick()
    browser.visibleMenuItem("Move to Space")?.click()
    try require(browser.visibleMenuItem("Work") != nil, "Move to Space has no Work")
    browser.visibleMenuItem("Work")?.click()
    _ = await Harness.wait(for: 10) { browser.folderNames.isEmpty }
    let afterMove = try await recordsAfterRelaunch(browser)
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let kept = await browser.waitForPinnedSection(30) { $0 == ["Counter end4", "Counter end3"] }
    XCTAssertTrue(kept, "Home's pins didn't keep their order: \(browser.pinnedSection)")
    let workID = try XCTUnwrap(try browser.spaceRecords().first { $0.value["name"] as? String == "Work" }?.key)
    let changes = changed(beforeMove, afterMove)
    let moved = changes.filter { afterMove[$0]?["space"] as? String == workID }
    XCTAssertEqual(moved.count, 3, "Moving a folder of two pins rewrote \(moved.count) of its records")
    let others = changes.subtracting(moved).compactMap { afterMove[$0]?["url"] as? String }
    XCTAssertEqual(others.count, 1, "Moving End 4 rewrote \(others.count) records")
    XCTAssertTrue(others.allSatisfy { $0.hasSuffix("?end4") }, "Moving End 4 rewrote \(others)")

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
  /// out of a folder", "Reordering folders"; add-tab-folders D12). It drags
  /// with the mouse's own events, and skips where the runner may not post them.
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
    try browser.drag(try XCTUnwrap(browser.tabRow("Counter spec")), onto: browser.folderRow("Docs"))
    let onRow = await browser.waitForPinnedSection { $0 == ["Counter home", "[Docs]", "  Counter spec"] }
    try require(onRow, "A drop on Docs' row didn't pin into it: \(browser.pinnedSection)")
    let kept = try await browser.target(endingWith: "?spec")
    XCTAssertNotNil(kept, "Pinning into the folder closed the page")
    try browser.drag(try XCTUnwrap(browser.tabRow("Counter plan")), onto: browser.folderRow("Docs"))
    let firstIn = await browser.waitForPinnedSection {
      $0 == ["Counter home", "[Docs]", "  Counter plan", "  Counter spec"]
    }
    XCTAssertTrue(firstIn, "The second drop isn't Docs' first tab: \(browser.pinnedSection)")

    // A drop on a closed folder's row lands in it too.
    browser.folderRow("Docs").click()
    _ = await browser.waitForPinnedSection { $0 == ["Counter home", "[Docs]"] }
    try browser.drag(try XCTUnwrap(browser.tabRow("Counter note")), onto: browser.folderRow("Docs"))
    try await Task.sleep(for: .seconds(1))
    browser.folderRow("Docs").click()
    let closedDrop = await browser.waitForPinnedSection {
      $0 == ["Counter home", "[Docs]", "  Counter note", "  Counter plan", "  Counter spec"]
    }
    XCTAssertTrue(closedDrop, "A drop on the closed folder didn't land in it: \(browser.pinnedSection)")

    // A folder's tab dragged above the folder leaves it.
    try browser.drag(browser.pinRow("Counter note"), onto: browser.folderRow("Docs"), topEdge: true)
    let out = await browser.waitForPinnedSection {
      $0 == ["Counter home", "Counter note", "[Docs]", "  Counter plan", "  Counter spec"]
    }
    XCTAssertTrue(out, "Dragging Note above Docs didn't take it out: \(browser.pinnedSection)")

    // Into Today, below the divider, it's unpinned with its page.
    try browser.drag(browser.pinRow("Counter spec"), onto: browser.element("clair.newTabRow"))
    let today = await browser.waitForTabs { $0.contains("Counter spec") }
    XCTAssertTrue(today, "Dragging Spec into Today didn't unpin it: \(browser.tabTitles)")

    // The folder reorders above Home, with its tabs, and stays put when
    // dropped below the divider.
    try browser.drag(browser.folderRow("Docs"), onto: browser.pinRow("Counter home"), topEdge: true)
    let reordered = await browser.waitForPinnedSection { $0.first == "[Docs]" }
    XCTAssertTrue(reordered, "Docs didn't move above Home: \(browser.pinnedSection)")
    let section = browser.pinnedSection
    try browser.drag(browser.folderRow("Docs"), onto: try XCTUnwrap(browser.tabRow("Counter spec")))
    try await Task.sleep(for: .seconds(1))
    XCTAssertEqual(browser.pinnedSection, section, "Docs moved below the divider")

    // Reordering Spaces rewrites only the Space that moved.
    try await browser.createSpace("Work")
    let spacesBefore = try await spaceRecordsAfterRelaunch(browser)
    let items = browser.switcherItems
    try require(items.count == 2, "The switcher doesn't show two Spaces")
    try browser.drag(
      from: CGPoint(x: items[1].frame.midX, y: items[1].frame.midY),
      to: CGPoint(x: items[0].frame.minX + items[0].frame.width * 0.2, y: items[0].frame.midY))
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
