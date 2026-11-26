// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

// MARK: The divider (add-split-view design D3)

/// The gap between a split's panes: a grabber, the resize pointer, and a drag
/// that resizes the panes, reporting the divider's centre in the page area.
/// The grabber stays faint until the pointer is over the divider or drags
/// it.
final class SplitDividerView: NSView {
  /// The divider moved to `x`, from the page area's leading edge; `done` on
  /// the drag's last step.
  var onDrag: ((CGFloat, _ done: Bool) -> Void)?
  /// The page area's leading edge, in the divider's superview.
  var areaMinX: CGFloat = 0

  private let grabber = DynamicFillView(color: SplitDividerView.grabberColor)
  private var dragOffset: CGFloat = 0
  private var isHovered = false
  private var isDragging = false

  static let grabberColor = NSColor(name: "clair.splitGrabber") { appearance in
    appearance.isDark ? NSColor(white: 1, alpha: 0.28) : NSColor(white: 0, alpha: 0.22)
  }
  static let grabberSize = CGSize(width: 4, height: 32)
  /// The grabber's opacity while the pointer is elsewhere, and under it.
  static let restingAlpha: CGFloat = 0.35
  static let activeAlpha: CGFloat = 1

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    grabber.wantsLayer = true
    grabber.layer?.cornerRadius = Self.grabberSize.width / 2
    grabber.alphaValue = Self.restingAlpha
    addSubview(grabber)
    setAccessibilityElement(true)
    setAccessibilityRole(.splitter)
    setAccessibilityLabel("Split view divider")
    setAccessibilityIdentifier("clair.splitDivider")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override var isFlipped: Bool { true }

  /// The grabber's opacity now, for tests.
  var grabberAlpha: CGFloat { grabber.alphaValue }

  override func layout() {
    super.layout()
    grabber.frame = CGRect(
      x: (bounds.width - Self.grabberSize.width) / 2, y: (bounds.height - Self.grabberSize.height) / 2,
      width: Self.grabberSize.width, height: Self.grabberSize.height)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(
      NSTrackingArea(
        rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    updateGrabber()
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    updateGrabber()
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .resizeLeftRight)
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    dragOffset = point.x - bounds.midX
    isDragging = true
    updateGrabber()
  }

  override func mouseDragged(with event: NSEvent) {
    report(event, done: false)
  }

  override func mouseUp(with event: NSEvent) {
    isDragging = false
    report(event, done: true)
    isHovered = bounds.contains(convert(event.locationInWindow, from: nil))
    updateGrabber()
  }

  private func report(_ event: NSEvent, done: Bool) {
    guard let superview else { return }
    let x = superview.convert(event.locationInWindow, from: nil).x - dragOffset - areaMinX
    onDrag?(x, done)
  }

  /// Fades the grabber to its full colour under the pointer or a drag, and
  /// back.
  private func updateGrabber() {
    let alpha = isHovered || isDragging ? Self.activeAlpha : Self.restingAlpha
    guard grabber.alphaValue != alpha else { return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
      grabber.animator().alphaValue = alpha
    }
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
  /// The row Rename… edits for this chip: its tab's, or its pinned tab's; a
  /// favorite's is a dialog.
  var renameRow: RowRename.Row? = nil
  /// The rename in progress in this chip, or nil.
  var rename: RowRename? = nil

  /// `page`'s chip, with its rename while `renaming` is its row's.
  static func editable(
    title: String, icon: NSImage?, tab: (any ClairTab)?, pin: (any ClairPin)?, renaming: RowRename?
  ) -> SplitChipPage {
    let row: RowRename.Row? =
      if let pin { pin.isFavorite ? nil : .pin(pin.pinID) } else { tab.map { .tab($0.tabID) } }
    return SplitChipPage(
      title: title, icon: icon, tab: tab, pin: pin, renameRow: row,
      rename: row != nil && renaming?.row == row ? renaming : nil)
  }
}

/// A split as one row in the sidebar, as in Arc: a chip per page with its
/// favicon and title, a thin line between them while not selected, a grey
/// pill each while selected. In Today, hovering the row shows a × on each
/// chip, which closes that page; in the pinned section, the row shows − or ×.
struct SplitRow: View {
  let pages: [SplitChipPage]
  let isActive: Bool
  let isWindowKey: Bool
  /// The button the row shows on hover.
  enum Button: Equatable {
    case closeKeepingPins
    case removePin

    var help: String {
      switch self {
      case .closeKeepingPins: "Close and Keep Pinned"
      case .removePin: "Remove Pin"
      }
    }

    var systemImage: String { self == .closeKeepingPins ? "minus" : "xmark" }
    var shortcut: [String] { self == .removePin ? [] : ["⌘", "W"] }
    var identifier: String {
      switch self {
      case .closeKeepingPins: "clair.pinClose"
      case .removePin: "clair.pinRemove"
      }
    }
  }

  /// The row's button, or nil for a × on each chip.
  let button: Button?
  let onTap: () -> Void
  let onButton: () -> Void
  /// Closes a chip's page, by its index: its × and a middle-click.
  var onChipClose: ((Int) -> Void)?
  /// The chip of the focused pane while the split shows, whose × Cmd+W is.
  var focusedIndex: Int?
  /// Each chip's context menu, by its index.
  let menuItems: (Int) -> [RowClickCatcher.Item]
  /// Ends a chip's rename in place.
  var onRenameEnd: ((RowRename.Row, PinsLogic.NameChange) -> Void)?

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  /// The gap between the chips.
  static let chipGap: CGFloat = 3
  /// The row's inset around its chips.
  static let inset: CGFloat = 4

  var body: some View {
    HStack(spacing: Self.chipGap) {
      ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
        if index > 0 {
          // Kept, clear, while selected, so the chips don't move, as in Arc.
          Rectangle()
            .fill(PinFill.divider)
            .frame(width: 1, height: 16)
            .opacity(isActive ? 0 : 1)
        }
        chip(page, index: index)
      }
      if isHovered, let button {
        IconButton(
          systemImage: button.systemImage, help: button.help, shortcut: button.shortcut, size: TabRow.closeSize,
          glyphSize: 12, glyphWeight: .bold, dimsWhenInactive: false, action: onButton
        )
        .accessibilityIdentifier(button.identifier)
      }
    }
    .padding(.horizontal, Self.inset)
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
    let showsClose = onChipClose != nil && isHovered
    return HStack(spacing: 6) {
      PinIcon(icon: page.icon, isLoading: page.tab?.isLoading == true && page.icon == nil, size: TabRow.faviconSize)
        .frame(width: TabRow.iconSize, height: TabRow.iconSize)
      if let rename = page.rename, let row = page.renameRow {
        RenameField(
          text: page.title, placeholder: page.pin?.title ?? page.tab?.title ?? "", rename: rename,
          current: page.pin == nil ? page.tab?.name : nil
        ) { change in onRenameEnd?(row, change) }
      } else {
        Text(page.title).font(TabRow.titleFont).lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.leading, 6)
    // Room for the chip's ×, which then covers the title's end.
    .padding(.trailing, showsClose ? TabRow.closeSize : 6)
    .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
    .background {
      if isActive {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
      }
    }
    .contentShape(Rectangle())
    .overlay(
      RowClickCatcher(onMiddleClick: { onChipClose?(index) }, menuItems: menuItems(index)))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(page.title)
    .accessibilityIdentifier("clair.splitChip.\(index)")
    .overlay(alignment: .trailing) {
      if showsClose, let onChipClose {
        IconButton(
          systemImage: "xmark", help: "Close tab", shortcut: focusedIndex == index ? ["⌘", "W"] : [],
          size: TabRow.closeSize, glyphSize: 12, glyphWeight: .bold, dimsWhenInactive: false
        ) { onChipClose(index) }
        .padding(.trailing, 1)
        .accessibilityIdentifier("clair.splitClose.\(index)")
      }
    }
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
/// page, Move Left or Right, Separate Tabs and Close This Tab in a pane. It's
/// the toolbar's icon button, whose click opens the menu below it.
struct SplitButton: View {
  let entries: [SplitLogic.MenuEntry]
  /// Each Today tab's favicon, by ID.
  let icon: (TabID) -> NSImage?
  let choose: (SplitLogic.MenuEntry) -> Void

  @State private var anchor = MenuAnchor.Box()

  static let symbol = "square.split.2x1"

  var body: some View {
    IconButton(
      systemImage: Self.symbol, help: "Split view", height: IconButtonSize.toolbarHeight,
      glyphSize: IconButtonSize.toolbarSiteControlsGlyph, glyphWeight: .regular
    ) {
      anchor.popUp(Self.menu(entries, icon: icon, choose: choose))
    }
    .background(MenuAnchor(box: anchor))
    .accessibilityIdentifier("clair.splitButton")
  }

  /// The menu for `entries`: a heading as a section header, a tab with its
  /// favicon.
  static func menu(
    _ entries: [SplitLogic.MenuEntry], icon: (TabID) -> NSImage?, choose: @escaping (SplitLogic.MenuEntry) -> Void
  ) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    for entry in entries {
      let item: NSMenuItem
      switch entry {
      case .separator:
        menu.addItem(.separator())
        continue
      case .heading(let title):
        menu.addItem(.sectionHeader(title: title))
        continue
      case .tab(let tabID, let title):
        item = MenuAnchor.item(title) { choose(entry) }
        item.setFavicon(icon(tabID))
      case .moveLeft(let isEnabled), .moveRight(let isEnabled):
        item = MenuAnchor.item(entry.title) { choose(entry) }
        item.isEnabled = isEnabled
      case .newTab, .separateTabs, .closeThisTab:
        item = MenuAnchor.item(entry.title) { choose(entry) }
      }
      menu.addItem(item)
    }
    return menu
  }
}

/// An invisible view behind a SwiftUI button that a menu pops up from.
struct MenuAnchor: NSViewRepresentable {
  /// Holds the view, for the button's action to reach.
  @MainActor
  final class Box {
    weak var view: NSView?

    /// Pops `menu` up below the view, its trailing edge at the view's when
    /// it's wider, as the button sits at the toolbar's trailing end.
    func popUp(_ menu: NSMenu) {
      guard let view else { return }
      let x = min(0, view.bounds.width - menu.size.width)
      menu.popUp(positioning: nil, at: NSPoint(x: x, y: view.isFlipped ? view.bounds.maxY + 4 : -4), in: view)
    }
  }

  let box: Box

  func makeNSView(context: Context) -> NSView {
    let view = AnchorView()
    box.view = view
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    box.view = view
  }

  private final class AnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }

  /// A menu item that runs `action`.
  static func item(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(ItemTarget.run(_:)), keyEquivalent: "")
    item.target = ItemTarget.shared
    item.representedObject = RowClickCatcher.ItemAction(run: action)
    return item
  }

  @MainActor
  private final class ItemTarget: NSObject {
    static let shared = ItemTarget()

    @objc func run(_ sender: NSMenuItem) {
      (sender.representedObject as? RowClickCatcher.ItemAction)?.run()
    }
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
      SplitChipPage.editable(
        title: SplitLogic.title(of: pane), icon: pane.favicon, tab: pane, pin: model.pin(ofTab: pane.tabID),
        renaming: model.renaming)
    }
    let tabID = tab.tabID
    let focusedIndex = model.shownSplit.flatMap { split in
      panes.contains { $0.tabID == split.paneIDs[split.focusedIndex] } ? split.focusedIndex : nil
    }
    return SplitRow(
      pages: pages, isActive: panes.contains { $0.tabID == highlighted }, isWindowKey: model.isWindowKey,
      button: nil,
      onTap: { [weak actions] in actions?.showSplit(of: tabID) },
      onButton: {},
      // Each chip's × closes its page only, as a pane's × does.
      onChipClose: { [weak actions] index in actions?.close(tab: panes[index].tabID) },
      focusedIndex: focusedIndex,
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
      onRenameEnd: { [weak actions] row, change in actions?.endRenaming(row, change: change) })
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
      return SplitChipPage.editable(
        title: PinsLogic.title(of: pin, tab: tab), icon: PinsLogic.icon(of: pin, tab: tab), tab: tab, pin: pin,
        renaming: model.renaming)
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
      },
      onRenameEnd: { [weak actions] row, change in actions?.endRenaming(row, change: change) })
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

  /// A favicon sized for a menu item, or the globe that stands for a page
  /// without one elsewhere, at the same size so titles stay aligned.
  static func menuIcon(_ image: NSImage?) -> NSImage {
    HistoryMenuBuilder.icon(image)
  }
}

extension NSMenuItem {
  /// Shows a page's favicon, or the globe, beside the title: macOS 27 hides
  /// menu item images unless they're asked to show.
  func setFavicon(_ favicon: NSImage?) {
    image = SplitRows.menuIcon(favicon)
    if #available(macOS 27, *) {
      preferredImageVisibility = .visible
    }
  }
}
