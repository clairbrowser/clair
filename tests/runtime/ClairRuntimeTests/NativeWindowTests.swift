// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import XCTest

/// The native window's fundamentals (replace-browser-window design D14): the
/// build-pipeline spec's native window coverage. XCUITest finds ClairUI's views by accessibility identifier, and
/// DevTools reads the pages' state.
@MainActor
class NativeWindowTestCase: RuntimeTestCase {
  func url(_ page: String) -> String { "\(fixture.baseURL)/pages/\(page)" }

  /// Starts Clair with one tab showing `page`, and returns that tab.
  func startWithPage(
    _ page: String = "index.html", arguments: [String] = [], searchSuggestions: Bool = false
  ) async throws -> (Browser, DevToolsSession) {
    let browser = try await startBrowser(arguments: arguments, searchSuggestions: searchSuggestions)
    let tab = try await browser.open(url(page))
    browser.ui.activate()
    try require(browser.nativeWindow.waitForExistence(timeout: 30), "Clair shows no native window")
    return (browser, tab)
  }

  /// A session on the background script of the extension named `name`.
  /// Chromium's own component extensions run background scripts too, so the
  /// worker is told apart by its extension's manifest. `--load-extension`
  /// loads an extension into every profile: `pageEndingWith` picks the
  /// worker of the profile of the page whose URL ends with it.
  func extensionWorker(
    _ browser: Browser, named name: String, pageEndingWith page: String? = nil
  ) async throws -> DevToolsSession {
    let session = try await browser.browserSession()
    defer { session.close() }
    var worker: DevToolsSession?
    let started = await Harness.wait(for: 30) {
      let targets = try await session.send("Target.getTargets")
      let infos = targets["targetInfos"] as? [[String: Any]] ?? []
      let context = page.flatMap { suffix in
        infos.first { $0["type"] as? String == "page" && ($0["url"] as? String)?.hasSuffix(suffix) == true }?[
          "browserContextId"] as? String
      }
      if page != nil && context == nil { return false }
      for info in infos where info["type"] as? String == "service_worker" {
        guard let id = info["targetId"] as? String,
          (info["url"] as? String)?.hasPrefix("chrome-extension://") == true,
          context == nil || info["browserContextId"] as? String == context
        else { continue }
        let candidate = try await browser.session(onTarget: id)
        if (try? await candidate.evaluate("chrome.runtime.getManifest().name")) as? String == name {
          worker = candidate
          return true
        }
        candidate.close()
      }
      return false
    }
    try require(started, "\(name)'s background script didn't start")
    return try XCTUnwrap(worker)
  }
}

extension Browser {
  /// The first window with a sidebar.
  var nativeWindow: XCUIElement {
    ui.windows.containing(.any, identifier: "clair.sidebar").firstMatch
  }

  func element(_ identifier: String, in root: XCUIElement? = nil) -> XCUIElement {
    (root ?? nativeWindow).descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  var sidebar: XCUIElement { element("clair.sidebar") }

  /// Pins the window's one extension from the Site Control Center, and
  /// returns its pinned button.
  @discardableResult
  func pinExtensionFromSiteControls() throws -> XCUIElement {
    // The site-controls button shows under the pointer, and a tile's pin badge
    // only while the pointer is on the tile: hidden views have no element.
    let urlField = element("clair.urlField")
    try require(urlField.waitForExistence(timeout: 30), "The sidebar has no URL field")
    urlField.hover()
    let siteControls = element("clair.siteControls")
    try require(siteControls.waitForExistence(timeout: 10), "Hovering the URL field shows no site controls")
    siteControls.click()
    let tile = ui.descendants(matching: .any).matching(identifier: "clair.siteControlsExtension").firstMatch
    try require(tile.waitForExistence(timeout: 30), "The Site Control Center doesn't list the extension")
    // A pointer that lands on the tile in one jump can miss its hover in a
    // popover that has just opened, so move across it as a pointer would.
    let pin = ui.buttons["Pin"].firstMatch
    var hovered = false
    for offset in [0.2, 0.5, 0.8] where !hovered {
      tile.coordinate(withNormalizedOffset: CGVector(dx: offset, dy: 0.5)).hover()
      hovered = pin.waitForExistence(timeout: 3)
    }
    try require(hovered, "Hovering a tile shows no pin badge")
    pin.click()
    ui.typeKey(.escape, modifierFlags: [])
    let pinned = element("clair.extensionAction")
    try require(pinned.waitForExistence(timeout: 10), "The pinned action has no button")
    return pinned
  }

  /// Whether the sidebar is in the window, shown or revealed, rather than
  /// moved out of it. XCUITest's isHittable can't see into the sidebar's
  /// SwiftUI content, so this goes by its frame.
  var isSidebarInWindow: Bool {
    guard sidebar.exists else { return false }
    let frame = sidebar.frame
    return frame.width > 0 && frame.minX >= nativeWindow.frame.minX - 1
  }
  var card: XCUIElement { element("clair.card") }

  var tabRows: [XCUIElement] {
    nativeWindow.descendants(matching: .any).matching(identifier: "clair.tabRow").allElementsBoundByIndex
  }

  /// The rows' titles, read from one snapshot of the window: reading each
  /// row's label in turn fails the test when a row closes meanwhile.
  var tabTitles: [String] {
    guard let window = try? nativeWindow.snapshot() else { return [] }
    var titles: [String] = []
    func collect(_ element: any XCUIElementSnapshot) {
      if element.identifier == "clair.tabRow" {
        titles.append(element.label)
      }
      element.children.forEach(collect)
    }
    collect(window)
    return titles
  }

  /// Waits for the sidebar's tab titles to satisfy `condition`.
  func waitForTabs(_ seconds: TimeInterval = 15, _ condition: @escaping ([String]) -> Bool) async -> Bool {
    await Harness.wait(for: seconds) { condition(self.tabTitles) }
  }

  /// The page's `document.visibilityState`.
  func visibility(of tab: DevToolsSession) async throws -> String {
    try await tab.evaluate("document.visibilityState") as? String ?? ""
  }

  /// The window that shows `tab`, as DevTools sees it.
  func windowBounds(of tab: DevToolsSession, targetID: String? = nil) async throws -> [String: Any] {
    let session = try await browserSession()
    defer { session.close() }
    var parameters: [String: Any] = [:]
    if let targetID { parameters["targetId"] = targetID }
    let window = try await session.send("Browser.getWindowForTarget", parameters)
    return window["bounds"] as? [String: Any] ?? [:]
  }

  /// Lets downloads save to a folder without asking, as ungoogled-chromium
  /// otherwise does for every download. The setting lasts as long as the
  /// returned session, which the caller closes.
  func allowDownloads(to folder: URL) async throws -> DevToolsSession {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let session = try await browserSession()
    try await session.send("Browser.setDownloadBehavior", ["behavior": "allow", "downloadPath": folder.path])
    return session
  }

  /// A point in the card, as a fraction of its size.
  func cardPoint(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
    card.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
  }
}

extension DevToolsSession {
  /// The target this session is attached to, through its URL.
  func targetID(in browser: Browser) async throws -> String? {
    let href = try await evaluate("location.href") as? String
    return try await browser.pageTargets().first { $0.url == href }?.id
  }

  var innerWidth: Double {
    get async throws { try await evaluate("innerWidth") as? Double ?? 0 }
  }
}

/// Which windows are native, and how the window is laid out (task 4.1).
@MainActor
final class NativeWindowStructureTests: NativeWindowTestCase {
  func testWhichWindowsAreNative() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    XCTAssertTrue(browser.sidebar.exists, "The window has no sidebar")
    XCTAssertTrue(browser.card.exists, "The window has no card")
    XCTAssertFalse(browser.ui.windows.toolbars.firstMatch.exists, "The window shows a toolbar")

    // An incognito window is native, says so, and lists only its own tab.
    let regular = browser.nativeWindows.first
    browser.ui.typeKey("n", modifierFlags: [.command, .shift])
    let incognito = await Harness.wait(for: 30) {
      browser.ui.windows.containing(.any, identifier: "clair.sidebar").count >= 2
    }
    XCTAssertTrue(incognito, "The incognito window isn't native")
    XCTAssertTrue(
      browser.ui.staticTexts["Incognito"].waitForExistence(timeout: 10), "The incognito window doesn't say so")
    browser.ui.typeKey(.escape, modifierFlags: [])
    if let window = browser.nativeWindows.first(where: { $0.frame != regular?.frame }) {
      let own = await window.waitForTabs { $0.count == 1 }
      XCTAssertTrue(own, "The incognito window lists other windows' tabs: \(window.tabTitles)")
      XCTAssertFalse(
        window.tabTitles.contains("Clair runtime test page"), "The incognito window lists a regular tab")
    } else {
      XCTFail("Can't find the incognito window")
    }
    browser.ui.typeKey("w", modifierFlags: [.command, .shift])

    // A pop-up keeps Chromium's window.
    let windowsBefore = browser.ui.windows.count
    _ = try await tab.evaluate("window.open('index.html?popup', 'popup', 'popup,width=420,height=320'); 1")
    let popup = await Harness.wait(for: 30) { browser.ui.windows.count > windowsBefore }
    try require(popup, "The pop-up didn't open")
    let native = browser.ui.windows.containing(.any, identifier: "clair.sidebar").count
    XCTAssertEqual(native, 1, "The pop-up opened in a native window")
  }

  /// The window's anatomy: the window controls at Arc's place, and the
  /// toolbar across the card's top with its controls at Arc's places
  /// (add-page-toolbar), before and after a title change
  /// (place-traffic-lights-with-appkit); selecting a row shows its page in the
  /// card; the row's favicon, speaker and title sit where they were checked
  /// against Arc (design D12, D18); and the page follows the card's size.
  ///
  /// Accessibility reports what's drawn, not the layout's frames: on the audio
  /// page, which has no favicon, the favicon is the 13 pt globe glyph centred
  /// in its 18 pt frame 9 pt into the pill, so it reads 12 pt in, with the
  /// title 10 pt after it. While the tab plays sound, the speaker sits between
  /// them with the same visible gap on each side as the title has from the
  /// favicon without it, which reads 7 pt before the speaker's reported frame
  /// and 5.5 pt after it.
  func testBrowserWindowLayout() async throws {
    let (browser, audio) = try await startWithPage("audio.html")
    let second = try await browser.open(url("index.html?second"))
    defer {
      audio.close()
      second.close()
    }

    // The window controls and the toolbar.
    let listed = await browser.waitForTabs { $0.count >= 2 }
    try require(listed, "The sidebar doesn't list both tabs: \(browser.tabTitles)")
    browser.checkToolbar("at first")
    _ = try await second.evaluate("document.title = 'A different title'; 1")
    let retitled = await browser.waitForTabs { $0.contains("A different title") }
    try require(retitled, "The page's new title didn't reach the sidebar")
    // Give AppKit's title bar a moment to lay out for the new window title.
    try await Task.sleep(for: .seconds(1))
    browser.checkToolbar("after a title change")

    // The newest tab is at the top; selecting the row below shows its page.
    XCTAssertEqual(browser.tabTitles.first, "A different title", "The newest tab isn't at the top")
    guard let row = browser.tabRows.first(where: { $0.label == "Clair runtime audio page" }) else {
      throw HarnessError("No row for the audio page: \(browser.tabTitles)")
    }
    row.click()
    let switched = await Harness.wait(for: 15) { try await browser.visibility(of: audio) == "visible" }
    XCTAssertTrue(switched, "Selecting the tab didn't show its page")
    let hidden = try await browser.visibility(of: second)
    XCTAssertEqual(hidden, "hidden", "The previous page isn't hidden")

    // The row's favicon and title, without sound.
    let favicon = browser.element("clair.tabFavicon", in: row)
    let title = browser.element("clair.tabTitle", in: row)
    try require(favicon.waitForExistence(timeout: 10) && title.exists, "The row shows no favicon or title")
    XCTAssertEqual(favicon.frame.minX - row.frame.minX, 12, accuracy: 1, "The favicon's inset in the pill")
    XCTAssertEqual(favicon.frame.width, 13, accuracy: 1, "The favicon's width")
    XCTAssertEqual(title.frame.minX - favicon.frame.maxX, 10, accuracy: 1, "The gap between favicon and title")

    // With sound: the speaker sits between them with even gaps.
    let state = try await audio.evaluate("startTone()") as? String
    try require(state == "running", "The test tone didn't start")
    let speaker = browser.element("clair.tabSpeaker", in: row)
    let shown = await Harness.wait(for: 15) { speaker.exists && speaker.frame.width > 10 }
    try require(shown, "The playing tab shows no speaker")
    try await Task.sleep(for: .milliseconds(500))
    XCTAssertEqual(speaker.frame.minX - favicon.frame.maxX, 7, accuracy: 1, "The gap between favicon and speaker")
    XCTAssertEqual(title.frame.minX - speaker.frame.maxX, 5.5, accuracy: 1, "The gap between speaker and title")
    XCTAssertEqual(favicon.frame.minX - row.frame.minX, 12, accuracy: 1, "The favicon moved when the speaker showed")
    _ = try await audio.evaluate("stopTone()")

    // The page follows the card's size.
    let session = try await browser.browserSession()
    defer { session.close() }
    let targetID = try await audio.targetID(in: browser) ?? ""
    let window = try await session.send("Browser.getWindowForTarget", ["targetId": targetID])
    let windowID = window["windowId"] as? Int ?? 0
    try await session.send(
      "Browser.setWindowBounds", ["windowId": windowID, "bounds": ["width": 900, "height": 600]])
    let resized = await Harness.wait(for: 15) {
      let width = try await audio.innerWidth
      return abs(width - Double(browser.card.frame.width)) <= 2
    }
    XCTAssertTrue(resized, "The page's viewport doesn't match the card after a resize")
    // The page starts below the toolbar.
    let height = try await audio.evaluate("innerHeight") as? Double ?? 0
    XCTAssertEqual(
      height, Double(browser.card.frame.height) - 32, accuracy: 2, "The page's viewport doesn't start below the toolbar")
  }

  /// With the toolbar off, the sidebar's top row holds the browser controls,
  /// lined up with the window controls (place-traffic-lights-with-appkit),
  /// and the page fills the card.
  func testBrowserWindowLayoutWithoutTheToolbar() async throws {
    try Harness.setShowsToolbar(false)
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    let listed = await browser.waitForTabs { !$0.isEmpty }
    try require(listed, "The sidebar lists no tab")
    browser.checkTopRow("without the toolbar")
    XCTAssertFalse(browser.element("clair.toolbar").exists, "The window shows the toolbar")
    XCTAssertTrue(
      browser.element("clair.urlField", in: browser.sidebar).exists, "The sidebar has no URL field without the toolbar")
    let height = try await tab.evaluate("innerHeight") as? Double ?? 0
    XCTAssertEqual(height, Double(browser.card.frame.height), accuracy: 2, "The page doesn't fill the card")
  }
}

extension Browser {
  var windowControls: (close: XCUIElement, zoom: XCUIElement) {
    let close = nativeWindow.buttons[XCUIIdentifierCloseWindow]
    // A window that can go full screen has a full-screen button for zoom.
    let fullScreen = nativeWindow.buttons[XCUIIdentifierFullScreenWindow]
    return (close, fullScreen.exists ? fullScreen : nativeWindow.buttons[XCUIIdentifierZoomWindow])
  }

  /// The window controls at Arc's place from the sidebar's top-leading
  /// corner.
  func checkWindowControls(_ when: String) {
    let sidebar = sidebar.frame
    let (close, zoom) = windowControls
    guard close.exists, zoom.exists else {
      XCTFail("The window controls are missing \(when)")
      return
    }
    XCTAssertEqual(close.frame.minX - sidebar.minX, 12, accuracy: 1.5, "The close button's x \(when)")
    XCTAssertEqual(close.frame.minY - sidebar.minY, 16, accuracy: 1.5, "The close button's y \(when)")
  }

  /// The sidebar's top row with the toolbar off: centred on the window
  /// controls, after the zoom button.
  func checkTopRow(_ when: String) {
    checkWindowControls(when)
    let (close, zoom) = windowControls
    let hideSidebar = element("clair.hideSidebar", in: sidebar)
    guard close.exists, hideSidebar.exists else {
      XCTFail("The sidebar has no hide-sidebar button \(when)")
      return
    }
    XCTAssertEqual(hideSidebar.frame.midY, close.frame.midY, accuracy: 1, "The top row isn't centred on the window controls \(when)")
    XCTAssertGreaterThanOrEqual(hideSidebar.frame.minX, zoom.frame.maxX, "The hide-sidebar button overlaps the zoom button \(when)")
  }

  /// The toolbar across the card's top, 32 pt tall, with the sidebar toggle,
  /// back, forward and reload at Arc's places from the card's leading edge,
  /// the site controls 21 pt from its trailing edge, and the host centred;
  /// the sidebar keeps only the window controls (add-page-toolbar).
  func checkToolbar(_ when: String) {
    checkWindowControls(when)
    let toolbar = element("clair.toolbar")
    guard toolbar.exists else {
      XCTFail("The window shows no toolbar \(when)")
      return
    }
    let card = card.frame
    XCTAssertEqual(toolbar.frame.minX, card.minX, accuracy: 1, "The toolbar's leading edge \(when)")
    XCTAssertEqual(toolbar.frame.minY, card.minY, accuracy: 1, "The toolbar's top \(when)")
    XCTAssertEqual(toolbar.frame.width, card.width, accuracy: 1, "The toolbar's width \(when)")
    XCTAssertEqual(toolbar.frame.height, 32, accuracy: 1, "The toolbar's height \(when)")
    for (identifier, x) in [
      ("clair.hideSidebar", 21.0), ("clair.back", 57.75), ("clair.forward", 94.75), ("clair.reload", 132),
    ] {
      let control = element(identifier, in: toolbar)
      guard control.exists else {
        XCTFail("The toolbar has no \(identifier) \(when)")
        continue
      }
      XCTAssertEqual(control.frame.midX - card.minX, x, accuracy: 1, "\(identifier)'s place in the toolbar \(when)")
      XCTAssertEqual(control.frame.midY - card.minY, 16, accuracy: 1, "\(identifier) isn't centred in the toolbar \(when)")
    }
    // The split button takes the trailing slot, and site controls the next
    // (add-split-view D9).
    let splitButton = element("clair.splitButton", in: toolbar)
    XCTAssertTrue(splitButton.exists, "The toolbar has no split button \(when)")
    if splitButton.exists {
      XCTAssertEqual(card.maxX - splitButton.frame.midX, 21, accuracy: 1, "The split button's place \(when)")
    }
    let siteControls = element("clair.siteControls", in: toolbar)
    XCTAssertTrue(siteControls.exists, "The toolbar has no site controls \(when)")
    if siteControls.exists {
      XCTAssertEqual(card.maxX - siteControls.frame.midX, 57, accuracy: 1, "The site controls' place \(when)")
    }
    let host = element("clair.urlField", in: toolbar)
    XCTAssertTrue(host.exists, "The toolbar has no host \(when)")
    if host.exists {
      XCTAssertEqual(host.frame.midX, card.midX, accuracy: 1, "The host isn't centred on the card \(when)")
    }
    XCTAssertFalse(element("clair.urlField", in: sidebar).exists, "The sidebar still has a URL field \(when)")
    XCTAssertFalse(element("clair.hideSidebar", in: sidebar).exists, "The sidebar still has a toggle \(when)")
  }
}

/// DevTools docked in the card (task 4.3).
@MainActor
final class DockedDevToolsTests: NativeWindowTestCase {
  func testDevToolsDocksInTheCardAndUndocks() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    let full = try await tab.innerWidth
    browser.cardPoint(0.5, 0.5).click()
    browser.ui.typeKey("i", modifierFlags: [.command, .option])
    let docked = await Harness.wait(for: 30) {
      try await tab.innerWidth < full - 200
    }
    XCTAssertTrue(docked, "DevTools didn't narrow the page")
    let windows = browser.ui.windows.count
    XCTAssertEqual(
      browser.ui.windows.containing(.any, identifier: "clair.sidebar").count, windows,
      "DevTools opened in a window of its own")

    // Undocked, it moves to its own window and the page fills the card again.
    browser.ui.typeKey("d", modifierFlags: [.command, .shift])
    let undocked = await Harness.wait(for: 30) {
      abs(try await tab.innerWidth - full) <= 2
    }
    XCTAssertTrue(undocked, "Undocking didn't give the page its width back")
  }
}

/// Page full screen (task 4.4).
@MainActor
final class FullscreenTests: NativeWindowTestCase {
  func testPageFullscreenFillsTheScreenAndEndsWithEscape() async throws {
    let (browser, tab) = try await startWithPage("fullscreen.html")
    defer { tab.close() }
    let entered = try await tab.evaluate("enter()") as? String
    try require(entered == "entered", "The page couldn't enter full screen")
    let screen = NSScreen.main?.frame.size ?? .zero
    let filled = await Harness.wait(for: 30) {
      let width = try await tab.evaluate("innerWidth") as? Double ?? 0
      return abs(width - Double(screen.width)) <= 2
    }
    XCTAssertTrue(filled, "The page doesn't fill the screen")
    XCTAssertFalse(browser.isSidebarInWindow, "The sidebar shows in page full screen")
    // The notice appears once the window has finished moving into full screen.
    // The window hides its sidebar now, so look for it in the whole app.
    let notice = browser.ui.descendants(matching: .any).matching(identifier: "clair.fullscreenNotice").firstMatch
    XCTAssertTrue(notice.waitForExistence(timeout: 15), "No notice says how to leave full screen")
    browser.ui.typeKey(.escape, modifierFlags: [])
    let ended = await Harness.wait(for: 30) {
      try await tab.evaluate("document.fullscreenElement === null") as? Bool == true
    }
    XCTAssertTrue(ended, "Esc didn't end page full screen")
    let back = await Harness.wait(for: 30) { browser.isSidebarInWindow }
    XCTAssertTrue(back, "The sidebar didn't come back")
  }
}

/// The top row's back and forward buttons (task 5.1), and the back button's
/// history menu (arc-navigation-feedback task 4.2).
@MainActor
final class NavigationTests: NativeWindowTestCase {
  func testBackForwardAndTheBackMenu() async throws {
    let (browser, tab) = try await startWithPage("link.html")
    defer { tab.close() }
    try await tab.navigate(to: url("index.html?second"))
    try await tab.navigate(to: url("find.html"))
    let back = browser.element("clair.back")
    let forward = browser.element("clair.forward")
    let enabled = await Harness.wait(for: 15) { back.isEnabled }
    try require(enabled, "Back isn't available after a navigation")
    back.click()
    let wentBack = await Harness.wait(for: 15) {
      try await tab.evaluate("location.search") as? String == "?second"
    }
    XCTAssertTrue(wentBack, "Back didn't return to the previous page")
    let forwardEnabled = await Harness.wait(for: 15) { forward.isEnabled }
    XCTAssertTrue(forwardEnabled, "Forward isn't available after going back")
    forward.click()
    let wentForward = await Harness.wait(for: 15) {
      (try await tab.evaluate("location.pathname") as? String)?.hasSuffix("find.html") == true
    }
    try require(wentForward, "Forward didn't go to the next page")

    // The back menu lists the history session's pages, nearest first.
    back.rightClick()
    // The back menu, not the menu bar's History menu, which lists the same
    // pages: the toolbar's, in the card, by default.
    let menu = browser.nativeWindow.descendants(matching: .menu).firstMatch
    try require(menu.waitForExistence(timeout: 10), "Right-clicking back opened no menu")
    let first = menu.menuItems["Clair link page"]
    try require(first.waitForExistence(timeout: 10), "The back menu doesn't list the first page")
    let second = menu.menuItems["Clair runtime test page"]
    XCTAssertTrue(second.exists, "The back menu doesn't list the second page")
    if second.exists {
      XCTAssertLessThan(second.frame.minY, first.frame.minY, "The back menu isn't nearest first")
    }
    first.click()
    let wentToFirst = await Harness.wait(for: 15) {
      (try await tab.evaluate("location.pathname") as? String)?.hasSuffix("link.html") == true
    }
    XCTAssertTrue(wentToFirst, "Choosing the first page didn't go there")
    let forwardAgain = await Harness.wait(for: 15) { forward.isEnabled }
    XCTAssertTrue(forwardAgain, "Forward isn't available after going back through the menu")
  }
}

/// Permission prompts attached to the sidebar or the card's corner (task 5.2).
@MainActor
final class PermissionPromptTests: NativeWindowTestCase {
  private func ask(_ browser: Browser, _ tab: DevToolsSession, choose button: String, expect result: String) async throws {
    _ = try await tab.evaluate("ask(); 1")
    let choice = browser.ui.buttons[button]
    try require(choice.waitForExistence(timeout: 20), "No permission prompt with \(button)")
    if let screen = NSScreen.main?.frame {
      XCTAssertTrue(
        screen.contains(choice.frame), "The prompt's \(button) button is off screen at \(choice.frame)")
    }
    choice.click()
    let answered = await Harness.wait(for: 15) {
      try await tab.evaluate("window.permissionResult") as? String == result
    }
    XCTAssertTrue(answered, "Choosing \(button) didn't give \(result)")
  }

  /// The prompt stays on screen with the sidebar shown and hidden (#93). The
  /// second prompt comes from another origin, which hasn't been asked.
  func testPromptWithTheSidebarShownAndHidden() async throws {
    let (browser, tab) = try await startWithPage("notify.html")
    defer { tab.close() }
    try await ask(browser, tab, choose: "Allow", expect: "granted")

    let port = URL(string: fixture.baseURL)?.port ?? 80
    let other = try await browser.open("http://127.0.0.1:\(port)/pages/notify.html")
    defer { other.close() }
    browser.ui.typeKey("s", modifierFlags: .command)
    let hidden = await Harness.wait(for: 10) { !browser.isSidebarInWindow }
    try require(hidden, "Cmd+S didn't hide the sidebar")
    try await ask(browser, other, choose: "Block", expect: "denied")
  }
}

/// An extension action's popup (task 5.3).
@MainActor
final class ExtensionActionTests: NativeWindowTestCase {
  /// The popup opens from the action's pinned button, from the Extensions menu,
  /// and from the background script.
  func testOpeningAPopup() async throws {
    let extensionPath = Fixture.directory.appending(path: "extensions/popup-badge").path
    let (browser, tab) = try await startWithPage(arguments: ["--load-extension=\(extensionPath)"])
    defer { tab.close() }
    let pinned = try browser.pinExtensionFromSiteControls()
    let badge = await Harness.wait(for: 15) { (pinned.value as? String) == "3" }
    XCTAssertTrue(badge, "The pinned action doesn't show its badge")
    // The button keeps its action's title, not the extension's name
    // (label-extensions-by-name task 3.1).
    XCTAssertEqual(pinned.label, "3 badges for this page", "The pinned action's VoiceOver label isn't its title")
    pinned.click()
    let popup = browser.ui.dialogs["clair.extensionPopup"]
    XCTAssertTrue(popup.waitForExistence(timeout: 15), "The action's popup didn't open")
    let session = try await browser.browserSession()
    defer { session.close() }
    let targets = try await session.send("Target.getTargets")
    let infos = targets["targetInfos"] as? [[String: Any]] ?? []
    XCTAssertTrue(
      infos.contains { ($0["url"] as? String)?.hasSuffix("/popup.html") == true },
      "No popup page is loaded")
    let close = popup.buttons[XCUIIdentifierCloseWindow]
    try require(close.waitForExistence(timeout: 10), "The popup window has no close button")
    XCTAssertTrue(close.isEnabled, "The popup window's close button is disabled")
    close.click()
    let closed = await Harness.wait(for: 15) { !popup.exists }
    try require(closed, "The close button didn't close the popup")

    // The Extensions menu.
    let menu = browser.ui.menuBars.menuBarItems["Extensions"]
    try require(menu.waitForExistence(timeout: 30), "The menu bar has no Extensions menu")
    // The menu lists what the window has when it opens, and the extension may
    // still be loading: open it again until it's there. It lists the extension
    // by its name, not its action's title (label-extensions-by-name task 3.1).
    let item = browser.ui.menuItems["Clair Test Action"]
    var listed = false
    for _ in 0..<5 where !listed {
      menu.click()
      listed = item.waitForExistence(timeout: 3)
      if !listed {
        browser.ui.typeKey(.escape, modifierFlags: [])
      }
    }
    try require(listed, "The Extensions menu doesn't list the extension")
    XCTAssertTrue(browser.ui.menuItems["Manage Extensions…"].exists, "The Extensions menu has no Manage Extensions…")
    item.click()
    XCTAssertTrue(popup.waitForExistence(timeout: 15), "Choosing the extension didn't open its popup")
    if close.waitForExistence(timeout: 5) {
      close.click()
    }
    let closedAgain = await Harness.wait(for: 15) { !popup.exists }
    try require(closedAgain, "The popup from the Extensions menu didn't close")

    // The background script.
    let worker = try await extensionWorker(browser, named: "Clair Test Action")
    defer { worker.close() }
    _ = try await worker.evaluate("chrome.action.openPopup()")
    XCTAssertTrue(popup.waitForExistence(timeout: 15), "chrome.action.openPopup() didn't open the popup")
  }

  /// A popup that closes its own window while it loads goes with the window,
  /// and the browser keeps running.
  func testPopupThatClosesItsWindowWhileLoading() async throws {
    let extensionPath = Fixture.directory.appending(path: "extensions/popup-closes-window").path
    let (browser, tab) = try await startWithPage(arguments: ["--load-extension=\(extensionPath)"])
    defer { tab.close() }
    let worker = try await extensionWorker(browser, named: "Clair Test Closing Popup")
    defer { worker.close() }
    let windowCount = "chrome.windows.getAll().then(all => all.length)"
    let before = try await worker.evaluate(windowCount) as? Int
    // The page's close request and the end of its first load reach the browser
    // back to back; a few rounds make sure that order comes up.
    for round in 1...5 {
      let result = try await worker.evaluate(
        """
        (async () => {
          const opened = await chrome.windows.create({url: 'about:blank', focused: true});
          await chrome.action.setPopup({popup: 'popup.html?window=' + opened.id});
          // A new window takes a moment to become the active one.
          for (let attempt = 0; attempt < 50; attempt++) {
            try {
              await chrome.action.openPopup({windowId: opened.id});
              return 'shown';
            } catch (error) {
              if (!error.message.includes('inactive window')) {
                return error.message;
              }
            }
            await new Promise(resolve => setTimeout(resolve, 100));
          }
          return 'never active';
        })()
        """) as? String
      XCTAssertEqual(result, "Failed to open popup.", "Round \(round): the popup outlived its window")
      let closed = await Harness.wait(for: 15) {
        try await worker.evaluate(windowCount) as? Int == before
      }
      try require(closed, "Round \(round): the popup didn't close its window")
      XCTAssertNotNil(try browser.runningProcessID(), "Round \(round): Clair quit")
    }
    let answer = try await tab.evaluate("1 + 1") as? Int
    XCTAssertEqual(answer, 2, "The first window's tab stopped answering")
  }
}

/// The downloads button and list (task 5.4).
@MainActor
final class DownloadsTests: NativeWindowTestCase {
  func testDownloadsButtonShowsProgressAndUnseenDownloads() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    let folder = browser.workDirectory.appending(path: "downloads")
    let downloads = try await browser.allowDownloads(to: folder)
    defer { downloads.close() }

    // The progress is the whole app's, as on the Dock: an incognito window,
    // another profile, shows the regular window's download too.
    browser.ui.typeKey("n", modifierFlags: [.command, .shift])
    let opened = await Harness.wait(for: 30) {
      browser.ui.windows.containing(.any, identifier: "clair.sidebar").count >= 2
    }
    try require(opened, "No incognito window opened")
    // The one with the "Incognito" badge, found as testWhichWindowsAreNative
    // finds it.
    let incognito = browser.ui.windows.containing(.staticText, identifier: "Incognito").firstMatch
    try require(incognito.waitForExistence(timeout: 10), "The new window has no incognito badge")
    _ = try await tab.evaluate("location.href = '/slow-download'; 1")
    let incognitoButton = browser.element("clair.downloads", in: incognito)
    let shared = await Harness.wait(for: 30) { (incognitoButton.value as? String)?.hasSuffix("%") == true }
    XCTAssertTrue(shared, "The incognito window doesn't show the other profile's download")
    browser.ui.typeKey("w", modifierFlags: [.command, .shift])
    let closed = await Harness.wait(for: 15) {
      browser.ui.windows.containing(.any, identifier: "clair.sidebar").count == 1
    }
    try require(closed, "The incognito window didn't close")

    let button = browser.element("clair.downloads")
    try require(button.waitForExistence(timeout: 30), "No downloads button appeared")
    let progress = await Harness.wait(for: 30) { (button.value as? String)?.hasSuffix("%") == true }
    XCTAssertTrue(progress, "The downloads button shows no progress")
    _ = try await URLSession.shared.data(from: URL(string: "\(fixture.baseURL)/slow-download/finish")!)

    // The button's mark for an unseen download is part of the button, which
    // says "New" as its value.
    let unseen = await Harness.wait(for: 30) { (button.value as? String) == "New" }
    XCTAssertTrue(unseen, "The finished download isn't marked")
    button.click()
    let row = browser.ui.descendants(matching: .any).matching(identifier: "clair.downloadRow").firstMatch
    try require(row.waitForExistence(timeout: 10), "The downloads list is empty")
    row.click()
    let seen = await Harness.wait(for: 15) { (button.value as? String) != "New" }
    XCTAssertTrue(seen, "Opening the download didn't clear its mark")
    _ = try? Harness.run("/usr/bin/pkill", ["-x", "TextEdit"])
  }
}

/// The tab list and where new tabs go (task 5.5).
@MainActor
final class TabListTests: NativeWindowTestCase {
  func testSelectingClosingNewTabsAndReordering() async throws {
    let browser = try await startBrowser()
    var tabs: [DevToolsSession] = []
    for index in 1...5 {
      tabs.append(try await browser.open(url("index.html?\(index)")))
    }
    defer { tabs.forEach { $0.close() } }
    browser.ui.activate()
    let five = await browser.waitForTabs { $0.filter { $0 == "Clair runtime test page" }.count >= 5 }
    try require(five, "The sidebar doesn't list five tabs: \(browser.tabTitles)")
    let count = browser.tabRows.count

    // Selecting: the newest tab is at the top, so the third row is tab 3.
    browser.tabRows[2].click()
    let selected = await Harness.wait(for: 15) { try await browser.visibility(of: tabs[2]) == "visible" }
    XCTAssertTrue(selected, "Clicking a row didn't select its tab")

    // A link Cmd-clicked in that tab opens at the top, in the background.
    try await tabs[2].navigate(to: url("link.html"))
    // A real click: Chromium opens a scripted click's background tab in the
    // foreground, so a page can't open tabs behind the user.
    let center =
      try await tabs[2].evaluate(
        "(() => { const r = document.getElementById('link').getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; })()"
      ) as? [Double] ?? [0, 0]
    for type in ["mousePressed", "mouseReleased"] {
      // Modifier 4 is Meta, the Command key.
      try await tabs[2].send(
        "Input.dispatchMouseEvent",
        ["type": type, "x": center[0], "y": center[1], "button": "left", "clickCount": 1, "modifiers": 4])
    }
    let opened = await browser.waitForTabs { $0.count == count + 1 }
    try require(opened, "The Cmd-clicked link opened no tab")
    let linked = try await browser.pageTargets().first { $0.url.hasSuffix("?linked") }
    let rowsNow = browser.tabRows
    XCTAssertEqual(rowsNow.first?.label, "Clair runtime test page", "The new tab isn't first")
    XCTAssertNotNil(linked, "No tab shows the linked page")
    let stillActive = try await browser.visibility(of: tabs[2])
    XCTAssertEqual(stillActive, "visible", "The link's tab didn't stay active")

    // Closing with the row's button.
    let row = browser.tabRows[1]
    row.hover()
    let close = browser.element("clair.tabClose", in: row)
    try require(close.waitForExistence(timeout: 10), "Hovering a row shows no close button")
    close.click()
    let closed = await browser.waitForTabs { $0.count == count }
    XCTAssertTrue(closed, "The close button didn't close the tab")

    // Dragging the third row above the first makes it tab 1.
    let rows = browser.tabRows
    let moving = rows[2]
    moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(forDuration: 0.4, thenDragTo: rows[0].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
    try await Task.sleep(for: .seconds(1))
    browser.ui.typeKey("1", modifierFlags: .command)
    let first = browser.tabRows.first
    let isFirstSelected = await Harness.wait(for: 15) { first?.isSelected == true }
    XCTAssertTrue(isFirstSelected, "Cmd+1 didn't select the tab dragged to the top")
  }
}

/// Hiding, revealing and Save Page As (task 5.6).
@MainActor
final class SidebarHidingTests: NativeWindowTestCase {
  /// Cmd+S hides the sidebar without saving the page, resting at the leading
  /// edge reveals it over the page without resizing the page (#93), Cmd+S
  /// brings it back, and Shift+Cmd+S saves.
  func testHidingAndRevealingTheSidebar() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    let window = browser.nativeWindow.frame
    browser.cardPoint(0.5, 0.5).click()
    browser.ui.typeKey("s", modifierFlags: .command)
    let hidden = await Harness.wait(for: 10) {
      abs(browser.card.frame.minX - window.minX - 10) <= 2 && !browser.isSidebarInWindow
    }
    try require(hidden, "Cmd+S didn't hide the sidebar and widen the card")
    try await Task.sleep(for: .seconds(1))
    XCTAssertFalse(browser.ui.sheets.firstMatch.exists, "Cmd+S opened a save panel")

    let width = try await tab.innerWidth
    browser.nativeWindow.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
      .withOffset(CGVector(dx: 2, dy: 0)).hover()
    let revealed = await Harness.wait(for: 10) { browser.isSidebarInWindow }
    XCTAssertTrue(revealed, "Resting at the leading edge didn't reveal the sidebar")
    let after = try await tab.innerWidth
    XCTAssertEqual(after, width, accuracy: 1, "Revealing the sidebar resized the page")
    // Leave the edge, so the revealed sidebar slides away again.
    browser.cardPoint(0.5, 0.5).hover()
    _ = await Harness.wait(for: 5) { !browser.isSidebarInWindow }

    browser.ui.typeKey("s", modifierFlags: .command)
    let shown = await Harness.wait(for: 10) {
      abs(browser.card.frame.minX - browser.sidebar.frame.maxX) <= 2 && browser.isSidebarInWindow
    }
    XCTAssertTrue(shown, "Cmd+S didn't bring the sidebar back")

    browser.cardPoint(0.5, 0.5).click()
    browser.ui.typeKey("s", modifierFlags: [.command, .shift])
    let saving =
      browser.ui.sheets.firstMatch.waitForExistence(timeout: 10)
      || browser.ui.dialogs.firstMatch.waitForExistence(timeout: 5)
    XCTAssertTrue(saving, "Shift+Cmd+S opened no save panel")
    browser.ui.typeKey(.escape, modifierFlags: [])
  }
}

/// The command bar (task 6.2).
@MainActor
final class CommandBarTests: NativeWindowTestCase {
  private func openCommandBar(_ browser: Browser, _ key: String) throws -> XCUIElement {
    browser.ui.typeKey(key, modifierFlags: .command)
    let field = browser.element("clair.commandBarField")
    try require(field.waitForExistence(timeout: 10), "Cmd+\(key.uppercased()) didn't open the command bar")
    return field
  }

  /// Cmd+T opens a typed URL as the first, active row; Cmd+L navigates the
  /// current tab; a Switch to Tab suggestion activates the open tab.
  func testOpeningURLsAndSwitchingTabs() async throws {
    let (browser, first) = try await startWithPage("index.html?open")
    defer { first.close() }
    let count = browser.tabRows.count
    let typed = try openCommandBar(browser, "t")
    typed.typeText(url("index.html?typed") + "\n")
    let opened = await Harness.wait(for: 15) {
      try await browser.pageTargets().contains { $0.url.hasSuffix("?typed") }
    }
    try require(opened, "The typed URL didn't open")
    let listed = await browser.waitForTabs { $0.count == count + 1 }
    XCTAssertTrue(listed, "The new tab isn't in the sidebar")
    XCTAssertTrue(browser.tabRows.first?.isSelected == true, "The new tab isn't first and active")

    let tabs = try await browser.pageTargets().count
    let edited = try openCommandBar(browser, "l")
    edited.typeKey("a", modifierFlags: .command)
    edited.typeText(url("index.html?edited") + "\n")
    let navigated = await Harness.wait(for: 15) {
      let urls = try await browser.pageTargets().map(\.url)
      return urls.contains { $0.hasSuffix("?edited") } && !urls.contains { $0.hasSuffix("?typed") }
    }
    XCTAssertTrue(navigated, "Cmd+L didn't navigate the current tab")
    let afterEdit = try await browser.pageTargets().count
    XCTAssertEqual(afterEdit, tabs, "Cmd+L created a tab")

    let field = try openCommandBar(browser, "t")
    field.typeText(url("index.html?open"))
    let row = browser.ui.descendants(matching: .any).matching(
      NSPredicate(format: "identifier == 'clair.suggestion' AND label CONTAINS 'Switch to Tab'")
    ).firstMatch
    try require(row.waitForExistence(timeout: 15), "No Switch to Tab suggestion")
    row.click()
    let switched = await Harness.wait(for: 15) { try await browser.visibility(of: first) == "visible" }
    XCTAssertTrue(switched, "Choosing Switch to Tab didn't activate the open tab")
    let afterSwitch = try await browser.pageTargets().count
    XCTAssertEqual(afterSwitch, tabs, "Switch to Tab created a tab")
  }

  /// A visited page's row shows its favicon (command-bar spec, "Favicon").
  /// The page's favicon is a magenta square, which no kind's icon or row
  /// background is.
  func testRowsShowFavicons() async throws {
    let (browser, tab) = try await startWithPage("favicon.html")
    defer { tab.close() }
    // The favicon reaches the database some time after the page loads, so
    // reopen the bar until the row shows it.
    let shown = await Harness.wait(for: 30) {
      let field = try self.openCommandBar(browser, "t")
      defer { browser.ui.typeKey(.escape, modifierFlags: []) }
      field.typeText("favicon.html")
      // A history row reads as the page's title.
      let row = browser.ui.descendants(matching: .any).matching(
        NSPredicate(format: "identifier == 'clair.suggestion' AND label BEGINSWITH 'Clair favicon test page'")
      ).firstMatch
      guard row.waitForExistence(timeout: 10) else { return false }
      return await Harness.wait(for: 3) { Self.showsMagenta(row.screenshot().image, within: 40) }
    }
    XCTAssertTrue(shown, "The row doesn't show the page's favicon")
  }

  /// Whether the leading `width` points of `image` have a patch of magenta.
  private static func showsMagenta(_ image: NSImage, within width: CGFloat) -> Bool {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let bitmap = NSBitmapImageRep(cgImage: cgImage).converting(to: .sRGB, renderingIntent: .default)
    else {
      return false
    }
    let scale = CGFloat(bitmap.pixelsWide) / image.size.width
    var count = 0
    for x in 0..<min(bitmap.pixelsWide, Int(width * scale)) {
      for y in 0..<bitmap.pixelsHigh {
        guard let color = bitmap.colorAt(x: x, y: y) else { continue }
        if color.redComponent > 0.8, color.blueComponent > 0.8, color.greenComponent < 0.25 {
          count += 1
        }
      }
    }
    // At least a 6 pt square's worth, so stray antialiasing doesn't count.
    return CGFloat(count) >= 36 * scale * scale
  }
}

/// Turning the toolbar on and off (add-page-toolbar task 5.3).
@MainActor
final class ToolbarTests: NativeWindowTestCase {
  /// Every native window, by its frame (SharedTabsTests' `NativeWindow`).
  private func windows(_ browser: Browser) -> [XCUIElement] {
    browser.ui.windows.containing(.any, identifier: "clair.sidebar").allElementsBoundByIndex
  }

  private func toolbarShows(in window: XCUIElement) -> Bool {
    window.descendants(matching: .any).matching(identifier: "clair.toolbar").firstMatch.exists
  }

  private func sidebarHasURLField(in window: XCUIElement) -> Bool {
    let sidebar = window.descendants(matching: .any).matching(identifier: "clair.sidebar").firstMatch
    return sidebar.descendants(matching: .any).matching(identifier: "clair.urlField").firstMatch.exists
  }

  /// Waits until every native window shows the toolbar, or none does with
  /// the sidebar's URL field back.
  private func waitForToolbar(_ shown: Bool, in browser: Browser) async -> Bool {
    await Harness.wait(for: 10) {
      let all = self.windows(browser)
      return all.count >= 2
        && all.allSatisfy { self.toolbarShows(in: $0) == shown && self.sidebarHasURLField(in: $0) == !shown }
    }
  }

  /// Shift+Cmd+D hides the toolbar in both windows and opens no bookmark UI;
  /// View's item then reads Show Toolbar, and the keys bring it back.
  func testShiftCmdDTogglesTheToolbarInEveryWindow() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    let other = try await browser.open(url("index.html?second"), newWindow: true)
    defer { other.close() }
    let both = await waitForToolbar(true, in: browser)
    try require(both, "Two windows don't both show the toolbar")
    let windowCount = browser.ui.windows.count

    browser.cardPoint(0.5, 0.5).click()
    browser.ui.typeKey("d", modifierFlags: [.command, .shift])
    let hidden = await waitForToolbar(false, in: browser)
    XCTAssertTrue(hidden, "Shift+Cmd+D didn't move the controls into every window's sidebar")
    try await Task.sleep(for: .seconds(1))
    XCTAssertEqual(browser.ui.windows.count, windowCount, "Shift+Cmd+D opened a window")
    XCTAssertFalse(browser.ui.sheets.firstMatch.exists, "Shift+Cmd+D opened a sheet")
    XCTAssertFalse(browser.ui.dialogs.firstMatch.exists, "Shift+Cmd+D opened a bookmark dialog")

    browser.ui.menuBars.menuBarItems["View"].click()
    XCTAssertTrue(
      browser.ui.menuBars.menuItems["Show Toolbar"].waitForExistence(timeout: 5), "View doesn't offer Show Toolbar")
    browser.ui.typeKey(.escape, modifierFlags: [])

    browser.ui.typeKey("d", modifierFlags: [.command, .shift])
    let shown = await waitForToolbar(true, in: browser)
    XCTAssertTrue(shown, "Shift+Cmd+D again didn't bring the toolbar back")
  }

  /// Choosing Sidebar on Settings › General moves the controls into the
  /// sidebar of every window, and Toolbar brings them back.
  func testTheLocationBarRowInSettings() async throws {
    let (browser, tab) = try await startWithPage()
    defer { tab.close() }
    let other = try await browser.open(url("index.html?second"), newWindow: true)
    defer { other.close() }
    let both = await waitForToolbar(true, in: browser)
    try require(both, "Two windows don't both show the toolbar")

    browser.ui.typeKey(",", modifierFlags: .command)
    let general = browser.ui.windows["General"]
    try require(general.waitForExistence(timeout: 15), "Settings didn't open on General")
    let row = general.descendants(matching: .any).matching(identifier: "clair.locationBar").firstMatch
    try require(row.waitForExistence(timeout: 10), "General has no Location bar row")
    XCTAssertEqual(row.label, "Location bar", "The row's group isn't labelled Location bar")
    let toolbar = general.descendants(matching: .any).matching(identifier: "clair.locationBar.toolbar").firstMatch
    let sidebar = general.descendants(matching: .any).matching(identifier: "clair.locationBar.sidebar").firstMatch
    XCTAssertTrue(toolbar.isSelected, "Toolbar isn't the chosen layout at first")
    XCTAssertFalse(sidebar.isSelected, "Sidebar is chosen at first")

    _ = await Harness.wait(for: 5) { sidebar.isHittable }
    sidebar.click()
    let moved = await waitForToolbar(false, in: browser)
    XCTAssertTrue(moved, "Choosing Sidebar didn't move the controls into every window's sidebar")
    let chosen = await Harness.wait(for: 5) { sidebar.isSelected && !toolbar.isSelected }
    XCTAssertTrue(chosen, "Sidebar isn't marked chosen")

    // The windows lay out again as the controls move; wait for the row to
    // take clicks.
    _ = await Harness.wait(for: 5) { toolbar.isHittable }
    toolbar.click()
    let back = await waitForToolbar(true, in: browser)
    XCTAssertTrue(back, "Choosing Toolbar didn't bring the toolbar back")
  }
}
