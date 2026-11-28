// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import CommonCrypto
import CryptoKit
import Foundation
import SQLite3

/// A fake home folder holding other browsers' data, which Clair's sources read
/// through `CLAIR_TEST_IMPORT_ROOT` (add-browser-import design D12). Arc's comes
/// from ClairUI's unit test fixtures; the rest is made here, with pages of the
/// suite's server so a test can tell whether they loaded.
struct ImportHome {
  /// ClairUI's fixtures, beside this suite in the repository.
  static let unitFixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "native/ClairUITests/Fixtures/Import")

  /// The secret Dia's fixture is encrypted with, passed as
  /// `CLAIR_TEST_DIA_SECRET`.
  static let diaSecret = "clair-runtime-dia-secret"

  let root: URL
  let baseURL: String

  init(baseURL: String) throws {
    self.baseURL = baseURL
    root = FileManager.default.temporaryDirectory.appending(path: "ClairImportHome-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
  }

  var support: URL { root.appending(path: "Library/Application Support") }

  /// The launch environment that points Clair's sources here.
  var environment: [String: String] {
    ["CLAIR_TEST_IMPORT_ROOT": root.path, "CLAIR_TEST_DIA_SECRET": Self.diaSecret]
  }

  func page(_ name: String) -> String { "\(baseURL)/pages/index.html?\(name)" }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  // MARK: Arc

  /// Arc's probed sidebar, with "Work" holding a bookmark bar, Other
  /// Bookmarks and a history page.
  func addArc() throws {
    try FileManager.default.copyItem(
      at: Self.unitFixtures.appending(path: "home/Library/Application Support/Arc"), to: support.appending(path: "Arc"))
    try ChromiumHistory.write(
      to: support.appending(path: "Arc/User Data/Profile 6/History"),
      pages: [(page("arc-history"), "Clair Arc History Page", Date.now.addingTimeInterval(-3600))])
  }

  // MARK: Chrome

  /// Chrome's "Person 1": a window with the pinned tab, A and B, Docs and
  /// Mail split at 60%, D and E in the group "Trip"; another window with C.
  /// `extensions` are its Web Store extensions' settings.
  func addChrome(extensions: [String: Any] = [:], pinnedExtensions: [String] = []) throws {
    let chrome = support.appending(path: "Google/Chrome")
    let profile = chrome.appending(path: "Default")
    try FileManager.default.createDirectory(at: profile.appending(path: "Sessions"), withIntermediateDirectories: true)
    try write(["profile": ["info_cache": ["Default": ["name": "Person 1"]]]], to: chrome.appending(path: "Local State"))
    try write(
      [
        "roots": [
          "bookmark_bar": [
            "type": "folder", "name": "Bookmarks bar",
            "children": [
              ["type": "url", "name": "Chrome Bar Page", "url": page("chrome-bar")],
              [
                "type": "folder", "name": "Chrome News",
                "children": [["type": "url", "name": "Chrome Nested", "url": page("chrome-nested")]],
              ],
            ],
          ],
          "other": [
            "type": "folder", "name": "Other bookmarks",
            "children": [["type": "url", "name": "Chrome Other Page", "url": page("chrome-other")]],
          ],
          "synced": ["type": "folder", "name": "Mobile bookmarks", "children": [[String: Any]]()],
        ],
        "version": 1,
      ], to: profile.appending(path: "Bookmarks"))
    try write(
      ["extensions": ["pinned_extensions": pinnedExtensions, "settings": [String: Any]()]],
      to: profile.appending(path: "Preferences"))
    try write(["extensions": ["settings": extensions]], to: profile.appending(path: "Secure Preferences"))
    try ChromiumHistory.write(
      to: profile.appending(path: "History"),
      pages: [(page("chrome-history"), "Clair Chrome History Page", Date.now.addingTimeInterval(-7200))])

    var session = SessionFile()
    session.window(1, tabs: [
      .init(id: 10, url: page("chrome-pinned"), title: "Chrome Pinned", pinned: true),
      .init(id: 11, url: page("chrome-a"), title: "Chrome A"),
      .init(id: 12, url: page("chrome-b"), title: "Chrome B"),
      .init(id: 13, url: page("chrome-docs"), title: "Chrome Docs", split: 1),
      .init(id: 14, url: page("chrome-mail"), title: "Chrome Mail", split: 1),
      .init(id: 15, url: page("chrome-d"), title: "Chrome D", group: 7),
      .init(id: 16, url: page("chrome-e"), title: "Chrome E", group: 7),
    ])
    session.split(1, ratio: 0.6)
    session.window(2, tabs: [.init(id: 20, url: page("chrome-c"), title: "Chrome C")])
    try session.data().write(to: profile.appending(path: "Sessions/Session_13377777777777777"))
  }

  // MARK: Dia

  /// Dia's "Profile 2" and "Profile 3", sharing "Profile 4": a favorite, a
  /// pinned group nest, and a window with a split and a tab.
  func addDia() throws {
    let userData = support.appending(path: "Dia/User Data")
    try FileManager.default.createDirectory(at: userData, withIntermediateDirectories: true)
    try write(
      ["profile": ["info_cache": ["Profile 4": ["name": "Profile 2 (sharing data with 3)"]]]],
      to: userData.appending(path: "Local State"))
    typealias B = DiaDatabase
    var rows = [
      B.space("s1", "Profile 2"), B.space("s2", "Profile 3"),
      B.node(1, "favorites", order: 0, space: "s1"),
      B.node(2, "pinned_container", order: 1, space: "s1"),
      B.node(3, "window", order: 2, space: "s1"),
      B.node(4, "window", order: 0, space: "s2"),
    ]
    rows += B.tab(10, parent: 1, order: 0, space: "s1", pages: [(page("dia-favorite"), "Dia Favorite", nil)])
    rows += B.group(11, "Outer", parent: 2, order: 0, space: "s1")
    rows += B.group(12, "Inner", parent: 11, order: 0, space: "s1")
    rows += B.tab(13, parent: 12, order: 0, space: "s1", pages: [(page("dia-pinned"), "Dia Pinned", "Dia Renamed")])
    rows += B.tab(
      14, parent: 3, order: 0, space: "s1",
      pages: [(page("dia-left"), "Dia Left", nil), (page("dia-right"), "Dia Right", nil)], widths: "[700, 300]")
    rows += B.tab(15, parent: 3, order: 1, space: "s1", pages: [(page("dia-today"), "Dia Today", nil)])
    rows += B.tab(16, parent: 4, order: 0, space: "s2", pages: [(page("dia-second"), "Dia Second Space", nil)])
    try B.write(rows, to: userData.appending(path: "Profile 4/tabs.db"), secret: Self.diaSecret, profile: "Profile 4")
  }

  // MARK: Safari

  /// Safari's export as a .zip: Favorites holding a page and the folder
  /// "Safari News", a top-level page, a Reading List, and history.
  func safariExport() throws -> URL {
    let folder = root.appending(path: "Safari Export")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let html = """
      <!DOCTYPE NETSCAPE-Bookmark-file-1>
      <HTML><META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8"><Title>Bookmarks</Title><H1>Bookmarks</H1>
      <DT><H3 FOLDED>Favorites</H3>
      <DL><p>
      <DT><A HREF="\(page("safari-favorite"))">Safari Favorite Page</A>
      <DT><H3 FOLDED>Safari News</H3>
      <DL><p>
      <DT><A HREF="\(page("safari-news"))">Safari News Page</A>
      </DL><p>
      </DL><p>
      <DT><A HREF="\(page("safari-loose"))">Safari Loose Page</A>
      <DT><H3 FOLDED id="com.apple.ReadingList">Reading List</H3>
      <DL><p>
      <DT><A HREF="\(page("safari-later"))">Safari Read Later</A>
      </DL><p>
      </HTML>
      """
    try Data(html.utf8).write(to: folder.appending(path: "Bookmarks.html"))
    let visit = Int64((Date.now.timeIntervalSince1970 - 1800) * 1_000_000)
    try write(
      [
        "metadata": ["browser_name": "Safari", "data_type": "history", "schema_version": 1],
        "history": [
          ["url": page("safari-history"), "title": "Clair Safari History Page", "time_usec": visit, "visit_count": 2]
        ],
      ], to: folder.appending(path: "History.json"))
    let zip = root.appending(path: "Safari Export.zip")
    let ditto = Process()
    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    ditto.arguments = ["-c", "-k", "--keepParent", folder.path, zip.path]
    try ditto.run()
    ditto.waitUntilExit()
    try FileManager.default.removeItem(at: folder)
    return zip
  }

  private func write(_ object: Any, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: object).write(to: url)
  }
}

// MARK: Chromium's History

/// A Chromium `History` database with the `urls` table the import reads.
enum ChromiumHistory {
  static func write(to url: URL, pages: [(url: String, title: String, lastVisit: Date)]) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let db = try SQLiteFile(url)
    defer { db.close() }
    try db.exec(
      """
      CREATE TABLE urls(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR,
        visit_count INTEGER DEFAULT 0 NOT NULL, typed_count INTEGER DEFAULT 0 NOT NULL,
        last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0 NOT NULL);
      CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER NOT NULL, visit_time INTEGER NOT NULL);
      """)
    for page in pages {
      // Microseconds since 1601.
      let time = Int64((page.lastVisit.timeIntervalSince1970 + 11_644_473_600) * 1_000_000)
      try db.exec(
        "INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time, hidden) VALUES ('\(page.url)', '\(page.title)', 3, 1, \(time), 0)"
      )
    }
  }
}

/// A SQLite file opened through the C API.
final class SQLiteFile {
  private var db: OpaquePointer?

  init(_ url: URL, reserveBytes: Int32? = nil) throws {
    guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw HarnessError("Couldn't create \(url.path)") }
    if var reserve = reserveBytes {
      // SQLITE_FCNTL_RESERVE_BYTES.
      sqlite3_file_control(db, "main", 38, &reserve)
    }
  }

  func exec(_ sql: String) throws {
    var error: UnsafeMutablePointer<CChar>?
    let status = sqlite3_exec(db, sql, nil, nil, &error)
    let message = error.map { String(cString: $0) } ?? ""
    sqlite3_free(error)
    guard status == SQLITE_OK else { throw HarnessError("\(sql): \(message)") }
  }

  func close() {
    sqlite3_close(db)
    db = nil
  }
}

// MARK: Chrome's session file

/// Chromium's session file (SNSS, version 3): the commands
/// `sessions::RestoreSessionFromCommands` reads, then the marker that says
/// the state is complete. Payloads are Chromium's structs, little-endian, and
/// pickles.
struct SessionFile {
  struct Tab {
    var id: Int32
    var url: String
    var title: String
    var pinned = false
    var split: UInt64?
    var group: UInt64?
  }

  private var commands: [(id: UInt8, payload: Data)] = []

  mutating func window(_ id: Int32, tabs: [Tab]) {
    commands.append((9, int32s(id, 0)))  // kCommandSetWindowType, TYPE_NORMAL
    for (index, tab) in tabs.enumerated() {
      commands.append((0, int32s(id, tab.id)))  // kCommandSetTabWindow
      commands.append((2, int32s(tab.id, Int32(index))))  // kCommandSetTabIndexInWindow
      var navigation = Pickle()
      navigation.int32(tab.id)
      navigation.int32(0)  // its index
      navigation.string(tab.url)
      navigation.string16(tab.title)
      navigation.string("")  // page state
      navigation.int32(0)  // PAGE_TRANSITION_LINK
      commands.append((6, navigation.data()))  // kCommandUpdateTabNavigation
      commands.append((7, int32s(tab.id, 0)))  // kCommandSetSelectedNavigationIndex
      if tab.pinned {
        commands.append((12, int32s(tab.id) + Data([1, 0, 0, 0])))  // kCommandSetPinnedState
      }
      if let group = tab.group {
        commands.append((25, tokenPayload(tab.id, group)))  // kCommandSetTabGroup
      }
      if let split = tab.split {
        commands.append((36, tokenPayload(tab.id, split)))  // kCommandSetSplitTab
      }
    }
    commands.append((8, int32s(id, 0)))  // kCommandSetSelectedTabInIndex
  }

  mutating func split(_ token: UInt64, ratio: Double) {
    var data = Pickle()
    data.uint64(token)
    data.uint64(token)
    data.double(ratio)
    data.string("Vertical")
    commands.append((37, data.data()))  // kCommandSetSplitTabData
  }

  func data() -> Data {
    var out = int32s(0x5353_4E53, 3)
    for command in commands + [(255, Data())] {  // the marker
      out += le(UInt16(command.payload.count + 1)) + Data([command.id]) + command.payload
    }
    return out
  }

  /// `{int32 tab; (padding); uint64 high; uint64 low; bool has; (padding)}`.
  private func tokenPayload(_ tab: Int32, _ token: UInt64) -> Data {
    int32s(tab, 0) + le(token) + le(token) + Data([1, 0, 0, 0, 0, 0, 0, 0])
  }

  private func int32s(_ values: Int32...) -> Data {
    values.reduce(Data()) { $0 + le(UInt32(bitPattern: $1)) }
  }
}

/// Chromium's `base::Pickle`: a 4-byte payload size, then fields aligned to
/// 4 bytes.
struct Pickle {
  private var payload = Data()

  mutating func int32(_ value: Int32) { payload += le(UInt32(bitPattern: value)) }
  mutating func uint64(_ value: UInt64) { payload += le(value) }
  mutating func double(_ value: Double) { payload += le(value.bitPattern) }

  mutating func string(_ value: String) {
    let bytes = Data(value.utf8)
    int32(Int32(bytes.count))
    payload += bytes
    pad()
  }

  mutating func string16(_ value: String) {
    let units = Array(value.utf16)
    int32(Int32(units.count))
    for unit in units { payload += le(unit) }
    pad()
  }

  private mutating func pad() {
    while payload.count % 4 != 0 { payload.append(0) }
  }

  func data() -> Data { le(UInt32(payload.count)) + payload }
}

private func le<T: FixedWidthInteger>(_ value: T) -> Data {
  withUnsafeBytes(of: value.littleEndian) { Data($0) }
}

// MARK: Dia's tabs.db

/// Dia's `tabs.db`: a SQLCipher 4 database, its key derived from the "Dia
/// Safe Storage" secret as Dia does (design D5; Cra, MIT).
enum DiaDatabase {
  static func space(_ id: String, _ title: String) -> String {
    "INSERT INTO spaces VALUES ('\(id)', '\(title)', 'blue', '2026-11-01 10:00:00')"
  }

  static func node(_ id: Int, _ kind: String, entity: String = "", parent: Int? = nil, order: Double, space: String)
    -> String
  {
    "INSERT INTO nodes VALUES (\(id), '\(kind)', '\(entity)', \(parent.map(String.init) ?? "NULL"), \(order), NULL, '\(space)')"
  }

  static func tab(
    _ id: Int, parent: Int, order: Double, space: String, pages: [(url: String, title: String, custom: String?)],
    widths: String? = nil
  ) -> [String] {
    var rows = [
      node(id, "tab", entity: "tab-\(id)", parent: parent, order: order, space: space),
      "INSERT INTO tabs VALUES ('tab-\(id)', \(widths.map { "'\($0)'" } ?? "NULL"), '2026-11-27 10:00:00')",
    ]
    for (index, page) in pages.enumerated() {
      let pane = "pane-\(id)-\(index)"
      rows += [
        node(id * 100 + index, "content_pane", entity: pane, parent: id, order: Double(index), space: space),
        "INSERT INTO content_panes VALUES ('\(pane)', \(page.custom.map { "'\($0)'" } ?? "NULL"))",
        "INSERT INTO web_contents VALUES ('wc-\(pane)', '\(pane)', '\(page.url)', '\(page.title)')",
      ]
    }
    return rows
  }

  static func group(_ id: Int, _ title: String, parent: Int, order: Double, space: String) -> [String] {
    [
      node(id, "group", entity: "group-\(id)", parent: parent, order: order, space: space),
      "INSERT INTO tab_groups VALUES ('group-\(id)', '\(title)')",
    ]
  }

  static func write(_ rows: [String], to url: URL, secret: String, profile: String) throws {
    let plain = FileManager.default.temporaryDirectory.appending(path: "clair-dia-plain-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: plain) }
    let db = try SQLiteFile(plain, reserveBytes: 80)
    try db.exec("PRAGMA page_size = 4096")
    try db.exec(
      """
      CREATE TABLE spaces (id TEXT PRIMARY KEY, title TEXT, theme TEXT, creation_date TEXT);
      CREATE TABLE nodes (id INTEGER PRIMARY KEY, kind TEXT NOT NULL, entity_id TEXT, parent_id INTEGER,
                          "order" REAL, deleted_at TEXT, space_id TEXT);
      CREATE TABLE tabs (id TEXT PRIMARY KEY, split_view_widths TEXT, creation_date TEXT);
      CREATE TABLE tab_groups (id TEXT PRIMARY KEY, title TEXT);
      CREATE TABLE content_panes (id TEXT PRIMARY KEY, custom_title TEXT);
      CREATE TABLE web_contents (id TEXT PRIMARY KEY, content_pane_id TEXT, url TEXT, title TEXT);
      """)
    for row in rows { try db.exec(row) }
    db.close()
    let image = try Data(contentsOf: plain)
    let key = databaseKey(secret: Data(secret.utf8), label: "profile/\(profile)/tabs")
    let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    var out = Data()
    for index in 0..<image.count / 4096 {
      let page = image.subdata(in: index * 4096..<(index + 1) * 4096)
      let iv = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
      let body = page.subdata(in: (index == 0 ? 16 : 0)..<4096 - 80)
      out += (index == 0 ? salt : Data()) + aes(body, key: key, iv: iv) + iv + Data(count: 64)
    }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try out.write(to: url)
  }

  private static let saltKey = Data(base64Encoded: "iOe1Ue/XtonbieE/5m1nAgewvWQlePHRcKnoU10EyOM=")!

  private static func databaseKey(secret: Data, label: String) -> Data {
    var root = Data(count: 16)
    let salt = Data("saltysalt".utf8)
    _ = root.withUnsafeMutableBytes { out in
      secret.withUnsafeBytes { password in
        salt.withUnsafeBytes { saltBytes in
          CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2), password.baseAddress?.assumingMemoryBound(to: CChar.self), secret.count,
            saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, out.baseAddress?.assumingMemoryBound(to: UInt8.self), 16)
        }
      }
    }
    let info = Data(label.utf8)
    let hkdfSalt = Data(HMAC<SHA256>.authenticationCode(for: info, using: SymmetricKey(data: saltKey)))
    return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: root), salt: hkdfSalt, info: info, outputByteCount: 32)
      .withUnsafeBytes { Data($0) }
  }

  private static func aes(_ input: Data, key: Data, iv: Data) -> Data {
    var output = Data(count: input.count)
    var moved = 0
    let count = output.count
    _ = output.withUnsafeMutableBytes { out in
      input.withUnsafeBytes { inp in
        key.withUnsafeBytes { k in
          iv.withUnsafeBytes { v in
            CCCrypt(
              CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), 0, k.baseAddress, key.count, v.baseAddress,
              inp.baseAddress, input.count, out.baseAddress, count, &moved)
          }
        }
      }
    }
    return output
  }
}
