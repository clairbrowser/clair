// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// What the switcher needs from its window (add-tab-switcher-and-tabs-menu
/// D1, D2).
@MainActor
protocol TabSwitcherHost: AnyObject {
  /// The browser window the switcher sits over.
  var switcherWindow: NSWindow { get }
  /// Whether the switcher may take keys now: the window is key, with no
  /// Clair dialog or sheet up.
  var switcherMayAct: Bool { get }
  /// The window's recent tabs, most recent first.
  var recentTabIDs: [TabID] { get }
  /// The cards for `entries`.
  func switcherCards(for entries: [TabID]) -> [SwitcherCard]
  /// Asks for a preview of `tabID`'s page, `size` in points.
  func requestSwitcherPreview(of tabID: TabID, size: NSSize, completion: @escaping (NSImage?) -> Void)
  /// Shows the tab chosen, as selecting its row or tile does.
  func showFromSwitcher(_ tabID: TabID)
}

/// Ctrl+Tab's switcher for one window: a local key monitor, a mouse monitor
/// while the panel shows, and the panel (add-tab-switcher-and-tabs-menu D2,
/// D3). The rules are `SwitcherState`'s; this is the glue.
@MainActor
final class TabSwitcher {
  private static let tabKey: UInt16 = 48
  private static let escapeKey: UInt16 = 53

  weak var host: (any TabSwitcherHost)?
  private(set) var state = SwitcherState()
  let panelModel = TabSwitcherPanelModel()
  private(set) lazy var panel = TabSwitcherPanel(model: panelModel)

  /// The clock and the wait for the panel's delay, injected by tests.
  var now: () -> ContinuousClock.Instant = { .now }
  var wait: (Duration) async -> Void = { duration in try? await Task.sleep(for: duration) }

  private var keyMonitor: Any?
  private var mouseMonitor: Any?
  private var delay: Task<Void, Never>?
  /// The keys whose key-down the switcher took, whose key-up it takes too.
  private var takenKeys: Set<UInt16> = []

  init(host: any TabSwitcherHost) {
    self.host = host
  }

  isolated deinit {
    stop()
  }

  /// Installs the key monitor.
  func start() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
      let taken = MainActor.assumeIsolated { self?.handle(event) ?? false }
      return taken ? nil : event
    }
  }

  func stop() {
    cancel()
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  // MARK: Keys

  /// Whether the switcher takes `event`, which then goes no further: not to
  /// the page, a field or Chromium. Costs one flag test for any other key
  /// while the switcher is closed.
  @discardableResult
  func handle(_ event: NSEvent) -> Bool {
    switch event.type {
    case .flagsChanged:
      // Releasing Ctrl chooses the selected card. The page keeps hearing the
      // modifiers, so it never thinks Ctrl is still down.
      if state.isOpen, !event.modifierFlags.contains(.control) {
        commit()
      }
      return false
    case .keyUp:
      return takenKeys.remove(event.keyCode) != nil
    case .keyDown:
      break
    default:
      return false
    }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if !state.isOpen {
      guard event.keyCode == Self.tabKey, flags.contains(.control),
        flags.isDisjoint(with: [.command, .option]), host?.switcherMayAct == true
      else { return false }
      take(event)
      open(forward: !flags.contains(.shift))
      return true
    }
    take(event)
    switch event.keyCode {
    case Self.tabKey:
      state.step(forward: !flags.contains(.shift))
      render()
    case Self.escapeKey:
      cancel()
    default:
      break
    }
    return true
  }

  /// The key's release is the switcher's too, unless the key was down
  /// before: a repeat's release belongs to whoever had its first press.
  private func take(_ event: NSEvent) {
    if !event.isARepeat {
      takenKeys.insert(event.keyCode)
    }
  }

  private func open(forward: Bool) {
    guard let host, state.open(recents: host.recentTabIDs, forward: forward, at: now()) else { return }
    let cards = host.switcherCards(for: state.entries)
    guard cards.count == state.entries.count else {
      // A recent tab the window can't draw: no switcher rather than a wrong
      // one.
      state.cancel()
      return
    }
    panelModel.cards = cards
    panelModel.previews = [:]
    requestPreviews(for: cards)
    render()
    let wait = self.wait
    delay = Task { [weak self] in
      await wait(SwitcherState.panelDelay)
      guard !Task.isCancelled, let self else { return }
      self.state.update(at: self.now())
      self.render()
    }
  }

  private func requestPreviews(for cards: [SwitcherCard]) {
    for card in cards {
      let width = SwitcherLayout.previewSize.width / CGFloat(card.paneIDs.count)
      let size = NSSize(width: width, height: SwitcherLayout.previewSize.height)
      for paneID in card.paneIDs {
        host?.requestSwitcherPreview(of: paneID, size: size) { [weak self] image in
          guard let self, self.state.isOpen, let image else { return }
          // A preview arriving late replaces the placeholder in place.
          self.panelModel.previews[paneID] = image
        }
      }
    }
  }

  // MARK: Choosing and cancelling

  /// Releasing Ctrl: shows the selected tab, unless it's the shown one.
  func commit() {
    finish(state.commit())
  }

  /// A click on card `index` while the panel shows.
  func choose(card index: Int) {
    guard state.isPanelShown else { return }
    finish(state.commit(card: index))
  }

  /// Esc, the window resigning key, or the shown tab closing.
  func cancel() {
    guard state.isOpen else { return }
    state.cancel()
    finish(nil)
  }

  /// The shown tab, the first card, is gone: the switcher closes.
  func tabsDidChange(open: Set<TabID>) {
    if let shown = state.entries.first, !open.contains(shown) {
      cancel()
    }
  }

  private func finish(_ chosen: TabID?) {
    delay?.cancel()
    delay = nil
    render()
    if let chosen {
      host?.showFromSwitcher(chosen)
    }
  }

  // MARK: The panel

  /// Shows, updates or hides the panel as the state says, with no animation.
  private func render() {
    panelModel.selection = state.selection
    guard state.isPanelShown, let window = host?.switcherWindow else {
      hidePanel()
      return
    }
    let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
    panel.setFrame(
      SwitcherLayout.panelFrame(cards: panelModel.cards.count, window: window.frame, visible: visible), display: false)
    if panel.parent == nil {
      window.addChildWindow(panel, ordered: .above)
    }
    panel.orderFront(nil)
    startMouseMonitor()
  }

  private func hidePanel() {
    stopMouseMonitor()
    guard panel.parent != nil || panel.isVisible else { return }
    panel.parent?.removeChildWindow(panel)
    panel.orderOut(nil)
  }

  /// A click on a card, Ctrl held, chooses it before AppKit can take the
  /// Control-click for a secondary click (D2). No other mouse event.
  private func startMouseMonitor() {
    guard mouseMonitor == nil else { return }
    mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
      let taken = MainActor.assumeIsolated {
        guard let self, event.window === self.panel else { return false }
        return self.click(at: event.locationInWindow)
      }
      return taken ? nil : event
    }
  }

  private func stopMouseMonitor() {
    if let mouseMonitor {
      NSEvent.removeMonitor(mouseMonitor)
      self.mouseMonitor = nil
    }
  }

  /// A click at `point` in the panel, from its bottom left: chooses the card
  /// under it. Returns whether one was.
  @discardableResult
  func click(at point: CGPoint) -> Bool {
    let height = panel.frame.height
    let fromTop = CGPoint(x: point.x, y: height - point.y)
    guard state.isPanelShown, let index = SwitcherLayout.card(at: fromTop, cards: panelModel.cards.count) else {
      return false
    }
    choose(card: index)
    return true
  }
}

/// What the panel draws.
@MainActor
@Observable
final class TabSwitcherPanelModel {
  var cards: [SwitcherCard] = []
  var selection = 0
  /// Each page's preview, by its tab, as it arrives.
  var previews: [TabID: NSImage] = [:]
}

/// The switcher's panel: borderless and non-activating, a child of the
/// browser window, hosting the cards (D3). It never becomes key, so the
/// window keeps its keys.
final class TabSwitcherPanel: NSPanel {
  init(model: TabSwitcherPanelModel) {
    super.init(
      contentRect: CGRect(origin: .zero, size: SwitcherLayout.panelSize(cards: 2)),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    isReleasedWhenClosed = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    animationBehavior = .none
    hidesOnDeactivate = false
    collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
    contentView = NSHostingView(rootView: TabSwitcherView(model: model))
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// The cards in one row, left to right, the selected one highlighted in the
/// accent colour, as in Arc (`tab-switcher` "Switcher panel", "Cards").
struct TabSwitcherView: View {
  let model: TabSwitcherPanelModel

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, card in
        TabSwitcherCardView(
          card: card, previews: card.paneIDs.map { model.previews[$0] }, isSelected: index == model.selection)
      }
    }
    .padding(.horizontal, SwitcherLayout.padding - SwitcherLayout.highlightInset)
    .padding(.top, SwitcherLayout.padding - SwitcherLayout.highlightInset)
    .frame(
      width: SwitcherLayout.panelSize(cards: model.cards.count).width, height: SwitcherLayout.height,
      alignment: .topLeading
    )
    .background {
      RoundedRectangle(cornerRadius: SwitcherLayout.cornerRadius, style: .continuous)
        .fill(Color(nsColor: SwitcherLayout.background))
        .overlay {
          RoundedRectangle(cornerRadius: SwitcherLayout.cornerRadius, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.tabSwitcher")
  }
}

struct TabSwitcherCardView: View {
  let card: SwitcherCard
  let previews: [NSImage?]
  let isSelected: Bool

  private var labelHeight: CGFloat {
    SwitcherLayout.highlightHeight - SwitcherLayout.previewSize.height - 2 * SwitcherLayout.highlightInset
  }

  var body: some View {
    VStack(spacing: 0) {
      preview
        .frame(width: SwitcherLayout.previewSize.width, height: SwitcherLayout.previewSize.height)
        .clipShape(RoundedRectangle(cornerRadius: SwitcherLayout.previewRadius, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: SwitcherLayout.previewRadius, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
      label.frame(width: SwitcherLayout.previewSize.width, height: labelHeight)
    }
    .padding(SwitcherLayout.highlightInset)
    .frame(width: SwitcherLayout.pitch, height: SwitcherLayout.highlightHeight)
    .background {
      if isSelected {
        RoundedRectangle(cornerRadius: SwitcherLayout.highlightRadius, style: .continuous)
          .fill(Color.accentColor.opacity(0.18))
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(card.label)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityIdentifier("clair.tabSwitcherCard")
  }

  /// The page from its top, fitted to the card's width; a split's two side
  /// by side in pane order; a blank card with the favicon while there's no
  /// preview.
  private var preview: some View {
    HStack(spacing: 1) {
      ForEach(previews.indices, id: \.self) { index in
        page(previews[index], favicon: card.favicons.indices.contains(index) ? card.favicons[index] : nil)
      }
    }
    .background(Color(nsColor: .textBackgroundColor))
  }

  @ViewBuilder
  private func page(_ image: NSImage?, favicon: NSImage?) -> some View {
    if let image {
      Image(nsImage: image)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fill)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    } else {
      Color(nsColor: .textBackgroundColor)
        .overlay { PinIcon(icon: favicon, size: 24) }
    }
  }

  private var label: some View {
    HStack(spacing: 6) {
      ForEach(card.favicons.indices, id: \.self) { index in
        PinIcon(icon: card.favicons[index], size: SwitcherLayout.faviconSize)
      }
      if !card.title.isEmpty {
        Text(card.title)
          .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
          .foregroundStyle(isSelected ? .primary : .secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
    .frame(maxWidth: .infinity)
  }
}
