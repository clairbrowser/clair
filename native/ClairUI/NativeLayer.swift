// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Foundation
import os

/// The running native layer. Chromium starts it once per launch, and it keeps
/// the host for as long as the app runs.
final class NativeLayer {
  static let logger = Logger(subsystem: "com.clairbrowser.clair", category: "ClairUI")

  /// The layer Chromium started, if it has.
  private(set) static var current: NativeLayer?

  let host: any ClairHost

  /// Every Space and its tabs, as the host reports them (add-spaces D10).
  let spaces: SpacesModel

  /// Sparkle, once the layer is running inside Clair.app.
  private(set) var updates: UpdateController?

  /// The About window behind "About Clair", once the layer is running inside
  /// Clair.app.
  private(set) var about: AboutWindowController?

  /// The Settings window behind Settings…, once the layer is running inside
  /// Clair.app.
  private(set) var settings: SettingsWindowController?

  /// The menu bar's Extensions menu.
  private(set) var extensionsMenu: ExtensionsMenu?

  /// The menu bar's Spaces menu (add-spaces D8).
  private(set) var spacesMenu: SpacesMenu?
  /// Clair's items in the Tab and View menus (add-pinned-tabs-and-favorites
  /// D11).
  private(set) var pinsMenu: PinsMenu?
  /// Split view's menu bar items (add-split-view D9).
  private(set) var splitMenu: SplitMenu?
  /// The Tabs menu (add-tab-switcher-and-tabs-menu D5).
  private(set) var tabsMenu: TabsMenu?
  /// View › Hide Toolbar's target (add-page-toolbar D8).
  let toolbarMenu = ToolbarMenuTarget()

  init(host: any ClairHost) {
    self.host = host
    spaces = SpacesModel(host: host)
  }

  /// Runs what only makes sense inside the app: not in a unit test's process,
  /// whose main bundle isn't Clair.
  private func startInApp() {
    guard Bundle.main.bundleIdentifier == "com.clairbrowser.clair" else {
      return
    }
    let about = AboutWindowController(host: host, info: AboutInfo(bundle: .main, host: host))
    about.install(in: NSApp.mainMenu)
    self.about = about
    let settings = SettingsWindowController(host: host, spaces: spaces)
    settings.install(in: NSApp.mainMenu)
    self.settings = settings
    MainMenuTitles.apply(to: NSApp.mainMenu)
    MainMenuTitles.addCopyURL(to: NSApp.mainMenu)
    // The engine adds View › Hide Sidebar once this start returns, and Hide
    // Toolbar goes after it.
    DispatchQueue.main.async { [toolbarMenu] in
      if MainMenuTitles.addToolbarItem(to: NSApp.mainMenu, target: toolbarMenu) == nil {
        NativeLayer.logger.error("The View menu has no Hide Sidebar; View › Hide Toolbar isn't added")
      }
    }
    let extensionsMenu = ExtensionsMenu()
    extensionsMenu.install(in: NSApp.mainMenu)
    self.extensionsMenu = extensionsMenu
    let spacesMenu = SpacesMenu(spaces: spaces)
    spacesMenu.install(in: NSApp.mainMenu)
    self.spacesMenu = spacesMenu
    // add-pinned-tabs-and-favorites D11.
    let pinsMenu = PinsMenu()
    pinsMenu.install(in: NSApp.mainMenu)
    self.pinsMenu = pinsMenu
    let splitMenu = SplitMenu()
    splitMenu.install(in: NSApp.mainMenu)
    self.splitMenu = splitMenu
    // add-tab-switcher-and-tabs-menu D5: in place of Chromium's Tab menu,
    // which the engine deleted.
    let tabsMenu = TabsMenu()
    tabsMenu.install(in: NSApp.mainMenu)
    self.tabsMenu = tabsMenu

    let updates = UpdateController(host: host, configuration: .current)
    updates.start()
    self.updates = updates
  }

  /// Starts the native layer with Chromium's host. A second call keeps the
  /// first layer and its host.
  @discardableResult
  static func start(host: any ClairHost) -> NativeLayer {
    if let current {
      logger.error("ClairUI was started twice; keeping the first host")
      return current
    }
    let layer = NativeLayer(host: host)
    current = layer
    layer.startInApp()
    logger.info(
      "ClairUI started with Chromium \(host.chromiumVersion, privacy: .public) (ungoogled-chromium \(host.ungoogledChromiumVersion, privacy: .public))"
    )
    return layer
  }
}
