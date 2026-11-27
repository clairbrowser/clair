// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import Foundation

/// Whether the browser controls show in a toolbar above the page or in the
/// sidebar (add-page-toolbar design D8). On unless the user turned it off;
/// windows observe it, so a change reaches every open window at once.
struct ToolbarPreference {
  static let key = "ClairShowsToolbar"

  let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: [Self.key: true])
  }

  var isOn: Bool {
    get { defaults.bool(forKey: Self.key) }
    nonmutating set { defaults.set(newValue, forKey: Self.key) }
  }

  /// The View menu's and the context menus' titles for the change.
  static func menuTitle(isOn: Bool) -> String {
    isOn ? "Hide Toolbar" : "Show Toolbar"
  }
}

/// Where a window's browser controls show (add-page-toolbar design D1): the
/// one rule every view follows, so split view only has to change the pane
/// count.
struct PageHeaderPolicy: Equatable {
  /// Whether each pane shows a header above its page.
  let panesShowHeader: Bool
  /// Whether the sidebar shows its full top row with the hide-sidebar
  /// button, the URL field and the pinned extensions: while the toolbar is
  /// off, a split's pane headers included, as in Arc, so the sidebar doesn't
  /// shift as the user moves between a split and other tabs.
  let sidebarShowsControls: Bool
  /// Whether the sidebar's top row shows back, forward and reload: only while
  /// no pane shows a header.
  let sidebarShowsNavigation: Bool
  /// The pane whose header leads with the sidebar toggle, if any: the
  /// leading pane, while the sidebar's top row doesn't hold the toggle.
  let togglePane: Int?

  init(showsToolbar: Bool, paneCount: Int) {
    panesShowHeader = showsToolbar || paneCount > 1
    sidebarShowsControls = !showsToolbar
    sidebarShowsNavigation = !panesShowHeader
    togglePane = showsToolbar ? 0 : nil
  }
}
