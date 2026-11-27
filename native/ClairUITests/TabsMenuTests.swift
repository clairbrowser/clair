// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Testing

@testable import ClairUI

/// The menu bar's Tabs menu (add-tab-switcher-and-tabs-menu D5, `tabs-menu`).
@MainActor
struct TabsMenuTests {
  let window = PinWindow()
  let menu = TabsMenu()

  init() {
    menu.currentController = { [controller = window.controller] in controller }
  }

  private func item(_ command: TabsMenu.Command) -> NSMenuItem { menu.items[command]! }

  private func isEnabled(_ command: TabsMenu.Command) -> Bool { menu.validateMenuItem(item(command)) }

  /// tabs-menu, "The items".
  @Test func itListsItsItemsInGroups() {
    #expect(
      menu.menu.items.map { $0.isSeparatorItem ? "|" : $0.title } == [
        "Pin Tab", "Pin to Favorites", "New Folder…", "|", "Next Tab", "Previous Tab", "|", "Split with Tab",
        "Move to Space", "|", "Clear Unpinned Tabs",
      ])
    #expect(item(.pinTab).keyEquivalent == "d" && item(.pinTab).keyEquivalentModifierMask == [.command])
    let clear = item(.clearUnpinnedTabs)
    #expect(clear.keyEquivalent == "k" && clear.keyEquivalentModifierMask == [.command, .shift])
    #expect(item(.splitWithTab).submenu != nil && item(.moveToSpace).submenu != nil)
  }

  /// Next and Previous Tab are Chromium's commands, sent to the key window
  /// as its own items are.
  @Test func nextAndPreviousTabAreChromiumsCommands() throws {
    let next = try #require(menu.nextTab)
    let previous = try #require(menu.previousTab)
    #expect(next.action == NSSelectorFromString("commandDispatch:") && next.target == nil)
    #expect(next.tag == 34016 && previous.tag == 34017)
    #expect(next.keyEquivalent == String(Character(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!)))
    #expect(previous.keyEquivalent == String(Character(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!)))
    #expect(next.keyEquivalentModifierMask == [.command, .option])
  }

  /// tabs-menu, "Tabs menu items": just before the Window menu.
  @Test func itGoesBeforeTheWindowMenu() {
    let main = NSMenu()
    for (title, tag) in [("File", 0), ("View", PinsMenu.viewMenuTag), ("Window", TabsMenu.windowMenuTag), ("Help", 0)] {
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      item.tag = tag
      item.submenu = NSMenu(title: title)
      main.addItem(item)
    }
    #expect(menu.install(in: main))
    #expect(main.items.map(\.title) == ["File", "View", "Tabs", "Window", "Help"])
    #expect(!menu.install(in: main))
  }

  /// tabs-menu, "No window".
  @Test func everyItemIsOffWithoutAWindow() {
    menu.currentController = { nil }
    for command in TabsMenu.Command.allCases {
      #expect(!isEnabled(command), "\(command)")
    }
  }

  /// tabs-menu, "Pin Tab".
  @Test func pinTabPinsTheShownTodayTab() {
    let mail = window.browser.addTab(title: "Mail", url: "https://mail.example/")
    #expect(item(.pinTab).title == "Pin Tab" && isEnabled(.pinTab))
    #expect(isEnabled(.pinToFavorites))
    menu.choose(item(.pinTab))
    #expect(window.pinTitles == ["Mail"])
    #expect(window.host.boundTab(of: window.model.pins[0].pinID)?.tabID == mail.tabID)
  }

  /// tabs-menu, "On a pinned tab".
  @Test func onAPinnedTabTheFirstItemReadsUnpinTab() {
    let pinID = window.host.addPin(url: "https://docs.example/", title: "Docs")
    window.browser.addTab(title: "News")
    window.browser.openPin(pinID)
    _ = menu.validateMenuItem(item(.pinTab))
    #expect(item(.pinTab).title == "Unpin Tab")
    #expect(isEnabled(.pinToFavorites))
    menu.choose(item(.pinToFavorites))
    #expect(window.model.favorites.map(\.title) == ["Docs"])
  }

  /// tabs-menu, "On a favorite".
  @Test func aFavoriteCantBePinnedOrMoved() {
    window.host.addSpaces("Work")
    let pinID = window.host.addPin(url: "https://mail.example/", title: "Mail", inSpace: nil)
    window.browser.addTab(title: "News")
    window.browser.openPin(pinID)
    #expect(!isEnabled(.pinTab))
    #expect(!isEnabled(.pinToFavorites))
    #expect(!isEnabled(.moveToSpace))
    #expect(isEnabled(.newFolder))
  }

  /// tabs-menu, "Pin items" and "Move to Space submenu": nothing to pin or
  /// move in an incognito window.
  @Test func incognitoHasNoPinItems() {
    let host = FakeHost()
    host.addSpaces("Work")
    let browser = FakeBrowser(host: host, profileKind: .incognito)
    let controller = BrowserWindowController(browser: browser, spaces: browser.spaces)
    browser.clairWindow = controller
    browser.addTab(title: "Secret")
    menu.currentController = { controller }
    for command in [TabsMenu.Command.pinTab, .pinToFavorites, .newFolder, .moveToSpace, .clearUnpinnedTabs] {
      #expect(!isEnabled(command), "\(command)")
    }
    #expect(isEnabled(.splitWithTab))
  }

  /// tabs-menu, "Moving the shown tab" and "One Space".
  @Test func moveToSpaceListsTheOtherSpaces() throws {
    let docs = window.browser.addTab(title: "Docs")
    #expect(!isEnabled(.moveToSpace))
    let ids = window.host.addSpaces("Research", "Travel")
    #expect(isEnabled(.moveToSpace))
    let submenu = try #require(item(.moveToSpace).submenu)
    menu.menuNeedsUpdate(submenu)
    #expect(submenu.items.map(\.title) == ["Research", "Travel"])
    #expect(menu.validateMenuItem(submenu.items[0]))
    menu.chooseSpace(submenu.items[0])
    #expect(window.host.tab(docs.tabID)?.spaceID == ids[0])
  }

  /// tabs-menu, "Clearing".
  @Test func clearUnpinnedTabsClosesTheTodayTabs() {
    #expect(!isEnabled(.clearUnpinnedTabs))
    let pinID = window.host.addPin(url: "https://docs.example/", title: "Docs")
    window.browser.addTab(title: "One")
    window.browser.addTab(title: "Two")
    window.browser.openPin(pinID)
    #expect(isEnabled(.clearUnpinnedTabs))
    menu.choose(item(.clearUnpinnedTabs))
    #expect(window.todayTitles.isEmpty)
    #expect(window.pinTitles == ["Docs"])
  }

  /// Split with Tab › lists the Today tabs, and is off while split.
  @Test func splitWithTabFollowsTheSplit() throws {
    let docs = window.browser.addTab(title: "Docs")
    let mail = window.browser.addTab(title: "Mail")
    let submenu = try #require(item(.splitWithTab).submenu)
    menu.menuNeedsUpdate(submenu)
    let docsItem = try #require(submenu.items.first { $0.title == "Docs" })
    menu.chooseTab(docsItem)
    #expect(window.host.tab(mail.tabID)?.splitPartnerID == docs.tabID)
    #expect(!isEnabled(.splitWithTab))
  }
}
