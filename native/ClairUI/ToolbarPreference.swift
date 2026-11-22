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
  /// Whether the sidebar shows back, forward, reload, the URL field and the
  /// pinned extensions: only while no pane shows a header.
  let sidebarShowsControls: Bool
  /// The pane whose header leads with the sidebar toggle, if any pane shows
  /// one: the leading pane.
  let togglePane: Int?

  init(showsToolbar: Bool, paneCount: Int) {
    panesShowHeader = showsToolbar || paneCount > 1
    sidebarShowsControls = !panesShowHeader
    togglePane = panesShowHeader ? 0 : nil
  }
}
