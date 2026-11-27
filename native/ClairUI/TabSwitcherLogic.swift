// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// A window's tabs in the order it last showed them, most recent first, for
/// Ctrl+Tab's switcher (add-tab-switcher-and-tabs-menu design D1). An entry
/// is a row's tab: a tab and its Peek are one, as the two tabs of a split
/// are, through its leading pane. It holds only open tabs, so it needs no cap.
struct RecentTabs: Equatable {
  private(set) var ids: [TabID] = []

  init(_ ids: [TabID] = []) {
    self.ids = ids
  }

  /// The row `tabID` shows in, among `tabs`: its parent for a Peek, the
  /// leading pane for a split's; nil when `tabs` doesn't list it, as for
  /// the still's placeholder, which is in no Space.
  static func row(of tabID: TabID, in tabs: [TabID: any ClairTab]) -> TabID? {
    guard var tab = tabs[tabID] else { return nil }
    if tab.peekParentID != ClairTabIDNone {
      guard let parent = tabs[tab.peekParentID] else { return nil }
      tab = parent
    }
    if tab.splitPartnerID != ClairTabIDNone, !tab.isLeadingPane, tabs[tab.splitPartnerID] != nil {
      return tab.splitPartnerID
    }
    return tab.tabID
  }

  /// The window showed `tabID`: its row moves to the front. Returns false,
  /// changing nothing, when `tabs` doesn't list it yet.
  @discardableResult
  mutating func show(_ tabID: TabID, in tabs: [TabID: any ClairTab]) -> Bool {
    guard let row = Self.row(of: tabID, in: tabs) else { return false }
    ids.removeAll { $0 == row }
    ids.insert(row, at: 0)
    return true
  }

  /// Keeps the entries whose tab is still open, each as the row it is now,
  /// once: a closed page, a closed tab and a tab of a removed Space leave; a
  /// tab that joined a split counts as the split.
  mutating func prune(in tabs: [TabID: any ClairTab]) {
    var seen: Set<TabID> = []
    ids = ids.compactMap { id in
      guard let row = Self.row(of: id, in: tabs), seen.insert(row).inserted else { return nil }
      return row
    }
  }
}

/// Ctrl+Tab's switcher while Ctrl is held (add-tab-switcher-and-tabs-menu
/// D2, D3): its cards, the selected one, and whether the panel shows yet.
struct SwitcherState: Equatable {
  /// The cards the panel holds at most.
  static let maxCards = 5
  /// How long Ctrl is held before the panel shows, as in Arc, whose delay
  /// measured between 90 and 130 ms.
  static let panelDelay: Duration = .milliseconds(100)

  /// The recent tabs the cards stand for, the shown tab first; empty while
  /// the switcher is closed.
  private(set) var entries: [TabID] = []
  private(set) var selection = 0
  private(set) var isPanelShown = false
  private var openedAt: ContinuousClock.Instant?

  var isOpen: Bool { !entries.isEmpty }
  var selectedTab: TabID? { entries.indices.contains(selection) ? entries[selection] : nil }

  /// Ctrl+Tab (`forward`) or Ctrl+Shift+Tab: opens on the window's first
  /// recent tabs with the second card or the last selected. With fewer than
  /// two, it stays closed and returns false.
  @discardableResult
  mutating func open(recents: [TabID], forward: Bool, at now: ContinuousClock.Instant) -> Bool {
    guard recents.count >= 2 else { return false }
    entries = Array(recents.prefix(Self.maxCards))
    selection = forward ? 1 : entries.count - 1
    isPanelShown = false
    openedAt = now
    return true
  }

  /// When the panel is due, while the switcher is open and it isn't shown.
  var panelDeadline: ContinuousClock.Instant? {
    guard isOpen, !isPanelShown, let openedAt else { return nil }
    return openedAt.advanced(by: Self.panelDelay)
  }

  /// Shows the panel once its delay is over.
  mutating func update(at now: ContinuousClock.Instant) {
    if let deadline = panelDeadline, now >= deadline {
      isPanelShown = true
    }
  }

  /// Tab or Shift+Tab, Ctrl still held: the next card or the previous one,
  /// wrapping; the panel shows at once if it hadn't.
  mutating func step(forward: Bool) {
    guard isOpen else { return }
    selection = (selection + (forward ? 1 : -1) + entries.count) % entries.count
    isPanelShown = true
  }

  /// Ends the switcher on the selected card, or on `card` when the pointer
  /// chose it, and returns its tab; nil for the first card, the shown tab,
  /// which leaves the window as it is.
  mutating func commit(card: Int? = nil) -> TabID? {
    guard isOpen else { return nil }
    if let card, entries.indices.contains(card) {
      selection = card
    }
    let chosen = selection == 0 ? nil : selectedTab
    cancel()
    return chosen
  }

  /// Esc, another app, or the shown tab closing: closes without switching.
  mutating func cancel() {
    entries = []
    selection = 0
    isPanelShown = false
    openedAt = nil
  }
}

/// The switcher panel's layout, from Arc's measurements
/// (add-tab-switcher-and-tabs-menu D3, `arc-reference/`), in points, from the
/// panel's top left.
enum SwitcherLayout {
  /// A card's preview of its page, 3:2.
  static let previewSize = CGSize(width: 157.5, height: 105)
  /// From the panel's edge to a preview.
  static let padding: CGFloat = 27
  /// Between two previews.
  static let gap: CGFloat = 24
  /// The selection's highlight around a preview and its label.
  static let highlightInset: CGFloat = 12
  static let highlightHeight: CGFloat = 157.5
  static let highlightRadius: CGFloat = 12
  static let height: CGFloat = 189
  static let cornerRadius: CGFloat = 22
  static let previewRadius: CGFloat = 5
  static let faviconSize: CGFloat = 16

  /// From one card to the next.
  static var pitch: CGFloat { previewSize.width + gap }

  static func panelSize(cards: Int) -> CGSize {
    let count = CGFloat(max(cards, 1))
    return CGSize(width: 2 * padding + count * previewSize.width + (count - 1) * gap, height: height)
  }

  /// The highlight of card `index`, which a click lands on.
  static func cardFrame(_ index: Int) -> CGRect {
    CGRect(
      x: padding - highlightInset + CGFloat(index) * pitch, y: padding - highlightInset,
      width: pitch, height: highlightHeight)
  }

  /// The card under `point`, from the panel's top left, or nil.
  static func card(at point: CGPoint, cards: Int) -> Int? {
    (0..<cards).first { cardFrame($0).contains(point) }
  }

  /// The panel's frame on screen: centred on `window`, then moved inside
  /// `visible`, the screen's visible frame, its leading edge first when it's
  /// wider.
  static func panelFrame(cards: Int, window: CGRect, visible: CGRect) -> CGRect {
    let size = panelSize(cards: cards)
    var frame = CGRect(
      x: window.midX - size.width / 2, y: window.midY - size.height / 2, width: size.width, height: size.height)
    frame.origin.x = max(min(frame.origin.x, visible.maxX - size.width), visible.minX)
    frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - size.height)
    return frame
  }
}

/// One card of the switcher: a tab, or a split's two in pane order.
struct SwitcherCard: Identifiable {
  /// The row's tab, which choosing the card shows.
  let id: TabID
  /// The pages it shows, one, or a split's two in pane order.
  let paneIDs: [TabID]
  /// The title or custom name; empty for a split, whose card shows both
  /// favicons with no title.
  let title: String
  let favicons: [NSImage?]
  /// What VoiceOver and the runtime suite read: the title, or a split's
  /// two.
  let label: String

  /// The card of row `rowID`, from the tabs the window can show.
  static func make(_ rowID: TabID, in tabs: [TabID: any ClairTab]) -> SwitcherCard? {
    guard let tab = tabs[rowID] else { return nil }
    let name = { (tab: any ClairTab) -> String in
      if let name = tab.name, !name.isEmpty { return name }
      return tab.title
    }
    if tab.splitPartnerID != ClairTabIDNone, let partner = tabs[tab.splitPartnerID] {
      let panes = tab.isLeadingPane ? [tab, partner] : [partner, tab]
      return SwitcherCard(
        id: rowID, paneIDs: panes.map(\.tabID), title: "", favicons: panes.map(\.favicon),
        label: panes.map(name).joined(separator: ", "))
    }
    return SwitcherCard(id: rowID, paneIDs: [rowID], title: name(tab), favicons: [tab.favicon], label: name(tab))
  }
}
