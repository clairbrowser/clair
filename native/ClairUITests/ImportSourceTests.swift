// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import Testing

@testable import ClairUI

/// The names of folders and the titles of tabs, custom names first, splits as
/// "A|B".
private func outline(_ items: [ImportItem]) -> [String] {
  items.map { item in
    switch item {
    case .tab(let tab): tab.name ?? tab.title
    case .split(let panes, _): panes.map { $0.name ?? $0.title }.joined(separator: "|")
    case .folder(let name, let children): "\(name)[\(outline(children).joined(separator: ","))]"
    }
  }
}

private func outline(_ bookmarks: [ImportBookmark]?) -> [String] {
  (bookmarks ?? []).map { bookmark in
    switch bookmark {
    case .bookmark(let title, _): title
    case .folder(let name, let children): "\(name)[\(outline(children).joined(separator: ","))]"
    }
  }
}

private func mode(_ url: URL) -> Int? {
  (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
}

// MARK: Which sources show (design D2, browser-import "Which sources show")

struct ImportPresenceTests {
  @Test func onlySafariShowsWithoutBrowserData() throws {
    let fixture = try ImportFixture(empty: true)
    defer { fixture.remove() }
    #expect(ImportSources.present(fixture.environment()).map(\.id) == ["safari"])
  }

  @Test func sourcesShowInTheirOrderWhenTheirDataExists() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    // Dia's fixture has no tabs.db yet.
    #expect(ImportSources.present(fixture.environment()).map(\.id) == ["safari", "arc", "chrome"])
    try DiaDatabaseBuilder.write(
      userData: fixture.applicationSupport.appending(path: "Dia/User Data"), profile: "Profile 4", base: [], walOnly: [])
    #expect(ImportSources.present(fixture.environment()).map(\.id) == ["safari", "arc", "dia", "chrome"])
  }

  @Test func arcNeedsItsSidebar() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    try FileManager.default.removeItem(at: fixture.applicationSupport.appending(path: "Arc/StorableSidebar.json"))
    #expect(!ChromiumFamilySource(.arc, environment: fixture.environment()).isPresent)
  }

  @Test func chromeNeedsAProfile() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    try FileManager.default.removeItem(at: fixture.applicationSupport.appending(path: "Google/Chrome/Default"))
    #expect(!ChromiumFamilySource(.chrome, environment: fixture.environment()).isPresent)
  }

  @Test func theRootOverridePointsEverySourceAtTheFixtures() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let environment = ImportEnvironment(
      infoDictionary: [UpdateConfiguration.nonOfficialPackageKey: true],
      environment: [ImportEnvironment.rootOverrideVariable: fixture.home.path])
    #expect(environment.home.standardizedFileURL == fixture.home.standardizedFileURL)
    #expect(ImportSources.present(environment).map(\.id) == ["safari", "arc", "chrome"])
    let arc = ChromiumFamilySource(.arc, environment: environment)
    #expect(arc.userData.path.hasPrefix(fixture.home.path))
  }

  @Test func releasePackagesIgnoreTheTestSwitches() {
    let environment = ImportEnvironment(
      infoDictionary: [:],
      environment: [ImportEnvironment.rootOverrideVariable: "/tmp/elsewhere", ImportEnvironment.diaSecretOverrideVariable: "x"])
    #expect(environment.home == FileManager.default.homeDirectoryForCurrentUser)
    #expect(environment.keychain is SystemKeychain)
  }

  @Test func theDiaSecretSwitchReplacesTheKeychain() {
    let environment = ImportEnvironment(
      infoDictionary: [UpdateConfiguration.nonOfficialPackageKey: true],
      environment: [ImportEnvironment.diaSecretOverrideVariable: "secret"])
    #expect(environment.keychain.password(service: "Dia Safe Storage") == Data("secret".utf8))
  }
}

// MARK: Chromium-family profiles (design D7, D10, D13)

struct ChromiumFamilyTests {
  @Test func profilesComeFromLocalStateInItsOrder() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let arc = ChromiumFamilySource(.arc, environment: fixture.environment())
    #expect(arc.profiles().map(\.name) == ["Your Arc", "Work"])
    #expect(arc.profiles().map(\.key) == ["Default", "Profile 6"])
  }

  @Test func diaRowsNameTheProfilesSharingData() {
    #expect(ChromiumFamilySource.diaProfileNames("Profile 2 (sharing data with 3)") == ["Profile 2", "Profile 3"])
    #expect(ChromiumFamilySource.diaProfileNames("Work (sharing data with Home)") == ["Work", "Home"])
    #expect(ChromiumFamilySource.diaProfileNames("Profile 1") == ["Profile 1"])
    #expect(
      ChromiumFamilySource.diaProfileNames("Profile 2 (sharing data with 3 and 4)") == ["Profile 2", "Profile 3", "Profile 4"])
  }

  @Test func diaRowAndNewProfileName() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let dia = ChromiumFamilySource(.dia, environment: fixture.environment())
    #expect(dia.profiles() == [ImportSourceProfile(key: "Profile 4", name: "Profile 2, Profile 3", newProfileName: "Profile 2")])
  }

  @Test func chromeBookmarksBarFirstWithNoFolderAdded() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let chrome = ChromiumFamilySource(.chrome, environment: fixture.environment())
    let plan = try chrome.makePlan(try fixture.context())
    let profile = try #require(plan.profiles.first)
    #expect(
      outline(profile.bookmarks) == [
        "Google", "News[BBC,Tech[The Verge],Engadget]", "Account Bar", "Docs", "Phone",
      ])
  }

  @Test func chromePlanNamesItsSpaceAndSessionCopy() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let chrome = ChromiumFamilySource(.chrome, environment: fixture.environment())
    let context = try fixture.context(destinations: ["Default": .profile("Default")])
    let plan = try chrome.makePlan(context)
    #expect(plan.source == "chrome")
    #expect(plan.folder == context.folder.url.path)
    let profile = try #require(plan.profiles.first)
    #expect(profile.destination == .profile("Default"))
    #expect(profile.spaces.isEmpty)
    #expect(profile.favorites.isEmpty)
    let session = try #require(profile.session)
    #expect(session.space == "Person 1")
    #expect(session.chromiumSessions.hasPrefix(context.folder.url.path))
    let files = try FileManager.default.contentsOfDirectory(atPath: session.chromiumSessions).sorted()
    #expect(files == ["Session_13377777777777777", "Tabs_13377777777777777"])
  }

  @Test func extensionsAsSpecified() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let plan = try ChromiumFamilySource(.chrome, environment: fixture.environment()).makePlan(try fixture.context())
    let profile = try #require(plan.profiles.first)
    #expect(
      profile.extensions == [
        // Turned off by the user, in Preferences rather than Secure Preferences.
        ImportPlan.Extension(id: "cjpalhdlnbpafiamejdnhcphjbkeiagm", name: "uBlock Origin", enabled: false, pinned: false),
        ImportPlan.Extension(id: "eimadpbcbfnmbkopoojfekhnkhdbieeh", name: "Dark Reader", enabled: true, pinned: true),
        // Disabled only for its manifest version, its name from its locale.
        ImportPlan.Extension(id: "gighmmpiobklfepjocnamgkkbiglidom", name: "AdBlock", enabled: true, pinned: false),
      ])
    // The unpacked one and the theme are reported; Chromium's own aren't.
    #expect(
      profile.skipped == [
        ImportSkip(reason: .notFromWebStore, name: "My Unpacked Extension"),
        ImportSkip(reason: .themeOrApp, name: "Just Black"),
      ])
  }

  @Test func copiesArePrivateAndTheOriginalsUntouched() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let original = fixture.applicationSupport.appending(path: "Google/Chrome/Default/History")
    let originalMode = mode(original)
    let originalData = try Data(contentsOf: original)
    let context = try fixture.context()
    let plan = try ChromiumFamilySource(.chrome, environment: fixture.environment()).makePlan(context)
    let profile = try #require(plan.profiles.first)

    #expect(mode(context.folder.url) == 0o700)
    guard case .chromiumDB(let history) = profile.history, case .chromiumDB(let favicons) = profile.favicons else {
      Issue.record("no history or favicons copy")
      return
    }
    let historyCopy = URL(fileURLWithPath: history)
    #expect(historyCopy.path.hasPrefix(context.folder.url.path))
    #expect(mode(historyCopy) == 0o600)
    #expect(mode(URL(fileURLWithPath: favicons)) == 0o600)
    // Its journal comes along.
    let journal = URL(fileURLWithPath: history + "-journal")
    #expect(mode(journal) == 0o600)
    #expect(mode(historyCopy.deletingLastPathComponent()) == 0o700)
    for file in try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: profile.session!.chromiumSessions), includingPropertiesForKeys: nil) {
      #expect(mode(file) == 0o600)
    }
    #expect(mode(URL(fileURLWithPath: profile.session!.chromiumSessions)) == 0o700)
    #expect(try Data(contentsOf: original) == originalData)
    #expect(mode(original) == originalMode)
  }

  @Test func aProfileWithoutHistoryHasNone() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let plan = try ChromiumFamilySource(.arc, environment: fixture.environment()).makePlan(try fixture.context())
    #expect(plan.profiles.allSatisfy { $0.history == nil && $0.favicons == nil && $0.session == nil })
  }

  @Test func readsNothingButLocalStateBeforeThePlan() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let keychain = RecordingKeychain(secret: nil)
    let dia = ChromiumFamilySource(.dia, environment: fixture.environment(keychain: keychain))
    _ = dia.isPresent
    _ = dia.profiles()
    #expect(keychain.reads.isEmpty)
    // Nothing is copied before Import either.
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.temporary.path).isEmpty)
  }
}

// MARK: Arc's sidebar (design D4)

struct ArcSidebarTests {
  private func plan() throws -> ImportPlan {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    return try ChromiumFamilySource(.arc, environment: fixture.environment()).makePlan(
      try fixture.context(destinations: ["Default": .profile("Default"), "Profile 6": .newProfile("Work")]))
  }

  @Test func spacesWithTheirEmojiAndProfile() throws {
    let plan = try plan()
    #expect(plan.profiles.map(\.sourceName) == ["Your Arc", "Work"])
    #expect(plan.profiles[0].spaces.map(\.name) == ["Space 1", "Space 2"])
    #expect(plan.profiles[0].spaces.map(\.icon) == [nil, "😀"])
    #expect(plan.profiles[1].spaces.map(\.name) == ["Space 3"])
    #expect(plan.profiles[1].destination == .newProfile("Work"))
  }

  @Test func pinnedFoldersFlattenWithTheirPathAndCustomNames() throws {
    let space = try plan().profiles[0].spaces[0]
    #expect(
      outline(space.pinned) == [
        "Parent Folder[The Verge|Ars Technica - Serving the Technologist since 1998. News, reviews, and analysis.]",
        "Parent Folder / Child Folder[RENAMED TAB]",
      ])
    guard case .folder(_, let children) = space.pinned[1], case .tab(let tab) = children[0] else {
      Issue.record("no renamed tab")
      return
    }
    // Arc's pinned URL, its page's title and the custom name.
    #expect(tab.url == "https://www.bbc.com/news")
    #expect(tab.title.hasPrefix("BBC News"))
    #expect(tab.name == "RENAMED TAB")
  }

  @Test func todaySplitsOfTwoStackedAndThree() throws {
    let today = try plan().profiles[0].spaces[0].today
    // The three-pane split's pages in its place, then the stacked split, the
    // split of two and the tab; the Easel is left out.
    let urls = today.map { $0.tabs.map(\.url).joined(separator: "|") }
    #expect(
      urls == [
        "https://en.wikipedia.org/wiki/Africa", "https://en.wikipedia.org/wiki/Europe", "https://en.wikipedia.org/wiki/Asia",
        "https://en.wikipedia.org/wiki/Dog|https://en.wikipedia.org/wiki/Cat",
        "https://news.ycombinator.com/|https://www.engadget.com/", "https://weather.com/",
      ])
    guard case .split(_, let stackedRatio) = today[3], case .split(_, let ratio) = today[4] else {
      Issue.record("no splits")
      return
    }
    #expect(stackedRatio == 0.5)
    #expect(ratio == 0.5)
  }

  @Test func favoritesPerProfile() throws {
    let plan = try plan()
    #expect(plan.profiles[0].favorites.flatMap(\.tabs).map(\.url) == ["https://example.com/", "https://www.wiktionary.org/"])
    #expect(plan.profiles[1].favorites.flatMap(\.tabs).map(\.url) == ["https://www.wikipedia.org/"])
  }

  @Test func unknownItemKindsAreReported() throws {
    #expect(try plan().profiles[0].skipped.contains(ImportSkip(reason: .unsupportedItem, name: "Trip Board")))
  }

  @Test func bookmarksAndExtensionsOfTheWorkProfile() throws {
    let work = try plan().profiles[1]
    #expect(outline(work.bookmarks) == ["Google", "Docs"])
    #expect(work.extensions.map(\.name) == ["Dark Reader"])
    #expect(work.extensions.first?.pinned == true)
  }

  @Test func anUnreadableSidebarIsReportedOnce() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    try Data("{".utf8).write(to: fixture.applicationSupport.appending(path: "Arc/StorableSidebar.json"))
    let plan = try ChromiumFamilySource(.arc, environment: fixture.environment()).makePlan(try fixture.context())
    #expect(plan.profiles.flatMap(\.skipped).filter { $0.reason == .sidebarUnreadable }.count == 1)
    #expect(plan.profiles[1].bookmarks != nil)
  }
}

// MARK: Dia's sidebar (design D5)

@Suite(.serialized)
struct DiaSidebarTests {
  typealias B = DiaDatabaseBuilder

  /// Profile 2 and Profile 3 share "Profile 4": favorites, a pinned group
  /// nest, a window with a split of two, one of three and a tab, a deleted
  /// window's orphan, and a tab committed only to the log.
  static func write(_ fixture: ImportFixture, secret: Data = B.secret) throws {
    var base = [
      B.space("s1", "Profile 2", created: "2026-11-01 10:00:00"),
      B.space("s2", "Profile 3", created: "2026-11-02 10:00:00"),
      B.node(1, "favorites", order: 0, space: "s1"),
      B.node(2, "pinned_container", order: 1, space: "s1"),
      B.node(3, "window", order: 2, space: "s1"),
      B.node(4, "window", order: 3, space: "s1", deleted: true),
      B.node(5, "favorites", order: 0, space: "s2"),
      B.node(6, "window", order: 1, space: "s2"),
    ]
    base += B.tab(10, parent: 1, order: 0, space: "s1", pages: [("https://example.com/", "Example", nil)])
    base += B.group(11, "A", parent: 2, order: 0, space: "s1")
    base += B.group(12, "B", parent: 11, order: 0, space: "s1")
    base += B.group(13, "C", parent: 12, order: 0, space: "s1")
    base += B.tab(14, parent: 13, order: 0, space: "s1", pages: [("https://bbc.example/", "BBC", "Renamed")])
    base += B.tab(
      15, parent: 3, order: 0, space: "s1", pages: [("https://docs.example/", "Docs", nil), ("https://mail.example/", "Mail", nil)],
      widths: "[600, 400]")
    base += B.tab(
      16, parent: 3, order: 1, space: "s1",
      pages: [("https://africa.example/", "Africa", nil), ("https://europe.example/", "Europe", nil), ("https://asia.example/", "Asia", nil)],
      widths: "[1, 1, 1]")
    base += B.tab(17, parent: 3, order: 2, space: "s1", pages: [("https://weather.example/", "Weather", nil)])
    base += B.tab(18, parent: 4, order: 0, space: "s1", pages: [("https://orphan.example/", "Orphan", nil)])
    base += B.tab(19, parent: 5, order: 0, space: "s2", pages: [("https://example.com/", "Example again", nil)])
    base += B.tab(20, parent: 5, order: 1, space: "s2", pages: [("https://wiktionary.example/", "Wiktionary", nil)])
    base += B.tab(21, parent: 6, order: 0, space: "s2", pages: [("https://three.example/", "Space three tab", nil)])
    let wal = B.tab(22, parent: 6, order: 1, space: "s2", pages: [("https://wal.example/", "Only in the log", nil)])
    try B.write(
      userData: fixture.applicationSupport.appending(path: "Dia/User Data"), profile: "Profile 4", secret: secret, base: base,
      walOnly: wal)
  }

  private func plan(secret: Data?, fixture: ImportFixture) throws -> ImportPlan {
    let keychain = RecordingKeychain(secret: secret)
    let dia = ChromiumFamilySource(.dia, environment: fixture.environment(keychain: keychain))
    let plan = try dia.makePlan(try fixture.context(keychain: keychain))
    #expect(keychain.reads == ["Dia Safe Storage"])
    return plan
  }

  @Test func readsSpacesFromTheirLiveRoots() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    try Self.write(fixture)
    let profile = try #require(try plan(secret: B.secret, fixture: fixture).profiles.first)
    #expect(profile.sourceName == "Profile 2, Profile 3")
    #expect(profile.spaces.map(\.name) == ["Profile 2", "Profile 3"])
    #expect(outline(profile.spaces[0].pinned) == ["A / B / C[Renamed]"])
    // The deleted window's orphan stays out.
    #expect(outline(profile.spaces[0].today) == ["Docs|Mail", "Africa", "Europe", "Asia", "Weather"])
    guard case .split(_, let ratio) = profile.spaces[0].today[0] else {
      Issue.record("no split")
      return
    }
    #expect(ratio == 0.6)
    // The tab committed only to the log comes over.
    #expect(outline(profile.spaces[1].today) == ["Space three tab", "Only in the log"])
    // Favorites of both Spaces, in Space order, without the repeated URL.
    #expect(outline(profile.favorites) == ["Example", "Wiktionary"])
    #expect(profile.skipped.isEmpty)
  }

  @Test func aWrongKeyReadsNoSidebarAndSaysSo() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    try Self.write(fixture)
    let profile = try #require(try plan(secret: Data("wrong".utf8), fixture: fixture).profiles.first)
    #expect(profile.spaces.isEmpty)
    #expect(profile.favorites.isEmpty)
    #expect(profile.skipped.map(\.reason) == [.sidebarUnreadable])
  }

  @Test func aDeniedKeychainStillImportsTheRest() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    try Self.write(fixture)
    let profile = try #require(try plan(secret: nil, fixture: fixture).profiles.first)
    #expect(profile.spaces.isEmpty)
    #expect(profile.skipped.map(\.reason) == [.sidebarUnreadable])
    #expect(profile.destination == .newProfile("Profile 2"))
  }

  @Test func theLogsOlderGenerationIsIgnored() throws {
    var count = 0
    // A log whose header checksum doesn't hold contributes nothing.
    #expect(DiaSidebarReader.committedFrames(wal: Data(count: 64), pageCount: &count).isEmpty)
  }

  @Test func writesNothingOutsideTheTestsFolder() throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    try Self.write(fixture)
    let temporary = FileManager.default.temporaryDirectory
    let ignored = { (name: String) in name.hasPrefix("ClairImportTests-") || name.hasPrefix("ClairDiaPlain-") }
    let before = Set(try FileManager.default.contentsOfDirectory(atPath: temporary.path).filter { !ignored($0) })
    let profileFolder = fixture.applicationSupport.appending(path: "Dia/User Data/Profile 4")
    let profileBefore = try FileManager.default.contentsOfDirectory(atPath: profileFolder.path).sorted()
    let sidebar = DiaSidebarReader.read(
      userData: fixture.applicationSupport.appending(path: "Dia/User Data"), profiles: ["Profile 4"], secret: B.secret)
    #expect(sidebar.profiles["Profile 4"]?.spaces.count == 2)
    let after = Set(try FileManager.default.contentsOfDirectory(atPath: temporary.path).filter { !ignored($0) })
    #expect(after.subtracting(before).isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: profileFolder.path).sorted() == profileBefore)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.temporary.path).isEmpty)
  }
}

// MARK: Safari's export (design D6)

struct SafariExportTests {
  private func zip(_ folder: URL, in fixture: ImportFixture, name: String = "Safari Export.zip") throws -> URL {
    let zip = fixture.root.appending(path: name)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--keepParent", folder.path, zip.path]
    try process.run()
    process.waitUntilExit()
    return zip
  }

  private func plan(_ url: URL, fixture: ImportFixture) throws -> ImportPlan.Profile {
    let source = SafariExportSource(export: try SafariExport.check(url))
    let plan = try source.makePlan(try fixture.context(destinations: ["Safari": .profile("Default")]))
    #expect(plan.source == "safari")
    return try #require(plan.profiles.first)
  }

  @Test func aZipBringsBookmarksAndHistory() throws {
    let fixture = try ImportFixture(empty: true)
    defer { fixture.remove() }
    let zip = try zip(ImportFixture.safariFolder, in: fixture)
    let export = try SafariExport.check(zip)
    #expect(export.kind == .zip)
    #expect(export.hasBookmarks && export.hasHistory)
    // Checking doesn't unpack it.
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.temporary.path).isEmpty)

    let profile = try plan(zip, fixture: fixture)
    #expect(profile.sourceName == "Safari")
    #expect(profile.destination == .profile("Default"))
    // Favorites' contents first, no folder added, a nested "Favorites" kept
    // as a folder, then the rest; the Reading List dropped.
    #expect(
      outline(profile.bookmarks) == [
        "Apple", "News[BBC & Friends,Favorites[Nested, not the bar]]", "Recipes[Soup]", "Loose – one",
      ])
    #expect(profile.favorites.isEmpty)
    #expect(profile.spaces.isEmpty)
    guard case .safariJSON(let history) = profile.history else {
      Issue.record("no history")
      return
    }
    #expect(history.hasPrefix(fixture.temporary.path))
    #expect(FileManager.default.fileExists(atPath: history))
  }

  @Test func aFolderIsReadInPlace() throws {
    let fixture = try ImportFixture(empty: true)
    defer { fixture.remove() }
    let profile = try plan(ImportFixture.safariFolder, fixture: fixture)
    #expect(profile.history == .safariJSON(ImportFixture.safariFolder.appending(path: "History.json").path))
    #expect(profile.bookmarks?.count == 4)
  }

  @Test func aBookmarksOnlyExport() throws {
    let fixture = try ImportFixture(empty: true)
    defer { fixture.remove() }
    let folder = fixture.root.appending(path: "Bookmarks Only")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.copyItem(
      at: ImportFixture.safariFolder.appending(path: "Bookmarks.html"), to: folder.appending(path: "Bookmarks.html"))
    let zip = try zip(folder, in: fixture, name: "Bookmarks.zip")
    let export = try SafariExport.check(zip)
    #expect(export.hasBookmarks && !export.hasHistory)
    let profile = try plan(zip, fixture: fixture)
    #expect(profile.history == nil)
    #expect(profile.bookmarks?.isEmpty == false)
  }

  @Test func aWrongFileIsRefused() throws {
    let fixture = try ImportFixture(empty: true)
    defer { fixture.remove() }
    let text = fixture.root.appending(path: "notes.txt")
    try Data("hello".utf8).write(to: text)
    #expect(throws: SafariExport.Error.notAnExport) { try SafariExport.check(text) }
    let otherZip = try zip(text, in: fixture, name: "Other.zip")
    #expect(throws: SafariExport.Error.notAnExport) { try SafariExport.check(otherZip) }
    #expect(throws: SafariExport.Error.notAnExport) { try SafariExport.check(fixture.root.appending(path: "missing.zip")) }
  }
}
