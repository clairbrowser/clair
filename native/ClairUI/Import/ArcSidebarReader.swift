// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation

/// Reads Arc's `StorableSidebar.json` (add-browser-import design D4): its
/// Spaces with their emoji and profile, their pinned and Today trees, and each
/// profile's favorites. Arc keeps every list as a flat array alternating an
/// ID, or a key, and its object.
nonisolated enum ArcSidebarReader {
  static func read(_ file: URL) -> ImportSidebar {
    guard let data = try? Data(contentsOf: file),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return ImportSidebar(unreadable: "Arc's sidebar")
    }
    return read(json)
  }

  static func read(_ json: [String: Any]) -> ImportSidebar {
    let containers = (json["sidebar"] as? [String: Any])?["containers"] as? [Any] ?? []
    guard let container = containers.compactMap({ $0 as? [String: Any] }).first(where: { $0["spaces"] != nil }) else {
      return ImportSidebar(unreadable: "Arc's sidebar")
    }
    var items: [String: [String: Any]] = [:]
    for (key, value) in pairs(container["items"]) {
      if let id = key as? String, let item = value as? [String: Any] {
        items[id] = item
      }
    }
    var walker = Walker(items: items)
    var sidebar = ImportSidebar()

    for (_, value) in pairs(container["spaces"]) {
      guard let space = value as? [String: Any] else { continue }
      let profile = profileKey(space["profile"])
      var sections: [String: String] = [:]
      for (key, value) in pairs(space["containerIDs"]) {
        if let key = key as? String, let id = value as? String {
          sections[key] = id
        }
      }
      let name = (space["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Space"
      let result = ImportSidebar.Space(
        name: name, icon: emoji(space["customInfo"]),
        pinned: sections["pinned"].map { walker.children(of: $0) } ?? [],
        today: sections["unpinned"].map { walker.children(of: $0) } ?? [])
      sidebar.profiles[profile, default: ImportSidebar.Profile()].spaces.append(result)
    }

    for (key, value) in pairs(container["topAppsContainerIDs"]) {
      guard let id = value as? String else { continue }
      sidebar.profiles[profileKey(key), default: ImportSidebar.Profile()].favorites += walker.children(of: id)
    }

    // What couldn't come over goes with the first profile Arc lists.
    if !walker.skipped.isEmpty {
      let first = sidebar.profiles.keys.sorted { lhs, rhs in lhs == "Default" || (rhs != "Default" && lhs < rhs) }.first
      sidebar.profiles[first ?? "Default", default: ImportSidebar.Profile()].skipped += walker.skipped
    }
    return sidebar
  }

  private struct Walker {
    let items: [String: [String: Any]]
    var skipped: [ImportSkip] = []

    /// The items under `id`, in `childrenIds`' order, so items in no
    /// container are never reached.
    mutating func children(of id: String) -> [ImportItem] {
      let ids = items[id]?["childrenIds"] as? [String] ?? []
      return ids.compactMap { item(id: $0) }
    }

    private mutating func item(id: String) -> ImportItem? {
      guard let item = items[id], let data = item["data"] as? [String: Any] else { return nil }
      let customName = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      if let tab = data["tab"] as? [String: Any] {
        guard let tab = Self.tab(tab, name: customName) else { return nil }
        return .tab(tab)
      }
      if data["list"] != nil {
        return .folder(name: customName ?? "Folder", children: children(of: id))
      }
      if let split = data["splitView"] as? [String: Any] {
        let childIDs = item["childrenIds"] as? [String] ?? []
        let panes = childIDs.compactMap { childID -> ImportTab? in
          guard let tab = (items[childID]?["data"] as? [String: Any])?["tab"] as? [String: Any] else { return nil }
          let name = (items[childID]?["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
          return Self.tab(tab, name: name)
        }
        return .split(panes: panes, ratio: Self.leadingShare(split, paneIDs: childIDs))
      }
      // Easels, notes and other kinds Clair has no place for.
      let kind = data.keys.sorted().first ?? "item"
      skipped.append(ImportSkip(reason: .unsupportedItem, name: customName ?? kind))
      return nil
    }

    private static func tab(_ tab: [String: Any], name: String?) -> ImportTab? {
      guard let url = tab["savedURL"] as? String, !url.isEmpty else { return nil }
      return ImportTab(url: url, title: tab["savedTitle"] as? String ?? url, name: name)
    }

    /// The first pane's share: `itemWidthFactors` alternates a pane's ID and
    /// its share for every pane but the last.
    private static func leadingShare(_ split: [String: Any], paneIDs: [String]) -> Double {
      guard let first = paneIDs.first else { return 0.5 }
      for (key, value) in ArcSidebarReader.pairs(split["itemWidthFactors"]) {
        if key as? String == first, let share = value as? Double {
          return share
        }
      }
      return paneIDs.isEmpty ? 0.5 : 1 / Double(paneIDs.count)
    }
  }

  /// A flat alternating array as pairs.
  fileprivate static func pairs(_ value: Any?) -> [(Any, Any)] {
    guard let array = value as? [Any] else { return [] }
    return stride(from: 0, to: array.count - 1, by: 2).map { (array[$0], array[$0 + 1]) }
  }

  /// The profile folder a Space or favorites container names:
  /// `{"default": true}` is "Default", `{"custom": {"_0": {"directoryBasename":
  /// "Profile 6"}}}` is "Profile 6".
  static func profileKey(_ value: Any?) -> String {
    guard let profile = value as? [String: Any],
      let custom = (profile["custom"] as? [String: Any])?["_0"] as? [String: Any],
      let folder = custom["directoryBasename"] as? String, !folder.isEmpty
    else { return "Default" }
    return folder
  }

  /// A Space's emoji icon, from `customInfo.iconType`.
  private static func emoji(_ value: Any?) -> String? {
    guard let icon = (value as? [String: Any])?["iconType"] as? [String: Any] else { return nil }
    if let emoji = icon["emoji_v2"] as? String, !emoji.isEmpty {
      return emoji
    }
    if let code = icon["emoji"] as? Int, let scalar = Unicode.Scalar(code) {
      return String(Character(scalar))
    }
    return nil
  }
}
