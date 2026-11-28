// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation

/// What sets one Chromium-based browser apart (design D2): another one, such
/// as Brave, Edge or Vivaldi, is a descriptor like Chrome's.
nonisolated struct ChromiumFamilyDescriptor: Sendable {
  enum Sidebar: Sendable {
    /// Arc's `StorableSidebar.json`, at this path under Application Support.
    case arc(path: String)
    /// Dia's encrypted `tabs.db` in each profile, whose key is this keychain
    /// item's.
    case dia(keychainService: String)
    /// Chromium's own last session, which the engine reads (D13).
    case session
  }

  var id: String
  var name: String
  var bundleID: String
  /// The user data folder under Application Support.
  var userDataPath: String
  var sidebar: Sidebar

  static let arc = ChromiumFamilyDescriptor(
    id: "arc", name: "Arc", bundleID: "company.thebrowser.Browser", userDataPath: "Arc/User Data",
    sidebar: .arc(path: "Arc/StorableSidebar.json"))
  static let dia = ChromiumFamilyDescriptor(
    id: "dia", name: "Dia", bundleID: "company.thebrowser.dia", userDataPath: "Dia/User Data",
    sidebar: .dia(keychainService: "Dia Safe Storage"))
  static let chrome = ChromiumFamilyDescriptor(
    id: "chrome", name: "Chrome", bundleID: "com.google.Chrome", userDataPath: "Google/Chrome", sidebar: .session)
}

/// A Chromium-based browser's data (design D2, D7): `Local State`'s profiles
/// and, per profile, bookmarks, history, favicons and extensions, with Arc's
/// or Dia's sidebar or Chrome's session.
nonisolated struct ChromiumFamilySource: ImportSource {
  let descriptor: ChromiumFamilyDescriptor
  let environment: ImportEnvironment

  init(_ descriptor: ChromiumFamilyDescriptor, environment: ImportEnvironment) {
    self.descriptor = descriptor
    self.environment = environment
  }

  var id: String { descriptor.id }
  var name: String { descriptor.name }
  var bundleID: String { descriptor.bundleID }

  var items: [ImportItemKind] {
    switch descriptor.sidebar {
    case .arc, .dia: ImportItemKind.allCases
    case .session: [.pinnedTabs, .todayTabs, .bookmarks, .history, .extensions]
    }
  }

  var requirement: ImportRequirement {
    if case .dia(let service) = descriptor.sidebar {
      return .keychain(service: service)
    }
    return .none
  }

  var userData: URL { environment.applicationSupport.appending(path: descriptor.userDataPath, directoryHint: .isDirectory) }

  /// Arc when its sidebar exists, Dia when a profile has its `tabs.db`,
  /// Chrome when `Local State` lists a profile (D2).
  var isPresent: Bool {
    switch descriptor.sidebar {
    case .arc(let path):
      return FileManager.default.fileExists(atPath: environment.applicationSupport.appending(path: path).path)
    case .dia:
      return localState.keys.contains {
        FileManager.default.fileExists(atPath: userData.appending(path: "\($0)/tabs.db").path)
      }
    case .session:
      return !localState.keys.isEmpty
    }
  }

  var localState: ChromiumLocalState { ChromiumLocalState(userData: userData) }

  func profiles() -> [ImportSourceProfile] {
    localState.profiles.map { key, name in
      if case .dia = descriptor.sidebar {
        let names = Self.diaProfileNames(name)
        return ImportSourceProfile(key: key, name: names.joined(separator: ", "), newProfileName: names[0])
      }
      return ImportSourceProfile(key: key, name: name, newProfileName: name)
    }
  }

  /// Dia names a Chromium profile its Dia profiles share as "Profile 2
  /// (sharing data with 3)"; its row reads "Profile 2, Profile 3"
  /// (browser-import "Choosing destination profiles").
  static func diaProfileNames(_ name: String) -> [String] {
    guard let open = name.range(of: " (sharing data with "), name.hasSuffix(")") else { return [name] }
    let first = String(name[..<open.lowerBound])
    let list = name[open.upperBound..<name.index(before: name.endIndex)]
    let others = list.replacingOccurrences(of: " and ", with: ",").split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    // "Profile 2" sharing with "3" is "Profile 3"; a full name stays as is.
    let prefix = first.split(separator: " ").dropLast().joined(separator: " ")
    let lastWord = first.split(separator: " ").last.map(String.init) ?? ""
    return [first]
      + others.map { other in
        Int(other) != nil && Int(lastWord) != nil && !prefix.isEmpty ? "\(prefix) \(other)" : other
      }
  }

  func makePlan(_ context: ImportContext) throws -> ImportPlan {
    let sourceProfiles = profiles()
    var sidebar = ImportSidebar()
    switch descriptor.sidebar {
    case .arc(let path):
      sidebar = ArcSidebarReader.read(environment.applicationSupport.appending(path: path))
    case .dia(let service):
      sidebar = DiaSidebarReader.read(
        userData: userData, profiles: sourceProfiles.map(\.key), secret: context.keychain.password(service: service))
    case .session:
      break
    }
    var planProfiles: [ImportPlan.Profile] = []
    for (index, source) in sourceProfiles.enumerated() {
      let directory = userData.appending(path: source.key, directoryHint: .isDirectory)
      let copies = try context.folder.subfolder("\(index)")
      var profile = ImportPlan.Profile(
        sourceKey: source.key, sourceName: source.name,
        destination: context.destinations[source.key] ?? .newProfile(source.newProfileName))
      if let content = sidebar.profiles[source.key] {
        profile.spaces = content.spaces.map {
          ImportPlan.Space(name: $0.name, icon: $0.icon, pinned: ImportShape.pinned($0.pinned), today: ImportShape.flat($0.today))
        }
        profile.favorites = ImportShape.flat(content.favorites)
        profile.skipped = content.skipped
      }
      // A sidebar that couldn't be read at all is reported once.
      if let unreadable = sidebar.unreadable, index == 0 {
        profile.skipped.append(ImportSkip(reason: .sidebarUnreadable, name: unreadable))
      }
      profile.bookmarks = ChromiumBookmarks.read(profile: directory)
      if let history = try ImportWorkFolder.copyDatabase(directory.appending(path: "History"), into: copies) {
        profile.history = .chromiumDB(history.path)
      }
      if let favicons = try ImportWorkFolder.copyDatabase(directory.appending(path: "Favicons"), into: copies) {
        profile.favicons = .chromiumDB(favicons.path)
      }
      if case .session = descriptor.sidebar,
        let sessions = try ImportWorkFolder.copyFolder(directory.appending(path: "Sessions"), into: copies)
      {
        profile.session = ImportPlan.Session(chromiumSessions: sessions.path, space: source.name)
      }
      let extensions = ChromiumExtensions.read(profile: directory)
      profile.extensions = extensions.kept
      profile.skipped += extensions.skipped
      planProfiles.append(profile)
    }
    return ImportPlan(source: id, sourceName: name, folder: context.folder.url.path, profiles: planProfiles)
  }
}

/// What a sidebar reader found, by source profile key.
nonisolated struct ImportSidebar: Sendable {
  struct Space: Equatable, Sendable {
    var name: String
    var icon: String?
    var pinned: [ImportItem] = []
    var today: [ImportItem] = []
  }

  struct Profile: Equatable, Sendable {
    var spaces: [Space] = []
    var favorites: [ImportItem] = []
    var skipped: [ImportSkip] = []
  }

  var profiles: [String: Profile] = [:]
  /// Set when the sidebar couldn't be read: what the summary names.
  var unreadable: String?
}

/// `Local State`'s profiles: their folder names and display names, in
/// Chromium's order.
nonisolated struct ChromiumLocalState {
  let profiles: [(key: String, name: String)]

  var keys: [String] { profiles.map(\.key) }

  init(userData: URL) {
    guard let data = try? Data(contentsOf: userData.appending(path: "Local State")),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let profile = json["profile"] as? [String: Any],
      let cache = profile["info_cache"] as? [String: Any]
    else {
      profiles = []
      return
    }
    let order = (profile["profiles_order"] as? [String]) ?? []
    let keys =
      order.filter { cache[$0] != nil }
      + cache.keys.filter { !order.contains($0) }.sorted { lhs, rhs in
        lhs == "Default" || (rhs != "Default" && lhs.localizedStandardCompare(rhs) == .orderedAscending)
      }
    profiles = keys.compactMap { key in
      // A profile in the cache whose folder is gone has nothing to import.
      guard FileManager.default.fileExists(atPath: userData.appending(path: key).path) else { return nil }
      let name = ((cache[key] as? [String: Any])?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? key
      return (key, name)
    }
  }
}

/// A profile's bookmarks (D7): `Bookmarks`, and `AccountBookmarks` when
/// signed in, as one list: the bar's contents, then the other bookmarks',
/// then the mobile ones', as Clair's own bar drain orders them.
nonisolated enum ChromiumBookmarks {
  static func read(profile: URL) -> [ImportBookmark]? {
    let roots = ["Bookmarks", "AccountBookmarks"].compactMap { file -> [String: Any]? in
      guard let data = try? Data(contentsOf: profile.appending(path: file)),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { return nil }
      return json["roots"] as? [String: Any]
    }
    var result: [ImportBookmark] = []
    for root in ["bookmark_bar", "other", "synced"] {
      for file in roots {
        result += children(of: file[root])
      }
    }
    return result.isEmpty ? nil : result
  }

  private static func children(of node: Any?) -> [ImportBookmark] {
    guard let node = node as? [String: Any], let children = node["children"] as? [[String: Any]] else { return [] }
    return children.compactMap { child in
      let name = child["name"] as? String ?? ""
      switch child["type"] as? String {
      case "url":
        guard let url = child["url"] as? String, !url.isEmpty else { return nil }
        return .bookmark(title: name, url: url)
      case "folder":
        return .folder(name: name, children: Self.children(of: child))
      default:
        return nil
      }
    }
  }
}

/// A profile's extensions (D7): the union of `extensions.settings` in
/// `Preferences` and `Secure Preferences`. Kept: those installed from the
/// Chrome Web Store that aren't themes or apps.
nonisolated enum ChromiumExtensions {
  /// Chromium's `Manifest::Location::kInternal`, a store install.
  private static let internalLocation = 1
  /// Chromium's component locations, its own extensions, which aren't the
  /// user's and aren't reported.
  private static let componentLocations: Set<Int> = [5, 10]
  /// Chrome's `DISABLE_UNSUPPORTED_MANIFEST_VERSION`, which Clair doesn't
  /// apply: an extension disabled only for it comes over turned on.
  private static let unsupportedManifestVersion = 1 << 23

  static func read(profile: URL) -> (kept: [ImportPlan.Extension], skipped: [ImportSkip]) {
    let preferences = ["Preferences", "Secure Preferences"].map { file -> [String: Any] in
      guard let data = try? Data(contentsOf: profile.appending(path: file)),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { return [:] }
      return json
    }
    var settings: [String: [String: Any]] = [:]
    var pinned: Set<String> = []
    for json in preferences {
      let extensions = json["extensions"] as? [String: Any] ?? [:]
      for (id, value) in extensions["settings"] as? [String: Any] ?? [:] {
        guard let value = value as? [String: Any] else { continue }
        settings[id, default: [:]].merge(value) { _, new in new }
      }
      pinned.formUnion(extensions["pinned_extensions"] as? [String] ?? [])
    }
    var kept: [ImportPlan.Extension] = []
    var skipped: [ImportSkip] = []
    for id in settings.keys.sorted() {
      let entry = settings[id] ?? [:]
      guard let location = entry["location"] as? Int, !componentLocations.contains(location) else { continue }
      let manifest = Self.manifest(entry, profile: profile)
      let name = Self.name(manifest, entry: entry, profile: profile) ?? id
      guard location == internalLocation, entry["from_webstore"] as? Bool == true else {
        skipped.append(ImportSkip(reason: .notFromWebStore, name: name))
        continue
      }
      if manifest["theme"] != nil || manifest["app"] != nil {
        skipped.append(ImportSkip(reason: .themeOrApp, name: name))
        continue
      }
      let manifestJSON = manifest.isEmpty
        ? nil : (try? JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) }
      kept.append(
        ImportPlan.Extension(
          id: id, name: name, enabled: isEnabled(entry), pinned: pinned.contains(id), manifest: manifestJSON))
    }
    return (kept, skipped)
  }

  /// Turned on unless a reason other than the manifest version's disables it.
  /// Newer Chromium keeps a list of reasons, older a bit mask, older still a
  /// `state` of 0.
  static func isEnabled(_ entry: [String: Any]) -> Bool {
    var reasons: [Int] = []
    if let list = entry["disable_reasons"] as? [Int] {
      reasons = list
    } else if let mask = entry["disable_reasons"] as? Int {
      reasons = (0..<31).map { 1 << $0 }.filter { mask & $0 != 0 }
    } else if entry["state"] as? Int == 0 {
      return false
    }
    return reasons.allSatisfy { $0 == unsupportedManifestVersion }
  }

  /// The manifest the prefs keep, or else the one in the profile's
  /// `Extensions` folder.
  private static func manifest(_ entry: [String: Any], profile: URL) -> [String: Any] {
    if let manifest = entry["manifest"] as? [String: Any] {
      return manifest
    }
    guard let folder = installFolder(entry, profile: profile),
      let data = try? Data(contentsOf: folder.appending(path: "manifest.json")),
      let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return manifest
  }

  private static func installFolder(_ entry: [String: Any], profile: URL) -> URL? {
    guard let path = entry["path"] as? String, !path.isEmpty else { return nil }
    return path.hasPrefix("/") ? URL(fileURLWithPath: path) : profile.appending(path: "Extensions/\(path)")
  }

  /// The manifest's name, its `__MSG_…__` placeholder looked up in the
  /// default locale's messages.
  private static func name(_ manifest: [String: Any], entry: [String: Any], profile: URL) -> String? {
    guard let name = manifest["name"] as? String, !name.isEmpty else { return nil }
    guard name.hasPrefix("__MSG_"), name.hasSuffix("__") else { return name }
    let key = String(name.dropFirst(6).dropLast(2)).lowercased()
    guard let locale = manifest["default_locale"] as? String, let folder = installFolder(entry, profile: profile),
      let data = try? Data(contentsOf: folder.appending(path: "_locales/\(locale)/messages.json")),
      let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    let message = messages.first { $0.key.lowercased() == key }?.value as? [String: Any]
    return message?["message"] as? String
  }
}
