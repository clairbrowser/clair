// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit

/// Titles of Chromium's menu items that read differently in Clair.
enum MainMenuTitles {
  /// Chromium's IDC_FOCUS_LOCATION, File > Open Location… (Cmd+L), which
  /// opens the command bar on the current URL.
  static let focusLocationTag = 39001
  /// "Location" alone is vague to most people.
  static let focusLocationTitle = "Open Location Bar"

  /// Edit > Copy URL's action, which the native window's root view answers
  /// through the responder chain, showing Arc's "Copied Current URL".
  static let copyURLAction = #selector(BrowserRootView.copyCurrentURL(_:))

  /// Adds Edit > Copy URL (Shift+Cmd+C) after Copy, as in Arc (design D18),
  /// and returns it. `copy-url-shortcut.patch` frees Shift+Cmd+C from
  /// Chromium's own table, where it inspected an element.
  @discardableResult
  static func addCopyURL(to menu: NSMenu?) -> NSMenuItem? {
    guard let menu else { return nil }
    for item in menu.items {
      guard let submenu = item.submenu else { continue }
      if let copy = submenu.items.firstIndex(where: { $0.action == #selector(NSText.copy(_:)) }) {
        if let existing = submenu.items.first(where: { $0.action == copyURLAction }) {
          return existing
        }
        let copyURL = NSMenuItem(title: "Copy URL", action: copyURLAction, keyEquivalent: "c")
        copyURL.keyEquivalentModifierMask = [.command, .shift]
        submenu.insertItem(copyURL, at: copy + 1)
        return copyURL
      }
      if let found = addCopyURL(to: submenu) {
        return found
      }
    }
    return nil
  }

  /// The engine's View › Hide Sidebar, which `clair_window_hooks.mm` adds.
  static let toggleSidebarAction = NSSelectorFromString("toggleSidebar:")

  /// Adds View › Hide Toolbar (Shift+Cmd+D) after the engine's Hide Sidebar,
  /// as in Arc (add-page-toolbar D8), once, and returns it. Chromium binds
  /// Shift+Cmd+D only through Bookmark All Tabs, which Clair hides and
  /// clears.
  @discardableResult
  static func addToolbarItem(to menu: NSMenu?, target: ToolbarMenuTarget) -> NSMenuItem? {
    guard let menu else { return nil }
    for item in menu.items {
      guard let submenu = item.submenu else { continue }
      if let existing = submenu.items.first(where: { $0.action == ToolbarMenuTarget.action }) {
        return existing
      }
      if let sidebar = submenu.items.firstIndex(where: { $0.action == toggleSidebarAction }) {
        let toolbar = NSMenuItem(
          title: ToolbarPreference.menuTitle(isOn: target.preference.isOn), action: ToolbarMenuTarget.action,
          keyEquivalent: "d")
        toolbar.keyEquivalentModifierMask = [.command, .shift]
        toolbar.target = target
        submenu.insertItem(toolbar, at: sidebar + 1)
        return toolbar
      }
      if let found = addToolbarItem(to: submenu, target: target) {
        return found
      }
    }
    return nil
  }

  static func apply(to menu: NSMenu?) {
    guard let menu else { return }
    for item in menu.items {
      if item.tag == focusLocationTag {
        item.title = focusLocationTitle
      }
      apply(to: item.submenu)
    }
  }
}

/// View › Hide Toolbar's target (add-page-toolbar D8): it turns the
/// preference over, and titles the item from it.
final class ToolbarMenuTarget: NSObject, NSMenuItemValidation {
  static let action = #selector(ToolbarMenuTarget.toggleToolbar(_:))

  let preference: ToolbarPreference

  init(preference: ToolbarPreference = ToolbarPreference()) {
    self.preference = preference
  }

  @objc func toggleToolbar(_ sender: Any?) {
    preference.isOn.toggle()
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == Self.action {
      menuItem.title = ToolbarPreference.menuTitle(isOn: preference.isOn)
    }
    return true
  }
}
