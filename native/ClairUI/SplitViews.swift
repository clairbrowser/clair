// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

// MARK: The divider (add-split-view design D3)

/// The gap between a split's panes: a grabber, the resize pointer, and a drag
/// that resizes the panes, reporting the divider's centre in the page area.
final class SplitDividerView: NSView {
  /// The divider moved to `x`, from the page area's leading edge; `done` on
  /// the drag's last step.
  var onDrag: ((CGFloat, _ done: Bool) -> Void)?
  /// The page area's leading edge, in the divider's superview.
  var areaMinX: CGFloat = 0

  private let grabber = DynamicFillView(color: SplitDividerView.grabberColor)
  private var dragOffset: CGFloat = 0

  static let grabberColor = NSColor(name: "clair.splitGrabber") { appearance in
    appearance.isDark ? NSColor(white: 1, alpha: 0.28) : NSColor(white: 0, alpha: 0.22)
  }
  static let grabberSize = CGSize(width: 4, height: 32)

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    grabber.wantsLayer = true
    grabber.layer?.cornerRadius = Self.grabberSize.width / 2
    addSubview(grabber)
    setAccessibilityElement(true)
    setAccessibilityRole(.splitter)
    setAccessibilityLabel("Split view divider")
    setAccessibilityIdentifier("clair.splitDivider")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override var isFlipped: Bool { true }

  override func layout() {
    super.layout()
    grabber.frame = CGRect(
      x: (bounds.width - Self.grabberSize.width) / 2, y: (bounds.height - Self.grabberSize.height) / 2,
      width: Self.grabberSize.width, height: Self.grabberSize.height)
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .resizeLeftRight)
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    dragOffset = point.x - bounds.midX
  }

  override func mouseDragged(with event: NSEvent) {
    report(event, done: false)
  }

  override func mouseUp(with event: NSEvent) {
    report(event, done: true)
  }

  private func report(_ event: NSEvent, done: Bool) {
    guard let superview else { return }
    let x = superview.convert(event.locationInWindow, from: nil).x - dragOffset - areaMinX
    onDrag?(x, done)
  }
}

// MARK: Dragging a tab onto the page (D8)

/// Takes a sidebar row or tile dragged over the page: the half or pane under
/// it becomes a drop zone, the drag turns into Arc's portrait card, and a
/// drop makes or changes the split. Clicks go through it to the page.
final class PageDropView: NSView {
  /// The zone under `point`, in the view, for `item`, or nil where a drop
  /// does nothing.
  var zone: ((SidebarDragItem, CGPoint) -> SplitLogic.DropZone?)?
  /// The favicon and title of what's dragged.
  var describe: ((SidebarDragItem) -> (icon: NSImage?, title: String))?
  /// The zone the drag is over, or nil once it leaves or drops.
  var onTarget: ((SplitLogic.DropZone?) -> Void)?
  var onDrop: ((SidebarDragItem, SplitLogic.DropZone) -> Void)?

  private let zoneView = DropZoneView()
  private var item: SidebarDragItem?
  private var current: SplitLogic.DropZone?
  private var originals: [Int: (offset: CGPoint, size: CGSize, components: [NSDraggingImageComponent])] = [:]
  private var card: NSImage?

  /// The zone's frame in the view for a zone, set by the window's layout.
  var zoneFrame: ((SplitLogic.DropZone) -> CGRect)?

  override init(frame: NSRect) {
    super.init(frame: frame)
    registerForDraggedTypes([NSPasteboard.PasteboardType(SidebarDragItem.type.identifier)])
    zoneView.isHidden = true
    addSubview(zoneView)
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func layout() {
    super.layout()
    if let current, let frame = zoneFrame?(current) {
      zoneView.frame = frame
    }
  }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    let payload = sender.draggingPasteboard.string(
      forType: NSPasteboard.PasteboardType(SidebarDragItem.type.identifier))
    item = payload.flatMap(SidebarDragItem.init(payload:))
    originals = [:]
    card = nil
    return update(sender)
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    update(sender)
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    if let sender { restore(sender) }
    setZone(nil)
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    guard let item, let current else { return false }
    setZone(nil)
    onDrop?(item, current)
    return true
  }

  override func draggingEnded(_ sender: any NSDraggingInfo) {
    item = nil
    originals = [:]
    setZone(nil)
  }

  private func setZone(_ zone: SplitLogic.DropZone?) {
    guard zone != current else { return }
    current = zone
    onTarget?(zone)
    if let zone, let frame = zoneFrame?(zone) {
      zoneView.frame = frame
      zoneView.isHidden = false
    } else {
      zoneView.isHidden = true
    }
  }

  private func update(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard let item else { return [] }
    let point = convert(sender.draggingLocation, from: nil)
    guard let zone = zone?(item, point) else {
      restore(sender)
      setZone(nil)
      return []
    }
    setZone(zone)
    morph(sender, at: point)
    return sender.draggingSourceOperationMask.contains(.move) ? .move : .generic
  }

  /// Arc's portrait card: the favicon above the title, on a white card.
  private func cardImage() -> NSImage? {
    if let card { return card }
    guard let item, let description = describe?(item) else { return nil }
    let renderer = ImageRenderer(
      content: DraggedPageCard(icon: description.icon, title: description.title)
        .environment(\.colorScheme, effectiveAppearance.isDark ? .dark : .light))
    renderer.scale = window?.backingScaleFactor ?? 2
    card = renderer.nsImage
    return card
  }

  private func morph(_ sender: any NSDraggingInfo, at point: CGPoint) {
    guard let image = cardImage() else { return }
    sender.enumerateDraggingItems(
      options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]
    ) { [self] draggingItem, index, _ in
      if originals[index] == nil {
        let frame = draggingItem.draggingFrame
        originals[index] = (
          CGPoint(x: frame.minX - point.x, y: frame.minY - point.y), frame.size, draggingItem.imageComponents ?? []
        )
      }
      let size = image.size
      draggingItem.setDraggingFrame(
        NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
        contents: image)
    }
  }

  private func restore(_ sender: any NSDraggingInfo) {
    guard !originals.isEmpty else { return }
    let point = convert(sender.draggingLocation, from: nil)
    sender.enumerateDraggingItems(
      options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]
    ) { [self] draggingItem, index, _ in
      guard let original = originals[index] else { return }
      let components = original.components
      draggingItem.draggingFrame = NSRect(
        origin: CGPoint(x: point.x + original.offset.x, y: point.y + original.offset.y), size: original.size)
      draggingItem.imageComponentsProvider = { components }
    }
    originals = [:]
  }
}

/// The drop zone: the accent colour at low opacity with a 2 pt accent
/// border, as Arc's (arc-reference/README.md, "Dragging a tab onto the
/// page").
final class DropZoneView: NSView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = PageCardView.cornerRadius
    layer?.cornerCurve = .continuous
    layer?.borderWidth = 2
    updateColors()
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier("clair.splitDropZone")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  private func updateColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.borderColor = NSColor.controlAccentColor.cgColor
      layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.06).cgColor
    }
  }
}

/// A tab dragged over the page, as Arc draws it: a white portrait card with
/// the favicon above the title in bold.
struct DraggedPageCard: View {
  let icon: NSImage?
  let title: String

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: 14) {
      PinIcon(icon: icon, size: 16)
        .frame(width: 18, height: 18)
      Text(title)
        .font(.system(size: 13, weight: .bold))
        .multilineTextAlignment(.center)
        .lineLimit(3)
        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
    }
    .padding(16)
    .frame(width: SplitLogic.dragCardSize.width, height: SplitLogic.dragCardSize.height)
    .background(
      colorScheme == .dark ? Color(white: 0.2) : Color.white,
      in: .rect(cornerRadius: 14, style: .continuous))
  }
}

// MARK: The split row (add-split-view design D13)

/// One page of a split row.
struct SplitChipPage {
  let title: String
  let icon: NSImage?
  /// The tab, while the page is open.
  let tab: (any ClairTab)?
  /// The pin, for a pinned or favorited split's page.
  let pin: (any ClairPin)?
}

/// A split as one row in the sidebar, as in Arc: a chip per page with its
/// favicon and title, a thin line between them while not selected, a grey
/// pill each while selected; × in Today, − or × in the pinned section.
struct SplitRow: View {
  let pages: [SplitChipPage]
  let isActive: Bool
  let isWindowKey: Bool
  /// The button the row shows on hover.
  enum Button: Equatable {
    case close
    case closeKeepingPins
    case removePin

    var help: String {
      switch self {
      case .close: "Close tab"
      case .closeKeepingPins: "Close and Keep Pinned"
      case .removePin: "Remove Pin"
      }
    }

    var systemImage: String { self == .closeKeepingPins ? "minus" : "xmark" }
    var shortcut: [String] { self == .removePin ? [] : ["⌘", "W"] }
    var identifier: String {
      switch self {
      case .close: "clair.splitClose"
      case .closeKeepingPins: "clair.pinClose"
      case .removePin: "clair.pinRemove"
      }
    }
  }

  let button: Button
  let onTap: () -> Void
  let onButton: () -> Void
  /// Each chip's context menu, by its index.
  let menuItems: (Int) -> [RowClickCatcher.Item]
  var onMiddleClick: () -> Void = {}

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  /// The gap between the chips.
  static let chipGap: CGFloat = 3

  var body: some View {
    HStack(spacing: Self.chipGap) {
      ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
        if index > 0, !isActive {
          Rectangle()
            .fill(PinFill.divider)
            .frame(width: 1, height: 16)
        }
        chip(page, index: index)
      }
      if isHovered {
        IconButton(
          systemImage: button.systemImage, help: button.help, shortcut: button.shortcut, size: TabRow.closeSize,
          glyphSize: 12, glyphWeight: .bold, dimsWhenInactive: false, action: onButton
        )
        .accessibilityIdentifier(button.identifier)
      }
    }
    .padding(.horizontal, 4)
    .frame(height: TabRow.pillHeight)
    .background {
      if isActive {
        RoundedRectangle(cornerRadius: TabRow.cornerRadius, style: .continuous)
          .fill(SidebarFill.activePill(colorScheme, isWindowKey: isWindowKey))
          .shadow(color: SidebarFill.activeShadow, radius: 2, y: 1)
      } else if isHovered {
        RoundedRectangle(cornerRadius: TabRow.cornerRadius, style: .continuous).fill(SidebarFill.hover(colorScheme))
      }
    }
    .padding(.top, TabRow.pillInset)
    .padding(.bottom, TabRow.pillInset + TabRow.spacing)
    .contentShape(Rectangle())
    .onTapGesture(perform: onTap)
    .onHover { isHovered = $0 }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(pages.map(\.title).joined(separator: ", "))
    .accessibilityIdentifier("clair.splitRow")
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }

  private func chip(_ page: SplitChipPage, index: Int) -> some View {
    HStack(spacing: 6) {
      PinIcon(icon: page.icon, isLoading: page.tab?.isLoading == true && page.icon == nil, size: TabRow.faviconSize)
        .frame(width: TabRow.iconSize, height: TabRow.iconSize)
      Text(page.title).font(TabRow.titleFont).lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 6)
    .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
    .background {
      if isActive {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
      }
    }
    .contentShape(Rectangle())
    .overlay(RowClickCatcher(onMiddleClick: onMiddleClick, menuItems: menuItems(index)))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(page.title)
    .accessibilityIdentifier("clair.splitChip.\(index)")
  }
}

// MARK: The favorite split tile (add-split-view spec, "The favorite split tile")

/// A favorited split's tile: a segment per page with its icon, a thin line
/// between them, and, while shown, a white or light grey tile with a ring
/// blending from the leading page's icon colour to the trailing page's.
struct FavoriteSplitTile: View {
  let icons: [NSImage?]
  let isSelected: Bool
  let onTap: () -> Void
  let menuItems: (Int) -> [RowClickCatcher.Item]
  let titles: [String]

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: FavoriteTile.cornerRadius, style: .continuous)
        .fill(PinFill.tile(colorScheme, hovered: isHovered, selected: isSelected))
      if isSelected {
        RoundedRectangle(cornerRadius: FavoriteTile.cornerRadius, style: .continuous)
          .strokeBorder(
            LinearGradient(
              colors: icons.map { Color(nsColor: IconColor.ring(of: $0)) }, startPoint: .leading,
              endPoint: .trailing),
            lineWidth: 2)
      }
      HStack(spacing: 0) {
        ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
          if index > 0 {
            Rectangle()
              .fill(PinFill.divider)
              .frame(width: 1)
              .padding(.vertical, 10)
          }
          PinIcon(icon: icon, size: FavoriteTile.iconSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay(RowClickCatcher(onMiddleClick: {}, menuItems: menuItems(index)))
            .accessibilityElement()
            .accessibilityLabel(titles.indices.contains(index) ? titles[index] : "")
            .accessibilityIdentifier("clair.splitChip.\(index)")
        }
      }
    }
    .contentShape(Rectangle())
    .onTapGesture(perform: onTap)
    .onHover { hovering in withAnimation(sidebarHoverFade) { isHovered = hovering } }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(titles.joined(separator: ", "))
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityIdentifier("clair.favoriteSplitTile")
  }
}

// MARK: The split button (add-split-view design D9)

/// The split button, as in Arc, with Dia's menu: Split with Tab on a single
/// page, Move Left or Right, Separate Tabs and Close This Tab in a pane.
struct SplitButton: View {
  let entries: [SplitLogic.MenuEntry]
  /// Each Today tab's favicon, by ID.
  let icon: (TabID) -> NSImage?
  let choose: (SplitLogic.MenuEntry) -> Void

  var body: some View {
    Menu {
      ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
        switch entry {
        case .separator:
          Divider()
        case .heading(let title):
          Section(title) {}
        case .tab(let tabID, let title):
          Button {
            choose(entry)
          } label: {
            if let icon = icon(tabID) {
              Label { Text(title) } icon: { Image(nsImage: icon) }
            } else {
              Label(title, systemImage: "globe")
            }
          }
        case .moveLeft(let isEnabled), .moveRight(let isEnabled):
          Button(entry.title) { choose(entry) }.disabled(!isEnabled)
        case .newTab, .separateTabs, .closeThisTab:
          Button(entry.title) { choose(entry) }
        }
      }
    } label: {
      Image(systemName: "rectangle.split.2x1")
        .font(.system(size: IconButtonSize.toolbarSiteControlsGlyph))
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .frame(width: ToolbarArrangement.buttonSize, height: IconButtonSize.toolbarHeight)
    .help("Split view")
    .accessibilityLabel("Split view")
    .accessibilityIdentifier("clair.splitButton")
  }
}

// MARK: The sidebar's split rows (add-split-view design D2, D10)

/// Builds a split's row in Today or the pinned section.
@MainActor
enum SplitRows {
  /// A Today split's row, its chips in pane order. A chip holding a pinned
  /// tab's or favorite's page has that pin's menu.
  static func today(
    _ tab: any ClairTab, model: BrowserWindowModel, highlighted: TabID, moveTargets: [any ClairSpace],
    actions: (any SidebarActions)?
  ) -> some View {
    let panes = TabListLogic.panes(of: tab, in: model.allTabs).map { [$0.leading, $0.trailing] } ?? [tab]
    let pages = panes.map { pane in
      SplitChipPage(title: SplitLogic.title(of: pane), icon: pane.favicon, tab: pane, pin: model.pin(ofTab: pane.tabID))
    }
    let tabID = tab.tabID
    return SplitRow(
      pages: pages, isActive: panes.contains { $0.tabID == highlighted }, isWindowKey: model.isWindowKey,
      button: .close,
      onTap: { [weak actions] in actions?.showSplit(of: tabID) },
      onButton: { [weak actions] in actions?.closeSplit(of: tabID) },
      menuItems: { [weak actions] index in
        let page = pages[index]
        guard let pane = page.tab else { return [] }
        if let pin = page.pin {
          return pin.isFavorite
            ? PinMenus.items(
              PinsLogic.favoriteMenu(isShown: true, isOpen: true, isMuted: pane.isMuted, inSplit: true), pin: pin,
              actions: actions)
            : PinMenus.pinnedItems(pin: pin, tab: pane, moveTargets: moveTargets, actions: actions, inSplit: true)
        }
        return TabRow.menuItems(
          tab: pane, canPin: model.showsPins, moveTargets: moveTargets, actions: actions, inSplit: true)
      },
      onMiddleClick: { [weak actions] in actions?.closeSplit(of: tabID) })
  }

  /// A pinned split's row: its pages' titles from when they were last open,
  /// − while selected and × otherwise (split-view spec, "The pinned split
  /// row").
  static func pinned(
    _ split: any ClairPinnedSplit, model: BrowserWindowModel, highlighted: TabID, moveTargets: [any ClairSpace],
    actions: (any SidebarActions)?
  ) -> some View {
    let pins = split.pins
    let pages = pins.map { pin in
      let tab = model.tab(ofPin: pin)
      return SplitChipPage(
        title: PinsLogic.title(of: pin, tab: tab), icon: PinsLogic.icon(of: pin, tab: tab), tab: tab, pin: pin)
    }
    let isActive = pins.contains { $0.tabID != ClairTabIDNone && $0.tabID == highlighted }
    let openTab = pins.first { $0.tabID != ClairTabIDNone }?.tabID
    let firstPin = pins.first?.pinID
    return SplitRow(
      pages: pages, isActive: isActive, isWindowKey: model.isWindowKey,
      button: isActive ? .closeKeepingPins : .removePin,
      onTap: { [weak actions] in open(openTab: openTab, firstPin: firstPin, actions: actions) },
      onButton: { [weak actions] in
        if isActive, let openTab {
          actions?.closeSplit(of: openTab)
        } else if let firstPin {
          actions?.removePin(firstPin)
        }
      },
      menuItems: { [weak actions] index in
        PinMenus.pinnedItems(
          pin: pages[index].pin!, tab: pages[index].tab, moveTargets: moveTargets, actions: actions, inSplit: true)
      })
  }

  /// A favorited split's tile.
  static func favorite(_ split: any ClairPinnedSplit, model: BrowserWindowModel, actions: (any SidebarActions)?)
    -> some View
  {
    let pins = split.pins
    let tabs = pins.map { model.tab(ofPin: $0) }
    let highlighted = model.highlightedTab
    let isShown = pins.contains { $0.tabID != ClairTabIDNone && $0.tabID == highlighted }
    let openTab = pins.first { $0.tabID != ClairTabIDNone }?.tabID
    let firstPin = pins.first?.pinID
    return FavoriteSplitTile(
      icons: zip(pins, tabs).map { PinsLogic.icon(of: $0, tab: $1) }, isSelected: isShown,
      onTap: { [weak actions] in open(openTab: openTab, firstPin: firstPin, actions: actions) },
      menuItems: { [weak actions] index in
        PinMenus.items(
          PinsLogic.favoriteMenu(
            isShown: isShown, isOpen: tabs[index] != nil, isMuted: tabs[index]?.isMuted == true, inSplit: true),
          pin: pins[index], actions: actions)
      },
      titles: zip(pins, tabs).map { PinsLogic.title(of: $0, tab: $1) })
  }

  /// Shows an open pinned split with the pane focused last, or opens its
  /// pages.
  private static func open(openTab: TabID?, firstPin: PinID?, actions: (any SidebarActions)?) {
    if let openTab {
      actions?.showSplit(of: openTab)
    } else if let firstPin {
      actions?.openPin(firstPin)
    }
  }

  /// A favicon sized for a menu item.
  static func menuIcon(_ image: NSImage) -> NSImage {
    let size = NSSize(width: 16, height: 16)
    return NSImage(size: size, flipped: false) { rect in
      image.draw(in: rect)
      return true
    }
  }
}
