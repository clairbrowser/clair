// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Foundation
import Security

/// A kind of item an import brings, as the second step lists it
/// (browser-import "What will come over").
nonisolated enum ImportItemKind: String, CaseIterable, Sendable {
  case spaces, favorites, pinnedTabs, todayTabs, bookmarks, history, extensions

  var title: String {
    switch self {
    case .spaces: "Spaces"
    case .favorites: "Favorites"
    case .pinnedTabs: "Pinned Tabs"
    case .todayTabs: "Today Tabs"
    case .bookmarks: "Bookmarks"
    case .history: "History"
    case .extensions: "Extensions"
    }
  }

  var symbol: String {
    switch self {
    case .spaces: "square.stack"
    case .favorites: "star"
    case .pinnedTabs: "pin"
    case .todayTabs: "sun.max"
    case .bookmarks: "book"
    case .history: "clock"
    case .extensions: "puzzlepiece.extension"
    }
  }
}

/// What a source needs before it can import (design D2).
nonisolated enum ImportRequirement: Equatable, Sendable {
  case none
  /// Safari: the file its File › Export Browsing Data to File… writes.
  case exportFile
  /// Dia: its storage key, read from the keychain after Import.
  case keychain(service: String)
}

/// One of the source's profiles: a row of the second step.
nonisolated struct ImportSourceProfile: Equatable, Sendable {
  /// The source's key for it, such as "Profile 6".
  var key: String
  /// What its row reads.
  var name: String
  /// The name a new Clair profile for it takes.
  var newProfileName: String
}

/// Reads a keychain item's password; a fake in tests (D5).
nonisolated protocol ImportKeychain: Sendable {
  /// The password of the generic password item `service`, or nil when it's
  /// missing or the user denied access.
  func password(service: String) -> Data?
}

/// The login keychain, through `SecItemCopyMatching`, so macOS asks the user
/// and its prompt names Clair.
nonisolated struct SystemKeychain: ImportKeychain {
  func password(service: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
    return result as? Data
  }
}

/// The keychain with a fixed secret, for the runtime suite's
/// `CLAIR_TEST_DIA_SECRET` (D12).
nonisolated struct FixedKeychain: ImportKeychain {
  let secret: Data
  func password(service: String) -> Data? { secret }
}

/// Where sources look, and the test switches that move them (design D12):
/// `CLAIR_TEST_IMPORT_ROOT` stands for the home folder and
/// `CLAIR_TEST_DIA_SECRET` for the keychain, honoured only in packages
/// package.sh marks as non-official, as the updater's test switches are.
nonisolated struct ImportEnvironment: Sendable {
  static let rootOverrideVariable = "CLAIR_TEST_IMPORT_ROOT"
  static let diaSecretOverrideVariable = "CLAIR_TEST_DIA_SECRET"

  /// The folder sources' paths start from: the home folder.
  var home: URL
  var keychain: any ImportKeychain
  /// Where the import's private folder goes.
  var temporaryDirectory: URL

  init(home: URL, keychain: any ImportKeychain = SystemKeychain(), temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
    self.home = home
    self.keychain = keychain
    self.temporaryDirectory = temporaryDirectory
  }

  init(infoDictionary: [String: Any], environment: [String: String]) {
    var home = FileManager.default.homeDirectoryForCurrentUser
    var keychain: any ImportKeychain = SystemKeychain()
    if infoDictionary[UpdateConfiguration.nonOfficialPackageKey] as? Bool == true {
      if let root = environment[Self.rootOverrideVariable], !root.isEmpty {
        home = URL(fileURLWithPath: root, isDirectory: true)
      }
      if let secret = environment[Self.diaSecretOverrideVariable], !secret.isEmpty {
        keychain = FixedKeychain(secret: Data(secret.utf8))
      }
    }
    self.init(home: home, keychain: keychain)
  }

  static var current: ImportEnvironment {
    ImportEnvironment(infoDictionary: Bundle.main.infoDictionary ?? [:], environment: ProcessInfo.processInfo.environment)
  }

  var applicationSupport: URL { home.appending(path: "Library/Application Support", directoryHint: .isDirectory) }
}

/// What making a plan is given once the user clicks Import.
nonisolated struct ImportContext: Sendable {
  /// Each source profile's destination, by its key; a profile missing here
  /// goes to a new profile.
  var destinations: [String: ImportPlan.Destination]
  var folder: ImportWorkFolder
  var keychain: any ImportKeychain
}

/// A browser Clair imports from (design D2).
nonisolated protocol ImportSource: Sendable {
  /// A stable ID, such as "arc", which the plan names.
  var id: String { get }
  var name: String { get }
  /// The app's bundle ID, for its icon and whether it runs.
  var bundleID: String { get }
  /// What the second step lists.
  var items: [ImportItemKind] { get }
  var requirement: ImportRequirement { get }
  /// Whether it has something to import on this Mac. Reads only what finding
  /// it needs (D10).
  var isPresent: Bool { get }
  /// Its profiles, the second step's rows. Reads only their names (D10).
  func profiles() -> [ImportSourceProfile]
  /// Reads the source and makes the plan. Runs off the main thread; it may
  /// read the keychain.
  func makePlan(_ context: ImportContext) throws -> ImportPlan
}

extension ImportSource {
  /// The app's icon from its bundle ID, or a generic one when it isn't
  /// installed.
  @MainActor var icon: NSImage {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
      return NSWorkspace.shared.icon(forFile: url.path)
    }
    return NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
  }
}

/// The import's private folder (design D10): mode 0700 in the user's
/// temporary directory, holding copies readable by the user alone. The engine
/// removes it when the import ends, and any left by a crash at launch, by its
/// prefix.
nonisolated struct ImportWorkFolder: Sendable {
  static let prefix = "clair-import-"

  let url: URL

  /// Creates a new, empty one.
  static func create(in directory: URL) throws -> ImportWorkFolder {
    let url = directory.appending(path: prefix + UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    return ImportWorkFolder(url: url)
  }

  /// A new subfolder, mode 0700.
  func subfolder(_ name: String) throws -> URL {
    let url = self.url.appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    return url
  }

  /// Copies `source` into `directory` with its name, mode 0600, and returns
  /// the copy; nil when the source doesn't exist.
  @discardableResult
  static func copy(_ source: URL, into directory: URL) throws -> URL? {
    guard FileManager.default.fileExists(atPath: source.path) else { return nil }
    let copy = directory.appending(path: source.lastPathComponent)
    try FileManager.default.copyItem(at: source, to: copy)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copy.path)
    return copy
  }

  /// Copies a SQLite database with its `-wal` and `-journal`, so nothing
  /// reads or locks the source's own files (D7). Nil when it doesn't exist.
  static func copyDatabase(_ source: URL, into directory: URL) throws -> URL? {
    guard let copy = try copy(source, into: directory) else { return nil }
    for suffix in ["-wal", "-journal"] {
      try Self.copy(URL(fileURLWithPath: source.path + suffix), into: directory)
    }
    return copy
  }

  /// Copies a folder's files, not its subfolders, into a new 0700 folder of
  /// the same name in `directory`. Nil when it doesn't exist.
  static func copyFolder(_ source: URL, into directory: URL) throws -> URL? {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      return nil
    }
    let copy = directory.appending(path: source.lastPathComponent, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isRegularFileKey]) {
      if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
        try Self.copy(file, into: copy)
      }
    }
    return copy
  }

  func remove() {
    try? FileManager.default.removeItem(at: url)
  }
}

/// Every source Clair knows, in the first step's order (browser-import
/// "Choosing a browser").
nonisolated enum ImportSources {
  static func all(_ environment: ImportEnvironment) -> [any ImportSource] {
    [
      SafariExportSource(),
      ChromiumFamilySource(.arc, environment: environment),
      ChromiumFamilySource(.dia, environment: environment),
      ChromiumFamilySource(.chrome, environment: environment),
    ]
  }

  /// The sources with something to import on this Mac.
  static func present(_ environment: ImportEnvironment) -> [any ImportSource] {
    all(environment).filter(\.isPresent)
  }
}
