// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation
import SQLite3
import Testing

@testable import ClairUI

/// The import fixtures (add-browser-import design D12), copied into a
/// temporary folder per test so tests can add and remove files.
nonisolated struct ImportFixture {
  /// Fixtures/Import in the test bundle.
  static let directory = Bundle(for: FakeHost.self).resourceURL!.appending(path: "Fixtures/Import")

  /// The test's own folder, removed by `remove()`.
  let root: URL
  /// The fake home folder sources read.
  let home: URL
  /// Where the import's private folders go.
  let temporary: URL

  /// A copy of the fixture home; `empty` leaves it with no browser data.
  init(empty: Bool = false) throws {
    root = FileManager.default.temporaryDirectory.appending(path: "ClairImportTests-\(UUID().uuidString)")
    home = root.appending(path: "home")
    temporary = root.appending(path: "tmp")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    if empty {
      try FileManager.default.createDirectory(
        at: home.appending(path: "Library/Application Support"), withIntermediateDirectories: true)
    } else {
      try FileManager.default.copyItem(at: Self.directory.appending(path: "home"), to: home)
    }
  }

  var applicationSupport: URL { home.appending(path: "Library/Application Support") }

  func environment(keychain: any ImportKeychain = FixedKeychain(secret: Data())) -> ImportEnvironment {
    ImportEnvironment(home: home, keychain: keychain, temporaryDirectory: temporary)
  }

  func context(
    destinations: [String: ImportPlan.Destination] = [:], keychain: any ImportKeychain = FixedKeychain(secret: Data())
  ) throws -> ImportContext {
    ImportContext(destinations: destinations, folder: try ImportWorkFolder.create(in: temporary), keychain: keychain)
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  /// Safari's export as a folder.
  static var safariFolder: URL { directory.appending(path: "Safari Export") }
}

/// A keychain that records reads.
nonisolated final class RecordingKeychain: ImportKeychain, @unchecked Sendable {
  private let lock = NSLock()
  private var _reads: [String] = []
  let secret: Data?

  init(secret: Data?) {
    self.secret = secret
  }

  var reads: [String] { lock.withLock { _reads } }

  func password(service: String) -> Data? {
    lock.withLock { _reads.append(service) }
    return secret
  }
}

/// Builds a Dia `tabs.db` as Dia writes it: SQLCipher 4 pages encrypted with a
/// key derived from a known secret, and a `-wal` whose last transaction isn't
/// checkpointed (design D5, D12).
nonisolated struct DiaDatabaseBuilder {
  static let secret = Data("clair-test-dia-secret".utf8)

  /// Writes `Profile <n>/tabs.db` and `tabs.db-wal` under `userData`, the
  /// main file holding `base` and the log holding `walOnly`.
  static func write(userData: URL, profile: String, secret: Data = secret, base: [String], walOnly: [String]) throws {
    let scratch = FileManager.default.temporaryDirectory.appending(path: "ClairDiaPlain-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let plain = scratch.appending(path: "tabs.db")

    var db: OpaquePointer?
    try check(sqlite3_open(plain.path, &db) == SQLITE_OK, "open")
    var reserve: Int32 = Int32(DiaSidebarReader.reserve)
    // SQLITE_FCNTL_RESERVE_BYTES: SQLCipher keeps 80 bytes at each page's end.
    sqlite3_file_control(db, "main", 38, &reserve)
    try exec(db, "PRAGMA page_size = 4096")
    try exec(db, "PRAGMA journal_mode = WAL")
    try exec(db, "PRAGMA wal_autocheckpoint = 0")
    try exec(db, schema)
    for statement in base { try exec(db, statement) }
    try exec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
    for statement in walOnly { try exec(db, statement) }
    // Copied while the connection is open, as Dia leaves them.
    let mainImage = try Data(contentsOf: plain)
    let walImage = (try? Data(contentsOf: URL(fileURLWithPath: plain.path + "-wal"))) ?? Data()
    sqlite3_close(db)

    let key = DiaSidebarReader.databaseKey(
      rootKey: DiaSidebarReader.rootKey(secret: secret), label: "profile/\(profile)/tabs")
    let folder = userData.appending(path: profile)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try encrypt(main: mainImage, key: key).write(to: folder.appending(path: "tabs.db"))
    try encrypt(wal: walImage, key: key).write(to: folder.appending(path: "tabs.db-wal"))
  }

  static let schema = """
    CREATE TABLE spaces (id TEXT PRIMARY KEY, title TEXT, theme TEXT, creation_date TEXT);
    CREATE TABLE nodes (id INTEGER PRIMARY KEY, kind TEXT NOT NULL, entity_id TEXT, parent_id INTEGER,
                        "order" REAL, deleted_at TEXT, space_id TEXT);
    CREATE TABLE tabs (id TEXT PRIMARY KEY, split_view_widths TEXT, creation_date TEXT);
    CREATE TABLE tab_groups (id TEXT PRIMARY KEY, title TEXT);
    CREATE TABLE content_panes (id TEXT PRIMARY KEY, custom_title TEXT);
    CREATE TABLE web_contents (id TEXT PRIMARY KEY, content_pane_id TEXT, url TEXT, title TEXT);
    """

  private static let pageSize = DiaSidebarReader.pageSize
  private static let reserve = DiaSidebarReader.reserve

  private static func encrypt(page: Data, first: Bool, key: Data, salt: Data) -> Data {
    let iv = random(16)
    let start = first ? DiaSidebarReader.saltSize : 0
    let body = page.subdata(in: start..<pageSize - reserve)
    let cipher = DiaSidebarReader.aes(decrypt: false, body, key: key, iv: iv)!
    return (first ? salt : Data()) + cipher + iv + random(reserve - 16)
  }

  private static let salt = random(16)

  private static func encrypt(main: Data, key: Data) -> Data {
    var out = Data()
    for index in 0..<main.count / pageSize {
      out += encrypt(page: main.subdata(in: index * pageSize..<(index + 1) * pageSize), first: index == 0, key: key, salt: salt)
    }
    return out
  }

  /// Encrypts each frame's page and recomputes the running checksums, as
  /// SQLCipher's log holds them.
  private static func encrypt(wal: Data, key: Data) -> Data {
    guard wal.count > 32 else { return wal }
    var out = wal.subdata(in: 0..<32)
    let bigEndian = DiaSidebarReader.be32(wal, 0) & 1 == 1
    var checksum = (DiaSidebarReader.be32(wal, 24), DiaSidebarReader.be32(wal, 28))
    var offset = 32
    while offset + 24 + pageSize <= wal.count {
      var header = wal.subdata(in: offset..<offset + 24)
      let number = DiaSidebarReader.be32(header, 0)
      let page = encrypt(
        page: wal.subdata(in: offset + 24..<offset + 24 + pageSize), first: number == 1, key: key, salt: salt)
      checksum = DiaSidebarReader.walChecksum(header.subdata(in: 0..<8) + page, bigEndian: bigEndian, seed: checksum)
      header.replaceSubrange(16..<20, with: be(checksum.0))
      header.replaceSubrange(20..<24, with: be(checksum.1))
      out += header + page
      offset += 24 + pageSize
    }
    return out
  }

  private static func be(_ value: UInt32) -> Data {
    Data([UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
  }

  private static func random(_ count: Int) -> Data {
    Data((0..<count).map { _ in UInt8.random(in: 0...255) })
  }

  private static func exec(_ db: OpaquePointer?, _ sql: String) throws {
    var error: UnsafeMutablePointer<CChar>?
    let status = sqlite3_exec(db, sql, nil, nil, &error)
    let message = error.map { String(cString: $0) } ?? ""
    sqlite3_free(error)
    try check(status == SQLITE_OK, "\(sql): \(message)")
  }

  private struct Failure: Error { let message: String }

  private static func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure(message: message) }
  }

  // MARK: Rows

  static func space(_ id: String, _ title: String, created: String) -> String {
    "INSERT INTO spaces VALUES ('\(id)', '\(title)', 'blue', '\(created)')"
  }

  static func node(
    _ id: Int, _ kind: String, entity: String = "", parent: Int? = nil, order: Double, space: String,
    deleted: Bool = false
  ) -> String {
    "INSERT INTO nodes VALUES (\(id), '\(kind)', '\(entity)', \(parent.map(String.init) ?? "NULL"), \(order), "
      + "\(deleted ? "'2026-11-27 10:00:00'" : "NULL"), '\(space)')"
  }

  /// A tab node holding one pane per page, and its rows.
  static func tab(
    _ id: Int, parent: Int, order: Double, space: String, pages: [(url: String, title: String, custom: String?)],
    widths: String? = nil
  ) -> [String] {
    var rows = [
      node(id, "tab", entity: "tab-\(id)", parent: parent, order: order, space: space),
      "INSERT INTO tabs VALUES ('tab-\(id)', \(widths.map { "'\($0)'" } ?? "NULL"), '2026-11-27 10:00:00')",
    ]
    for (index, page) in pages.enumerated() {
      let paneID = "pane-\(id)-\(index)"
      rows += [
        node(id * 100 + index, "content_pane", entity: paneID, parent: id, order: Double(index), space: space),
        "INSERT INTO content_panes VALUES ('\(paneID)', \(page.custom.map { "'\($0)'" } ?? "NULL"))",
        "INSERT INTO web_contents VALUES ('wc-\(paneID)', '\(paneID)', '\(page.url)', '\(page.title)')",
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
}
