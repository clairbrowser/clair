// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Foundation
import Testing

@testable import ClairUI

/// Running apps as the test says.
@MainActor
final class FakeAppWatcher: ImportAppWatcher {
  var onChange: (() -> Void)?
  var running: Set<String> = []
  private(set) var terminated: [String] = []
  /// Whether the app quits when asked; false as when its own confirmation is
  /// cancelled.
  var quitsWhenAsked = true

  func isRunning(_ bundleID: String) -> Bool { running.contains(bundleID) }

  func terminate(_ bundleID: String) {
    terminated.append(bundleID)
    if quitsWhenAsked {
      running.remove(bundleID)
      onChange?()
    }
  }

  func launch(_ bundleID: String) {
    running.insert(bundleID)
    onChange?()
  }
}

@MainActor
struct ImportFlowTests {
  let host = FakeHost()
  let apps = FakeAppWatcher()

  private func flow(_ fixture: ImportFixture, keychain: any ImportKeychain = FixedKeychain(secret: Data())) -> ImportFlow {
    ImportFlow(host: host, environment: fixture.environment(keychain: keychain), shownProfile: FakeHost.defaultProfileID, apps: apps)
  }

  private func select(_ id: String, in flow: ImportFlow) {
    flow.selectedIndex = flow.sources.firstIndex { $0.id == id }!
  }

  // MARK: Choosing a browser

  @Test func theFirstStepShowsThePresentSourcesWithTheFirstSelected() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    try DiaDatabaseBuilder.write(
      userData: fixture.applicationSupport.appending(path: "Dia/User Data"), profile: "Profile 4", base: [], walOnly: [])
    let flow = flow(fixture)
    #expect(flow.step == .choose)
    #expect(flow.sources.map(\.name) == ["Safari", "Arc", "Dia", "Chrome"])
    #expect(flow.selectedIndex == 0)
    #expect(flow.title == "Import from your old browser")
    #expect(flow.defaultButtonTitle == "Continue")
  }

  @Test func continueAndBackKeepTheSelection() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let flow = flow(fixture)
    select("arc", in: flow)
    flow.continueToDetails()
    #expect(flow.step == .details)
    #expect(flow.title == "Import from Arc")
    #expect(flow.defaultButtonTitle == "Import")
    flow.back()
    #expect(flow.step == .choose)
    #expect(flow.source.id == "arc")
  }

  // MARK: What comes over, and where

  @Test func arcsRowsStartOnTheShownProfileThenNewProfile() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let flow = flow(fixture)
    select("arc", in: flow)
    flow.continueToDetails()
    #expect(flow.source.items == ImportItemKind.allCases)
    #expect(flow.rows.map(\.profile.name) == ["Your Arc", "Work"])
    #expect(flow.rows.map(\.destination) == [.profile(FakeHost.defaultProfileID), .newProfile])
    #expect(flow.profiles.map(\.name) == ["Default"])
    #expect(flow.privacyNote == nil)
  }

  @Test func chromesListAndRows() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let flow = flow(fixture)
    select("chrome", in: flow)
    flow.continueToDetails()
    #expect(flow.source.items.map(\.title) == ["Pinned Tabs", "Today Tabs", "Bookmarks", "History", "Extensions"])
    #expect(flow.rows.map(\.profile.name) == ["Person 1"])
  }

  @Test func diasStepCarriesItsNote() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    try DiaDatabaseBuilder.write(
      userData: fixture.applicationSupport.appending(path: "Dia/User Data"), profile: "Profile 4", base: [], walOnly: [])
    let flow = flow(fixture)
    select("dia", in: flow)
    flow.continueToDetails()
    #expect(flow.privacyNote == ImportFlow.diaNote)
    #expect(flow.rows.map(\.profile.name) == ["Profile 2, Profile 3"])
  }

  // MARK: Quitting the source

  @Test func aRunningSourceAsksToQuitThenImports() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    apps.running = ["company.thebrowser.Browser"]
    let flow = flow(fixture)
    select("arc", in: flow)
    flow.continueToDetails()
    #expect(flow.detailsAction == .quitSource)
    #expect(flow.defaultButtonTitle == "Quit Arc")
    #expect(flow.quitNotice == "Quit Arc to import from it.")
    // Import does nothing while Arc runs.
    flow.startImport()
    #expect(flow.step == .details)
    flow.quitSource()
    #expect(apps.terminated == ["company.thebrowser.Browser"])
    #expect(flow.defaultButtonTitle == "Import")
    #expect(flow.quitNotice == nil)
    // Opened again before Import: it asks again.
    apps.launch("company.thebrowser.Browser")
    #expect(flow.defaultButtonTitle == "Quit Arc")
  }

  @Test func aCancelledQuitKeepsAsking() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    apps.running = ["com.google.Chrome"]
    apps.quitsWhenAsked = false
    let flow = flow(fixture)
    select("chrome", in: flow)
    flow.continueToDetails()
    flow.quitSource()
    #expect(flow.defaultButtonTitle == "Quit Chrome")
  }

  @Test func aSourceNotRunningImports() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let flow = flow(fixture)
    select("chrome", in: flow)
    flow.continueToDetails()
    #expect(flow.defaultButtonTitle == "Import")
  }

  // MARK: Safari's file

  @Test func safariAsksForItsFileAndRefusesAWrongOne() throws {
    let fixture = try ImportFixture(empty: true)
    defer { fixture.remove() }
    apps.running = ["com.apple.Safari"]
    let flow = flow(fixture)
    flow.continueToDetails()
    #expect(flow.source.id == "safari")
    #expect(flow.detailsAction == .chooseFile)
    #expect(flow.defaultButtonTitle == "Choose File…")
    let wrong = fixture.root.appending(path: "notes.txt")
    try Data("hi".utf8).write(to: wrong)
    flow.chooseSafariFile(wrong)
    #expect(flow.safariError == ImportFlow.wrongFile)
    #expect(flow.detailsAction == .chooseFile)
    flow.chooseSafariFile(ImportFixture.safariFolder)
    #expect(flow.safariError == nil)
    // Safari may keep running: its data comes from the file.
    #expect(flow.defaultButtonTitle == "Import")
    #expect(flow.source.items.map(\.title) == ["Bookmarks", "History"])
    #expect(flow.rows.map(\.profile.name) == ["Safari"])
    #expect(flow.rows.map(\.destination) == [.profile(FakeHost.defaultProfileID)])
  }

  @Test func safariImportsTheChosenFile() async throws {
    let fixture = try ImportFixture(empty: true)
    defer { fixture.remove() }
    let flow = flow(fixture)
    flow.continueToDetails()
    flow.chooseSafariFile(ImportFixture.safariFolder)
    flow.startImport()
    #expect(flow.step == .importing)
    await flow.importTask?.value
    #expect(flow.step == .summary)
    let plan = try #require(host.importPlans.first)
    #expect(plan.source == "safari")
    #expect(plan.profiles.first?.destination == .profile(FakeHost.defaultProfileID))
    #expect(plan.profiles.first?.bookmarks?.isEmpty == false)
  }

  // MARK: Importing

  @Test func importingSendsThePlanWithTheRowsDestinations() async throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    host.importSummary = ImportSummary(
      imported: .init(spaces: 3, favorites: 3, pinnedTabs: 2, todayTabs: 6, bookmarks: 2, history: 0, extensions: 1),
      alreadyInClair: .init(bookmarks: 1),
      skipped: [ImportSkip(reason: .storeFailed, name: "Gone")])
    host.importsAtOnce = false
    let flow = flow(fixture)
    select("arc", in: flow)
    flow.continueToDetails()
    flow.setDestination(.newProfile, forRow: 0)
    flow.setDestination(.profile(FakeHost.defaultProfileID), forRow: 1)
    flow.startImport()
    #expect(flow.step == .importing)
    #expect(flow.defaultButtonTitle == nil)
    // Wait for the plan to reach the host.
    for _ in 0..<200 where host.importPlans.isEmpty {
      try await Task.sleep(for: .milliseconds(10))
    }
    let plan = try #require(host.importPlans.first)
    #expect(plan.profiles.map(\.destination) == [.newProfile("Your Arc"), .profile(FakeHost.defaultProfileID)])
    host.finishImport()
    await flow.importTask?.value
    #expect(flow.step == .summary)
    #expect(flow.title == "Import Complete")
    #expect(flow.defaultButtonTitle == "Done")
    #expect(flow.progress == 1)
    #expect(
      flow.summaryLines == [
        "3 Spaces", "3 favorites", "2 pinned tabs", "6 Today tabs", "2 bookmarks", "0 history entries", "1 extension",
        "Already in Clair: 1 bookmark",
      ])
    // The reader's skips come first, then the engine's.
    #expect(flow.skippedLines.first == "Trip Board: Clair has no place for it")
    #expect(flow.skippedLines.last == "Gone: the Chrome Web Store couldn't provide it")
  }

  @Test func aDeniedDiaKeyStillImportsTheRest() async throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    try DiaSidebarTests.write(fixture)
    let keychain = RecordingKeychain(secret: nil)
    let flow = flow(fixture, keychain: keychain)
    select("dia", in: flow)
    flow.continueToDetails()
    // Nothing reads the keychain before Import.
    #expect(keychain.reads.isEmpty)
    flow.startImport()
    await flow.importTask?.value
    #expect(keychain.reads == ["Dia Safe Storage"])
    let plan = try #require(host.importPlans.first)
    #expect(plan.profiles.first?.spaces.isEmpty == true)
    #expect(
      flow.skippedLines == [
        "Dia's Spaces, favorites, pinned and Today tabs couldn't be read without access to “Dia Safe Storage”, or in this version of Dia"
      ])
  }

  @Test func aFailedPlanEndsWithASummarySayingSo() async throws {
    let fixture = try ImportFixture(empty: true)
    defer { fixture.remove() }
    // The export vanished after it was chosen.
    let folder = fixture.root.appending(path: "Export")
    try FileManager.default.copyItem(at: ImportFixture.safariFolder, to: folder)
    let zip = fixture.root.appending(path: "Export.zip")
    let ditto = Process()
    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    ditto.arguments = ["-c", "-k", folder.path, zip.path]
    try ditto.run()
    ditto.waitUntilExit()
    let flow = flow(fixture)
    flow.continueToDetails()
    flow.chooseSafariFile(zip)
    try FileManager.default.removeItem(at: zip)
    flow.startImport()
    await flow.importTask?.value
    #expect(host.importPlans.isEmpty)
    #expect(flow.skippedLines == ["The import from Safari couldn't run"])
    // Its private folder is gone.
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.temporary.path).isEmpty)
  }
}

// MARK: The dialog (design D9) and the menu item

@MainActor
struct ImportDialogTests {
  let host = FakeHost()
  let apps = FakeAppWatcher()

  @Test func eachStepsButtons() async throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let flow = ImportFlow(host: host, environment: fixture.environment(), shownProfile: "Default", apps: apps)
    var page = ImportDialog.page(for: flow) { _ in }
    #expect(page.isStepped)
    #expect(page.width == ImportDialog.width)
    #expect(page.backButton == nil)
    #expect(page.buttons.map(\.title) == ["Cancel", "Continue"])

    flow.selectedIndex = 1
    flow.continueToDetails()
    page = ImportDialog.page(for: flow) { _ in }
    #expect(page.title == "Import from Arc")
    #expect(page.backButton?.title == "Back")
    #expect(page.buttons.map(\.title) == ["Cancel", "Import"])
    #expect(page.width == ImportDialog.width)

    flow.startImport()
    page = ImportDialog.page(for: flow) { _ in }
    #expect(page.buttons.isEmpty)
    await flow.importTask?.value
    page = ImportDialog.page(for: flow) { _ in }
    #expect(page.title == "Import Complete")
    #expect(page.buttons.map(\.title) == ["Done"])
    #expect(page.escapePressesDefault)
  }

  @Test func theDialogFollowsTheFlowAndBackReturns() async throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let presenter = ClairDialogPresenter(host: .init(begin: { _ in }, end: { _ in }))
    let flow = ImportFlow(host: host, environment: fixture.environment(), shownProfile: "Default", apps: apps)
    let dialog = ImportDialog.show(flow, on: presenter) { _ in }
    dialog.press(dialog.page.buttons[1])
    try await Task.sleep(for: .milliseconds(50))
    #expect(dialog.page.title == "Import from Safari")
    #expect(dialog.page.buttons.last?.title == "Choose File…")
    dialog.pressBack()
    try await Task.sleep(for: .milliseconds(50))
    #expect(dialog.page.title == "Import from your old browser")
    #expect(presenter.showing === dialog)
  }

  @Test func theItemGoesWhereChromiumsImportItemStood() {
    let menu = NSMenu()
    for title in ["About Clair", "Check for Updates…", "", "Settings…", "", "Clear Browsing Data…", "Import Bookmarks and Settings…", ""] {
      menu.addItem(title.isEmpty ? .separator() : NSMenuItem(title: title, action: nil, keyEquivalent: ""))
    }
    #expect(ImportMenu.insertionIndex(in: menu) == 7)
    // With Chromium's item hidden (design D11).
    menu.removeItem(at: 6)
    #expect(ImportMenu.insertionIndex(in: menu) == 6)
    let main = NSMenu()
    let app = NSMenuItem(title: "Clair", action: nil, keyEquivalent: "")
    app.submenu = menu
    main.addItem(app)
    let importMenu = ImportMenu(host: host)
    importMenu.install(in: main)
    importMenu.install(in: main)
    #expect(menu.items.map(\.title).filter { $0 == ImportMenu.title }.count == 1)
    #expect(menu.items[6].title == "Import from Another Browser…")
  }

  @Test func oneDialogAtATime() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let window = PinWindow()
    let importMenu = ImportMenu(host: window.host) { fixture.environment() }
    importMenu.show(on: window.controller)
    let first = importMenu.dialog
    #expect(first != nil)
    importMenu.show(on: window.controller)
    #expect(importMenu.dialog === first)
    #expect(window.controller.dialogs.showing === first)
  }
}
