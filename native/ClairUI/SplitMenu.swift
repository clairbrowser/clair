// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// Split view's items in the View menu (add-split-view design D9): Add Split
/// View (⌃⇧=), Close Split Pane (⌃⇧−) and Separate Tabs. They act on the main
/// window, which enables them. Split with Tab › is the Tabs menu's
/// (`TabsMenu`).
final class SplitMenu: NSObject, NSMenuItemValidation {
  enum Command: Int, CaseIterable {
    case addSplitView = 2
    case closeSplitPane
    case separateTabs

    var title: String {
      switch self {
      case .addSplitView: "Add Split View"
      case .closeSplitPane: "Close Split Pane"
      case .separateTabs: "Separate Tabs"
      }
    }

    /// Whether the item can be chosen: Add Split View always (it shows
    /// "Cannot Add New Pane" while split), the others while split.
    func isEnabled(isSplit: Bool) -> Bool {
      switch self {
      case .addSplitView: true
      case .closeSplitPane, .separateTabs: isSplit
      }
    }
  }

  /// Clair's tags for these items, clear of Chromium's and `PinsMenu`'s.
  static let baseTag = 0x436C_5100

  /// The window the items act on.
  var currentController: () -> BrowserWindowController? = { BrowserWindowController.main }

  private(set) var items: [Command: NSMenuItem] = [:]

  /// Adds the items, once.
  @discardableResult
  func install(in mainMenu: NSMenu?) -> Bool {
    guard let mainMenu, items.isEmpty,
      let viewMenu = mainMenu.items.first(where: { $0.tag == PinsMenu.viewMenuTag })?.submenu
    else { return false }
    // After Collapse Pinned Tabs, if it's there.
    var index = viewMenu.items.firstIndex { $0.tag >= PinsMenu.baseTag && $0.tag < Self.baseTag }.map { $0 + 1 } ?? 0
    for command in Command.allCases {
      viewMenu.insertItem(make(command), at: index)
      index += 1
    }
    viewMenu.insertItem(.separator(), at: index)
    return true
  }

  private func make(_ command: Command) -> NSMenuItem {
    let item: NSMenuItem
    switch command {
    case .addSplitView:
      item = NSMenuItem(title: command.title, action: #selector(choose(_:)), keyEquivalent: "=")
      item.keyEquivalentModifierMask = [.control, .shift]
    case .closeSplitPane:
      item = NSMenuItem(title: command.title, action: #selector(choose(_:)), keyEquivalent: "-")
      item.keyEquivalentModifierMask = [.control, .shift]
    case .separateTabs:
      item = NSMenuItem(title: command.title, action: #selector(choose(_:)), keyEquivalent: "")
    }
    item.target = self
    item.tag = Self.baseTag + command.rawValue
    items[command] = item
    return item
  }

  private var isSplit: Bool { currentController()?.model.shownSplit != nil }

  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    guard let command = Command(rawValue: item.tag - Self.baseTag) else { return false }
    return currentController() != nil && command.isEnabled(isSplit: isSplit)
  }

  @objc func choose(_ sender: NSMenuItem) {
    guard let command = Command(rawValue: sender.tag - Self.baseTag), let controller = currentController(),
      command.isEnabled(isSplit: controller.model.shownSplit != nil)
    else { return }
    switch command {
    case .addSplitView: controller.addSplitView()
    case .closeSplitPane: controller.closeSplitPane()
    case .separateTabs: controller.separateSplit(of: controller.focusedPaneTabID)
    }
  }
}
