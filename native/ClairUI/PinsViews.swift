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

  // Folders (add-tab-folders design D4, D6 to D8, D11); New Folder is a
  // SpaceActions call.
  /// Tabs › New Folder…: asks for the name first.
  func newFolderWithDialog()
  /// A click on the folder's row.
  func toggleFolder(_ folderID: FolderID)
  /// Close This Folder.
  func closeTabs(inFolder folderID: FolderID)
  func turnFolderIntoSpace(_ folderID: FolderID)
  func duplicateFolder(_ folderID: FolderID)
  func moveFolder(_ folderID: FolderID, toSpace spaceID: SpaceID)
  /// Asks first when it has tabs.
  func deleteFolder(_ folderID: FolderID)
}

// MARK: Dragging between sections (design D5, D11)

/// What a row or tile carries while dragged.
enum SidebarDragItem: Equatable {
  case tab(TabID)
  case pin(PinID)
  /// A folder, which moves only within its Space's pinned section
  /// (add-tab-folders D4).
  case folder(FolderID)

  /// Its own type, so a page's text or link dropped on the sidebar is
  /// ignored. It's text, which `package.sh` declares too: a list row dragged
  /// with a type that's only data carries a file promise instead, which no
  /// drop outside the list, such as the favorites, accepts.
  static let type = UTType(exportedAs: "com.clairbrowser.clair.sidebar-item", conformingTo: .utf8PlainText)

  var payload: String {
    switch self {
    case .tab(let tabID): "tab:\(tabID)"
    case .pin(let pinID): "pin:\(pinID)"
    case .folder(let folderID): "folder:\(folderID)"
    }
  }

  nonisolated init?(payload: String) {
    if payload.hasPrefix("tab:"), let tabID = TabID(payload.dropFirst(4)) {
      self = .tab(tabID)
    } else if payload.hasPrefix("pin:") {
      self = .pin(String(payload.dropFirst(4)))
    } else if payload.hasPrefix("folder:") {
      self = .folder(String(payload.dropFirst(7)))
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
  /// At this index among the Space's pinned items, pinned tabs and folders.
  case pinned(Int)
  /// At this index among a folder's pinned tabs (add-tab-folders D4, D5).
  case folder(FolderID, Int)
  case today(Int)
  case favorites(Int)
}

/// Takes a row or tile dropped on a view for one place, such as the Space
/// header for the end of the pinned section: a move, so the pointer shows no
/// "+".
struct PinningDropDelegate: DropDelegate {
  let isEnabled: Bool
  let target: SidebarDropTarget
  @Binding var isTargeted: Bool
  weak var actions: (any SidebarActions)?

  func validateDrop(info: DropInfo) -> Bool { isEnabled }

  func dropEntered(info: DropInfo) { isTargeted = true }

  func dropExited(info: DropInfo) { isTargeted = false }

  func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

  func performDrop(info: DropInfo) -> Bool {
    isTargeted = false
    let actions = actions
    let target = target
    SidebarDragItem.load(from: info.itemProviders(for: [SidebarDragItem.type])) { item in
      actions?.drop(item, on: target)
    }
    return true
  }
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
    // A favorited split is one tile (add-split-view D10).
    let favorites = model.favoriteItems
    let room = dropIndex.map { min($0, favorites.count) }
    let layout = FavoritesLayout(count: favorites.count + (room == nil ? 0 : 1), width: width)
    let highlighted = model.highlightedTab
    ZStack(alignment: .topLeading) {
      ForEach(Array(favorites.enumerated()), id: \.offset) { index, item in
        let slot = room.map { index >= $0 ? index + 1 : index } ?? index
        let frame = layout.frame(of: slot)
        Group {
          if let split = item.split {
            SplitRows.favorite(split, model: model, actions: actions)
              .onDrag { SidebarDragItem.pin(split.pins.first?.pinID ?? "").itemProvider() }
          } else if let pin = item.pin {
            FavoriteTile(
              pin: pin, tab: model.tab(ofPin: pin), peek: peek(of: pin),
              isSelected: pin.tabID != ClairTabIDNone && pin.tabID == highlighted, isWindowKey: model.isWindowKey,
              isShown: pin.tabID != ClairTabIDNone && pin.tabID == highlighted, actions: actions
            )
          }
        }
        .id(PinsLogic.itemID(item))
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .frame(height: layout.height, alignment: .topLeading)
    .animation(.snappy(duration: 0.15), value: room)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    .overlay {
      FavoritesDropArea(
        slot: { [width] in FavoritesLayout(count: favorites.count, width: width).dropIndex(at: $0) },
        tileSize: { [width] in FavoritesLayout(count: favorites.count + 1, width: width).frame(of: $0).size },
        icon: { [model] in model.icon(of: $0) },
        onTarget: { [$dropIndex] in $dropIndex.wrappedValue = $0 },
        onDrop: { [actions] item, slot in actions?.drop(item, on: .favorites(slot)) })
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.favorites")
  }

  private func peek(of pin: any ClairPin) -> (any ClairTab)? {
    guard let tab = model.tab(ofPin: pin), tab.peekID != ClairTabIDNone else { return nil }
    return model.pinTabs[tab.peekID]
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
  /// Arc draws the icon at about 16 pt, whatever the tile's size.
  static let iconSize: CGFloat = 16

  var body: some View {
    let icon = PinsLogic.icon(of: pin, tab: tab)
    ZStack {
      RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        .fill(PinFill.tile(colorScheme, hovered: isHovered, selected: isSelected))
      if isSelected {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
          .strokeBorder(Color(nsColor: IconColor.ring(of: icon)), lineWidth: 2)
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
    // No tooltip: Arc shows none on a tile, renamed or not.
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
/// dismiss ×. As the drop zone a drag opens once the box is gone
/// (show-favorites-drop-zone D3), it has no ×, a fainter border and a faint
/// white fill, and under the drag a solid border and faded contents, as in
/// Arc.
struct FavoritesHintBox: View {
  let model: BrowserWindowModel
  weak var actions: (any SidebarActions)?
  var isDropZone = false

  @State private var isTargeted = false

  /// The box as drawn, 8 pt below the URL field and 30 pt above the Space
  /// name's centre, as in Arc.
  static let height: CGFloat = 94
  static let topInset: CGFloat = 8
  static let bottomInset: CGFloat = 11.5
  static let title = "Drag to add Favorites"
  static let message = "Favorites keep your most used sites and apps close"

  var body: some View {
    // Arc's, measured: a 16 pt star 11.5 pt from the top, the title centred
    // 42 pt down and the message's lines 15 pt apart, in a 94 pt box.
    VStack(spacing: 0) {
      Image(systemName: "star.fill")
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 16, height: 16)
        .background(Color.accentColor, in: .circle)
        .padding(.top, 11.5)
      Text(Self.title)
        .font(.system(size: 13, weight: .semibold))
        .padding(.top, 6.5)
      Text(Self.message)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.top, 3)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    // Arc fades the drop zone's contents to about half under the drag.
    .opacity(isDropZone && isTargeted ? 0.5 : 1)
    .frame(maxWidth: .infinity)
    .frame(height: Self.height)
    .background(fill, in: .rect(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: isDropZone && isTargeted ? [] : [4, 3]))
    }
    .overlay(alignment: .topTrailing) {
      if !isDropZone {
        IconButton(systemImage: "xmark", help: "Dismiss", size: 22, glyphSize: 9, glyphWeight: .bold) {
          actions?.dismissFavoritesHint()
        }
        .padding(4)
        .accessibilityIdentifier("clair.favoritesHintDismiss")
      }
    }
    .overlay {
      GeometryReader { geometry in
        // Over the drop zone, Arc's drag shows a square tile (D4).
        let tileWidth = isDropZone ? FavoritesLayout.tileHeight : geometry.size.width
        FavoritesDropArea(
          slot: { _ in 0 },
          tileSize: { _ in CGSize(width: tileWidth, height: FavoritesLayout.tileHeight) },
          icon: { [model] in model.icon(of: $0) },
          onTarget: { [$isTargeted] in $isTargeted.wrappedValue = $0 != nil },
          onDrop: { [actions] item, _ in actions?.drop(item, on: .favorites(0)) })
      }
    }
    .padding(.horizontal, FavoritesLayout.inset)
    .padding(.top, Self.topInset)
    .padding(.bottom, Self.bottomInset)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(isDropZone ? "clair.favoritesDropZone" : "clair.favoritesHint")
  }

  /// The box's accent tint, or the drop zone's white, measured in Arc:
  /// about 12 % white, and 30 % under the drag.
  private var fill: Color {
    guard isDropZone else { return Color.accentColor.opacity(isTargeted ? 0.16 : 0.08) }
    return Color.white.opacity(isTargeted ? 0.3 : 0.12)
  }

  /// The drop zone's border is about 30 % accent in Arc, fainter than the
  /// box's.
  private var border: Color { Color.accentColor.opacity(isDropZone ? 0.3 : 0.6) }
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

  /// Arc's Back to Pinned URL button: 38 pt, 10 pt before the icon.
  static let backButtonSize: CGFloat = 38
  static let backButtonLeading: CGFloat = 10
  /// The "/" between the icon and the title, which starts 10 pt after the
  /// icon, as Arc's at x=45.
  static let slashWidth: CGFloat = 10

  var body: some View {
    let navigated = PinsLogic.isNavigatedAway(pin)
    let title = PinsLogic.title(of: pin, tab: tab)
    let button = PinsLogic.rowButton(isSelected: isActive)
    HStack(spacing: TabRow.titleGap) {
      HStack(spacing: 0) {
        if navigated {
          // D6: the icon turns into Back to Pinned URL under the pointer:
          // Arc's 38 pt button, from 10 pt before the icon to the title,
          // covering the "/".
          PinIcon(icon: PinsLogic.icon(of: pin, tab: tab), isLoading: tab?.isLoading == true, size: TabRow.faviconSize)
            .frame(width: TabRow.iconSize, height: TabRow.iconSize)
            .background {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isIconHovered ? PinFill.backButton(colorScheme) : .clear)
                .frame(width: Self.backButtonSize, height: Self.backButtonSize)
                .offset(x: (Self.backButtonSize - TabRow.iconSize) / 2 - Self.backButtonLeading)
            }
            .overlay {
              Color.clear
                .frame(width: Self.backButtonSize, height: Self.backButtonSize)
                .contentShape(Rectangle())
                .offset(x: (Self.backButtonSize - TabRow.iconSize) / 2 - Self.backButtonLeading)
                .onTapGesture { actions?.returnToPinnedURL(pin.pinID) }
                .onHover { isIconHovered = $0 }
                // A renamed pin's says where the icon goes; any other's is
                // the row's own (tab-names spec).
                .tooltip(
                  pin.name.flatMap { $0.isEmpty ? nil : "\($0)\nBack to Pinned URL" }
                    ?? PinsLogic.tooltip(title: title, name: nil),
                  delay: TabRow.titleTooltipDelay)
                .accessibilityElement()
                .accessibilityLabel("Back to Pinned URL")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("clair.backToPinnedURL")
            }
            .zIndex(1)
          Text("/")
            .font(TabRow.titleFont)
            .foregroundStyle(.tertiary)
            .opacity(isIconHovered ? 0 : 1)
            .frame(width: Self.slashWidth)
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
      // A double-click's field leaves the button, as Arc's; Rename…'s takes
      // its room.
      if isHovered && rename?.selectsAll != true {
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
          .shadow(color: SidebarFill.activeShadow, radius: 2, y: 1)
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
    PinMenus.pinnedItems(pin: pin, tab: tab, moveTargets: moveTargets, actions: actions)
  }
}

extension PinMenus {
  /// A pinned tab's menu, with Move to Space's submenu; a pinned split's
  /// chip's with `inSplit`.
  static func pinnedItems(
    pin: any ClairPin, tab: (any ClairTab)?, moveTargets: [any ClairSpace], actions: (any SidebarActions)?,
    inSplit: Bool = false
  ) -> [RowClickCatcher.Item] {
    var items = PinMenus.items(
      PinsLogic.pinnedMenu(
        isOpen: tab != nil, isMuted: tab?.isMuted == true, canMoveToSpace: !moveTargets.isEmpty, inSplit: inSplit),
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
      case .splitWithTab:
        // Disabled while the pin's page is in a split (add-split-view D9).
        if pin.tabs.contains(where: { $0.splitPartnerID != ClairTabIDNone }) {
          return .disabledSubmenu(item.title)
        }
        return .submenu(item.title, actions?.splitWithTabItems(tab: nil, pin: pinID) ?? [])
      case .separateTabs:
        // A pinned split's, or a Today split's holding the pin's page.
        return .action(item.title) { [weak actions] in
          if let splitID = pin.pinnedSplitID {
            actions?.separatePinnedSplit(splitID)
          } else if pin.tabID != ClairTabIDNone {
            actions?.separateSplit(of: pin.tabID)
          }
        }
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
    case .removeFavorite: actions?.removePin(pinID)
    case .pin, .editPinnedPage, .replacePinnedURL, .editPinnedURL, .moveToSpace, .closeTabsBelow, .turnIntoSpace,
      .deleteFolder, .splitWithTab, .separateTabs:
      break
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

  /// Where the hairline sits in the row, as Arc's.
  static let hairlineY: CGFloat = 7.5

  var body: some View {
    HStack(spacing: 6) {
      Rectangle()
        .fill(PinFill.divider)
        .frame(height: 0.5)
        .offset(y: Self.hairlineY + 0.25 - Self.height / 2)
      if showsClear {
        Button(action: action) {
          HStack(spacing: 3) {
            Image(systemName: "arrow.down")
              .font(.system(size: 9, weight: .bold))
            Text("Clear").font(.system(size: 11, weight: .medium))
          }
          // A little fainter than the sidebar's other secondary text.
          .foregroundStyle(isClearHovered ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.75))
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
    // Arc's tiles sit 16 below the sidebar in Light Mode and 19 above it in
    // Dark Mode, 22 and 29 under the pointer, out of 255.
    return scheme == .dark
      ? Color.white.opacity(hovered ? 0.12 : 0.08) : Color.black.opacity(hovered ? 0.10 : 0.07)
  }

  /// The divider's hairline, a little stronger than Arc's.
  static let divider = Color.primary.opacity(0.22)

  /// The Back to Pinned URL button under the pointer: Arc's hovered × or −
  /// background.
  static func backButton(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
  }
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
  /// The field's font: a folder's name is semibold (add-tab-folders D4).
  var font: NSFont = RenameField.font
  /// What a draft does to the current name: a row's name clears when
  /// emptied, a folder's stays (add-tab-folders D6).
  var change: (String, String?) -> PinsLogic.NameChange = { PinsLogic.nameChange(draft: $0, current: $1) }

  init(
    text: String, placeholder: String, rename: RowRename, current: String? = nil, font: NSFont = RenameField.font,
    change: @escaping (String, String?) -> PinsLogic.NameChange = { PinsLogic.nameChange(draft: $0, current: $1) },
    onEnd: @escaping (PinsLogic.NameChange) -> Void
  ) {
    self.text = text
    self.placeholder = placeholder
    self.rename = rename
    self.current = current
    self.font = font
    self.change = change
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
    Coordinator(onEnd: onEnd, current: current, change: change)
  }

  func makeNSView(context: Context) -> NSTextField {
    let field = FocusingField(string: text)
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = font
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
    var onWindow: (@MainActor () -> Void)?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard window != nil, let onWindow else { return }
      self.onWindow = nil
      Task { @MainActor in onWindow() }
    }
  }

  func updateNSView(_ field: NSTextField, context: Context) {
    field.placeholderString = placeholder
    context.coordinator.onEnd = onEnd
    context.coordinator.current = current
    context.coordinator.change = change
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var onEnd: (PinsLogic.NameChange) -> Void
    var current: String?
    var change: (String, String?) -> PinsLogic.NameChange
    var isEditing = false
    private var ended = false

    init(
      onEnd: @escaping (PinsLogic.NameChange) -> Void, current: String?,
      change: @escaping (String, String?) -> PinsLogic.NameChange
    ) {
      self.onEnd = onEnd
      self.current = current
      self.change = change
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
      switch selector {
      case #selector(NSResponder.insertNewline(_:)):
        end(change(textView.string, current))
        return true
      case #selector(NSResponder.cancelOperation(_:)):
        end(.unchanged)
        return true
      default:
        return false
      }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
      // Clicking elsewhere keeps the edit, as in Arc (tab-names spec); an end
      // before the field has the keyboard is no edit at all.
      guard isEditing, let field = notification.object as? NSTextField else { return }
      end(change(field.stringValue, current))
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

  /// The selected tile's ring: the icon's main colour, lightened about 30%
  /// toward white, as Arc's (Hacker News's orange 255 102 0 rings 254 144 93).
  static func ring(of image: NSImage?) -> NSColor {
    let main = Self.main(of: image) ?? .controlAccentColor
    return main.blended(withFraction: 0.3, of: .white) ?? main
  }

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
