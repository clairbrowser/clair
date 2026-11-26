// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// The rules behind pinned tabs, favorites and tab names
/// (add-pinned-tabs-and-favorites design D4 to D6, D8, D11), kept apart from
/// the views so they can be tested.
enum PinsLogic {
  // MARK: A pin's row

  /// The bound tab, or nil while the pin's page isn't open.
  static func tab(of pin: any ClairPin) -> (any ClairTab)? {
    pin.tabs.first { $0.tabID == pin.tabID }
  }

  /// The bound tab's Peek, whose favicon the row or tile shows as a badge.
  static func peek(of pin: any ClairPin) -> (any ClairTab)? {
    guard let tab = tab(of: pin), tab.peekID != ClairTabIDNone else { return nil }
    return pin.tabs.first { $0.tabID == tab.peekID && $0.peekParentID == tab.tabID }
  }

  /// Whether the pin's page is open at another URL than its pinned URL: its
  /// row shows "/" and its icon turns into Back to Pinned URL.
  static func isNavigatedAway(_ pin: any ClairPin) -> Bool {
    pin.tabID != ClairTabIDNone && !pin.isAtPinnedURL
  }

  /// What the row reads: the custom name; or else, while navigated away,
  /// the current page's title; or else the pinned page's title. `tab` is the
  /// bound tab's latest snapshot.
  static func title(of pin: any ClairPin, tab: (any ClairTab)?) -> String {
    if let name = pin.name, !name.isEmpty {
      return name
    }
    if isNavigatedAway(pin), let tab, !tab.title.isEmpty {
      return tab.title
    }
    return pin.title
  }

  /// The icon the row shows: the open page's while it's at the pinned URL,
  /// or else the one kept from the pinned page.
  static func icon(of pin: any ClairPin, tab: (any ClairTab)?) -> NSImage? {
    if !isNavigatedAway(pin), let favicon = tab?.favicon {
      return favicon
    }
    return pin.icon
  }

  /// The button a pinned row shows on hover (pinned-tabs spec, "Closing a
  /// pinned tab keeps it pinned", "Removing a pin").
  enum RowButton: Equatable {
    /// "Close and Keep Pinned", on the selected pinned tab.
    case closeKeepingPin
    /// "Remove Pin", on any other.
    case removePin

    var help: String {
      switch self {
      case .closeKeepingPin: "Close and Keep Pinned"
      case .removePin: "Remove Pin"
      }
    }

    var shortcut: [String] {
      self == .closeKeepingPin ? ["⌘", "W"] : []
    }

    var systemImage: String {
      self == .closeKeepingPin ? "minus" : "xmark"
    }
  }

  static func rowButton(isSelected: Bool) -> RowButton {
    isSelected ? .closeKeepingPin : .removePin
  }

  /// Whether the Space header offers its collapse chevron: while the Space
  /// has pinned items, pinned tabs or folders, or while its section is
  /// collapsed, so a section whose last pin went while it was collapsed can
  /// be expanded again.
  static func offersCollapse(pinCount: Int, collapsed: Bool) -> Bool {
    pinCount > 0 || collapsed
  }

  // MARK: Folders (add-tab-folders design D4)

  /// Every pinned tab of `items`, its folders' and splits' included, in
  /// order (add-split-view D10).
  static func allPins(_ items: [any ClairPinnedItem]) -> [any ClairPin] {
    items.flatMap { item -> [any ClairPin] in
      if let pin = item.pin { return [pin] }
      if let split = item.split { return split.pins }
      return item.folder.map { allPins($0.items) } ?? []
    }
  }

  /// The pinned or favorited split of `items`, its folders' included, that
  /// holds `pinID`.
  static func split(containing pinID: PinID, in items: [any ClairPinnedItem]) -> (any ClairPinnedSplit)? {
    for item in items {
      if let split = item.split, split.pins.contains(where: { $0.pinID == pinID }) { return split }
      if let folder = item.folder, let split = split(containing: pinID, in: folder.items) { return split }
    }
    return nil
  }

  /// A folder's pinned tabs, its splits' two included, in order.
  static func pins(of folder: any ClairFolder) -> [any ClairPin] {
    allPins(folder.items)
  }

  /// One row of the pinned section.
  enum PinnedRow {
    /// A pinned tab, under `folder` when it's listed in one.
    case pin(any ClairPin, folder: (any ClairFolder)?)
    /// A pinned split, one row for its two pages (add-split-view D10).
    case split(any ClairPinnedSplit, folder: (any ClairFolder)?)
    case folder(any ClairFolder)

    var id: String {
      switch self {
      case .pin(let pin, _): "pin-\(pin.pinID)"
      case .split(let split, _): "split-\(split.pinnedSplitID)"
      case .folder(let folder): "folder-\(folder.folderID)"
      }
    }

    /// The pinned tab, or a pinned split's leading one, which stands for the
    /// split in commands.
    var pin: (any ClairPin)? {
      switch self {
      case .pin(let pin, _): pin
      case .split(let split, _): split.pins.first
      case .folder: nil
      }
    }

    /// The ID of the item the row is: a pin's, a split's or a folder's.
    var itemID: String {
      switch self {
      case .pin(let pin, _): pin.pinID
      case .split(let split, _): split.pinnedSplitID
      case .folder(let folder): folder.folderID
      }
    }

    /// The folder a pin's or split's row is listed in.
    var parent: (any ClairFolder)? {
      switch self {
      case .pin(_, let folder), .split(_, let folder): folder
      case .folder: nil
      }
    }
  }

  /// The ID of a pinned item: its pin's, split's or folder's.
  static func itemID(_ item: any ClairPinnedItem) -> String {
    item.pin?.pinID ?? item.split?.pinnedSplitID ?? item.folder?.folderID ?? ""
  }

  /// Whether a pinned split's page shows: either pin's bound tab is
  /// `highlighted`.
  static func isSelected(_ split: any ClairPinnedSplit, highlighted: TabID) -> Bool {
    highlighted != ClairTabIDNone && split.pins.contains { $0.tabID == highlighted }
  }

  /// Whether any of a split's pages is open.
  static func isOpen(_ split: any ClairPinnedSplit) -> Bool {
    split.pins.contains { $0.tabID != ClairTabIDNone }
  }

  /// The pinned section's rows: each pinned tab; each folder, then its
  /// tabs while it's open, or those whose page is open while it's closed,
  /// as Arc does. A
  /// collapsed section lists only the selected tab, without its folder
  /// (pinned-tabs spec, "Collapsing the pinned section"; tab-folders spec,
  /// "Folders in a collapsed pinned section").
  static func pinnedRows(_ items: [any ClairPinnedItem], collapsed: Bool, highlighted: TabID) -> [PinnedRow] {
    let isSelected = { (pin: any ClairPin) in pin.tabID != ClairTabIDNone && pin.tabID == highlighted }
    // A row of an item at the top level or in `folder`: a pin or a split.
    let row = { (item: any ClairPinnedItem, folder: (any ClairFolder)?) -> PinnedRow? in
      if let pin = item.pin { return .pin(pin, folder: folder) }
      if let split = item.split { return .split(split, folder: folder) }
      return nil
    }
    if collapsed {
      let leaves = items.flatMap { item in item.folder?.items ?? [item] }
      return leaves.compactMap { item -> PinnedRow? in
        if let pin = item.pin, isSelected(pin) { return .pin(pin, folder: nil) }
        if let split = item.split, Self.isSelected(split, highlighted: highlighted) {
          return .split(split, folder: nil)
        }
        return nil
      }
    }
    var rows: [PinnedRow] = []
    for item in items {
      if let folder = item.folder {
        rows.append(.folder(folder))
        for child in folder.items {
          let open = child.pin.map { $0.tabID != ClairTabIDNone } ?? child.split.map(isOpen) ?? false
          if folder.isOpen || open, let child = row(child, folder) {
            rows.append(child)
          }
        }
      } else if let item = row(item, nil) {
        rows.append(item)
      }
    }
    return rows
  }

  /// The folder icon's state (tab-folders spec, "The folder row").
  enum FolderIcon: Equatable {
    case open
    case closed
    /// Closed, with "•••" while any of its tabs is open.
    case closedWithOpenTabs
  }

  static func hasOpenTabs(_ folder: any ClairFolder) -> Bool {
    pins(of: folder).contains { $0.tabID != ClairTabIDNone }
  }

  static func folderIcon(_ folder: any ClairFolder) -> FolderIcon {
    if folder.isOpen { return .open }
    return hasOpenTabs(folder) ? .closedWithOpenTabs : .closed
  }

  /// Whether a folder's row shows "Close This Folder" (−): on hover, while
  /// any of its tabs is open.
  static func showsCloseFolder(_ folder: any ClairFolder, isHovered: Bool) -> Bool {
    isHovered && hasOpenTabs(folder)
  }

  static let closeFolderHelp = "Close This Folder"
  /// D6: a new folder's name, and its field's placeholder.
  static let newFolderName = "Untitled"
  static let folderNamePlaceholder = "Folder Title"

  /// What keeping `draft` in a folder's name field does: an empty name keeps
  /// the one it has.
  static func folderNameChange(draft: String, current: String) -> NameChange {
    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty || trimmed == current ? .unchanged : .rename(trimmed)
  }

  /// Whether the divider shows: while the Space has Today tabs, in a window
  /// with a pinned section (not incognito or guest ones).
  static func showsDivider(todayRowCount: Int, showsPins: Bool) -> Bool {
    showsPins && todayRowCount > 0
  }

  /// Whether Clear shows on the divider: while the pointer is over the
  /// sidebar and the divider shows.
  static func showsClear(todayRowCount: Int, showsPins: Bool, isSidebarHovered: Bool) -> Bool {
    isSidebarHovered && showsDivider(todayRowCount: todayRowCount, showsPins: showsPins)
  }

  // MARK: Tab names (tab-names spec)

  /// A tab row's tooltip: its name alone, or its title with the hint.
  static func tooltip(title: String, name: String?) -> String? {
    if let name, !name.isEmpty {
      return name
    }
    return title.isEmpty ? nil : "\(title)\nDouble-click to rename"
  }

  /// What keeping `draft` in the rename field does.
  enum NameChange: Equatable {
    /// The row keeps the name it has.
    case unchanged
    /// The row is named `name`.
    case rename(String)
    /// The custom name goes, and the row shows its page's title again.
    case clear
  }

  static func nameChange(draft: String, current: String?) -> NameChange {
    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    let current = current ?? ""
    if trimmed.isEmpty {
      return current.isEmpty ? .unchanged : .clear
    }
    return trimmed == current ? .unchanged : .rename(trimmed)
  }

  // MARK: The pinned URL (design D6)

  /// The URL Edit Pinned URL saves for what the user typed, or nil while it
  /// isn't one: an http, https, file or chrome URL, with https added to a
  /// host typed alone, as Chromium's fix-up does.
  static func fixedUpURL(_ text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
    let lowered = trimmed.lowercased()
    if let schemeEnd = lowered.range(of: "://") {
      let scheme = String(lowered[..<schemeEnd.lowerBound])
      guard ["http", "https", "file", "chrome"].contains(scheme), let url = URL(string: trimmed) else {
        return nil
      }
      return scheme == "file" || (url.host()?.isEmpty == false) ? url : nil
    }
    // A host, with a dot or as localhost, and maybe a port and a path.
    let host = lowered.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
    let name = host.split(separator: ":").first.map(String.init) ?? ""
    guard name == "localhost" || (name.contains(".") && !name.hasPrefix(".") && !name.hasSuffix(".")) else {
      return nil
    }
    guard let url = URL(string: "https://\(trimmed)"), url.host()?.isEmpty == false else { return nil }
    return url
  }

  /// What Copy Link copies: the page's current URL, or the pinned URL while
  /// it's closed.
  static func link(of pin: any ClairPin) -> String {
    if let tab = tab(of: pin), let link = TabListLogic.link(of: tab) {
      return link
    }
    return pin.url.absoluteString
  }

  // MARK: Rows and commands (design D4)

  /// One of the rows Cmd+1 to Cmd+9 and Next Tab count: every pinned tab of
  /// the Space, open or not, then the Today rows. Favorites aren't rows, and
  /// neither are the tabs a closed folder hides (add-tab-folders D9).
  enum CommandRow: Equatable {
    case pin(PinID)
    case tab(TabID)
  }

  static func commandRows(pins: [any ClairPin], today: [any ClairTab]) -> [CommandRow] {
    pins.map { .pin($0.pinID) } + TabListLogic.rows(today).map { .tab($0.tabID) }
  }

  static func commandRows(items: [any ClairPinnedItem], highlighted: TabID, today: [any ClairTab]) -> [CommandRow] {
    let pins = pinnedRows(items, collapsed: false, highlighted: highlighted).compactMap(\.pin)
    return commandRows(pins: pins, today: today)
  }

  // MARK: Dragging (design D5, D11)

  /// Where a row dropped in the list goes.
  enum ListDrop: Equatable {
    /// At this index among the Space's pinned items, pinned tabs and folders.
    case pinned(Int)
    /// At this index among a folder's pinned tabs (add-tab-folders D4).
    case folder(FolderID, Int)
    /// At this index in the Space's Today list, Peeks counted.
    case today(Int)
  }

  /// Where a row dropped before list item `destination` goes, in a list of
  /// pinned rows, `rows` of `items`, then `boundaryCount` rows that are
  /// neither (the row of the divider and "New Tab"), then the Today rows of
  /// `today`. `movingPinnedRow` is the index of a pinned row being moved
  /// within the list, which no longer counts once it's lifted;
  /// `movingTodayRow` the same for a Today row.
  ///
  /// add-tab-folders D4: a gap after a folder's row, between its listed
  /// tabs, or after an open folder's last tab is in the folder, as in Arc;
  /// after a closed folder's last listed tab, or its row when it lists none,
  /// it's after the folder.
  static func listDrop(
    destination: Int, rows: [PinnedRow], items: [any ClairPinnedItem], collapsed: Bool = false,
    boundaryCount: Int, today: [any ClairTab], movingPinnedRow: Int? = nil, movingTodayRow: Int? = nil
  ) -> ListDrop {
    let pinCount = rows.count
    if destination <= pinCount {
      return pinnedDrop(
        destination: destination, rows: rows, items: items, collapsed: collapsed, moving: movingPinnedRow)
    }
    let rows = TabListLogic.rows(today)
    var row = min(max(destination - pinCount - boundaryCount, 0), rows.count)
    if let movingTodayRow, movingTodayRow < row {
      row -= 1
    }
    // Rows before it, each with its Peek and a split's other pane, less the
    // moving row's family.
    var others = rows
    if let movingTodayRow, rows.indices.contains(movingTodayRow) {
      others.remove(at: movingTodayRow)
    }
    let before = others.prefix(row)
    let index = before.reduce(0) { count, tab in
      count + TabListLogic.rowFamily(tab.tabID, in: today).count
    }
    return .today(index)
  }

  /// The place of a gap among the pinned rows.
  private static func pinnedDrop(
    destination: Int, rows: [PinnedRow], items: [any ClairPinnedItem], collapsed: Bool, moving: Int?
  ) -> ListDrop {
    var others = rows
    var gap = destination
    let lifted = moving.flatMap { rows.indices.contains($0) ? rows[$0] : nil }
    if let moving, rows.indices.contains(moving) {
      others.remove(at: moving)
      if moving < gap { gap -= 1 }
    }
    gap = min(max(gap, 0), others.count)
    // The items as they are once the lifted row's item is out of the way.
    let liftedID = lifted?.itemID
    let topItems = items.filter { itemID($0) != liftedID }
    let topIndex = { (id: String) -> Int? in
      topItems.firstIndex { itemID($0) == id }
    }
    let indexInFolder = { (id: String, folder: any ClairFolder) -> Int in
      folder.items.filter { itemID($0) != liftedID }.firstIndex { itemID($0) == id } ?? 0
    }
    /// The place of the item of a pin's or split's row itself, in a folder
    /// or at the top level.
    let placeOf = { (row: PinnedRow) -> ListDrop in
      for item in topItems {
        if let folder = item.folder, folder.items.contains(where: { itemID($0) == row.itemID }) {
          return .folder(folder.folderID, indexInFolder(row.itemID, folder))
        }
      }
      return .pinned(topIndex(row.itemID) ?? topItems.count)
    }
    if collapsed {
      // Only the selected tab shows: before it is its own place, after it
      // the end of the section.
      if gap < others.count, others[gap].pin != nil {
        return placeOf(others[gap])
      }
      return .pinned(topItems.count)
    }
    let below = gap < others.count ? others[gap] : nil
    guard gap > 0 else { return .pinned(0) }
    let above = others[gap - 1]
    if case .folder(let folder) = above {
      // Under a folder's row: first in it, or before its first listed tab
      // while it's closed; after it when it's closed and lists nothing.
      if let below, below.parent?.folderID == folder.folderID {
        return .folder(folder.folderID, indexInFolder(below.itemID, folder))
      }
      if folder.isOpen {
        return .folder(folder.folderID, 0)
      }
      return .pinned((topIndex(folder.folderID) ?? topItems.count - 1) + 1)
    }
    guard let parent = above.parent else {
      return .pinned((topIndex(above.itemID) ?? topItems.count - 1) + 1)
    }
    if parent.isOpen {
      return .folder(parent.folderID, indexInFolder(above.itemID, parent) + 1)
    }
    // Between two rows a closed folder lists: in it, before the lower one.
    if let below, below.parent?.folderID == parent.folderID {
      return .folder(parent.folderID, indexInFolder(below.itemID, parent))
    }
    return .pinned((topIndex(parent.folderID) ?? topItems.count - 1) + 1)
  }

  // MARK: Menus (sidebar, pinned-tabs and favorites specs)

  enum MenuCommand: Equatable {
    case copyLink
    case rename
    case duplicate
    case mute
    case unmute
    case pin
    case pinToFavorites
    case editPinnedPage
    case replacePinnedURL
    case editPinnedURL
    case moveToSpace
    case unpin
    case closeTab
    case closeTabsBelow
    case removeFavorite
    // A folder's (add-tab-folders).
    case turnIntoSpace
    case deleteFolder
    // Split view's (add-split-view D9, D10).
    case splitWithTab
    case separateTabs
  }

  struct MenuItem: Equatable {
    let title: String
    let command: MenuCommand
    var isEnabled = true
  }

  static let splitWithTab = MenuItem(title: "Split with Tab", command: .splitWithTab)
  static let separateTabs = MenuItem(title: "Separate Tabs", command: .separateTabs)

  /// A Today tab's menu: nil entries are separators. Incognito and guest
  /// windows have neither pin item. A split row's chip (`inSplit`) has no
  /// Split with Tab, and Separate Tabs (add-split-view, "The split row's
  /// menu").
  static func todayMenu(isMuted: Bool, canMoveToSpace: Bool, canPin: Bool, inSplit: Bool = false) -> [MenuItem?] {
    var items: [MenuItem?] = [
      MenuItem(title: "Copy Link", command: .copyLink),
      MenuItem(title: "Rename…", command: .rename),
      MenuItem(title: "Duplicate", command: .duplicate),
      MenuItem(title: isMuted ? "Unmute" : "Mute", command: isMuted ? .unmute : .mute),
    ]
    items += inSplit ? [nil, separateTabs] : [splitWithTab]
    if canPin {
      items += [nil, MenuItem(title: "Pin Tab", command: .pin), MenuItem(title: "Pin to Favorites", command: .pinToFavorites)]
    }
    if canMoveToSpace {
      items += [nil, MenuItem(title: "Move to Space", command: .moveToSpace)]
    }
    items += [
      nil,
      MenuItem(title: "Close Tab", command: .closeTab),
      MenuItem(title: "Close Tabs Below", command: .closeTabsBelow),
    ]
    return items
  }

  /// A pinned tab's menu; a pinned split's chip's has no Edit Pinned Page
  /// or Split with Tab, and Separate Tabs.
  static func pinnedMenu(isOpen: Bool, isMuted: Bool, canMoveToSpace: Bool, inSplit: Bool = false) -> [MenuItem?] {
    var items: [MenuItem?] = [
      MenuItem(title: "Copy Link", command: .copyLink),
      MenuItem(title: "Rename…", command: .rename),
      MenuItem(title: isMuted ? "Unmute" : "Mute", command: isMuted ? .unmute : .mute, isEnabled: isOpen),
    ]
    if !inSplit {
      items.append(MenuItem(title: "Edit Pinned Page", command: .editPinnedPage))
    }
    items.append(MenuItem(title: "Duplicate", command: .duplicate))
    items += inSplit ? [nil, separateTabs] : [splitWithTab]
    if canMoveToSpace {
      items += [nil, MenuItem(title: "Move to Space", command: .moveToSpace)]
    }
    items += [
      nil,
      MenuItem(title: "Pin to Favorites", command: .pinToFavorites),
      MenuItem(title: "Unpin Tab", command: .unpin),
    ]
    return items
  }

  /// A favorite's menu; Close Tab only while the window shows its page. A
  /// favorited split's segment's has no Edit Pinned Page or Split with Tab,
  /// and Separate Tabs.
  static func favoriteMenu(isShown: Bool, isOpen: Bool, isMuted: Bool, inSplit: Bool = false) -> [MenuItem?] {
    var items: [MenuItem?] = [
      MenuItem(title: "Copy Link", command: .copyLink),
      MenuItem(title: "Rename…", command: .rename),
      MenuItem(title: isMuted ? "Unmute" : "Mute", command: isMuted ? .unmute : .mute, isEnabled: isOpen),
    ]
    if !inSplit {
      items.append(MenuItem(title: "Edit Pinned Page", command: .editPinnedPage))
    }
    items.append(MenuItem(title: "Duplicate", command: .duplicate))
    items += inSplit ? [nil, separateTabs] : [splitWithTab]
    items.append(nil)
    if isShown {
      items.append(MenuItem(title: "Close Tab", command: .closeTab))
    }
    items.append(MenuItem(title: "Remove Favorite", command: .removeFavorite))
    return items
  }

  /// A folder's menu (tab-folders spec, "Folder menu"): Move to Space only
  /// with another Space.
  static func folderMenu(name: String, canMoveToSpace: Bool) -> [MenuItem?] {
    var items: [MenuItem?] = [
      MenuItem(title: "Turn “\(name)” into Space", command: .turnIntoSpace),
      nil,
      MenuItem(title: "Rename…", command: .rename),
      nil,
      MenuItem(title: "Duplicate", command: .duplicate),
    ]
    if canMoveToSpace {
      items.append(MenuItem(title: "Move to Space", command: .moveToSpace))
    }
    items += [nil, MenuItem(title: "Delete", command: .deleteFolder)]
    return items
  }

  // MARK: Folder dialogs (add-tab-folders design D6, D7)

  static let newFolderDialogTitle = "New Folder…"
  static let newFolderDialogPlaceholder = "What are you organizing?"
  static let newFolderDialogButton = "Create"

  /// Create needs a name (tab-folders spec, "New Folder dialog").
  static func canCreateFolder(_ text: String) -> Bool {
    !SpacesLogic.cleanName(text).isEmpty
  }

  /// Whether Delete asks first: only for a folder with tabs.
  static func folderDeletionNeedsConfirmation(_ folder: any ClairFolder) -> Bool {
    !folder.items.isEmpty
  }

  static func folderDeletionTitle(_ name: String) -> String {
    "Delete your “\(name)” folder?"
  }

  /// Clair has no archive: the tabs go.
  static let folderDeletionMessage = "Deleting this folder will remove the tabs inside it."
  static let folderDeletionButton = "Delete Folder"

  /// Edit Pinned Page's items; Replace needs the page open away from its
  /// pinned URL.
  static func editPinnedPageMenu(_ pin: any ClairPin) -> [MenuItem] {
    [
      MenuItem(title: "Replace Pinned URL with Current", command: .replacePinnedURL, isEnabled: isNavigatedAway(pin)),
      MenuItem(title: "Edit…", command: .editPinnedURL),
    ]
  }

  // MARK: The main menu's items (design D11)

  /// What the Tabs and View menus' Clair items act on in a window.
  struct MenuState: Equatable {
    var showsPins = true
    /// The selected row is a Today tab.
    var activeIsToday = false
    /// The selected row is a pinned tab, or a favorite.
    var activePinIsFavorite: Bool?
    var activePinIsNavigatedAway = false
    var todayRowCount = 0
    var isCollapsed = false
  }

  enum MainMenuCommand: Int, CaseIterable {
    case togglePin = 1
    case backToPinnedURL
    case closeKeepingPin
    case clearToday
    case toggleCollapse
    /// Tabs › New Folder… (add-tab-folders D6).
    case newFolder
  }

  static func title(of command: MainMenuCommand, in state: MenuState) -> String {
    switch command {
    case .togglePin: state.activePinIsFavorite == false ? "Unpin Tab" : "Pin Tab"
    case .backToPinnedURL: "Back to Pinned URL"
    case .closeKeepingPin: "Close and Keep Pinned"
    case .clearToday: "Clear Today"
    case .toggleCollapse: state.isCollapsed ? "Expand Pinned Tabs" : "Collapse Pinned Tabs"
    case .newFolder: newFolderDialogTitle
    }
  }

  static func isEnabled(_ command: MainMenuCommand, in state: MenuState) -> Bool {
    guard state.showsPins else { return false }
    switch command {
    case .togglePin: return state.activeIsToday || state.activePinIsFavorite == false
    case .backToPinnedURL: return state.activePinIsFavorite != nil && state.activePinIsNavigatedAway
    case .closeKeepingPin: return state.activePinIsFavorite != nil
    case .clearToday: return state.todayRowCount > 0
    case .toggleCollapse: return true
    case .newFolder: return true
    }
  }
}
