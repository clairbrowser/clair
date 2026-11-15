// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI
import UniformTypeIdentifiers

/// What the pinned rows, the favorites and the rename field ask the window
/// to do (add-pinned-tabs-and-favorites design D11).
@MainActor
protocol PinActions: AnyObject {
  /// Selects a pinned tab or favorite, opening its pinned URL if it isn't.
  func openPin(_ pinID: PinID)
  /// Pins a Today tab at the bottom of the pinned section, or makes it the
  /// last favorite.
  func pin(tab: TabID)
  func pinToFavorites(tab: TabID)
  func pinToFavorites(pin: PinID)
  func unpin(_ pinID: PinID)
  func removePin(_ pinID: PinID)
  /// The − button and Close Tab: closes the page and keeps the pin.
  func closeKeepingPin(_ pinID: PinID)
  func returnToPinnedURL(_ pinID: PinID)
  func replacePinnedURL(_ pinID: PinID)
  func editPinnedURL(_ pinID: PinID)
  func copyLink(ofPin pinID: PinID)
  func duplicate(pin pinID: PinID)
  func setMuted(_ muted: Bool, pin pinID: PinID)
  func movePin(_ pinID: PinID, toSpace spaceID: SpaceID)
  /// Turns a row's title into a field.
  func beginRenaming(_ rename: RowRename)
  /// The field closed: Return keeps `change`, anything else cancels.
  func endRenaming(_ row: RowRename.Row, change: PinsLogic.NameChange)
  /// The favorite's "Rename Tab…" dialog.
  func renameFavorite(_ pinID: PinID)
  func clearToday()
  func togglePinnedSection()
  func dismissFavoritesHint()
  /// A row or tile dropped somewhere it moves to.
  func drop(_ item: SidebarDragItem, on target: SidebarDropTarget)
}

// MARK: Dragging between sections (design D5, D11)

/// What a row or tile carries while dragged.
enum SidebarDragItem: Equatable {
  case tab(TabID)
  case pin(PinID)

  /// Its own type, so a page's text or link dropped on the sidebar is
  /// ignored.
  static let type = UTType(exportedAs: "dev.joshuapark.clair.sidebar-item", conformingTo: .data)

  var payload: String {
    switch self {
    case .tab(let tabID): "tab:\(tabID)"
    case .pin(let pinID): "pin:\(pinID)"
    }
  }

  nonisolated init?(payload: String) {
    if payload.hasPrefix("tab:"), let tabID = TabID(payload.dropFirst(4)) {
      self = .tab(tabID)
    } else if payload.hasPrefix("pin:") {
      self = .pin(String(payload.dropFirst(4)))
    } else {
      return nil
    }
  }

  func itemProvider() -> NSItemProvider {
    let provider = NSItemProvider()
    let data = Data(payload.utf8)
    provider.registerDataRepresentation(forTypeIdentifier: Self.type.identifier, visibility: .ownProcess) {
      completion in
      completion(data, nil)
      return nil
    }
    return provider
  }

  /// Reads the item a provider carries, on the main actor.
  static func load(from providers: [NSItemProvider], then done: @escaping @MainActor (SidebarDragItem) -> Void) {
    guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type.identifier) }) else {
      return
    }
    _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
      guard let data, let payload = String(data: data, encoding: .utf8), let item = SidebarDragItem(payload: payload)
      else { return }
      Task { @MainActor in done(item) }
    }
  }
}

/// Where a dragged row or tile lands.
enum SidebarDropTarget: Equatable {
  case pinned(Int)
  case today(Int)
  case favorites(Int)
}

// MARK: Favorites (favorites spec, design D11)

/// The favorites grid between the URL field and the Space header: tiles of
/// equal size in rows of at most four, the selected one white with a ring in
/// its icon's colour.
struct FavoritesGrid: View {
  let model: BrowserWindowModel
  weak var actions: (any SidebarActions)?

  @State private var width: CGFloat = SidebarState.defaultWidth
  /// Where a tile being dragged over the grid would land, which the tiles
  /// make room for.
  @State private var dropIndex: Int?

  var body: some View {
    let favorites = model.favorites
    let room = dropIndex.map { min($0, favorites.count) }
    let layout = FavoritesLayout(count: favorites.count + (room == nil ? 0 : 1), width: width)
    let highlighted = model.highlightedTab
    ZStack(alignment: .topLeading) {
      ForEach(Array(favorites.enumerated()), id: \.element.pinID) { index, pin in
        let slot = room.map { index >= $0 ? index + 1 : index } ?? index
        let frame = layout.frame(of: slot)
        FavoriteTile(
          pin: pin, tab: model.tab(ofPin: pin), peek: peek(of: pin),
          isSelected: pin.tabID != ClairTabIDNone && pin.tabID == highlighted, isWindowKey: model.isWindowKey,
          isShown: pin.tabID != ClairTabIDNone && pin.tabID == highlighted, actions: actions
        )
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .frame(height: layout.height, alignment: .topLeading)
    .animation(.snappy(duration: 0.15), value: room)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    .onDrop(of: [SidebarDragItem.type], delegate: FavoritesDropDelegate(layout: { [width] in
      FavoritesLayout(count: favorites.count, width: width)
    }, dropIndex: $dropIndex, actions: actions))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.favorites")
  }

  private func peek(of pin: any ClairPin) -> (any ClairTab)? {
    guard let tab = model.tab(ofPin: pin), tab.peekID != ClairTabIDNone else { return nil }
    return model.pinTabs[tab.peekID]
  }
}

/// Finds where a tile dropped on the grid goes.
struct FavoritesDropDelegate: DropDelegate {
  let layout: () -> FavoritesLayout
  @Binding var dropIndex: Int?
  weak var actions: (any SidebarActions)?

  func dropUpdated(info: DropInfo) -> DropProposal? {
    dropIndex = layout().dropIndex(at: info.location)
    return DropProposal(operation: .move)
  }

  func dropExited(info: DropInfo) {
    dropIndex = nil
  }

  func performDrop(info: DropInfo) -> Bool {
    let index = layout().dropIndex(at: info.location)
    dropIndex = nil
    let actions = actions
    SidebarDragItem.load(from: info.itemProviders(for: [SidebarDragItem.type])) { item in
      actions?.drop(item, on: .favorites(index))
    }
    return true
  }
}

/// One favorite: its icon centred on a tinted tile, white with a ring while
/// the window shows it, and its Peek's favicon as a badge.
struct FavoriteTile: View {
  let pin: any ClairPin
  let tab: (any ClairTab)?
  let peek: (any ClairTab)?
  let isSelected: Bool
  let isWindowKey: Bool
  let isShown: Bool
  weak var actions: (any SidebarActions)?

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  static let cornerRadius: CGFloat = 10
  static let iconSize: CGFloat = 20

  var body: some View {
    let icon = PinsLogic.icon(of: pin, tab: tab)
    ZStack {
      RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        .fill(PinFill.tile(colorScheme, hovered: isHovered, selected: isSelected))
      if isSelected {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
          .strokeBorder(Color(nsColor: IconColor.main(of: icon) ?? .controlAccentColor), lineWidth: 2)
      }
      PinIcon(icon: icon, isLoading: tab?.isLoading == true, size: Self.iconSize)
    }
    .overlay(alignment: .topTrailing) {
      if let peek {
        PeekBadge(peek: peek)
          .scaleEffect(0.75)
          .offset(x: 6, y: -6)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { actions?.openPin(pin.pinID) }
    .overlay(RowClickCatcher(onMiddleClick: {}, menuItems: menuItems))
    .onHover { hovering in withAnimation(sidebarHoverFade) { isHovered = hovering } }
    .onDrag { SidebarDragItem.pin(pin.pinID).itemProvider() }
    .tooltip(PinsLogic.title(of: pin, tab: tab), delay: TabRow.titleTooltipDelay)
    .accessibilityElement()
    .accessibilityLabel(PinsLogic.title(of: pin, tab: tab))
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityIdentifier("clair.favoriteTile")
  }

  private var menuItems: [RowClickCatcher.Item] {
    let isMuted = tab?.isMuted == true
    return PinMenus.items(
      PinsLogic.favoriteMenu(isShown: isShown, isOpen: tab != nil, isMuted: isMuted), pin: pin, actions: actions)
  }
}

/// The box where favorites go while a profile has none: a dashed accent
/// border on a light accent tint, a star, "Drag to add Favorites" and a
/// dismiss ×.
struct FavoritesHintBox: View {
  weak var actions: (any SidebarActions)?

  @State private var isTargeted = false

  static let height: CGFloat = 105.5
  static let title = "Drag to add Favorites"
  static let message = "Favorites keep your most used sites and apps close"

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "star.fill")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 26, height: 26)
        .background(Color.accentColor, in: .circle)
      Text(Self.title).font(.system(size: 13, weight: .bold))
      Text(Self.message)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity)
    .frame(height: Self.height)
    .background(Color.accentColor.opacity(isTargeted ? 0.16 : 0.08), in: .rect(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }
    .overlay(alignment: .topTrailing) {
      IconButton(systemImage: "xmark", help: "Dismiss", size: 22, glyphSize: 9, glyphWeight: .bold) {
        actions?.dismissFavoritesHint()
      }
      .padding(4)
      .accessibilityIdentifier("clair.favoritesHintDismiss")
    }
    .onDrop(of: [SidebarDragItem.type], isTargeted: $isTargeted) { providers in
      let actions = actions
      SidebarDragItem.load(from: providers) { item in actions?.drop(item, on: .favorites(0)) }
      return true
    }
    .padding(.horizontal, FavoritesLayout.inset)
    .padding(.vertical, FavoritesLayout.inset)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.favoritesHint")
  }
}

// MARK: The pinned section (pinned-tabs spec)

/// A pinned tab's row: its icon and title, "/" and the current title while
/// navigated away, with its icon turning into Back to Pinned URL under the
/// pointer, and − or × by selection.
struct PinRow: View {
  let pin: any ClairPin
  let tab: (any ClairTab)?
  let peek: (any ClairTab)?
  let isActive: Bool
  let isWindowKey: Bool
  var moveTargets: [any ClairSpace] = []
  /// The rename in progress on this row, if any.
  var rename: RowRename?
  weak var actions: (any SidebarActions)?

  @State private var isHovered = false
  @State private var isIconHovered = false
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let navigated = PinsLogic.isNavigatedAway(pin)
    let title = PinsLogic.title(of: pin, tab: tab)
    let button = PinsLogic.rowButton(isSelected: isActive)
    HStack(spacing: TabRow.titleGap) {
      HStack(spacing: 0) {
        if navigated {
          // D6: the icon turns into Back to Pinned URL under the pointer.
          Button {
            actions?.returnToPinnedURL(pin.pinID)
          } label: {
            PinIcon(icon: PinsLogic.icon(of: pin, tab: tab), isLoading: tab?.isLoading == true, size: TabRow.faviconSize)
              .frame(width: TabRow.iconSize, height: TabRow.iconSize)
              .padding(5)
              .background(
                isIconHovered ? SidebarFill.hover(colorScheme) : .clear, in: .rect(cornerRadius: 6, style: .continuous))
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .padding(.leading, -5)
          .padding(.vertical, -5)
          .onHover { isIconHovered = $0 }
          .tooltip("\(pin.name ?? pin.title)\nBack to Pinned URL")
          .accessibilityLabel("Back to Pinned URL")
          .accessibilityIdentifier("clair.backToPinnedURL")
          Text("/")
            .font(TabRow.titleFont)
            .foregroundStyle(.tertiary)
            .padding(.leading, 3)
            .padding(.trailing, 4)
        } else {
          PinIcon(icon: PinsLogic.icon(of: pin, tab: tab), isLoading: tab?.isLoading == true, size: TabRow.faviconSize)
            .frame(width: TabRow.iconSize, height: TabRow.iconSize)
            .padding(.trailing, TabRow.titleGap)
        }
        VStack(alignment: .leading, spacing: 1) {
          if let rename {
            RenameField(
              text: pin.name ?? title, placeholder: pin.title, rename: rename
            ) { change in
              actions?.endRenaming(.pin(pin.pinID), change: change)
            }
          } else {
            Text(title).font(TabRow.titleFont).lineLimit(1)
              .accessibilityIdentifier("clair.tabTitle")
          }
          if navigated && isIconHovered {
            Text("Back to Pinned URL")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
      }
      Spacer(minLength: 0)
      if let peek {
        PeekBadge(peek: peek)
          .padding(.trailing, isHovered ? 0 : PeekBadge.trailing - TabRow.horizontalPadding)
      }
      if isHovered && rename == nil {
        IconButton(
          systemImage: button.systemImage, help: button.help, shortcut: button.shortcut, size: TabRow.closeSize,
          glyphSize: 12, glyphWeight: .bold, dimsWhenInactive: false
        ) {
          if button == .closeKeepingPin {
            actions?.closeKeepingPin(pin.pinID)
          } else {
            actions?.removePin(pin.pinID)
          }
        }
        .padding(.trailing, TabRow.closeTrailing - TabRow.horizontalPadding)
        .accessibilityIdentifier(button == .closeKeepingPin ? "clair.pinClose" : "clair.pinRemove")
      }
    }
    .padding(.horizontal, TabRow.horizontalPadding)
    .frame(height: TabRow.pillHeight)
    .background {
      if isActive {
        RoundedRectangle(cornerRadius: TabRow.cornerRadius, style: .continuous)
          .fill(SidebarFill.activePill(colorScheme, isWindowKey: isWindowKey))
          .shadow(color: .black.opacity(isWindowKey ? 0.12 : 0), radius: 2, y: 1)
      } else if isHovered {
        RoundedRectangle(cornerRadius: TabRow.cornerRadius, style: .continuous).fill(SidebarFill.hover(colorScheme))
      }
    }
    .padding(.top, TabRow.pillInset)
    .padding(.bottom, TabRow.pillInset + TabRow.spacing)
    .contentShape(Rectangle())
    .onTapGesture { actions?.openPin(pin.pinID) }
    .simultaneousGesture(
      SpatialTapGesture(count: 2).onEnded { value in
        actions?.beginRenaming(
          RowRename(row: .pin(pin.pinID), selectsAll: false, caret: RenameField.caret(in: title, at: value.location.x)))
      })
    .overlay(RowClickCatcher(onMiddleClick: {}, menuItems: menuItems))
    .onHover { isHovered = $0 }
    .tooltip(PinsLogic.tooltip(title: title, name: pin.name), delay: TabRow.titleTooltipDelay)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(title)
    .accessibilityIdentifier("clair.pinRow")
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }

  private var menuItems: [RowClickCatcher.Item] {
    var items = PinMenus.items(
      PinsLogic.pinnedMenu(isOpen: tab != nil, isMuted: tab?.isMuted == true, canMoveToSpace: !moveTargets.isEmpty),
      pin: pin, actions: actions)
    // Move to Space's submenu.
    let pinID = pin.pinID
    items = items.map { item in
      guard case .action(let title, _) = item, title == "Move to Space" else { return item }
      return .submenu(
        title,
        moveTargets.map { space in
          let spaceID = space.spaceID
          return .action(SpacesLogic.label(of: space)) { [weak actions] in actions?.movePin(pinID, toSpace: spaceID) }
        })
    }
    return items
  }
}

/// A pin's icon: its favicon, a spinner while it loads without one, or a
/// globe.
struct PinIcon: View {
  let icon: NSImage?
  var isLoading = false
  let size: CGFloat

  var body: some View {
    Group {
      if isLoading && icon == nil {
        ProgressView().controlSize(.small)
      } else if let icon {
        Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
      } else {
        Image(systemName: "globe").font(.system(size: size * 0.8)).foregroundStyle(.secondary)
      }
    }
    .accessibilityElement()
    .accessibilityIdentifier("clair.tabFavicon")
  }
}

/// The context menus of pinned tabs and favorites, as RowClickCatcher items.
@MainActor
enum PinMenus {
  static func items(_ menu: [PinsLogic.MenuItem?], pin: any ClairPin, actions: (any SidebarActions)?)
    -> [RowClickCatcher.Item]
  {
    let pinID = pin.pinID
    return menu.map { item -> RowClickCatcher.Item in
      guard let item else { return .separator }
      guard item.isEnabled else { return .disabled(item.title) }
      switch item.command {
      case .editPinnedPage:
        return .submenu(
          item.title,
          PinsLogic.editPinnedPageMenu(pin).map { sub in
            guard sub.isEnabled else { return .disabled(sub.title) }
            return .action(sub.title) { [weak actions] in
              if sub.command == .replacePinnedURL {
                actions?.replacePinnedURL(pinID)
              } else {
                actions?.editPinnedURL(pinID)
              }
            }
          })
      default:
        return .action(item.title) { [weak actions] in run(item.command, pin: pin, actions: actions) }
      }
    }
  }

  private static func run(_ command: PinsLogic.MenuCommand, pin: any ClairPin, actions: (any SidebarActions)?) {
    let pinID = pin.pinID
    switch command {
    case .copyLink: actions?.copyLink(ofPin: pinID)
    case .rename:
      if pin.isFavorite {
        actions?.renameFavorite(pinID)
      } else {
        actions?.beginRenaming(RowRename(row: .pin(pinID), selectsAll: true, caret: nil))
      }
    case .duplicate: actions?.duplicate(pin: pinID)
    case .mute: actions?.setMuted(true, pin: pinID)
    case .unmute: actions?.setMuted(false, pin: pinID)
    case .pinToFavorites: actions?.pinToFavorites(pin: pinID)
    case .unpin: actions?.unpin(pinID)
    case .closeTab: actions?.closeKeepingPin(pinID)
    case .removePin, .removeFavorite: actions?.removePin(pinID)
    case .pin, .editPinnedPage, .replacePinnedURL, .editPinnedURL, .moveToSpace, .closeTabsBelow: break
    }
  }
}

/// The line between the pinned section and "New Tab", with "↓ Clear" at its
/// trailing end while the pointer is over the sidebar.
struct TodayDivider: View {
  let showsClear: Bool
  let action: () -> Void

  @State private var isClearHovered = false

  static let height: CGFloat = 17

  var body: some View {
    HStack(spacing: 6) {
      Rectangle()
        .fill(PinFill.divider)
        .frame(height: 0.5)
      if showsClear {
        Button(action: action) {
          HStack(spacing: 3) {
            Image(systemName: "arrow.down")
              .font(.system(size: 9, weight: .bold))
            Text("Clear").font(.system(size: 11, weight: .medium))
          }
          .foregroundStyle(isClearHovered ? Color.primary.opacity(0.8) : Color.secondary)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isClearHovered = $0 }
        .tooltip("Clear Today tabs", shortcut: ["⇧", "⌘", "K"])
        .accessibilityIdentifier("clair.clearToday")
        .transition(.opacity)
      }
    }
    .padding(.leading, 10)
    .padding(.trailing, 10)
    .frame(height: Self.height)
    .animation(sidebarHoverFade, value: showsClear)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.todayDivider")
  }
}

/// The pinned section's fills, as contrasts against the sidebar (design
/// D11, "Arc reference"): black overlays in Light Mode, white in Dark Mode.
enum PinFill {
  static func tile(_ scheme: ColorScheme, hovered: Bool, selected: Bool) -> Color {
    if selected {
      return scheme == .dark ? Color(white: 0.6) : Color.white
    }
    return scheme == .dark
      ? Color.white.opacity(hovered ? 0.16 : 0.11) : Color.black.opacity(hovered ? 0.11 : 0.07)
  }

  static let divider = Color.primary.opacity(0.14)
}

// MARK: Renaming in place (tab-names spec, design D11)

/// A row's title as a field: the same font, no border, on the row's pill.
/// Return keeps the text; Esc, or the field losing the keyboard, discards it.
struct RenameField: NSViewRepresentable {
  let text: String
  /// What an empty field shows: the page's title.
  let placeholder: String
  let rename: RowRename
  let onEnd: (PinsLogic.NameChange) -> Void
  /// The custom name now, which an unchanged draft keeps.
  var current: String?

  init(
    text: String, placeholder: String, rename: RowRename, current: String? = nil,
    onEnd: @escaping (PinsLogic.NameChange) -> Void
  ) {
    self.text = text
    self.placeholder = placeholder
    self.rename = rename
    self.current = current
    self.onEnd = onEnd
  }

  static let font = NSFont.systemFont(ofSize: 14)

  /// The caret's offset in `title` for a click `x` points from its start.
  static func caret(in title: String, at x: CGFloat) -> Int {
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    var offset = 0
    for index in title.indices {
      let prefix = String(title[..<title.index(after: index)])
      let width = (prefix as NSString).size(withAttributes: attributes).width
      let previous = (String(title[..<index]) as NSString).size(withAttributes: attributes).width
      if x < (previous + width) / 2 {
        return offset
      }
      offset += 1
    }
    return title.count
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onEnd: onEnd, current: current)
  }

  func makeNSView(context: Context) -> NSTextField {
    let field = FocusingField(string: text)
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = Self.font
    field.placeholderString = placeholder
    field.lineBreakMode = .byTruncatingTail
    field.cell?.usesSingleLineMode = true
    field.delegate = context.coordinator
    field.setAccessibilityIdentifier("clair.renameField")
    let rename = self.rename
    let coordinator = context.coordinator
    // Once it's in the window: before then, it can't take the keyboard.
    field.onWindow = { [weak field] in
      guard let field, let window = field.window, window.makeFirstResponder(field),
        let editor = field.currentEditor()
      else { return }
      let length = (field.stringValue as NSString).length
      if rename.selectsAll {
        editor.selectedRange = NSRange(location: 0, length: length)
      } else {
        editor.selectedRange = NSRange(location: min(rename.caret ?? length, length), length: 0)
      }
      coordinator.isEditing = true
    }
    return field
  }

  /// A field that runs `onWindow` once, after it joins a window.
  final class FocusingField: NSTextField {
    var onWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard window != nil, let onWindow else { return }
      self.onWindow = nil
      DispatchQueue.main.async(execute: onWindow)
    }
  }

  func updateNSView(_ field: NSTextField, context: Context) {
    field.placeholderString = placeholder
    context.coordinator.onEnd = onEnd
    context.coordinator.current = current
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var onEnd: (PinsLogic.NameChange) -> Void
    var current: String?
    var isEditing = false
    private var ended = false

    init(onEnd: @escaping (PinsLogic.NameChange) -> Void, current: String?) {
      self.onEnd = onEnd
      self.current = current
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
      switch selector {
      case #selector(NSResponder.insertNewline(_:)):
        end(PinsLogic.nameChange(draft: textView.string, current: current))
        return true
      case #selector(NSResponder.cancelOperation(_:)):
        end(.unchanged)
        return true
      default:
        return false
      }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
      // Clicking elsewhere discards the edit (tab-names spec); an end before
      // the field has the keyboard is no edit at all.
      guard isEditing else { return }
      end(.unchanged)
    }

    private func end(_ change: PinsLogic.NameChange) {
      guard !ended else { return }
      ended = true
      onEnd(change)
    }
  }
}

// MARK: The selected favorite's ring (design D11)

/// The main colour of an icon: its most saturated common colour, worked out
/// once per image.
enum IconColor {
  private static let cache = NSCache<NSImage, NSColor>()

  static func main(of image: NSImage?) -> NSColor? {
    guard let image else { return nil }
    if let cached = cache.object(forKey: image) {
      return cached
    }
    guard let color = compute(image) else { return nil }
    cache.setObject(color, forKey: image)
    return color
  }

  /// Averages the pixels of each of 12 hue buckets, weighted by saturation,
  /// and takes the bucket with the most weight.
  static func compute(_ image: NSImage) -> NSColor? {
    let side = 16
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    var buckets = [(weight: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)](repeating: (0, 0, 0, 0), count: 12)
    var grey = (weight: CGFloat(0), r: CGFloat(0), g: CGFloat(0), b: CGFloat(0))
    for y in 0..<side {
      for x in 0..<side {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5 else {
          continue
        }
        let saturation = color.saturationComponent
        let brightness = color.brightnessComponent
        if saturation < 0.2 || brightness < 0.15 {
          grey.weight += 1
          grey.r += color.redComponent
          grey.g += color.greenComponent
          grey.b += color.blueComponent
          continue
        }
        let bucket = min(Int(color.hueComponent * 12), 11)
        let weight = saturation * brightness
        buckets[bucket].weight += weight
        buckets[bucket].r += color.redComponent * weight
        buckets[bucket].g += color.greenComponent * weight
        buckets[bucket].b += color.blueComponent * weight
      }
    }
    if let best = buckets.max(by: { $0.weight < $1.weight }), best.weight > 1 {
      return NSColor(
        deviceRed: best.r / best.weight, green: best.g / best.weight, blue: best.b / best.weight, alpha: 1)
    }
    guard grey.weight > 0 else { return nil }
    return NSColor(deviceRed: grey.r / grey.weight, green: grey.g / grey.weight, blue: grey.b / grey.weight, alpha: 1)
  }
}
