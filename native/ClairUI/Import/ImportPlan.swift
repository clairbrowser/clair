// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation

/// What an import brings over, in the neutral form the engine writes
/// (add-browser-import design D3). It crosses `ClairHost.h` as UTF-8 JSON with
/// `"version": 1`. Every reader builds one, and `ImportShape` makes its trees
/// fit Clair before it leaves `ClairUI`, so the engine sees only what Clair
/// can show.
nonisolated struct ImportPlan: Codable, Equatable, Sendable {
  static let currentVersion = 1

  var version = ImportPlan.currentVersion
  /// The source's ID, such as "arc".
  var source: String
  /// The source's name, such as "Arc".
  var sourceName: String
  /// The import's private folder, which holds the copies the plan names; the
  /// engine removes it when the import ends (D10). Nil when nothing was
  /// copied.
  var folder: String?
  var profiles: [Profile]

  /// One profile of the source, and where it goes.
  struct Profile: Codable, Equatable, Sendable {
    /// The source's key for it, such as its profile folder "Profile 6".
    var sourceKey: String
    /// The name the source gives it, which labels its row.
    var sourceName: String
    var destination: Destination
    var spaces: [Space] = []
    var favorites: [ImportItem] = []
    /// The bookmarks bar's contents, then the other bookmarks, with no
    /// folder added around them (D7). Nil when the profile has none.
    var bookmarks: [ImportBookmark]?
    var history: History?
    var favicons: Favicons?
    /// Chrome's last session, which the engine reads (D13).
    var session: Session?
    var extensions: [Extension] = []
    /// What the reader left out, and why; the summary lists these with the
    /// engine's own.
    var skipped: [ImportSkip] = []
  }

  /// The Clair profile a source profile goes to.
  enum Destination: Codable, Equatable, Sendable {
    /// An existing profile, by ID.
    case profile(String)
    /// A profile to create, named after the source profile (the engine adds
    /// " 2", " 3" until the name is free).
    case newProfile(String)
  }

  struct Space: Codable, Equatable, Sendable {
    var name: String
    var icon: String?
    var pinned: [ImportItem] = []
    var today: [ImportItem] = []
  }

  enum History: Codable, Equatable, Sendable {
    /// A private copy of a Chromium `History` database.
    case chromiumDB(String)
    /// Safari's exported `History.json`.
    case safariJSON(String)
  }

  enum Favicons: Codable, Equatable, Sendable {
    /// A private copy of a Chromium `Favicons` database.
    case chromiumDB(String)
  }

  struct Session: Codable, Equatable, Sendable {
    /// A private copy of the profile's `Sessions` folder.
    var chromiumSessions: String
    /// The Space its tabs go to, named after the source profile.
    var space: String
  }

  struct Extension: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var enabled: Bool
    var pinned: Bool
    /// The installed version's manifest, as JSON text: the engine installs
    /// without a prompt only while the store's version asks for no more
    /// than it (design D8 step 8).
    var manifest: String?

    init(id: String, name: String, enabled: Bool, pinned: Bool, manifest: String? = nil) {
      self.id = id
      self.name = name
      self.enabled = enabled
      self.pinned = pinned
      self.manifest = manifest
    }
  }

  /// The plan as the engine reads it.
  func json() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(self)
  }
}

// The enums encode as one-key objects, `{"profile": "…"}`, as the design's
// JSON reads, rather than Swift's default `{"profile": {"_0": "…"}}`.
nonisolated extension ImportPlan.Destination {
  private enum CodingKeys: String, CodingKey { case profile, newProfile }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let id = try container.decodeIfPresent(String.self, forKey: .profile) {
      self = .profile(id)
    } else {
      self = .newProfile(try container.decode(String.self, forKey: .newProfile))
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .profile(let id): try container.encode(id, forKey: .profile)
    case .newProfile(let name): try container.encode(name, forKey: .newProfile)
    }
  }
}

nonisolated extension ImportPlan.History {
  private enum CodingKeys: String, CodingKey { case chromiumDB, safariJSON }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let path = try container.decodeIfPresent(String.self, forKey: .chromiumDB) {
      self = .chromiumDB(path)
    } else {
      self = .safariJSON(try container.decode(String.self, forKey: .safariJSON))
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .chromiumDB(let path): try container.encode(path, forKey: .chromiumDB)
    case .safariJSON(let path): try container.encode(path, forKey: .safariJSON)
    }
  }
}

nonisolated extension ImportPlan.Favicons {
  private enum CodingKeys: String, CodingKey { case chromiumDB }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self = .chromiumDB(try container.decode(String.self, forKey: .chromiumDB))
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .chromiumDB(let path): try container.encode(path, forKey: .chromiumDB)
    }
  }
}

/// A tab as an import brings it: its URL, its page's title and the custom
/// name the user gave it, if any.
nonisolated struct ImportTab: Codable, Equatable, Sendable {
  var url: String
  var title: String
  var name: String?

  init(url: String, title: String, name: String? = nil) {
    self.url = url
    self.title = title
    self.name = name.flatMap { $0.isEmpty ? nil : $0 }
  }
}

/// A sidebar item: a tab, a split or a folder. Readers may nest folders and
/// give splits any number of panes; `ImportShape` reduces both to Clair's.
nonisolated indirect enum ImportItem: Codable, Equatable, Sendable {
  case tab(ImportTab)
  /// Panes in order; `ratio` is the leading pane's share of the width.
  case split(panes: [ImportTab], ratio: Double)
  case folder(name: String, children: [ImportItem])

  private enum CodingKeys: String, CodingKey { case tab, split, folder }
  private struct Split: Codable { var panes: [ImportTab]; var ratio: Double }
  private struct Folder: Codable { var name: String; var children: [ImportItem] }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let tab = try container.decodeIfPresent(ImportTab.self, forKey: .tab) {
      self = .tab(tab)
    } else if let split = try container.decodeIfPresent(Split.self, forKey: .split) {
      self = .split(panes: split.panes, ratio: split.ratio)
    } else {
      let folder = try container.decode(Folder.self, forKey: .folder)
      self = .folder(name: folder.name, children: folder.children)
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .tab(let tab): try container.encode(tab, forKey: .tab)
    case .split(let panes, let ratio): try container.encode(Split(panes: panes, ratio: ratio), forKey: .split)
    case .folder(let name, let children): try container.encode(Folder(name: name, children: children), forKey: .folder)
    }
  }

  /// Every tab in it, in order.
  var tabs: [ImportTab] {
    switch self {
    case .tab(let tab): [tab]
    case .split(let panes, _): panes
    case .folder(_, let children): children.flatMap(\.tabs)
    }
  }
}

/// A bookmark or a bookmark folder, kept as the source has them.
nonisolated indirect enum ImportBookmark: Codable, Equatable, Sendable {
  case bookmark(title: String, url: String)
  case folder(name: String, children: [ImportBookmark])

  private enum CodingKeys: String, CodingKey { case bookmark, folder }
  private struct Bookmark: Codable { var title: String; var url: String }
  private struct Folder: Codable { var name: String; var children: [ImportBookmark] }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let bookmark = try container.decodeIfPresent(Bookmark.self, forKey: .bookmark) {
      self = .bookmark(title: bookmark.title, url: bookmark.url)
    } else {
      let folder = try container.decode(Folder.self, forKey: .folder)
      self = .folder(name: folder.name, children: folder.children)
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .bookmark(let title, let url): try container.encode(Bookmark(title: title, url: url), forKey: .bookmark)
    case .folder(let name, let children): try container.encode(Folder(name: name, children: children), forKey: .folder)
    }
  }

  /// How many bookmarks it holds, folders not counted.
  var count: Int {
    switch self {
    case .bookmark: 1
    case .folder(_, let children): children.reduce(0) { $0 + $1.count }
    }
  }
}

/// Why something didn't come over (D3). The raw values cross the contract.
nonisolated enum ImportSkipReason: String, Codable, Sendable, CaseIterable {
  /// An extension loaded unpacked or installed from outside the store.
  case notFromWebStore
  /// A theme or an app, which Clair doesn't install.
  case themeOrApp
  /// An extension the destination already has.
  case alreadyInstalled
  /// An extension the store couldn't provide.
  case storeFailed
  /// A sidebar item of a kind Clair has no place for, such as Arc's Easels.
  case unsupportedItem
  /// The source's sidebar couldn't be read: a denied keychain request, a
  /// wrong key or a changed format.
  case sidebarUnreadable
  /// A database copy that failed SQLite's `quick_check`.
  case unreadableData
  /// A page that couldn't be opened as a URL.
  case invalidURL
  /// The whole import: a plan the engine couldn't read, or one sent while
  /// another ran.
  case importFailed
}

nonisolated struct ImportSkip: Codable, Equatable, Sendable {
  var reason: ImportSkipReason
  /// The item's name or URL.
  var name: String
}

/// What an import did, as the engine reports it at the end (D3).
nonisolated struct ImportSummary: Codable, Equatable, Sendable {
  /// A count for each kind of item.
  struct Counts: Codable, Equatable, Sendable {
    var spaces = 0
    var favorites = 0
    var pinnedTabs = 0
    var todayTabs = 0
    var bookmarks = 0
    var history = 0
    var extensions = 0

    var isEmpty: Bool { self == Counts() }
  }

  /// What came over.
  var imported = Counts()
  /// What was skipped because the destination already had it ("Importing
  /// again").
  var alreadyInClair = Counts()
  var skipped: [ImportSkip] = []

  init(imported: Counts = Counts(), alreadyInClair: Counts = Counts(), skipped: [ImportSkip] = []) {
    self.imported = imported
    self.alreadyInClair = alreadyInClair
    self.skipped = skipped
  }

  init(json: Data) throws {
    self = try JSONDecoder().decode(ImportSummary.self, from: json)
  }
}

/// The pass every reader's trees go through before they're in a plan (D3),
/// so they fit what Clair shows: splits hold two panes side by side, pinned
/// folders hold no folders, and Today tabs and favorites hold no folders at
/// all.
nonisolated enum ImportShape {
  /// A Space's pinned section: nested folders become top-level folders named
  /// with their path ("Parent / Child"), each right after its parent; a
  /// folder holding only folders doesn't come over itself.
  static func pinned(_ items: [ImportItem]) -> [ImportItem] {
    var result: [ImportItem] = []
    for item in items {
      switch item {
      case .folder(let name, let children):
        result += folder(path: [name], children: children)
      default:
        result += tabsAndSplits(item)
      }
    }
    return result
  }

  /// Today tabs or favorites: a folder's contents take its place.
  static func flat(_ items: [ImportItem]) -> [ImportItem] {
    items.flatMap { item -> [ImportItem] in
      if case .folder(_, let children) = item {
        return flat(children)
      }
      return tabsAndSplits(item)
    }
  }

  private static func folder(path: [String], children: [ImportItem]) -> [ImportItem] {
    var own: [ImportItem] = []
    var nested: [ImportItem] = []
    for child in children {
      if case .folder(let name, let grandchildren) = child {
        nested += folder(path: path + [name], children: grandchildren)
      } else {
        own += tabsAndSplits(child)
      }
    }
    let onlyFolders = own.isEmpty && children.contains {
      if case .folder = $0 { return true }
      return false
    }
    let this: [ImportItem] = onlyFolders ? [] : [.folder(name: path.joined(separator: " / "), children: own)]
    return this + nested
  }

  /// A tab as it is; a split of two as a split, its ratio kept in (0, 1); a
  /// split of one or of three or more panes as its panes, in order.
  private static func tabsAndSplits(_ item: ImportItem) -> [ImportItem] {
    switch item {
    case .tab:
      return [item]
    case .split(let panes, let ratio):
      guard panes.count == 2 else { return panes.map(ImportItem.tab) }
      let clamped = ratio.isFinite && ratio > 0 && ratio < 1 ? ratio : 0.5
      return [.split(panes: panes, ratio: clamped)]
    case .folder(_, let children):
      return flat(children)
    }
  }
}
