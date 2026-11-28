// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation

/// Safari's data, from the .zip its File › Export Browsing Data to File…
/// writes, or the folder it unpacks to (add-browser-import design D6). Clair
/// asks for no Full Disk Access.
nonisolated struct SafariExportSource: ImportSource {
  /// The file the user chose, once it checked out.
  var export: SafariExport?

  var id: String { "safari" }
  var name: String { "Safari" }
  var bundleID: String { "com.apple.Safari" }
  var items: [ImportItemKind] { [.bookmarks, .history] }
  var requirement: ImportRequirement { .exportFile }
  /// Always: its data comes from a file the user exports.
  var isPresent: Bool { true }

  func profiles() -> [ImportSourceProfile] {
    [ImportSourceProfile(key: "Safari", name: "Safari", newProfileName: "Safari")]
  }

  func makePlan(_ context: ImportContext) throws -> ImportPlan {
    guard let export else { throw SafariExport.Error.notAnExport }
    let folder: URL
    switch export.kind {
    case .zip:
      folder = try context.folder.subfolder("safari")
      try SafariExport.unzip(export.url, into: folder)
    case .folder:
      folder = export.url
    }
    let files = SafariExport.files(in: folder)
    var profile = ImportPlan.Profile(
      sourceKey: "Safari", sourceName: "Safari", destination: context.destinations["Safari"] ?? .newProfile("Safari"))
    if let bookmarks = files.bookmarks, let html = try? String(contentsOf: bookmarks, encoding: .utf8) {
      let parsed = SafariBookmarks.parse(html)
      profile.bookmarks = parsed.isEmpty ? nil : parsed
    }
    if let history = files.history {
      profile.history = .safariJSON(history.path)
    }
    return ImportPlan(source: id, sourceName: name, folder: context.folder.url.path, profiles: [profile])
  }
}

/// A chosen Safari export, checked without unpacking it (D10).
nonisolated struct SafariExport: Equatable, Sendable {
  enum Kind: Sendable { case zip, folder }

  enum Error: Swift.Error, Equatable {
    /// Neither `Bookmarks.html` nor `History.json` is in it.
    case notAnExport
  }

  let url: URL
  let kind: Kind
  let hasBookmarks: Bool
  let hasHistory: Bool

  /// Checks `url`, a .zip or a folder, for Safari's files.
  static func check(_ url: URL) throws -> SafariExport {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { throw Error.notAnExport }
    let names: [String]
    let kind: Kind
    if isDirectory.boolValue {
      kind = .folder
      let found = files(in: url)
      names = [found.bookmarks, found.history].compactMap { $0?.lastPathComponent }
    } else {
      kind = .zip
      names = zipEntries(url).map { ($0 as NSString).lastPathComponent }
    }
    let hasBookmarks = names.contains(where: isBookmarks)
    let hasHistory = names.contains(where: isHistory)
    guard hasBookmarks || hasHistory else { throw Error.notAnExport }
    return SafariExport(url: url, kind: kind, hasBookmarks: hasBookmarks, hasHistory: hasHistory)
  }

  static func isBookmarks(_ name: String) -> Bool {
    name.lowercased().hasPrefix("bookmarks") && name.lowercased().hasSuffix(".html")
  }

  static func isHistory(_ name: String) -> Bool {
    name.lowercased().hasPrefix("history") && name.lowercased().hasSuffix(".json")
  }

  /// Safari's files in a folder or the folders under it; `History.json` is
  /// preferred over another history file.
  static func files(in folder: URL) -> (bookmarks: URL?, history: URL?) {
    var bookmarks: URL?
    var histories: [URL] = []
    // Relative paths keep the folder's own spelling of its path.
    let enumerator = FileManager.default.enumerator(atPath: folder.path)
    while let relative = enumerator?.nextObject() as? String {
      let file = folder.appending(path: relative)
      let name = file.lastPathComponent
      if bookmarks == nil, isBookmarks(name) {
        bookmarks = file
      } else if isHistory(name) {
        histories.append(file)
      }
    }
    let history = histories.first { $0.lastPathComponent == "History.json" } ?? histories.sorted { $0.path < $1.path }.first
    return (bookmarks, history)
  }

  /// The paths in a .zip, without unpacking it; empty when it isn't one.
  static func zipEntries(_ zip: URL) -> [String] {
    let output = run("/usr/bin/zipinfo", ["-1", zip.path])
    guard output.status == 0 else { return [] }
    return output.text.split(separator: "\n").map(String.init)
  }

  /// Unpacks a .zip with `ditto`.
  static func unzip(_ zip: URL, into folder: URL) throws {
    guard run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path]).status == 0 else { throw Error.notAnExport }
  }

  private static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, text: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return (-1, "")
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
  }
}

/// Safari's `Bookmarks.html`, in Netscape's format (D6): the Favorites bar's
/// contents first, then the file's other top-level items, with no folder
/// added around them; the Reading List is dropped.
nonisolated enum SafariBookmarks {
  private struct Folder {
    var name: String
    var id: String?
    var children: [ImportBookmark] = []
  }

  static func parse(_ html: String) -> [ImportBookmark] {
    var stack = [Folder(name: "")]
    var pendingFolder: (name: String, id: String?)?
    var index = html.startIndex
    while let open = html[index...].firstIndex(of: "<") {
      guard let close = html[open...].firstIndex(of: ">") else { break }
      let tag = html[html.index(after: open)..<close]
      let name = tag.prefix { !$0.isWhitespace }.uppercased()
      index = html.index(after: close)
      switch name {
      case "H3":
        let end = html[index...].range(of: "</H3>", options: .caseInsensitive)?.lowerBound ?? html.endIndex
        pendingFolder = (decode(String(html[index..<end])), attribute("id", in: tag))
        index = end
      case "DL":
        let folder = pendingFolder ?? (name: "", id: nil)
        stack.append(Folder(name: folder.name, id: folder.id))
        pendingFolder = nil
      case "/DL":
        guard stack.count > 1 else { continue }
        let folder = stack.removeLast()
        // Only the file's own top-level folders are Safari's special ones.
        stack[stack.count - 1].children.append(stack.count <= 2 ? marked(folder) : .folder(name: folder.name, children: folder.children))
      case "A":
        let end = html[index...].range(of: "</A>", options: .caseInsensitive)?.lowerBound ?? html.endIndex
        if let url = attribute("href", in: tag), !url.isEmpty {
          stack[stack.count - 1].children.append(.bookmark(title: decode(String(html[index..<end])), url: url))
        }
        index = end
      default:
        break
      }
    }
    // A file that never closes its lists.
    while stack.count > 1 {
      let folder = stack.removeLast()
      stack[stack.count - 1].children.append(marked(folder))
    }
    // The file's own outer list holds everything.
    var top = stack[0].children
    if top.count == 1, case .folder(let name, let children) = top[0], name.isEmpty {
      top = children
    }
    var favorites: [ImportBookmark] = []
    var rest: [ImportBookmark] = []
    for item in top {
      if case .folder(let name, let children) = item {
        if name == readingListMarker { continue }
        if name == favoritesMarker {
          favorites += children
          continue
        }
      }
      rest.append(item)
    }
    return favorites + rest
  }

  private static let readingListMarker = "\u{1}ReadingList"
  private static let favoritesMarker = "\u{1}Favorites"

  /// Marks Safari's Favorites bar and Reading List, which `parse` places or
  /// drops.
  private static func marked(_ folder: Folder) -> ImportBookmark {
    if folder.id == "com.apple.ReadingList" || folder.name == "Reading List" {
      return .folder(name: readingListMarker, children: folder.children)
    }
    if folder.id == "com.apple.FavoritesBar" || folder.name == "Favorites" || folder.name == "Favourites" {
      return .folder(name: favoritesMarker, children: folder.children)
    }
    return .folder(name: folder.name, children: folder.children)
  }

  private static func attribute(_ name: String, in tag: Substring) -> String? {
    guard let range = tag.range(of: name + "=", options: .caseInsensitive) else { return nil }
    var rest = tag[range.upperBound...]
    guard let quote = rest.first, quote == "\"" || quote == "'" else {
      return decode(String(rest.prefix { !$0.isWhitespace }))
    }
    rest = rest.dropFirst()
    return decode(String(rest.prefix { $0 != quote }))
  }

  /// HTML's entities, named and numeric.
  static func decode(_ text: String) -> String {
    guard text.contains("&") else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var result = ""
    var index = text.startIndex
    while index < text.endIndex {
      if text[index] == "&", let semicolon = text[index...].firstIndex(of: ";"),
        text.distance(from: index, to: semicolon) <= 10
      {
        let entity = text[text.index(after: index)..<semicolon]
        if let character = character(for: entity) {
          result.append(character)
          index = text.index(after: semicolon)
          continue
        }
      }
      result.append(text[index])
      index = text.index(after: index)
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func character(for entity: Substring) -> Character? {
    switch entity {
    case "amp": return "&"
    case "lt": return "<"
    case "gt": return ">"
    case "quot": return "\""
    case "apos": return "'"
    case "nbsp": return "\u{a0}"
    default:
      guard entity.hasPrefix("#") else { return nil }
      let digits = entity.dropFirst()
      let value = digits.hasPrefix("x") || digits.hasPrefix("X") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
      return value.flatMap(Unicode.Scalar.init).map(Character.init)
    }
  }
}
