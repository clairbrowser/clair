// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// The window's split view (add-split-view design D2, D3, D8, D9, D13).
extension BrowserWindowController: SplitActions {
  /// Wires the divider, the panes' hover, drops on the page and the
  /// modifier keys the link status reads.
  func setUpSplitView() {
    rootView.splitDivider.onDrag = { [weak self] x, done in
      self?.dividerMoved(to: x, done: done)
    }
    for (index, card) in [rootView.card, rootView.secondCard].enumerated() {
      card.onHover = { [weak model] inside in
        guard let model else { return }
        if inside {
          model.hoveredPane = index
        } else if model.hoveredPane == index {
          model.hoveredPane = nil
        }
      }
    }
    let drop = rootView.pageDrop
    drop.zone = { [weak self] item, point in
      guard let self else { return nil }
      let tab = self.tab(of: item)
      guard item.isTabOrPin, tab != nil || item.pinID != nil,
        SplitLogic.acceptsDrop(of: tab, shown: self.model.shownSplit, activeTabID: self.shownRowTabID)
      else { return nil }
      return SplitLogic.dropZone(at: point, in: drop.bounds, split: self.model.shownSplit)
    }
    drop.zoneFrame = { [weak self] zone in
      guard let self else { return .zero }
      let area = drop.bounds
      switch zone {
      case .half(let side):
        let panes = SplitLogic.paneFrames(in: area, ratio: 0.5)
        return side == .leading ? panes[0] : panes[1]
      case .pane(let index):
        let ratio = self.model.shownSplit?.ratio ?? 0.5
        return SplitLogic.paneFrames(in: area, ratio: ratio)[index]
      }
    }
    drop.describe = { [weak self] item in
      guard let self else { return (nil, "") }
      if let tab = self.tab(of: item) {
        return (tab.favicon, SplitLogic.title(of: tab))
      }
      if case .pin(let pinID) = item, let pin = self.model.spaces.pin(pinID) {
        return (pin.icon, PinsLogic.title(of: pin, tab: nil))
      }
      return (nil, "")
    }
    drop.onTarget = { [weak model] zone in
      model?.pageDrop = zone
    }
    drop.onDrop = { [weak self] item, zone in
      self?.dropped(item, on: zone)
    }
    // D13a: the link status follows Option and Shift as they're pressed.
    flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      MainActor.assumeIsolated {
        guard let self, event.window === self.window, self.model.statusText != nil else { return }
        self.model.statusModifiers = event.modifierFlags
      }
      return event
    }
  }

  /// The tab whose row the window shows: the active tab, or the active
  /// Peek's parent.
  var shownRowTabID: TabID {
    model.shownPeek?.parentID ?? model.activeTabID
  }

  /// The focused pane's tab while split, or the shown row's tab.
  var focusedPaneTabID: TabID {
    model.shownSplit.map { $0.paneIDs[$0.focusedIndex] } ?? shownRowTabID
  }

  /// The tab a dragged row or tile stands for, while open.
  private func tab(of item: SidebarDragItem) -> (any ClairTab)? {
    switch item {
    case .tab(let tabID): return model.allTabs.first { $0.tabID == tabID }
    case .pin(let pinID):
      guard let pin = model.spaces.pin(pinID), pin.tabID != ClairTabIDNone else { return nil }
      return model.tab(ofPin: pin) ?? PinsLogic.tab(of: pin)
    case .folder: return nil
    }
  }

  // MARK: The divider (D3)

  private func dividerMoved(to x: CGFloat, done: Bool) {
    guard let split = model.shownSplit else { return }
    let width = rootView.pageArea.width
    let current = model.liveSplitRatio ?? split.ratio
    if done {
      let ratio = SplitLogic.endRatio(forDividerAt: x, width: width, current: current)
      model.liveSplitRatio = ratio
      browser?.setSplitRatio(ratio, of: split.leadingID)
    } else {
      model.liveSplitRatio = SplitLogic.ratio(forDividerAt: x, width: width, current: current)
    }
  }

  /// Lets go of the dragged ratio once the engine reports it.
  func settleSplitRatio() {
    guard let live = model.liveSplitRatio else { return }
    if let split = model.shownSplit, abs(split.ratio - live) < 0.001 {
      model.liveSplitRatio = nil
    } else if model.shownSplit == nil {
      model.liveSplitRatio = nil
    }
  }

  // MARK: Drops on the page (D8)

  private func dropped(_ item: SidebarDragItem, on zone: SplitLogic.DropZone) {
    model.pageDrop = nil
    let shown = shownRowTabID
    guard let tabID = tab(of: item)?.tabID else {
      // A pinned tab or favorite whose page isn't open opens first.
      if case .pin(let pinID) = item {
        whenPinOpens(pinID) { [weak self] tabID in self?.split(dropping: tabID, on: zone, shown: shown) }
      }
      return
    }
    split(dropping: tabID, on: zone, shown: shown)
  }

  /// Opens a pin whose page is closed, then runs `then` with its tab.
  private func whenPinOpens(_ pinID: PinID, then: @escaping (TabID) -> Void) {
    pendingPinSplit = (pinID, then)
    browser?.openPin(pinID)
    finishPendingPinSplit()
  }

  private func split(dropping tabID: TabID, on zone: SplitLogic.DropZone, shown: TabID) {
    switch zone {
    case .half(let side):
      browser?.split(tab: shown, with: tabID, side: side)
    case .pane(let index):
      guard let split = model.shownSplit else { return }
      browser?.replacePane(of: split.paneIDs[index], with: tabID)
    }
  }

  /// A pin dropped on the page while closed has opened.
  func finishPendingPinSplit() {
    guard let pending = pendingPinSplit, let pin = model.spaces.pin(pending.pinID), pin.tabID != ClairTabIDNone
    else { return }
    pendingPinSplit = nil
    pending.then(pin.tabID)
  }

  func splitWithTabItems(tab tabID: TabID?, pin pinID: PinID?) -> [RowClickCatcher.Item] {
    let ownTab = tabID ?? pinID.flatMap { model.spaces.pin($0) }?.tabID ?? ClairTabIDNone
    let favicons = Dictionary(model.allTabs.map { ($0.tabID, $0.favicon) }, uniquingKeysWith: { first, _ in first })
    // Runs `action` on the menu's tab, opening a closed pin's page first.
    let onOwnTab: (@escaping (TabID) -> Void) -> Void = { [weak self] action in
      guard let self else { return }
      if let tabID {
        action(tabID)
      } else if let pinID, let pin = self.model.spaces.pin(pinID) {
        if pin.tabID != ClairTabIDNone { action(pin.tabID) } else { self.whenPinOpens(pinID, then: action) }
      }
    }
    return SplitLogic.splitWithTabSubmenu(for: ownTab, today: model.tabs).compactMap { entry in
      switch entry {
      case .tab(let other, let title):
        return .icon(title, favicons[other] ?? nil) { [weak self] in
          onOwnTab { self?.split(tab: $0, with: other, side: .trailing) }
        }
      case .newTab:
        return .action(entry.title) { [weak self] in onOwnTab { self?.splitWithNewTab($0) } }
      case .separator:
        return .separator
      default:
        return nil
      }
    }
  }

  // MARK: Menus (D9)

  /// View › Add Split View, and the menus' New Tab: a new tab page as the
  /// trailing pane, with the command bar; "Cannot Add New Pane" while split.
  func addSplitView() {
    guard model.shownSplit == nil else {
      showToast(Self.cannotAddPane)
      return
    }
    splitWithNewTab(shownRowTabID)
  }

  static let cannotAddPane = "Cannot Add New Pane"

  /// View › Close Split Pane: the focused pane's tab.
  func closeSplitPane() {
    guard model.shownSplit != nil else { return }
    browser?.close(tab: focusedPaneTabID)
  }

  // MARK: SplitActions

  func showSplit(of tabID: TabID) {
    browser?.showSplit(of: tabID)
  }

  func split(tab tabID: TabID, with otherID: TabID, side: SplitSide) {
    browser?.split(tab: tabID, with: otherID, side: side)
  }

  func splitWithNewTab(_ tabID: TabID) {
    // D13b: the command bar opens on the new pane once it's active.
    opensCommandBarOnNewPane = true
    browser?.splitWithNewTab(tabID)
  }

  func swapSplit(of tabID: TabID) {
    browser?.swapSplit(of: tabID)
  }

  func separateSplit(of tabID: TabID) {
    browser?.separateSplit(of: tabID)
  }

  func closeSplit(of tabID: TabID) {
    browser?.closeSplit(of: tabID)
  }

  func replacePane(of tabID: TabID, with newTabID: TabID) {
    browser?.replacePane(of: tabID, with: newTabID)
  }

  func setSplitRatio(_ ratio: Double, of tabID: TabID) {
    browser?.setSplitRatio(ratio, of: tabID)
  }

  func separatePinnedSplit(_ splitID: PinnedSplitID) {
    model.spaces.separatePinnedSplit(splitID)
  }

  func focusPane(_ tabID: TabID) {
    guard tabID != model.activeTabID, model.shownPeek?.parentID != tabID else { return }
    browser?.activate(tab: tabID)
  }

  /// Peek's Open in Split View (D11).
  func openPeekInSplit() {
    guard let peek = model.shownPeek else { return }
    browser?.openPeekInSplit(of: peek.parentID)
  }
}

extension SidebarDragItem {
  /// Whether it's a tab or a pin, which can join a split.
  var isTabOrPin: Bool {
    if case .folder = self { return false }
    return true
  }

  var pinID: PinID? {
    if case .pin(let pinID) = self { return pinID }
    return nil
  }
}
