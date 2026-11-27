// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// View › Collapse Pinned Tabs (add-pinned-tabs-and-favorites design D11),
/// which acts on the main window, which titles and enables it. The pin
/// items are the Tabs menu's (`TabsMenu`).
final class PinsMenu: NSObject, NSMenuItemValidation {
  /// Chromium's IDC_VIEW_MENU.
  static let viewMenuTag = 57327
  /// Clair's tags, clear of Chromium's command IDs.
  static let baseTag = 0x436C_5000

  /// The window the items act on.
  var currentController: () -> BrowserWindowController? = { BrowserWindowController.main }

  private(set) var items: [PinsLogic.MainMenuCommand: NSMenuItem] = [:]

  static func tag(of command: PinsLogic.MainMenuCommand) -> Int {
    baseTag + command.rawValue
  }

  /// Adds the item, once.
  @discardableResult
  func install(in mainMenu: NSMenu?) -> Bool {
    guard let mainMenu, items.isEmpty,
      let viewMenu = mainMenu.items.first(where: { $0.tag == Self.viewMenuTag })?.submenu
    else { return false }
    viewMenu.insertItem(make(.toggleCollapse), at: 0)
    return true
  }

  private func make(_ command: PinsLogic.MainMenuCommand) -> NSMenuItem {
    let title = PinsLogic.title(of: command, in: PinsLogic.MenuState())
    let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
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
