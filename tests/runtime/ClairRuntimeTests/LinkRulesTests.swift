// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import XCTest

extension Browser {
  /// Opens Settings on its Links page.
  func openLinksPage() throws {
    ui.typeKey(",", modifierFlags: .command)
    let page = ui.toolbars.buttons["Links"]
    try require(page.waitForExistence(timeout: 15), "Settings has no Links page")
    page.click()
    try require(ui.windows["Links"].waitForExistence(timeout: 10), "The Links page didn't open")
  }

  /// Chooses "Link Rules…" on the Links page, which must be open, and waits
  /// for the dialog.
  func openLinkRules() throws {
    let button = ui.windows["Links"].descendants(matching: .any).matching(identifier: "clair.linkRulesButton")
      .firstMatch
    try require(button.waitForExistence(timeout: 10), "The Links page has no Link Rules… button")
    button.click()
    try require(dialog.waitForExistence(timeout: 10), "Link Rules… didn't open the dialog")
  }

  func closeLinksPage() {
    ui.windows["Links"].typeKey("w", modifierFlags: .command)
  }

  /// The dialog's rule rows, in order.
  var linkRuleRows: [XCUIElement] {
    dialog.descendants(matching: .any).matching(identifier: "clair.linkRule").allElementsBoundByIndex
  }

  /// A SwiftUI text's string, which XCUITest reads as its value.
  func text(_ identifier: String) -> String {
    let element = dialogElement(identifier)
    return element.exists ? element.value as? String ?? element.label : ""
  }

  /// The enabled item titled `title` in the open menu: a popup grouped by
  /// profile also has a disabled header of a profile's name.
  func chooseEnabledMenuItem(_ title: String) async throws {
    var found: XCUIElement?
    let shown = await Harness.wait(for: 5) {
      found = self.ui.menuItems.matching(NSPredicate(format: "title == %@", title)).allElementsBoundByIndex
        .first { $0.isHittable && $0.isEnabled }
      return found != nil
    }
    try require(shown, "No open menu has an enabled \(title)")
    found!.click()
  }

  func linkRulePart(_ identifier: String, of row: XCUIElement) -> XCUIElement {
    row.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// Chooses Add Rule and fills in the new row: `match` as the match popup
  /// titles it, the text, and the Space.
  func addLinkRule(_ match: String = "URLs containing", _ text: String, in space: String) async throws {
    let count = linkRuleRows.count
    dialogElement("clair.dialogLeading").click()
    let added = await Harness.wait(for: 10) { self.linkRuleRows.count == count + 1 }
    try require(added, "Add Rule didn't add a row")
    guard let row = linkRuleRows.last else { throw HarnessError("The new row is gone") }
    let field = linkRulePart("clair.linkRuleText", of: row)
    field.click()
    field.typeText(text)
    if match != "URLs containing" {
      linkRulePart("clair.linkRuleMatch", of: row).click()
      try await chooseEnabledMenuItem(match)
    }
    let popup = linkRulePart("clair.linkRuleSpace", of: row)
    if popup.value as? String != space {
      popup.click()
      try await chooseEnabledMenuItem(space)
    }
  }

  /// Chooses Done and waits for the dialog to close.
  func saveLinkRules() async throws {
    dialogElement("clair.dialogDefault").click()
    let closed = await Harness.wait(for: 10) { !self.dialog.exists }
    let error = text("clair.linkRulesError")
    try require(closed, "Done didn't close the dialog: \(error.isEmpty ? "no error" : error)")
  }

  /// Hands `link` to Clair as another app does, through Launch Services: to
  /// the running Clair, or launching this copy with `arguments` when none
  /// runs.
  func openFromAnotherApp(_ link: String, arguments: [String] = []) async throws {
    guard let url = URL(string: link) else { throw HarnessError("Not a URL: \(link)") }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = arguments
    let failure: String? = await withCheckedContinuation { continuation in
      NSWorkspace.shared.open([url], withApplicationAt: appPath, configuration: configuration) { _, error in
        continuation.resume(returning: error?.localizedDescription)
      }
    }
    try require(failure == nil, "Launch Services didn't open \(link): \(failure ?? "")")
  }

  /// Deletes the Space the window shows from its header, confirming in the
  /// window's own dialog when its tabs make it ask.
  func deleteShownSpace() throws {
    element("clair.spaceHeader").rightClick()
    let delete = ui.menuItems["Delete Space"]
    try require(delete.waitForExistence(timeout: 5), "The header menu has no Delete Space")
    delete.click()
    let confirm = nativeWindow.descendants(matching: .any).matching(identifier: "clair.dialog").firstMatch
      .descendants(matching: .any).matching(identifier: "clair.dialogDefault").firstMatch
    if confirm.waitForExistence(timeout: 3) {
      confirm.click()
    }
  }
}

/// Link rules (add-link-rules task 3.5): the Link Rules dialog driven
/// through its identifiers, and links sent from the test runner as another
/// app sends them, through Launch Services, checked through the window's
/// Space and tabs and over DevTools.
@MainActor
final class LinkRulesTests: NativeWindowTestCase {
  override func setUp() async throws {
    // Each test drives the dialog and sends several links, some across a
    // relaunch, past run.sh's default allowance.
    executionTimeAllowance = 300
    try await super.setUp()
  }

  func counter(_ name: String) -> String { url("counter.html?\(name)") }
  func cookie(_ name: String) -> String { url("cookie.html?\(name)") }

  /// The pages' host and port without a scheme, such as "localhost:8123".
  var hostAndPort: String {
    let base = URL(string: fixture.baseURL)!
    return "\(base.host() ?? "localhost"):\(base.port ?? 80)"
  }

  /// Starts with a Home tab and the Spaces `names` after Home, showing Home.
  func start(withSpaces names: [String]) async throws -> (Browser, DevToolsSession) {
    try Harness.setRestoreWindows(false)
    let (browser, home) = try await startWithPage("counter.html?home")
    for name in names {
      try await browser.createSpace(name)
    }
    browser.ui.typeKey("1", modifierFlags: .control)
    let onHome = await browser.waitForSpace("Home")
    try require(onHome, "Ctrl+1 didn't show Home")
    return (browser, home)
  }

  /// Sends `link` from another app while the window shows Home, and checks
  /// that its tab, titled `title`, opens active in `space`, or in Home when
  /// `space` is nil, as without link rules.
  func expect(
    _ link: String, titled title: String, toOpenIn space: String?, in browser: Browser,
    file: StaticString = #filePath, line: UInt = #line
  ) async throws {
    if browser.spaceName != "Home" {
      browser.nativeWindow.click()
      browser.ui.typeKey("1", modifierFlags: .control)
      _ = await browser.waitForSpace("Home")
    }
    try await browser.openFromAnotherApp(link)
    let opened = await Harness.wait(for: 30) {
      browser.spaceName == (space ?? "Home") && browser.activeRow == title
    }
    XCTAssertTrue(
      opened, "\(link) didn't open in \(space ?? "Home"): \(browser.spaceName), \(browser.activeRow ?? "no row")",
      file: file, line: line)
  }

  /// Matching (link-rules' "Match options", "Texts without a scheme", "First
  /// matching rule wins", "Where a matched link opens", "Links opened inside
  /// Clair are not routed"), with rules saved through the dialog.
  func testRulesRouteLinksFromOtherApps() async throws {
    let (browser, home) = try await start(withSpaces: ["Work", "Personal"])
    defer { home.close() }
    try browser.openLinksPage()
    try browser.openLinkRules()
    XCTAssertEqual(browser.text("clair.linkRulesEmpty"), "No link rules yet", "The empty list doesn't say so")
    try await browser.addLinkRule("URLs containing", "Counter.HTML?Meet", in: "Work")
    try await browser.addLinkRule("this exact URL", "\(fixture.baseURL)/pages/counter.html?inbox", in: "Work")
    try await browser.addLinkRule("this exact URL", "\(hostAndPort)/pages/counter.html?either", in: "Personal")
    try await browser.addLinkRule("URLs starting with", "\(hostAndPort)/pages/counter.html?acme", in: "Personal")
    try await browser.addLinkRule("URLs containing", "counter.html?docs", in: "Work")
    // Matches the same links: the first rule wins.
    try await browser.addLinkRule("URLs containing", "html?docs", in: "Personal")
    XCTAssertEqual(browser.linkRuleRows.count, 6, "The dialog doesn't list six rules")
    try await browser.saveLinkRules()
    browser.closeLinksPage()
    browser.nativeWindow.click()

    // Containing, ignoring case; a matched link switches the window to the
    // rule's Space, in a new active tab.
    try await expect(counter("meet-abc"), titled: "Counter meet-abc", toOpenIn: "Work", in: browser)
    // This exact URL, ignoring the fragment, and nothing longer.
    try await expect(counter("inbox#top"), titled: "Counter inbox", toOpenIn: "Work", in: browser)
    try await expect(counter("inbox/old"), titled: "Counter inbox/old", toOpenIn: nil, in: browser)
    // A text without a scheme matches http links.
    try await expect(counter("either"), titled: "Counter either", toOpenIn: "Personal", in: browser)
    // Starting with, on the same host only.
    try await expect(counter("acme/app"), titled: "Counter acme/app", toOpenIn: "Personal", in: browser)
    let port = URL(string: fixture.baseURL)!.port ?? 80
    try await expect(
      "http://127.0.0.1:\(port)/pages/counter.html?acme/ip", titled: "Counter acme/ip", toOpenIn: nil, in: browser)
    // The first matching rule wins.
    try await expect(counter("docs-1"), titled: "Counter docs-1", toOpenIn: "Work", in: browser)

    // A link clicked inside Clair opens as it would without rules.
    browser.ui.typeKey("1", modifierFlags: .control)
    _ = await browser.waitForSpace("Home")
    let link = counter("docs-inside")
    _ = try await home.evaluate(
      """
      (() => { const a = document.createElement("a"); a.href = "\(link)"; a.target = "_blank";
               document.body.append(a); a.click(); return true; })()
      """)
    let inHome = await browser.waitForTabs { $0.contains("Counter docs-inside") }
    XCTAssertTrue(inHome, "A link clicked in Home didn't open in Home: \(browser.tabTitles)")
    XCTAssertEqual(browser.spaceName, "Home", "A link clicked inside Clair switched Space")

    // With no window open, a matched link opens a window showing its Space.
    browser.ui.typeKey("w", modifierFlags: [.command, .shift])
    let closed = await Harness.wait(for: 30) { browser.visibleNativeWindowCount == 0 }
    try require(closed, "Shift+Cmd+W didn't close the window")
    try await browser.openFromAnotherApp(counter("meet-new"))
    let reopened = await Harness.wait(for: 30) {
      browser.visibleNativeWindowCount == 1 && browser.spaceName == "Work" && browser.activeRow == "Counter meet-new"
    }
    XCTAssertTrue(reopened, "The link didn't open a window showing Work: \(browser.spaceName), \(browser.tabTitles)")
  }

  /// The dialog's states, checks and discarding (link-rules' "Link Rules
  /// empty states", "Link rule rows", "Saving link rules", "Link rule
  /// errors", "Discarding edits").
  func testTheDialogChecksAndDiscards() async throws {
    try Harness.setRestoreWindows(false)
    let (browser, home) = try await startWithPage("counter.html?home")
    defer { home.close() }

    // One Space: Add Rule is off, and the list says why.
    try browser.openLinksPage()
    try browser.openLinkRules()
    XCTAssertTrue(
      browser.text("clair.linkRulesEmpty").contains("more than one Space"),
      "The list doesn't say rules need another Space")
    XCTAssertFalse(browser.dialogElement("clair.dialogLeading").isEnabled, "Add Rule is on with one Space")
    browser.ui.typeKey(.escape, modifierFlags: [])
    let cancelled = await Harness.wait(for: 10) { !browser.dialog.exists }
    try require(cancelled, "Esc didn't close the dialog without edits")
    browser.closeLinksPage()
    browser.nativeWindow.click()
    try await browser.createSpace("Work")

    try browser.openLinksPage()
    try browser.openLinkRules()
    XCTAssertEqual(browser.text("clair.linkRulesEmpty"), "No link rules yet")
    XCTAssertTrue(browser.dialogElement("clair.dialogLeading").isEnabled, "Add Rule is off with two Spaces")
    // Add Rule: "URLs containing", an empty focused field, the first Space.
    browser.dialogElement("clair.dialogLeading").click()
    let added = await Harness.wait(for: 10) { browser.linkRuleRows.count == 1 }
    try require(added, "Add Rule didn't add a row")
    let row = browser.linkRuleRows[0]
    let field = browser.linkRulePart("clair.linkRuleText", of: row)
    let focused = await Harness.wait(for: 5) { field.value(forKey: "hasKeyboardFocus") as? Bool == true }
    XCTAssertTrue(focused, "The new row's field isn't focused")
    XCTAssertEqual(browser.linkRulePart("clair.linkRuleMatch", of: row).value as? String, "URLs containing")
    XCTAssertEqual(browser.linkRulePart("clair.linkRuleSpace", of: row).value as? String, "Home")

    // An invalid text keeps the dialog open, until an edit clears the error.
    field.click()
    field.typeText("not a url")
    browser.dialogElement("clair.dialogDefault").click()
    let error = browser.dialogElement("clair.linkRulesError")
    try require(error.waitForExistence(timeout: 5), "Done with an invalid text showed no error")
    XCTAssertEqual(browser.text("clair.linkRulesError"), "Enter a valid domain or URL.")
    XCTAssertTrue(browser.dialog.exists, "Done with an invalid text closed the dialog")
    field.typeKey("a", modifierFlags: .command)
    field.typeText("example.com")
    let cleared = await Harness.wait(for: 5) { !error.exists }
    XCTAssertTrue(cleared, "Editing didn't clear the error")

    // A duplicate keeps it open too; removing the row lets it through.
    try await browser.addLinkRule("URLs containing", "example.com", in: "Work")
    browser.dialogElement("clair.dialogDefault").click()
    try require(error.waitForExistence(timeout: 5), "Done with a duplicate showed no error")
    XCTAssertEqual(browser.text("clair.linkRulesError"), "Each domain or URL and matching option can only appear once.")
    browser.linkRulePart("clair.linkRuleRemove", of: browser.linkRuleRows[1]).click()
    let removed = await Harness.wait(for: 5) { browser.linkRuleRows.count == 1 }
    XCTAssertTrue(removed, "The × button didn't remove the row")

    // Esc with edits turns Cancel into Discard Changes; Esc again discards.
    browser.ui.typeKey(.escape, modifierFlags: [])
    let discard = browser.dialogButton("clair.dialogCancel")
    let turned = await Harness.wait(for: 5) { discard.label == "Discard Changes" }
    XCTAssertTrue(turned, "Esc with edits didn't turn Cancel into Discard Changes: \(discard.label)")
    XCTAssertTrue(browser.dialog.exists, "Esc with edits closed the dialog")
    browser.ui.typeKey(.escape, modifierFlags: [])
    let discarded = await Harness.wait(for: 10) { !browser.dialog.exists }
    try require(discarded, "Discard Changes didn't close the dialog")
    try browser.openLinkRules()
    XCTAssertEqual(browser.linkRuleRows.count, 0, "Discarded rules were saved")

    // Done drops an empty row.
    browser.dialogElement("clair.dialogLeading").click()
    try await browser.saveLinkRules()
    try browser.openLinkRules()
    XCTAssertEqual(browser.linkRuleRows.count, 0, "An empty row was saved")
    browser.ui.typeKey(.escape, modifierFlags: [])
  }

  /// Rules kept across launches and following their Space (link-rules'
  /// "Link rules", "Rules follow their Space", and "Space deleted while
  /// open").
  func testRulesFollowTheirSpaceAndLast() async throws {
    let (browser, home) = try await start(withSpaces: ["Work", "Personal"])
    try browser.openLinksPage()
    try browser.openLinkRules()
    try await browser.addLinkRule("URLs containing", "counter.html?keep", in: "Work")
    try await browser.saveLinkRules()
    browser.closeLinksPage()

    // Kept across a relaunch.
    home.close()
    try await Task.sleep(for: .seconds(2))
    try await browser.quit()
    try await browser.start()
    try require(browser.nativeWindow.waitForExistence(timeout: 60), "Clair didn't come back")
    try browser.openLinksPage()
    try browser.openLinkRules()
    try require(browser.linkRuleRows.count == 1, "The rule didn't survive a relaunch: \(browser.linkRuleRows.count)")
    let row = browser.linkRuleRows[0]
    XCTAssertEqual(browser.linkRulePart("clair.linkRuleText", of: row).value as? String, "counter.html?keep")
    XCTAssertEqual(browser.linkRulePart("clair.linkRuleSpace", of: row).value as? String, "Work")
    browser.ui.typeKey(.escape, modifierFlags: [])
    _ = await Harness.wait(for: 10) { !browser.dialog.exists }
    browser.closeLinksPage()

    // Renaming the Space keeps its rule.
    browser.nativeWindow.click()
    browser.ui.typeKey("2", modifierFlags: .control)
    _ = await browser.waitForSpace("Work")
    browser.element("clair.spaceHeader").rightClick()
    browser.ui.menuItems["Rename Space…"].click()
    let name = browser.element("clair.spaceNameField")
    try require(name.waitForExistence(timeout: 5), "Rename Space… didn't show a field")
    name.typeKey("a", modifierFlags: .command)
    name.typeText("Office\n")
    let renamed = await browser.waitForSpace("Office")
    try require(renamed, "Work wasn't renamed")
    try await expect(counter("keep-1"), titled: "Counter keep-1", toOpenIn: "Office", in: browser)

    // A rule whose Space is deleted while the dialog is open asks for
    // another; once the Space is gone, so is its rule.
    try browser.openLinksPage()
    try browser.openLinkRules()
    try await browser.addLinkRule("URLs containing", "counter.html?gone", in: "Personal")
    try await browser.saveLinkRules()
    try browser.openLinkRules()
    XCTAssertEqual(browser.linkRuleRows.count, 2, "The dialog doesn't list both rules")
    browser.nativeWindow.click()
    browser.ui.typeKey("3", modifierFlags: .control)
    let onPersonal = await browser.waitForSpace("Personal")
    try require(onPersonal, "Ctrl+3 didn't show Personal")
    try browser.deleteShownSpace()
    let deleted = await Harness.wait(for: 15) { browser.spaceName != "Personal" && !browser.spaceName.isEmpty }
    try require(deleted, "Personal wasn't deleted")
    browser.dialogElement("clair.dialogDefault").click()
    let error = browser.dialogElement("clair.linkRulesError")
    try require(error.waitForExistence(timeout: 5), "Done with a deleted Space showed no error")
    XCTAssertEqual(browser.text("clair.linkRulesError"), "Choose a Space for each rule.")
    browser.ui.windows["Links"].typeKey(.escape, modifierFlags: [])
    let closed = await Harness.wait(for: 10) { !browser.dialog.exists }
    try require(closed, "Cancel didn't close the dialog")
    try browser.openLinkRules()
    XCTAssertEqual(browser.linkRuleRows.count, 1, "The deleted Space's rule is still listed")
    browser.ui.typeKey(.escape, modifierFlags: [])
    _ = await Harness.wait(for: 10) { !browser.dialog.exists }
    browser.closeLinksPage()
    browser.nativeWindow.click()
    try await expect(counter("gone-1"), titled: "Counter gone-1", toOpenIn: nil, in: browser)
  }

  /// A link that launches Clair opens in its rule's Space, of another
  /// profile (link-rules' "Clair not running" and "Work uses another
  /// profile"). XCUITest doesn't follow a launch it didn't start, so the
  /// cookie the Work profile set tells where the link opened.
  func testALinkThatLaunchesClairOpensInItsProfile() async throws {
    try Harness.setRestoreWindows(false)
    let (browser, home) = try await startWithPage("counter.html?home")
    try browser.openProfilesPage()
    try await browser.addProfile("Client")
    browser.ui.windows["Profiles"].typeKey("w", modifierFlags: .command)
    browser.nativeWindow.click()
    try await browser.createSpace("Work", profile: "Client")
    let setter = try await browser.open(cookie("set"))
    let set = await Harness.wait(for: 15) { try await browser.hasCookie(setter) }
    try require(set, "The cookie page didn't set its cookie in Work")
    try browser.openLinksPage()
    try browser.openLinkRules()
    try await browser.addLinkRule("URLs containing", "cookie.html?cold", in: "Work")
    try await browser.saveLinkRules()
    browser.closeLinksPage()
    [home, setter].forEach { $0.close() }
    try await Task.sleep(for: .seconds(2))
    try await browser.quit()

    try? FileManager.default.removeItem(at: browser.dataDirectory.appending(path: "DevToolsActivePort"))
    try await browser.openFromAnotherApp(cookie("cold"), arguments: try browser.launchArguments())
    let opened = await browser.waitForTarget("?cold", seconds: 120)
    try require(opened, "The link that launched Clair didn't open")
    let cold = try await browser.session(endingWith: "?cold")
    defer { cold.close() }
    let inWork = await Harness.wait(for: 15) { try await browser.hasCookie(cold) }
    XCTAssertTrue(inWork, "The link didn't open in Work's profile")
  }
}
