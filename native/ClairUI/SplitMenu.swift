// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// Split view's items in the menu bar (add-split-view design D9): Tabs ›
/// Split with Tab ›, and View › Add Split View (⌃⇧=), Close Split Pane (⌃⇧−)
/// and Separate Tabs. They act on the main window, which enables them.
final class SplitMenu: NSObject, NSMenuItemValidation, NSMenuDelegate {
  enum Command: Int, CaseIterable {
    case splitWithTab = 1
    case addSplitView
    case closeSplitPane
    case separateTabs

    var title: String {
      switch self {
      case .splitWithTab: SplitLogic.splitWithTabTitle
      case .addSplitView: "Add Split View"
      case .closeSplitPane: "Close Split Pane"
      case .separateTabs: "Separate Tabs"
      }
    }

    /// Whether the item can be chosen: Split with Tab and Add Split View on
    /// a single page (Add Split View then shows "Cannot Add New Pane"), the
    /// others while split.
    func isEnabled(isSplit: Bool) -> Bool {
      switch self {
      case .splitWithTab: !isSplit
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
    guard let mainMenu, items.isEmpty else { return false }
    let tabMenu = mainMenu.items.first { $0.tag == PinsMenu.tabMenuTag }?.submenu
    let viewMenu = mainMenu.items.first { $0.tag == PinsMenu.viewMenuTag }?.submenu
    guard let tabMenu else { return false }
    // After Clair's pin items in Tabs.
    let lastPinItem = tabMenu.items.lastIndex { $0.tag >= PinsMenu.baseTag && $0.tag < Self.baseTag }
    tabMenu.insertItem(make(.splitWithTab), at: lastPinItem.map { $0 + 1 } ?? tabMenu.numberOfItems)
    if let viewMenu {
      // After Collapse Pinned Tabs, if it's there.
      var index = viewMenu.items.firstIndex { $0.tag >= PinsMenu.baseTag && $0.tag < Self.baseTag }.map { $0 + 1 } ?? 0
      for command in [Command.addSplitView, .closeSplitPane, .separateTabs] {
        viewMenu.insertItem(make(command), at: index)
        index += 1
      }
      viewMenu.insertItem(.separator(), at: index)
    }
    return true
  }

  private func make(_ command: Command) -> NSMenuItem {
    let item: NSMenuItem
    switch command {
    case .splitWithTab:
      // With an action, the menu asks validateMenuItem whether it's on; an
      // item with a submenu and none is always on.
      item = NSMenuItem(title: command.title, action: #selector(choose(_:)), keyEquivalent: "")
      let submenu = NSMenu(title: command.title)
      submenu.delegate = self
      item.submenu = submenu
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
    if item.action == #selector(chooseTab(_:)) || item.action == #selector(chooseNewTab(_:)) {
      return currentController() != nil && !isSplit
    }
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
    case .splitWithTab: break
    }
  }

  // MARK: Tabs › Split with Tab ›

  /// Lists the main window's Today tabs as the split button's menu does,
  /// with New Tab, for its shown tab.
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    guard let controller = currentController(), controller.model.shownSplit == nil else { return }
    let shown = controller.shownRowTabID
    let entries = SplitLogic.splitWithTabSubmenu(for: shown, today: controller.model.tabs)
    let favicons = Dictionary(
      controller.model.allTabs.map { ($0.tabID, $0.favicon) }, uniquingKeysWith: { first, _ in first })
    for entry in entries {
      switch entry {
      case .separator:
        menu.addItem(.separator())
      case .tab(let other, let title):
        let item = NSMenuItem(title: title, action: #selector(chooseTab(_:)), keyEquivalent: "")
        item.target = self
        item.tag = Int(truncatingIfNeeded: other)
        item.image =
          (favicons[other] ?? nil).map(SplitRows.menuIcon)
          ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        menu.addItem(item)
      case .newTab:
        let item = NSMenuItem(title: entry.title, action: #selector(chooseNewTab(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
      default:
        break
      }
    }
  }

  @objc func chooseTab(_ sender: NSMenuItem) {
    guard let controller = currentController(), controller.model.shownSplit == nil else { return }
    controller.split(tab: controller.shownRowTabID, with: TabID(sender.tag), side: .trailing)
  }

  @objc func chooseNewTab(_ sender: NSMenuItem) {
    guard let controller = currentController(), controller.model.shownSplit == nil else { return }
    controller.splitWithNewTab(controller.shownRowTabID)
  }
}
