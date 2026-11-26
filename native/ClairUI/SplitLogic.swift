// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// The split the window shows (add-split-view design D2, D3): its two tabs,
/// leading pane first, its ratio, and which pane is focused.
struct ShownSplit: Equatable {
  let leadingID: TabID
  let trailingID: TabID
  let ratio: Double
  /// The pane holding the active tab, or the parent of the active Peek.
  let focusedIndex: Int

  var paneIDs: [TabID] { [leadingID, trailingID] }

  /// The pane showing `tabID`, or nil.
  func index(of tabID: TabID) -> Int? {
    paneIDs.firstIndex(of: tabID)
  }
}

/// The rules of split view in the window, kept apart from the views so they
/// can be tested (add-split-view design D2, D3, D8, D9, D13).
enum SplitLogic {
  // MARK: The shown split

  /// The split the window shows while `activeTabID` is active: the active
  /// tab's, or the active Peek's parent's, while its partner is among `tabs`.
  static func shownSplit(activeTabID: TabID, in tabs: [any ClairTab]) -> ShownSplit? {
    guard let active = tabs.first(where: { $0.tabID == activeTabID }) else { return nil }
    var shown = active
    if active.peekParentID != ClairTabIDNone, let parent = tabs.first(where: { $0.tabID == active.peekParentID }) {
      shown = parent
    }
    guard let (leading, trailing) = TabListLogic.panes(of: shown, in: tabs) else { return nil }
    return ShownSplit(
      leadingID: leading.tabID, trailingID: trailing.tabID, ratio: leading.splitRatio,
      focusedIndex: shown.tabID == leading.tabID ? 0 : 1)
  }

  // MARK: Panes (D3)

  /// Arc's gap between the panes, where the divider sits.
  static let gap: CGFloat = 10
  /// The narrowest a pane's page gets while dragging the divider, as Dia's
  /// (dia-reference/README.md).
  static let minimumPageWidth: CGFloat = 210
  /// The divider this near the centre makes the panes equal.
  static let snapDistance: CGFloat = 20

  /// The panes' frames in the page area `area`, leading first, the leading
  /// pane taking `ratio` of the width left beside the gap.
  static func paneFrames(in area: CGRect, ratio: Double) -> [CGRect] {
    let room = max(0, area.width - gap)
    let leading = (room * CGFloat(min(max(ratio, 0), 1))).rounded()
    return [
      CGRect(x: area.minX, y: area.minY, width: leading, height: area.height),
      CGRect(x: area.minX + leading + gap, y: area.minY, width: room - leading, height: area.height),
    ]
  }

  /// The gap's frame between the panes.
  static func dividerFrame(in area: CGRect, ratio: Double) -> CGRect {
    let panes = paneFrames(in: area, ratio: ratio)
    return CGRect(x: panes[0].maxX, y: area.minY, width: gap, height: area.height)
  }

  /// The ratio the divider gives with its centre at `x` in a page area
  /// `width` wide: each pane's page stays at least `minimumPageWidth` wide,
  /// unless the area is too narrow for two such pages, when `current` holds.
  static func ratio(forDividerAt x: CGFloat, width: CGFloat, current: Double) -> Double {
    let room = width - gap
    guard room > 0 else { return current }
    guard room >= 2 * minimumPageWidth else { return current }
    let leading = min(max(x - gap / 2, minimumPageWidth), room - minimumPageWidth)
    return Double(leading / room)
  }

  /// The ratio the divider gives while dragged and when let go: equal panes
  /// within `snapDistance` of the page area's centre.
  static func snappedRatio(forDividerAt x: CGFloat, width: CGFloat, current: Double) -> Double {
    if abs(x - width / 2) <= snapDistance, width - gap >= 2 * minimumPageWidth {
      return 0.5
    }
    return ratio(forDividerAt: x, width: width, current: current)
  }

  // MARK: The split button's menus (D9)

  enum MenuEntry: Equatable {
    /// A heading, which can't be chosen.
    case heading(String)
    /// A Today tab to split with.
    case tab(TabID, title: String)
    case newTab
    case moveLeft(isEnabled: Bool)
    case moveRight(isEnabled: Bool)
    case separateTabs
    case closeThisTab
    case separator

    var title: String {
      switch self {
      case .heading(let title), .tab(_, let title): title
      case .newTab: "New Tab"
      case .moveLeft: "Move Left"
      case .moveRight: "Move Right"
      case .separateTabs: "Separate Tabs"
      case .closeThisTab: "Close This Tab"
      case .separator: ""
      }
    }
  }

  static let splitWithTabTitle = "Split with Tab"

  /// The Today tabs a split can be made with, in the sidebar's order: every
  /// Today row but `tabID` and the tabs already in a split.
  static func candidates(for tabID: TabID, today: [any ClairTab]) -> [any ClairTab] {
    TabListLogic.rows(today).filter { $0.tabID != tabID && $0.splitPartnerID == ClairTabIDNone }
  }

  /// The split button's menu on a single page: "Split with Tab", the Space's
  /// other Today tabs, a divider and New Tab, as in Dia.
  static func singlePageMenu(shown tabID: TabID, today: [any ClairTab]) -> [MenuEntry] {
    [.heading(splitWithTabTitle)] + candidates(for: tabID, today: today).map { .tab($0.tabID, title: title(of: $0)) }
      + [.separator, .newTab]
  }

  /// The split button's menu in a pane: Move Left or Move Right, a divider,
  /// Separate Tabs and Close This Tab.
  static func paneMenu(isLeading: Bool) -> [MenuEntry] {
    [.moveLeft(isEnabled: !isLeading), .moveRight(isEnabled: isLeading), .separator, .separateTabs, .closeThisTab]
  }

  /// A tab menu's Split with Tab › submenu: the other Today tabs, then New
  /// Tab.
  static func splitWithTabSubmenu(for tabID: TabID, today: [any ClairTab]) -> [MenuEntry] {
    candidates(for: tabID, today: today).map { .tab($0.tabID, title: title(of: $0)) } + [.separator, .newTab]
  }

  /// What a row reads: its custom name, or its title.
  static func title(of tab: any ClairTab) -> String {
    if let name = tab.name, !name.isEmpty { return name }
    return tab.title.isEmpty ? (tab.displayHost ?? tab.urlText) : tab.title
  }

  // MARK: Dragging a tab onto the page (D8)

  /// Where a dragged tab lands on the page.
  enum DropZone: Equatable {
    /// A split with the shown page, the dragged tab on this side.
    case half(SplitSide)
    /// In place of this pane's tab, while the page is split.
    case pane(Int)
  }

  /// The drop zone under `point` in a page area: the half under it, or,
  /// while split, the pane under it, the gap counting as the nearer pane.
  static func dropZone(at point: CGPoint, in area: CGRect, split: ShownSplit?) -> DropZone? {
    guard area.contains(point) else { return nil }
    guard let split else {
      return .half(point.x < area.midX ? .leading : .trailing)
    }
    let divider = dividerFrame(in: area, ratio: split.ratio)
    return .pane(point.x < divider.midX ? 0 : 1)
  }

  /// Whether a dragged item makes a drop zone over the page: a tab or pin
  /// that isn't shown there already and isn't a split row, open or not
  /// (`isPinnedSplit`, a pinned split's pin).
  static func acceptsDrop(
    of tab: (any ClairTab)?, isPinnedSplit: Bool = false, shown split: ShownSplit?, activeTabID: TabID
  ) -> Bool {
    if isPinnedSplit { return false }
    guard let tab else { return true }
    if tab.splitPartnerID != ClairTabIDNone { return false }
    if let split { return !split.paneIDs.contains(tab.tabID) }
    return tab.tabID != activeTabID && tab.peekParentID == ClairTabIDNone
  }

  /// Arc's portrait card for a tab dragged over the page.
  static let dragCardSize = CGSize(width: 216, height: 250)
  /// How long the page takes to slide aside, ease-out, as in Arc.
  static let slideDuration: TimeInterval = 0.2

  /// Where the page's card goes while a tab is dragged over the half
  /// `side`: the other half.
  static func slidFrame(in area: CGRect, dropSide side: SplitSide) -> CGRect {
    let panes = paneFrames(in: area, ratio: 0.5)
    return side == .leading ? panes[1] : panes[0]
  }

  // MARK: The link status (D13a)

  /// What the link status reads for a link `url`, with `modifiers` held:
  /// Option names the split, and Shift the Peek while the Peek preference is
  /// on; in a Peek, where neither applies, the URL alone.
  static func linkStatus(
    url: String, modifiers: NSEvent.ModifierFlags, opensPeekOnShiftClick: Bool, inPeek: Bool
  ) -> String {
    let flags = modifiers.intersection([.option, .shift, .command, .control])
    guard !inPeek else { return url }
    if flags == .option { return "Open \(url) in Split View" }
    if flags == .shift && opensPeekOnShiftClick { return "Open \(url) in Peek" }
    return url
  }

  // MARK: The command bar's place (D13b)

  /// The command bar's horizontal place: centred on `pane` while split, or
  /// on the window, and kept inside `bounds`, the window's content.
  static func commandBarMinX(width: CGFloat, pane: CGRect?, bounds: CGRect) -> CGFloat {
    let centre = pane?.midX ?? bounds.midX
    let x = centre - width / 2
    return min(max(x, bounds.minX), max(bounds.minX, bounds.maxX - width))
  }
}

/// The actions split view takes in the window (add-split-view design D2).
@MainActor
protocol SplitActions: AnyObject {
  /// Shows a split with the pane focused last, as its row's click does.
  func showSplit(of tabID: TabID)
  func split(tab tabID: TabID, with otherID: TabID, side: SplitSide)
  /// A new tab page beside `tabID`, with the command bar on it.
  func splitWithNewTab(_ tabID: TabID)
  func swapSplit(of tabID: TabID)
  func separateSplit(of tabID: TabID)
  /// Closes both panes, or a pinned split's pages (Close and Keep Pinned).
  func closeSplit(of tabID: TabID)
  func replacePane(of tabID: TabID, with newTabID: TabID)
  func setSplitRatio(_ ratio: Double, of tabID: TabID)
  func separatePinnedSplit(_ splitID: PinnedSplitID)
  /// Focuses a pane, as a click in it does.
  func focusPane(_ tabID: TabID)
  /// A tab menu's Split with Tab › items for a Today tab, or a pin
  /// (add-split-view D9).
  func splitWithTabItems(tab: TabID?, pin: PinID?) -> [RowClickCatcher.Item]
}
