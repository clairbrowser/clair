// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// Clair's items in Chromium's Tab menu and the View menu
/// (add-pinned-tabs-and-favorites design D11): Pin Tab (Cmd+D), Back to Pinned
/// URL, Close and Keep Pinned and Clear Today (Shift+Cmd+K), and View ›
/// Collapse Pinned Tabs. They act on the main window, which titles and
/// enables them. Chromium's own Pin Tab is hidden, and Cmd+D left its
/// bookmark item.
final class PinsMenu: NSObject, NSMenuItemValidation {
  /// Chromium's IDC_TAB_MENU and IDC_VIEW_MENU.
  static let tabMenuTag = 57323
  static let viewMenuTag = 57327
  /// Clair's tags, clear of Chromium's command IDs.
  static let baseTag = 0x436C_5000

  /// The window the items act on.
  var currentController: () -> BrowserWindowController? = { BrowserWindowController.main }

  private(set) var items: [PinsLogic.MainMenuCommand: NSMenuItem] = [:]

  static func tag(of command: PinsLogic.MainMenuCommand) -> Int {
    baseTag + command.rawValue
  }

  /// Adds the items, once.
  @discardableResult
  func install(in mainMenu: NSMenu?) -> Bool {
    guard let mainMenu, items.isEmpty else { return false }
    let tabMenu = mainMenu.items.first { $0.tag == Self.tabMenuTag }?.submenu
    let viewMenu = mainMenu.items.first { $0.tag == Self.viewMenuTag }?.submenu
    guard let tabMenu else { return false }
    // Where Chromium's own Pin Tab (IDC_WINDOW_PIN_TAB) and its alternate
    // (IDC_PIN_TARGET_TAB) were, which the engine hides.
    let chromiumPin = tabMenu.items.lastIndex { $0.tag == 35013 || $0.tag == 35051 }
    var index = chromiumPin.map { $0 + 1 } ?? tabMenu.numberOfItems
    for command in [PinsLogic.MainMenuCommand.togglePin, .backToPinnedURL, .closeKeepingPin, .clearToday] {
      tabMenu.insertItem(make(command), at: index)
      index += 1
    }
    if let viewMenu {
      viewMenu.insertItem(make(.toggleCollapse), at: 0)
    }
    return true
  }

  private func make(_ command: PinsLogic.MainMenuCommand) -> NSMenuItem {
    let title = PinsLogic.title(of: command, in: PinsLogic.MenuState())
    let item: NSMenuItem
    switch command {
    case .togglePin:
      item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "d")
      item.keyEquivalentModifierMask = [.command]
    case .clearToday:
      item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "k")
      item.keyEquivalentModifierMask = [.command, .shift]
    default:
      item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
    }
    item.target = self
    item.tag = Self.tag(of: command)
    items[command] = item
    return item
  }

  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    guard let command = PinsLogic.MainMenuCommand(rawValue: item.tag - Self.baseTag) else { return false }
    let state = currentController()?.pinMenuState ?? PinsLogic.MenuState(showsPins: false)
    item.title = PinsLogic.title(of: command, in: state)
    return currentController() != nil && PinsLogic.isEnabled(command, in: state)
  }

  @objc func choose(_ sender: NSMenuItem) {
    guard let command = PinsLogic.MainMenuCommand(rawValue: sender.tag - Self.baseTag),
      let controller = currentController(),
      PinsLogic.isEnabled(command, in: controller.pinMenuState)
    else { return }
    controller.perform(command)
  }
}
