// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// The menu bar's Tabs menu, in place of Chromium's Tab menu, which the
/// engine deletes (add-tab-switcher-and-tabs-menu design D5): Pin Tab (⌘D),
/// Pin to Favorites and New Folder…; Next Tab (⌥⌘↓) and Previous Tab (⌥⌘↑);
/// Split with Tab › and Move to Space ›; Clear Unpinned Tabs (⇧⌘K). The items
/// act on the main window and its shown tab, which enables them.
final class TabsMenu: NSObject, NSMenuItemValidation, NSMenuDelegate {
  static let title = "Tabs"
  /// Chromium's IDC_WINDOW_MENU, which the Tabs menu goes before.
  static let windowMenuTag = 57321
  /// Chromium's IDC_SELECT_NEXT_TAB and IDC_SELECT_PREVIOUS_TAB, which its
  /// own shortcut table runs first (space-shortcuts.patch): the items only
  /// show them, and Chromium validates them.
  static let nextTabTag = 34016
  static let previousTabTag = 34017
  /// Clair's tags, clear of Chromium's command IDs and the other menus'.
  static let baseTag = 0x436C_5200

  enum Command: Int, CaseIterable {
    case pinTab = 1
    case pinToFavorites
    case newFolder
    case splitWithTab
    case moveToSpace
    case clearUnpinnedTabs

    /// The pin command it runs, for the pin items.
    var pinCommand: PinsLogic.MainMenuCommand? {
      switch self {
      case .pinTab: .togglePin
      case .pinToFavorites: .pinToFavorites
      case .newFolder: .newFolder
      case .clearUnpinnedTabs: .clearToday
      case .splitWithTab, .moveToSpace: nil
      }
    }
  }

  let menu = NSMenu(title: TabsMenu.title)
  /// The window the items act on.
  var currentController: () -> BrowserWindowController? = { BrowserWindowController.main }

  private(set) var items: [Command: NSMenuItem] = [:]
  private(set) var nextTab: NSMenuItem?
  private(set) var previousTab: NSMenuItem?

  override init() {
    super.init()
    build()
  }

  /// Adds the menu just before the Window menu, once.
  @discardableResult
  func install(in mainMenu: NSMenu?) -> Bool {
    guard let mainMenu, !mainMenu.items.contains(where: { $0.submenu === menu }) else { return false }
    let item = NSMenuItem(title: Self.title, action: nil, keyEquivalent: "")
    item.submenu = menu
    let window =
      mainMenu.items.firstIndex { $0.tag == Self.windowMenuTag }
      ?? mainMenu.items.firstIndex { $0.submenu != nil && $0.submenu === NSApp?.windowsMenu }
    mainMenu.insertItem(item, at: window ?? mainMenu.numberOfItems)
    return true
  }

  private func build() {
    add(.pinTab, key: "d", modifiers: [.command])
    add(.pinToFavorites)
    add(.newFolder)
    menu.addItem(.separator())
    nextTab = addChromium("Next Tab", tag: Self.nextTabTag, arrow: NSDownArrowFunctionKey)
    previousTab = addChromium("Previous Tab", tag: Self.previousTabTag, arrow: NSUpArrowFunctionKey)
    menu.addItem(.separator())
    // With an action, the menu asks validateMenuItem whether a submenu's item
    // is on; one with a submenu and none is always on.
    for command in [Command.splitWithTab, .moveToSpace] {
      let item = add(command)
      let submenu = NSMenu(title: item.title)
      submenu.delegate = self
      item.submenu = submenu
    }
    menu.addItem(.separator())
    add(.clearUnpinnedTabs, key: "k", modifiers: [.command, .shift])
  }

  static func title(of command: Command, in state: PinsLogic.MenuState) -> String {
    switch command {
    case .splitWithTab: SplitLogic.splitWithTabTitle
    case .moveToSpace: "Move to Space"
    default: command.pinCommand.map { PinsLogic.title(of: $0, in: state) } ?? ""
    }
  }

  @discardableResult
  private func add(_ command: Command, key: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
    let item = NSMenuItem(
      title: Self.title(of: command, in: PinsLogic.MenuState()), action: #selector(choose(_:)), keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.target = self
    item.tag = Self.baseTag + command.rawValue
    items[command] = item
    menu.addItem(item)
    return item
  }

  /// One of Chromium's commands, sent down the responder chain to the key
  /// window as Chromium's own menu items are.
  private func addChromium(_ title: String, tag: Int, arrow: Int) -> NSMenuItem {
    let item = NSMenuItem(
      title: title, action: NSSelectorFromString("commandDispatch:"),
      keyEquivalent: String(Character(UnicodeScalar(UInt16(arrow))!)))
    item.keyEquivalentModifierMask = [.command, .option]
    item.tag = tag
    menu.addItem(item)
    return item
  }

  // MARK: Enabling

  /// The Spaces the shown tab can move to: every other Space, in the
  /// switcher's order; none on a favorite or in an incognito or guest
  /// window.
  private func moveTargets(of controller: BrowserWindowController) -> [any ClairSpace] {
    let model = controller.model
    guard model.showsSpaces, model.pin(ofTab: model.commandTab)?.isFavorite != true,
      model.highlightedTab != ClairTabIDNone
    else { return [] }
    return SpacesLogic.moveTargets(from: model.shownSpaceID, in: model.spaces.spaces)
  }

  /// Whether `command` can be chosen in `controller`'s window.
  func isEnabled(_ command: Command, in controller: BrowserWindowController) -> Bool {
    if let pinCommand = command.pinCommand {
      return PinsLogic.isEnabled(pinCommand, in: controller.pinMenuState)
    }
    switch command {
    case .splitWithTab:
      return controller.model.shownSplit == nil && controller.shownRowTabID != ClairTabIDNone
    case .moveToSpace:
      return !moveTargets(of: controller).isEmpty
    default:
      return false
    }
  }

  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    let controller = currentController()
    if item.action == #selector(chooseTab(_:)) || item.action == #selector(chooseNewTab(_:)) {
      return controller.map { isEnabled(.splitWithTab, in: $0) } ?? false
    }
    if item.action == #selector(chooseSpace(_:)) {
      return controller.map { isEnabled(.moveToSpace, in: $0) } ?? false
    }
    guard let command = Command(rawValue: item.tag - Self.baseTag) else { return false }
    item.title = Self.title(of: command, in: controller?.pinMenuState ?? PinsLogic.MenuState(showsPins: false))
    return controller.map { isEnabled(command, in: $0) } ?? false
  }

  @objc func choose(_ sender: NSMenuItem) {
    guard let command = Command(rawValue: sender.tag - Self.baseTag), let controller = currentController(),
      isEnabled(command, in: controller), let pinCommand = command.pinCommand
    else { return }
    controller.perform(pinCommand)
  }

  // MARK: The submenus

  func menuNeedsUpdate(_ submenu: NSMenu) {
    submenu.removeAllItems()
    guard let controller = currentController() else { return }
    if submenu === items[.splitWithTab]?.submenu {
      fillSplitWithTab(submenu, controller: controller)
    } else if submenu === items[.moveToSpace]?.submenu {
      for space in moveTargets(of: controller) {
        let item = NSMenuItem(title: SpacesLogic.label(of: space), action: #selector(chooseSpace(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = space.spaceID
        submenu.addItem(item)
      }
    }
  }

  /// Split with Tab ›: the main window's Today tabs as the split button's
  /// menu lists them, with New Tab, for its shown tab (add-split-view D9).
  private func fillSplitWithTab(_ submenu: NSMenu, controller: BrowserWindowController) {
    guard controller.model.shownSplit == nil else { return }
    let entries = SplitLogic.splitWithTabSubmenu(for: controller.shownRowTabID, today: controller.model.tabs)
    let favicons = Dictionary(
      controller.model.allTabs.map { ($0.tabID, $0.favicon) }, uniquingKeysWith: { first, _ in first })
    for entry in entries {
      switch entry {
      case .separator:
        submenu.addItem(.separator())
      case .tab(let other, let title):
        let item = NSMenuItem(title: title, action: #selector(chooseTab(_:)), keyEquivalent: "")
        item.target = self
        item.tag = Int(truncatingIfNeeded: other)
        item.setFavicon(favicons[other] ?? nil)
        submenu.addItem(item)
      case .newTab:
        let item = NSMenuItem(title: entry.title, action: #selector(chooseNewTab(_:)), keyEquivalent: "")
        item.target = self
        submenu.addItem(item)
      default:
        break
      }
    }
  }

  @objc func chooseTab(_ sender: NSMenuItem) {
    guard let controller = currentController(), isEnabled(.splitWithTab, in: controller) else { return }
    controller.split(tab: controller.shownRowTabID, with: TabID(sender.tag), side: .trailing)
  }

  @objc func chooseNewTab(_ sender: NSMenuItem) {
    guard let controller = currentController(), isEnabled(.splitWithTab, in: controller) else { return }
    controller.splitWithNewTab(controller.shownRowTabID)
  }

  /// Moves the shown tab, or the shown pinned tab, as its Move to Space does
  /// (`spaces`).
  @objc func chooseSpace(_ sender: NSMenuItem) {
    guard let spaceID = sender.representedObject as? SpaceID, let controller = currentController(),
      isEnabled(.moveToSpace, in: controller)
    else { return }
    let model = controller.model
    if let pin = model.pin(ofTab: model.commandTab) {
      controller.movePin(pin.pinID, toSpace: spaceID)
    } else {
      controller.moveTab(model.highlightedTab, toSpace: spaceID)
    }
  }
}
