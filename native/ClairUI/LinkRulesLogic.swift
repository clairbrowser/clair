// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import Foundation
import Observation

/// A rule as ClairUI hands it to `-[ClairHost replaceLinkRules:]`: an immutable
/// copy of a row (add-link-rules design D4). The engine copies its
/// properties in turn.
final class LinkRuleValue: NSObject, ClairLinkRule {
  let match: LinkRuleMatch
  let text: String
  let spaceID: SpaceID

  init(match: LinkRuleMatch, text: String, spaceID: SpaceID) {
    self.match = match
    self.text = text
    self.spaceID = spaceID
  }
}

extension LinkRuleMatch {
  /// The match popup's items, in Dia's order.
  static let menuOrder: [LinkRuleMatch] = [.contains, .exact, .prefix]

  /// The popup's title for it, as Dia's.
  var title: String {
    switch self {
    case .contains: "URLs containing"
    case .exact: "this exact URL"
    case .prefix: "URLs starting with"
    @unknown default: "URLs containing"
    }
  }
}

/// The Link Rules dialog's rows and what Done and Cancel do with them
/// (add-link-rules design D5). Edits stay here until Done saves them all.
@MainActor
@Observable
final class LinkRulesState {
  /// One rule as the dialog shows it, which may still be empty or invalid.
  struct Row: Identifiable, Equatable {
    let id: UUID
    var match: LinkRuleMatch
    var text: String
    var spaceID: SpaceID?
  }

  /// What a row saves as, for telling whether anything changed.
  private struct Saved: Equatable {
    var match: LinkRuleMatch
    var text: String
    var spaceID: SpaceID?
  }

  static let title = "Link Rules"
  static let addRule = "Add Rule"
  static let discardChanges = "Discard Changes"
  static let noRules = "No link rules yet"
  static let needsTwoSpaces = "Link rules work with more than one Space. Add another Space to get started."
  static let invalidText = "Enter a valid domain or URL."
  static let duplicate = "Each domain or URL and matching option can only appear once."
  static let noSpace = "Choose a Space for each rule."
  static let placeholder = "example.com"
  static let removeLabel = "Remove Link Rule"
  static let chooseSpace = "Choose a Space"

  @ObservationIgnored private let host: any ClairHost
  /// The Spaces and profiles, kept up to date by the host while the dialog
  /// is open.
  let spaces: SpacesModel
  private(set) var rows: [Row]
  /// The first failing check's message, shown under the list until the next
  /// edit.
  private(set) var error: String?
  /// The row whose field Add Rule focused.
  var focusedRow: Row.ID?
  /// Whether Cancel was pressed with unsaved edits, turning it into Discard
  /// Changes.
  private(set) var isDiscardArmed = false
  /// Return in a row's field: the dialog presses Done.
  @ObservationIgnored var onSubmit: (@MainActor () -> Void)?
  @ObservationIgnored private let original: [Saved]

  init(host: any ClairHost, spaces: SpacesModel) {
    self.host = host
    self.spaces = spaces
    let rows = host.linkRules.map { Row(id: UUID(), match: $0.match, text: $0.text, spaceID: $0.spaceID) }
    self.rows = rows
    original = rows.map(Self.saved)
  }

  // MARK: Showing

  /// Add Rule needs another Space to send links to.
  var canAddRule: Bool { spaces.spaces.count > 1 }

  /// What the list area shows with no rows.
  var emptyMessage: String? {
    guard rows.isEmpty else { return nil }
    return canAddRule ? Self.noRules : Self.needsTwoSpaces
  }

  /// The row's Space, unless it was deleted while the dialog is open.
  func space(of row: Row) -> (any ClairSpace)? {
    row.spaceID.flatMap { spaces.space($0) }
  }

  /// The Space popup's sections: one per profile, under its name, when
  /// there's more than one profile; otherwise one without a title. Profiles
  /// without Spaces are left out.
  var spaceSections: [(title: String?, spaces: [any ClairSpace])] {
    let profiles = spaces.profiles
    guard profiles.count > 1 else { return [(nil, spaces.spaces)] }
    return profiles.compactMap { profile in
      let own = spaces.spaces.filter { $0.profileID == profile.profileID }
      return own.isEmpty ? nil : (profile.name, own)
    }
  }

  // MARK: Editing

  /// Appends a row matching "URLs containing", with an empty field and the
  /// first Space, and focuses its field.
  func addRule() {
    guard canAddRule, let first = spaces.spaces.first else { return }
    let row = Row(id: UUID(), match: .contains, text: "", spaceID: first.spaceID)
    rows.append(row)
    focusedRow = row.id
    edited()
  }

  func remove(_ id: Row.ID) {
    rows.removeAll { $0.id == id }
    edited()
  }

  func setMatch(_ match: LinkRuleMatch, of id: Row.ID) {
    change(id) { $0.match = match }
  }

  func setText(_ text: String, of id: Row.ID) {
    change(id) { $0.text = text }
  }

  func setSpace(_ spaceID: SpaceID, of id: Row.ID) {
    change(id) { $0.spaceID = spaceID }
  }

  private func change(_ id: Row.ID, _ body: (inout Row) -> Void) {
    guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
    var row = rows[index]
    body(&row)
    guard row != rows[index] else { return }
    rows[index] = row
    edited()
  }

  /// Any edit clears the error line, and Discard Changes turns back into
  /// Cancel once the rows are as they were.
  private func edited() {
    error = nil
    if !hasUnsavedEdits {
      isDiscardArmed = false
    }
  }

  // MARK: Cancel and Done

  /// Whether the rows differ from the rules read when the dialog opened, in
  /// match, trimmed text, Space or order.
  var hasUnsavedEdits: Bool {
    rows.map(Self.saved) != original
  }

  /// Whether the cancelling button shows as a red "Discard Changes".
  var showsDiscard: Bool {
    isDiscardArmed && hasUnsavedEdits
  }

  /// Cancel or Esc. Returns whether the dialog closes: at once without
  /// edits, otherwise on the second press, the first turning Cancel into
  /// Discard Changes.
  func cancel() -> Bool {
    guard hasUnsavedEdits, !isDiscardArmed else { return true }
    isDiscardArmed = true
    return false
  }

  /// Done's checks, in order: rows with an empty field are dropped, then
  /// every text must be valid, every row's Space must exist, and no two rows
  /// may share a match and text. Returns the rules to save, in order, or nil
  /// with `error` set to the first failing check's message.
  func validatedRules() -> [LinkRuleValue]? {
    let filled = rows.filter { !Self.trimmed($0.text).isEmpty }
    if filled.contains(where: { !host.isValidLinkRuleText(Self.trimmed($0.text)) }) {
      return fail(Self.invalidText)
    }
    if filled.contains(where: { space(of: $0) == nil }) {
      return fail(Self.noSpace)
    }
    var seen = Set<String>()
    for row in filled {
      if !seen.insert("\(row.match.rawValue) \(Self.trimmed(row.text))").inserted {
        return fail(Self.duplicate)
      }
    }
    error = nil
    return filled.compactMap { row in
      row.spaceID.map { LinkRuleValue(match: row.match, text: Self.trimmed(row.text), spaceID: $0) }
    }
  }

  /// Done: saves the rules and returns true, or shows the error and returns
  /// false.
  func save() -> Bool {
    guard let rules = validatedRules() else { return false }
    host.replaceLinkRules(rules)
    return true
  }

  private func fail(_ message: String) -> [LinkRuleValue]? {
    error = message
    return nil
  }

  private static func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func saved(_ row: Row) -> Saved {
    Saved(match: row.match, text: trimmed(row.text), spaceID: row.spaceID)
  }
}
