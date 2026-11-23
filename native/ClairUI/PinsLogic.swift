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

  /// The pinned rows the section lists: every one, or only the selected one
  /// while it's collapsed (pinned-tabs spec, "Collapsing the pinned
  /// section").
  static func visiblePins(_ pins: [any ClairPin], collapsed: Bool, highlighted: TabID) -> [any ClairPin] {
    guard collapsed else { return pins }
    return pins.filter { $0.tabID != ClairTabIDNone && $0.tabID == highlighted }
  }

  /// Whether the Space header offers its collapse chevron: while the Space
  /// has pinned tabs, or while its section is collapsed, so a section whose
  /// last pin went while it was collapsed can be expanded again.
  static func offersCollapse(pinCount: Int, collapsed: Bool) -> Bool {
    pinCount > 0 || collapsed
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
  /// the Space, open or not, then the Today rows. Favorites aren't rows.
  enum CommandRow: Equatable {
    case pin(PinID)
    case tab(TabID)
  }

  static func commandRows(pins: [any ClairPin], today: [any ClairTab]) -> [CommandRow] {
    pins.map { .pin($0.pinID) } + TabListLogic.rows(today).map { .tab($0.tabID) }
  }

  // MARK: Dragging (design D5, D11)

  /// Where a row dropped in the list goes.
  enum ListDrop: Equatable {
    /// At this index among the Space's pinned tabs.
    case pinned(Int)
    /// At this index in the Space's Today list, Peeks counted.
    case today(Int)
  }

  /// Where a row dropped before list item `destination` goes, in a list of
  /// `pinCount` pinned rows, then `boundaryCount` rows that are neither (the
  /// row of the divider and "New Tab"), then the Today rows of `today`. `movingPin` is
  /// the index of a pinned row being moved within the list, which no longer
  /// counts once it's lifted; `movingTodayRow` the same for a Today row.
  static func listDrop(
    destination: Int, pinCount: Int, boundaryCount: Int, today: [any ClairTab], movingPin: Int? = nil,
    movingTodayRow: Int? = nil
  ) -> ListDrop {
    if destination <= pinCount {
      var index = destination
      if let movingPin, movingPin < destination {
        index -= 1
      }
      return .pinned(max(index, 0))
    }
    let rows = TabListLogic.rows(today)
    var row = min(max(destination - pinCount - boundaryCount, 0), rows.count)
    if let movingTodayRow, movingTodayRow < row {
      row -= 1
    }
    // Rows before it, each with its Peek, less the moving row's family.
    let moving = movingTodayRow.flatMap { rows.indices.contains($0) ? rows[$0].tabID : nil }
    var others = rows
    if let movingTodayRow, rows.indices.contains(movingTodayRow) {
      others.remove(at: movingTodayRow)
    }
    let before = others.prefix(row)
    let index = before.reduce(0) { count, tab in
      count + 1 + (TabListLogic.peek(ofRow: tab.tabID, in: today) == nil || tab.tabID == moving ? 0 : 1)
    }
    return .today(index)
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
    case removePin
    case removeFavorite
  }

  struct MenuItem: Equatable {
    let title: String
    let command: MenuCommand
    var isEnabled = true
  }

  /// A Today tab's menu: nil entries are separators. Incognito and guest
  /// windows have neither pin item.
  static func todayMenu(isMuted: Bool, canMoveToSpace: Bool, canPin: Bool) -> [MenuItem?] {
    var items: [MenuItem?] = [
      MenuItem(title: "Copy Link", command: .copyLink),
      MenuItem(title: "Rename…", command: .rename),
      MenuItem(title: "Duplicate", command: .duplicate),
      MenuItem(title: isMuted ? "Unmute" : "Mute", command: isMuted ? .unmute : .mute),
    ]
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

  /// A pinned tab's menu.
  static func pinnedMenu(isOpen: Bool, isMuted: Bool, canMoveToSpace: Bool) -> [MenuItem?] {
    var items: [MenuItem?] = [
      MenuItem(title: "Copy Link", command: .copyLink),
      MenuItem(title: "Rename…", command: .rename),
      MenuItem(title: isMuted ? "Unmute" : "Mute", command: isMuted ? .unmute : .mute, isEnabled: isOpen),
      MenuItem(title: "Edit Pinned Page", command: .editPinnedPage),
      MenuItem(title: "Duplicate", command: .duplicate),
    ]
    if canMoveToSpace {
      items += [nil, MenuItem(title: "Move to Space", command: .moveToSpace)]
    }
    items += [
      nil,
      MenuItem(title: "Pin to Favorites", command: .pinToFavorites),
      MenuItem(title: "Unpin Tab", command: .unpin),
      MenuItem(title: "Remove Pin", command: .removePin),
    ]
    return items
  }

  /// A favorite's menu; Close Tab only while the window shows its page.
  static func favoriteMenu(isShown: Bool, isOpen: Bool, isMuted: Bool) -> [MenuItem?] {
    var items: [MenuItem?] = [
      MenuItem(title: "Copy Link", command: .copyLink),
      MenuItem(title: "Rename…", command: .rename),
      MenuItem(title: isMuted ? "Unmute" : "Mute", command: isMuted ? .unmute : .mute, isEnabled: isOpen),
      MenuItem(title: "Edit Pinned Page", command: .editPinnedPage),
      MenuItem(title: "Duplicate", command: .duplicate),
      nil,
    ]
    if isShown {
      items.append(MenuItem(title: "Close Tab", command: .closeTab))
    }
    items.append(MenuItem(title: "Remove Favorite", command: .removeFavorite))
    return items
  }

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
  }

  static func title(of command: MainMenuCommand, in state: MenuState) -> String {
    switch command {
    case .togglePin: state.activePinIsFavorite == false ? "Unpin Tab" : "Pin Tab"
    case .backToPinnedURL: "Back to Pinned URL"
    case .closeKeepingPin: "Close and Keep Pinned"
    case .clearToday: "Clear Today"
    case .toggleCollapse: state.isCollapsed ? "Expand Pinned Tabs" : "Collapse Pinned Tabs"
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
    }
  }
}
