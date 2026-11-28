// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.
//
// How Dia encrypts its sidebar, and the constant its key derivation uses, come
// from Cra by Victor Kildahl (MIT, github.com/VictorKildahl/cra,
// Sources/Cra/Services/Import/DiaSidebar.swift); see CREDITS.md.

import CommonCrypto
import CryptoKit
import Foundation
import SQLite3

/// Reads Dia's sidebar (add-browser-import design D5): each profile's
/// `tabs.db`, a SQLCipher 4 database, decrypted in memory with its `-wal`
/// folded in and opened with `sqlite3_deserialize`, so no plaintext touches the
/// disk. Its Spaces are Dia's "profiles"; their favorites merge into the
/// Chromium profile's.
nonisolated enum DiaSidebarReader {
  /// The HMAC key of Dia's database key derivation, from its binary (Cra).
  private static let saltKey = Data(base64Encoded: "iOe1Ue/XtonbieE/5m1nAgewvWQlePHRcKnoU10EyOM=")!
  /// SQLCipher 4's defaults: 4096-byte pages ending in a 16-byte IV and a
  /// 64-byte HMAC-SHA512; page 1 starts with the 16-byte KDF salt.
  static let pageSize = 4096
  static let reserve = 80
  static let saltSize = 16

  /// Reads every profile's `tabs.db` with the "Dia Safe Storage" `secret`.
  /// Without a secret, nothing is read and the sidebar is reported
  /// unreadable; a profile whose database doesn't open is reported alone.
  static func read(userData: URL, profiles: [String], secret: Data?) -> ImportSidebar {
    guard var secret, !secret.isEmpty else {
      return ImportSidebar(unreadable: "Dia's Spaces, favorites, pinned and Today tabs")
    }
    var root = rootKey(secret: secret)
    secret.resetBytes(in: 0..<secret.count)
    defer { root.resetBytes(in: 0..<root.count) }
    var sidebar = ImportSidebar()
    var anyRead = false
    for profile in profiles {
      let file = userData.appending(path: "\(profile)/tabs.db")
      guard FileManager.default.fileExists(atPath: file.path) else { continue }
      var key = databaseKey(rootKey: root, label: "profile/\(profile)/tabs")
      defer { key.resetBytes(in: 0..<key.count) }
      if let content = read(database: file, key: key) {
        sidebar.profiles[profile] = content
        anyRead = true
      } else {
        sidebar.profiles[profile] = ImportSidebar.Profile(
          skipped: [ImportSkip(reason: .sidebarUnreadable, name: "Dia's Spaces, favorites, pinned and Today tabs")])
      }
    }
    if !anyRead {
      // One note for the whole import, not one per profile.
      return ImportSidebar(unreadable: "Dia's Spaces, favorites, pinned and Today tabs")
    }
    return sidebar
  }

  // MARK: The key

  /// Chromium's Safe Storage key: PBKDF2-HMAC-SHA1 of the keychain password,
  /// salt "saltysalt", 1003 rounds, 16 bytes.
  static func rootKey(secret: Data) -> Data {
    let salt = Data("saltysalt".utf8)
    var key = Data(count: 16)
    let keyCount = key.count
    _ = key.withUnsafeMutableBytes { out in
      secret.withUnsafeBytes { password in
        salt.withUnsafeBytes { saltBytes in
          CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2), password.baseAddress?.assumingMemoryBound(to: CChar.self), secret.count,
            saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
            1003, out.baseAddress?.assumingMemoryBound(to: UInt8.self), keyCount)
        }
      }
    }
    return key
  }

  /// A database's key: HKDF-SHA256 of the root key, salted with
  /// HMAC-SHA256(saltKey, label), with the label as info; the label is
  /// "profile/<profile folder>/tabs" (Cra).
  static func databaseKey(rootKey: Data, label: String) -> Data {
    let info = Data(label.utf8)
    let salt = Data(HMAC<SHA256>.authenticationCode(for: info, using: SymmetricKey(data: saltKey)))
    let key = HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: rootKey), salt: salt, info: info, outputByteCount: 32)
    return key.withUnsafeBytes { Data($0) }
  }

  // MARK: Decryption in memory

  /// The database as plain SQLite, the committed frames of its `-wal` folded
  /// in; nil for a wrong key or a damaged file.
  static func decrypt(database file: URL, key: Data) -> Data? {
    guard let encrypted = try? Data(contentsOf: file), encrypted.count >= pageSize, encrypted.count % pageSize == 0 else {
      return nil
    }
    var pages: [Int: Data] = [:]
    var count = encrypted.count / pageSize
    for index in 0..<count {
      pages[index + 1] = encrypted.subdata(in: index * pageSize..<(index + 1) * pageSize)
    }
    if let wal = try? Data(contentsOf: URL(fileURLWithPath: file.path + "-wal")) {
      for (number, page) in committedFrames(wal: wal, pageCount: &count) {
        pages[number] = page
      }
    }
    guard count >= 1, (1...count).allSatisfy({ pages[$0] != nil }) else { return nil }
    var plain = Data(capacity: count * pageSize)
    for number in 1...count {
      guard let page = decrypt(page: pages[number]!, first: number == 1, key: key) else {
        plain.resetBytes(in: 0..<plain.count)
        return nil
      }
      plain.append(page)
    }
    // A right key turns page 1 into SQLite's header: page size 4096, reserved
    // bytes 80, payload fractions 64/32/32.
    guard plain.starts(with: Data("SQLite format 3\0".utf8)), plain[16] == 0x10, plain[17] == 0, plain[20] == UInt8(reserve),
      plain[21] == 64, plain[22] == 32, plain[23] == 32
    else {
      plain.resetBytes(in: 0..<plain.count)
      return nil
    }
    // The image is read without its log, as a rollback-journal database, since
    // memory databases can't use WAL.
    plain[18] = 1
    plain[19] = 1
    return plain
  }

  private static func decrypt(page: Data, first: Bool, key: Data) -> Data? {
    let start = first ? saltSize : 0
    let body = page.subdata(in: start..<pageSize - reserve)
    let iv = page.subdata(in: pageSize - reserve..<pageSize - reserve + 16)
    guard let plain = aes(decrypt: true, body, key: key, iv: iv) else { return nil }
    return (first ? Data("SQLite format 3\0".utf8) : Data()) + plain + Data(count: reserve)
  }

  /// AES-256-CBC without padding.
  static func aes(decrypt: Bool, _ input: Data, key: Data, iv: Data) -> Data? {
    var output = Data(count: input.count)
    var moved = 0
    let outputCount = output.count
    let status = output.withUnsafeMutableBytes { out in
      input.withUnsafeBytes { inp in
        key.withUnsafeBytes { k in
          iv.withUnsafeBytes { v in
            CCCrypt(
              CCOperation(decrypt ? kCCDecrypt : kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), 0, k.baseAddress, key.count,
              v.baseAddress, inp.baseAddress, input.count, out.baseAddress, outputCount, &moved)
          }
        }
      }
    }
    guard status == kCCSuccess, moved == input.count else { return nil }
    return output
  }

  /// The pages of the log's committed transactions, in order (later frames
  /// win): frames of its current salt whose running checksum holds, up to the
  /// last commit frame. `pageCount` becomes that commit's database size.
  static func committedFrames(wal: Data, pageCount: inout Int) -> [(Int, Data)] {
    let headerSize = 32
    let frameHeaderSize = 24
    guard wal.count >= headerSize else { return [] }
    let magic = be32(wal, 0)
    guard magic == 0x377F_0682 || magic == 0x377F_0683, be32(wal, 8) == pageSize else { return [] }
    let bigEndian = magic & 1 == 1
    var checksum = walChecksum(wal.subdata(in: 0..<24), bigEndian: bigEndian, seed: (0, 0))
    guard checksum.0 == be32(wal, 24), checksum.1 == be32(wal, 28) else { return [] }
    let salt = wal.subdata(in: 16..<24)
    var committed: [(Int, Data)] = []
    var pending: [(Int, Data)] = []
    var offset = headerSize
    while offset + frameHeaderSize + pageSize <= wal.count {
      let header = wal.subdata(in: offset..<offset + frameHeaderSize)
      guard header.subdata(in: 8..<16) == salt else { break }
      let page = wal.subdata(in: offset + frameHeaderSize..<offset + frameHeaderSize + pageSize)
      checksum = walChecksum(header.subdata(in: 0..<8) + page, bigEndian: bigEndian, seed: checksum)
      guard checksum.0 == be32(header, 16), checksum.1 == be32(header, 20) else { break }
      pending.append((Int(be32(header, 0)), page))
      let commitSize = Int(be32(header, 4))
      if commitSize > 0 {
        committed += pending
        pending = []
        pageCount = commitSize
      }
      offset += frameHeaderSize + pageSize
    }
    return committed
  }

  /// SQLite's WAL checksum over `data`, in 8-byte steps.
  static func walChecksum(_ data: Data, bigEndian: Bool, seed: (UInt32, UInt32)) -> (UInt32, UInt32) {
    var (s0, s1) = seed
    data.withUnsafeBytes { bytes in
      var index = 0
      while index + 8 <= bytes.count {
        let word0 = word(bytes, index, bigEndian: bigEndian)
        let word1 = word(bytes, index + 4, bigEndian: bigEndian)
        s0 = s0 &+ word0 &+ s1
        s1 = s1 &+ word1 &+ s0
        index += 8
      }
    }
    return (s0, s1)
  }

  private static func word(_ bytes: UnsafeRawBufferPointer, _ index: Int, bigEndian: Bool) -> UInt32 {
    let b = (0..<4).map { UInt32(bytes[index + $0]) }
    return bigEndian ? b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3] : b[3] << 24 | b[2] << 16 | b[1] << 8 | b[0]
  }

  static func be32(_ data: Data, _ index: Int) -> UInt32 {
    data.withUnsafeBytes { bytes in
      let start = bytes.startIndex + index
      return (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[start + $1]) }
    }
  }

  // MARK: Reading the tree

  /// One profile's Spaces and favorites, or nil when the database doesn't
  /// decrypt or its schema isn't Dia's.
  static func read(database file: URL, key: Data) -> ImportSidebar.Profile? {
    guard var plain = decrypt(database: file, key: key) else { return nil }
    defer { plain.resetBytes(in: 0..<plain.count) }
    guard let database = MemoryDatabase(plain) else { return nil }
    defer { database.close() }
    return walk(database)
  }

  private struct Node {
    let id: Int64
    let kind: String
    let entityID: String
    let spaceID: String
  }

  private static func walk(_ db: MemoryDatabase) -> ImportSidebar.Profile? {
    let tables: Set<String> = Set(db.rows("SELECT name FROM sqlite_master WHERE type = 'table'").compactMap { $0[0] })
    guard ["spaces", "nodes", "tabs", "content_panes", "web_contents", "tab_groups"].allSatisfy(tables.contains) else {
      return nil
    }
    let spaceOrder = db.columns("spaces").contains("creation_date") ? "creation_date, rowid" : "rowid"
    guard
      let spaces = db.query("SELECT id, title FROM spaces ORDER BY \(spaceOrder)"),
      let nodeRows = db.query(
        "SELECT id, kind, entity_id, parent_id, space_id FROM nodes WHERE deleted_at IS NULL ORDER BY \"order\", id"),
      let groupRows = db.query("SELECT id, title FROM tab_groups"),
      let tabRows = db.query("SELECT id, split_view_widths FROM tabs"),
      let paneRows = db.query(
        "SELECT p.id, p.custom_title, w.url, w.title FROM content_panes p JOIN web_contents w ON w.content_pane_id = p.id")
    else { return nil }

    var children: [Int64: [Node]] = [:]
    var roots: [Node] = []
    for row in nodeRows {
      guard let id = row[0].flatMap(Int64.init), let kind = row[1] else { continue }
      let node = Node(id: id, kind: kind, entityID: row[2] ?? "", spaceID: row[4] ?? "")
      if let parent = row[3].flatMap(Int64.init) {
        children[parent, default: []].append(node)
      } else {
        roots.append(node)
      }
    }
    let groups = Dictionary(groupRows.map { ($0[0] ?? "", $0[1] ?? "") }) { first, _ in first }
    let widths = Dictionary(tabRows.map { ($0[0] ?? "", $0[1]) }) { first, _ in first }
    let panes = Dictionary(paneRows.map { ($0[0] ?? "", (custom: $0[1], url: $0[2], title: $0[3])) }) { first, _ in first }

    func pane(_ node: Node) -> ImportTab? {
      guard node.kind == "content_pane", let pane = panes[node.entityID], let url = pane.url, !url.isEmpty else { return nil }
      return ImportTab(url: url, title: pane.title ?? url, name: pane.custom)
    }

    func items(under parent: Int64) -> [ImportItem] {
      (children[parent] ?? []).compactMap { node -> ImportItem? in
        switch node.kind {
        case "tab":
          let tabPanes = (children[node.id] ?? []).compactMap(pane)
          switch tabPanes.count {
          case 0: return nil
          case 1: return .tab(tabPanes[0])
          default: return .split(panes: tabPanes, ratio: leadingShare(widths[node.entityID] ?? nil, count: tabPanes.count))
          }
        case "group":
          return .folder(name: groups[node.entityID].flatMap { $0.isEmpty ? nil : $0 } ?? "Folder", children: items(under: node.id))
        default:
          return nil
        }
      }
    }

    // Only live roots are walked, so orphans of deleted windows never come
    // over.
    func contents(_ kind: String, in space: String) -> [ImportItem] {
      roots.filter { $0.kind == kind && $0.spaceID == space }.flatMap { items(under: $0.id) }
    }

    var profile = ImportSidebar.Profile()
    var favoriteURLs: Set<String> = []
    for row in spaces {
      let id = row[0] ?? ""
      profile.spaces.append(
        ImportSidebar.Space(
          name: row[1].flatMap { $0.isEmpty ? nil : $0 } ?? "Space", icon: nil,
          pinned: contents("pinned_container", in: id), today: contents("window", in: id)))
      for favorite in contents("favorites", in: id) {
        let url = favorite.tabs.first?.url ?? ""
        if favoriteURLs.insert(url).inserted {
          profile.favorites.append(favorite)
        }
      }
    }
    return profile
  }

  /// The leading pane's share of `split_view_widths`, a JSON array of widths.
  private static func leadingShare(_ json: String?, count: Int) -> Double {
    guard let data = json?.data(using: .utf8), let widths = try? JSONSerialization.jsonObject(with: data) as? [Double],
      let first = widths.first
    else { return 1 / Double(count) }
    let sum = widths.reduce(0, +)
    return sum > 0 ? first / sum : 1 / Double(count)
  }
}

/// A read-only SQLite database over a buffer, through `sqlite3_deserialize`.
/// The buffer is zeroed and freed on `close()`.
private nonisolated final class MemoryDatabase {
  private var handle: OpaquePointer?
  private let buffer: UnsafeMutableRawPointer
  private let size: Int

  init?(_ image: Data) {
    size = image.count
    buffer = UnsafeMutableRawPointer.allocate(byteCount: max(size, 1), alignment: 8)
    image.withUnsafeBytes { buffer.copyMemory(from: $0.baseAddress!, byteCount: size) }
    guard sqlite3_open_v2(":memory:", &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
      sqlite3_deserialize(
        handle, "main", buffer.assumingMemoryBound(to: UInt8.self), Int64(size), Int64(size),
        UInt32(SQLITE_DESERIALIZE_READONLY)) == SQLITE_OK,
      quickCheck()
    else {
      close()
      return nil
    }
  }

  private var closed = false

  func close() {
    guard !closed else { return }
    closed = true
    sqlite3_close(handle)
    handle = nil
    memset(buffer, 0, size)
    buffer.deallocate()
  }

  private func quickCheck() -> Bool {
    query("PRAGMA quick_check")?.first?.first == "ok"
  }

  /// The rows of `sql`, each column as text; nil when it fails.
  func query(_ sql: String) -> [[String?]]? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(statement) }
    var rows: [[String?]] = []
    while true {
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { break }
      guard step == SQLITE_ROW else { return nil }
      rows.append(
        (0..<sqlite3_column_count(statement)).map { column in
          sqlite3_column_text(statement, column).map { String(cString: $0) }
        })
    }
    return rows
  }

  func rows(_ sql: String) -> [[String?]] { query(sql) ?? [] }

  func columns(_ table: String) -> Set<String> {
    Set(rows("PRAGMA table_info(\(table))").compactMap { $0.count > 1 ? $0[1] : nil })
  }
}
