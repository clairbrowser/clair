// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI
import Testing

@testable import ClairUI

/// The toolbar preference and where the controls show (add-page-toolbar D1,
/// D8).
@MainActor
struct ToolbarPreferenceTests {
  private let defaults: UserDefaults = {
    let name = "ClairUITests.Toolbar.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }()

  private func makeWindow() -> BrowserWindowController {
    let browser = FakeBrowser()
    browser.addTab(title: "Tab", url: "https://example.com/", at: 0, activate: true)
    let controller = BrowserWindowController(
      browser: browser, spaces: browser.spaces, preferences: SidebarPreferences(defaults: defaults),
      toolbarPreference: ToolbarPreference(defaults: defaults))
    browser.clairWindow = controller
    return controller
  }

  @Test func onUntilTurnedOff() {
    let preference = ToolbarPreference(defaults: defaults)
    #expect(preference.isOn)
    #expect(makeWindow().model.showsPageHeader)
    preference.isOn = false
    #expect(!ToolbarPreference(defaults: defaults).isOn)
  }

  @Test func aChangeReachesEveryWindow() {
    let first = makeWindow()
    let second = makeWindow()
    #expect(first.model.showsPageHeader && second.model.showsPageHeader)
    ToolbarPreference(defaults: defaults).isOn = false
    #expect(!first.model.showsPageHeader && !second.model.showsPageHeader)
    #expect(first.model.sidebarShowsControls && second.model.sidebarShowsControls)
    // A window opened afterwards starts without it too.
    #expect(!makeWindow().model.showsPageHeader)
    ToolbarPreference(defaults: defaults).isOn = true
    #expect(first.model.showsPageHeader && second.model.showsPageHeader)
  }

  @Test(arguments: [true, false])
  func onePaneFollowsThePreference(showsToolbar: Bool) {
    let policy = PageHeaderPolicy(showsToolbar: showsToolbar, paneCount: 1)
    #expect(policy.panesShowHeader == showsToolbar)
    #expect(policy.sidebarShowsControls == !showsToolbar)
    #expect(policy.sidebarShowsNavigation == !showsToolbar)
    #expect(policy.togglePane == (showsToolbar ? 0 : nil))
  }

  /// Split view: every pane shows its header whatever the setting. With the
  /// toolbar off, the sidebar keeps its toggle, URL field and pinned
  /// extensions, as in Arc, and only back, forward and reload leave it.
  @Test(arguments: [true, false])
  func twoPanesAlwaysShowHeaders(showsToolbar: Bool) {
    let policy = PageHeaderPolicy(showsToolbar: showsToolbar, paneCount: 2)
    #expect(policy.panesShowHeader)
    #expect(policy.sidebarShowsControls == !showsToolbar)
    #expect(!policy.sidebarShowsNavigation)
    #expect(policy.togglePane == (showsToolbar ? 0 : nil))
  }

  @Test func theModelFollowsThePolicy() {
    let toolbarOff = ToolbarPreference(defaults: UserDefaults(suiteName: "ToolbarTests.off")!)
    toolbarOff.isOn = false
    let browser = FakeBrowser()
    let controller = BrowserWindowController(
      browser: browser, spaces: browser.spaces,
      preferences: SidebarPreferences(defaults: UserDefaults(suiteName: "ToolbarTests")!),
      toolbarPreference: toolbarOff)
    browser.clairWindow = controller
    let mail = browser.addTab(title: "Mail")
    let news = browser.addTab(title: "News")
    let model = controller.model
    #expect(!model.showsPageHeader && model.sidebarShowsControls)
    // A split shows both panes' headers (add-split-view D9).
    browser.makeSplit(mail.tabID, with: news.tabID)
    #expect(model.paneCount == 2)
    #expect(model.showsPageHeader && model.sidebarShowsControls && !model.sidebarShowsNavigation)
    // Bubbles attach to the controls the user used last.
    #expect(!model.bubblesInSidebar)
    model.usedSidebarControls = true
    #expect(model.bubblesInSidebar)
  }
}

/// Where the toolbar's controls go (add-page-toolbar D4).
struct ToolbarArrangementTests {
  /// "example.com" in the host's font, with its background: about Arc's.
  let host = ToolbarArrangement.hostWidth(for: "example.com")

  func clair(extensions: Int = 0, indicators: Int = 0) -> ToolbarArrangement.Content {
    ToolbarArrangement.Content(
      leadingCount: 3, hostWidth: host, trailingFixedCount: 1, extensionCount: extensions, indicatorCount: indicators)
  }

  /// Arc's toolbar with the sidebar shown, as in its narrow captures: back
  /// and forward before reload, and split view after the site controls.
  func arc(extensions: Int) -> ToolbarArrangement.Content {
    ToolbarArrangement.Content(leadingCount: 2, hostWidth: host, trailingFixedCount: 2, extensionCount: extensions)
  }

  @Test func theHostIsAboutArcs() {
    // Arc's "example.com" is 81–82 pt, with 6.5 pt of background each side.
    #expect(abs(host - 13 - 82) <= 1)
  }

  @Test func leadingControlsAtArcsPlaces() {
    let layout = ToolbarArrangement(width: 962, content: clair())
    #expect(layout.leading == [21, 57.75, 94.75])
    #expect(layout.reload == 132)
  }

  @Test func trailingControlsOnArcsPitch() {
    let width: CGFloat = 962
    let layout = ToolbarArrangement(width: width, content: clair(extensions: 2, indicators: 1))
    #expect(layout.trailingFixed.map { width - $0 } == [21])
    // The first pinned is leftmost.
    #expect(layout.extensions.map { $0.map { width - $0 } } == [93, 57])
    #expect(layout.indicators.map { width - $0 } == [129])
  }

  @Test func theHostIsCentredWithItsLinkBefore() throws {
    let layout = ToolbarArrangement(width: 962, content: clair())
    #expect(layout.hostWidth == host)
    #expect(layout.hostMinX + layout.hostWidth / 2 == 481)
    // Arc's link glyph is centred 16 pt before the text.
    let link = try #require(layout.link)
    #expect(layout.hostMinX + ToolbarArrangement.hostPadding - link == 16)
  }

  /// toolbar-narrow-620.jpg: Arc's card is 382 pt; uBlock, farther from the
  /// site controls, is left out, and the rest stays.
  @Test func arcAt620LeavesOutTheFartherExtension() {
    let layout = ToolbarArrangement(width: 382, content: arc(extensions: 2))
    #expect(layout.extensions[0] == nil)
    #expect(layout.extensions[1] == CGFloat(382 - 93))
    #expect(layout.reload != nil && layout.link != nil)
    #expect(layout.hostWidth == host)
  }

  /// toolbar-narrow-520.jpg: at 282 pt, both extensions, reload and the link
  /// icon are out, and the host is whole and centred.
  @Test func arcAt520LeavesOutExtensionsReloadAndLink() {
    let layout = ToolbarArrangement(width: 282, content: arc(extensions: 2))
    #expect(layout.extensions == [nil, nil])
    #expect(layout.reload == nil && layout.link == nil)
    #expect(layout.hostWidth == host)
    #expect(layout.hostMinX + layout.hostWidth / 2 == 141)
  }

  /// Clair's toolbar has the sidebar toggle before back, and nothing after
  /// the site controls, so its leading side runs out of room first: in the
  /// same 382 pt card, reload and the link go and both extensions stay.
  @Test func clairAt620KeepsBothExtensions() {
    let layout = ToolbarArrangement(width: 382, content: clair(extensions: 2))
    #expect(layout.extensions == [CGFloat(289), CGFloat(325)])
    #expect(layout.reload == nil && layout.link == nil)
    #expect(layout.hostWidth == host)
  }

  /// With the sidebar shown in a 560 pt window (a 322 pt card), the farther
  /// extension goes, and the host keeps its centre.
  @Test func clairLeavesOutTheFartherExtensionFirst() {
    let layout = ToolbarArrangement(width: 322, content: clair(extensions: 2))
    #expect(layout.extensions[0] == nil)
    #expect(layout.extensions[1] == CGFloat(322 - 57))
    #expect(layout.hostMinX + layout.hostWidth / 2 == 161)
  }

  /// A 520 pt window with the sidebar hidden: a 500 pt card keeps everything.
  @Test func clairWithTheSidebarHiddenKeepsEverything() {
    let layout = ToolbarArrangement(width: 500, content: clair(extensions: 2))
    #expect(layout.extensions == [CGFloat(407), CGFloat(443)])
    #expect(layout.reload != nil && layout.link != nil)
    #expect(layout.hostWidth == host)
  }

  @Test func aLongHostTruncatesAroundTheCentre() {
    let long = ToolbarArrangement.hostWidth(for: "a-very-long-subdomain.of-an-example-host.example.com")
    let content = ToolbarArrangement.Content(leadingCount: 3, hostWidth: long, extensionCount: 1)
    let layout = ToolbarArrangement(width: 500, content: content)
    #expect(layout.extensions == [nil])
    #expect(layout.reload == nil && layout.link == nil)
    #expect(layout.hostWidth < long)
    #expect(layout.hostMinX + layout.hostWidth / 2 == 250)
    // Clear of forward and of the site controls.
    #expect(layout.hostMinX >= 94.75 + 16 + ToolbarArrangement.clearance)
    #expect(layout.hostMinX + layout.hostWidth <= 500 - 21 - 16 - ToolbarArrangement.clearance)
  }

  @Test func tenExtensionsKeepWhatFits() throws {
    let width: CGFloat = 962
    let layout = ToolbarArrangement(width: width, content: clair(extensions: 10))
    let kept = layout.extensions.compactMap { $0 }
    // From the last pinned, nearest the site controls, on the pitch.
    #expect(kept.count == 10)
    #expect(layout.extensions.last == width - 57)
    let narrow = ToolbarArrangement(width: 700, content: clair(extensions: 10))
    #expect(narrow.extensions.prefix(while: { $0 == nil }).count == narrow.extensions.filter { $0 == nil }.count)
    let leftmost = try #require(narrow.extensions.compactMap { $0 }.min())
    #expect(leftmost - 16 - ToolbarArrangement.clearance >= narrow.hostMinX + narrow.hostWidth)
    #expect(narrow.hostWidth == host)
  }

  @Test func aPeekHasNoTrailingControls() {
    let peek = ToolbarArrangement.Content(leadingCount: 2, hostWidth: host, trailingFixedCount: 0)
    let layout = ToolbarArrangement(width: 700, content: peek)
    #expect(layout.leading == [21, 57.75])
    #expect(layout.reload == 94.75)
    #expect(layout.trailingFixed.isEmpty && layout.extensions.isEmpty && layout.indicators.isEmpty)
    #expect(layout.hostMinX + layout.hostWidth / 2 == 350)
  }
}

/// What each page header holds (add-page-toolbar D3, D4).
struct PageHeaderContentTests {
  @Test func aPeekHasNoToggleExtensionsIndicatorsOrSiteControls() {
    let peek = PageHeaderContent.peek
    #expect(!peek.showsSidebarToggle)
    #expect(!peek.showsExtensions)
    #expect(!peek.showsIndicators)
    #expect(!peek.showsSiteControls)
    #expect(peek.leadingCount == 2)
    #expect(peek.identifier == "clair.peekToolbar")
  }

  @Test func theTabsToolbarHasEverything() {
    let tab = PageHeaderContent.tab
    #expect(tab.showsSidebarToggle && tab.showsExtensions && tab.showsIndicators && tab.showsSiteControls)
    #expect(tab.leadingCount == 3)
    #expect(tab.identifier == "clair.toolbar")
  }
}

/// Where bubbles attach while the toolbar shows (add-page-toolbar D6).
@MainActor
struct ToolbarAnchorTests {
  let sidebarSite = CGRect(x: 20, y: 700, width: 24, height: 24)
  let toolbarSite = CGRect(x: 1160, y: 758, width: 32, height: 32)
  let toolbarCamera = CGRect(x: 1052, y: 758, width: 32, height: 32)
  let toolbarPinned = CGRect(x: 1124, y: 760, width: 32, height: 28)
  let downloads = CGRect(x: 8, y: 9, width: 32, height: 32)
  let card = CGRect(x: 228, y: 10, width: 962, height: 780)

  func resolver(sidebarInPlace: Bool, toolbarShown: Bool, prefersSidebar: Bool = false) -> AnchorResolver {
    AnchorResolver(
      sidebarInPlace: sidebarInPlace,
      controls: [.siteControls: sidebarSite, .downloads: downloads],
      card: card, toolbarShown: toolbarShown,
      toolbarControls: [
        .siteControls: toolbarSite,
        .indicator(TabIndicators.camera.rawValue): toolbarCamera,
        .extensionAction("pinned"): toolbarPinned,
      ],
      prefersSidebar: prefersSidebar)
  }

  /// A split with the toolbar off shows the controls in the sidebar and the
  /// pane headers: bubbles attach where the user clicked, while the sidebar
  /// is in place.
  @Test func theSidebarWinsWhenUsedLast() {
    let used = resolver(sidebarInPlace: true, toolbarShown: true, prefersSidebar: true)
    #expect(used.anchorsInSidebar)
    #expect(used.anchor(for: .siteControls, indicator: [], extensionID: nil).rect == sidebarSite)
    let revealed = resolver(sidebarInPlace: false, toolbarShown: true, prefersSidebar: true)
    #expect(!revealed.anchorsInSidebar)
    #expect(revealed.anchor(for: .siteControls, indicator: [], extensionID: nil).rect == toolbarSite)
  }

  /// With the sidebar shown, hidden, or revealed (never in place): below the
  /// toolbar's control.
  @Test(arguments: [true, false])
  func theToolbarsControlsWin(sidebarInPlace: Bool) {
    let resolver = resolver(sidebarInPlace: sidebarInPlace, toolbarShown: true)
    let site = resolver.anchor(for: .siteControls, indicator: [], extensionID: nil)
    #expect(site.rect == toolbarSite)
    #expect(site.edge == .bottom)
    #expect(resolver.anchor(for: .indicator, indicator: .camera, extensionID: nil).rect == toolbarCamera)
    #expect(resolver.anchor(for: .extensionAction, indicator: [], extensionID: "pinned").rect == toolbarPinned)
    // A left-out extension falls back to the site controls.
    #expect(resolver.anchor(for: .extensionAction, indicator: [], extensionID: "other").rect == toolbarSite)
  }

  @Test func downloadsStayInTheSidebar() {
    let anchor = resolver(sidebarInPlace: true, toolbarShown: true).anchor(
      for: .downloads, indicator: [], extensionID: nil)
    #expect(anchor.rect == downloads)
    #expect(anchor.edge == .trailing)
  }

  /// Page full screen: the controller says the toolbar isn't shown, and
  /// bubbles fall back to the card's corner.
  @Test func pageFullscreenFallsBack() {
    let anchor = resolver(sidebarInPlace: false, toolbarShown: false).anchor(
      for: .siteControls, indicator: [], extensionID: nil)
    #expect(anchor.edge == .bottom)
    #expect(anchor.rect.origin == CGPoint(x: card.minX + AnchorResolver.fallbackInset, y: card.maxY))
  }

  @Test func toolbarOffKeepsTodaysResults() {
    let anchor = resolver(sidebarInPlace: true, toolbarShown: false).anchor(
      for: .siteControls, indicator: [], extensionID: nil)
    #expect(anchor.rect == sidebarSite)
    #expect(anchor.edge == .trailing)
  }

  /// The controller hands the toolbar's state to the resolver.
  @Test func theWindowResolvesWithItsToolbar() {
    let defaults = UserDefaults(suiteName: "ClairUITests.ToolbarAnchor.\(UUID().uuidString)")!
    let browser = FakeBrowser()
    browser.addTab(title: "Tab", url: "https://example.com/", at: 0, activate: true)
    let controller = BrowserWindowController(
      browser: browser, spaces: browser.spaces, preferences: SidebarPreferences(defaults: defaults),
      toolbarPreference: ToolbarPreference(defaults: defaults))
    #expect(controller.anchorResolver.toolbarShown)
    controller.pageFullscreenDidChange(true)
    #expect(!controller.anchorResolver.toolbarShown)
    controller.pageFullscreenDidChange(false)
    controller.setToolbarShown(false)
    #expect(!controller.anchorResolver.toolbarShown)
    #expect(!ToolbarPreference(defaults: defaults).isOn)
  }
}

/// Extension popups over the toolbar (add-page-toolbar D6).
@MainActor
struct ToolbarPopupPlacementTests {
  let size = NSSize(width: 273, height: 406)
  let visible = NSRect(x: 0, y: 0, width: 1512, height: 944)

  @Test func theTopTrailingCornerIsAtTheGivenPlace() {
    let frame = ExtensionPopupWindow.frame(size: size, topTrailing: NSPoint(x: 910, y: 904), visible: visible)
    #expect(frame.maxX == 910)
    #expect(frame.maxY == 904)
    #expect(frame.size == size)
  }

  @Test func aWindowNearTheScreensEdgeKeepsItOnScreen() {
    // The window's card starts near the leading edge, so the corner leaves
    // too little room for the popup's width; and near the bottom.
    let frame = ExtensionPopupWindow.frame(size: size, topTrailing: NSPoint(x: 100, y: 200), visible: visible)
    #expect(frame.minX == visible.minX + ExtensionPopupWindow.screenMargin)
    #expect(frame.minY == visible.minY + ExtensionPopupWindow.screenMargin)
    #expect(visible.contains(frame))
  }

  /// A page that resizes itself keeps the popup's top-trailing corner over
  /// the toolbar, and its top-leading corner beside a sidebar button.
  @Test func resizingKeepsThePlacementsCorner() {
    let frame = NSRect(x: 852, y: 500, width: 320, height: 200)
    let size = NSSize(width: 264, height: 177)
    let toolbar = ExtensionPopupWindow.resized(frame, to: size, placement: .topTrailing(.zero))
    #expect(toolbar.maxX == frame.maxX && toolbar.maxY == frame.maxY && toolbar.size == size)
    let beside = ExtensionPopupWindow.resized(frame, to: size, placement: .besideAnchor)
    #expect(beside.minX == frame.minX && beside.maxY == frame.maxY && beside.size == size)
  }

  /// The window opens with the toolbar placement and closes as any popup
  /// does. Where it lands depends on the screen, which the runners' window
  /// server may adjust, so the maths above checks the place.
  @Test func theWindowOpensOverTheToolbarAndCloses() {
    let parent = NSWindow(
      contentRect: NSRect(x: 200, y: 200, width: 900, height: 700), styleMask: [.titled], backing: .buffered,
      defer: false)
    var dismissals = 0
    let popup = ExtensionPopupWindow(
      page: NSView(), size: NSSize(width: 200, height: 200), name: "Extension", parent: parent,
      anchor: NSRect(x: 780, y: 694, width: 32, height: 28), placement: .topTrailing(NSPoint(x: 850, y: 690))
    ) { dismissals += 1 }
    popup.present()
    #expect(popup.isVisible)
    popup.dismiss()
    #expect(dismissals == 1)
    #expect(!popup.isVisible)
  }
}

/// View › Hide Toolbar (add-page-toolbar D8).
@MainActor
struct ToolbarMenuTests {
  private let defaults: UserDefaults = {
    let name = "ClairUITests.ToolbarMenu.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }()

  /// Chromium's View menu once the engine has added Hide Sidebar.
  private func mainMenu() -> (NSMenu, NSMenu) {
    let main = NSMenu()
    let view = NSMenu(title: "View")
    view.addItem(NSMenuItem(title: "Hide Sidebar", action: MainMenuTitles.toggleSidebarAction, keyEquivalent: "s"))
    view.addItem(.separator())
    view.addItem(NSMenuItem(title: "Collapse Pinned Tabs", action: nil, keyEquivalent: ""))
    main.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = NSMenu(title: "File")
    main.addItem(withTitle: "View", action: nil, keyEquivalent: "").submenu = view
    return (main, view)
  }

  @Test func addedOnceAfterHideSidebar() throws {
    let (main, view) = mainMenu()
    let target = ToolbarMenuTarget(preference: ToolbarPreference(defaults: defaults))
    let item = try #require(MainMenuTitles.addToolbarItem(to: main, target: target))
    #expect(view.items.firstIndex(of: item) == 1)
    #expect(item.keyEquivalent == "d")
    #expect(item.keyEquivalentModifierMask == [.command, .shift])
    #expect(item.target === target)
    #expect(MainMenuTitles.addToolbarItem(to: main, target: target) === item)
    #expect(view.items.filter { $0.action == ToolbarMenuTarget.action }.count == 1)
  }

  @Test func itsTitleFollowsThePreference() throws {
    let (main, _) = mainMenu()
    let preference = ToolbarPreference(defaults: defaults)
    let target = ToolbarMenuTarget(preference: preference)
    let item = try #require(MainMenuTitles.addToolbarItem(to: main, target: target))
    #expect(target.validateMenuItem(item))
    #expect(item.title == "Hide Toolbar")
    NSApplication.shared.sendAction(ToolbarMenuTarget.action, to: target, from: item)
    #expect(!preference.isOn)
    #expect(target.validateMenuItem(item))
    #expect(item.title == "Show Toolbar")
    NSApplication.shared.sendAction(ToolbarMenuTarget.action, to: target, from: item)
    #expect(preference.isOn)
  }

  @Test func aMenuWithoutHideSidebarGetsNothing() {
    let main = NSMenu()
    main.addItem(withTitle: "View", action: nil, keyEquivalent: "").submenu = NSMenu(title: "View")
    let target = ToolbarMenuTarget(preference: ToolbarPreference(defaults: defaults))
    #expect(MainMenuTitles.addToolbarItem(to: main, target: target) == nil)
  }
}

/// Settings › General's "Location bar" row (add-page-toolbar D9).
@MainActor
struct LocationBarPickerTests {
  private let defaults: UserDefaults = {
    let name = "ClairUITests.LocationBar.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }()

  @Test func choicesFollowThePreference() {
    #expect(LocationBarChoice(showsToolbar: true) == .toolbar)
    #expect(LocationBarChoice(showsToolbar: false) == .sidebar)
    #expect(LocationBarChoice.allCases.map(\.label) == ["Toolbar", "Sidebar"])
  }

  /// The row reads the preference: Toolbar is chosen with no stored value.
  /// SwiftUI doesn't build its accessibility tree in the test process, so
  /// the runtime suite checks the group by its identifiers.
  @Test func theRowDefaultsToToolbar() {
    let options = LocationBarPicker.options(showsToolbar: ToolbarPreference(defaults: defaults).isOn)
    #expect(options.map(\.label) == ["Toolbar", "Sidebar"])
    #expect(options.map(\.isChosen) == [true, false])
    #expect(options.map(\.identifier) == ["clair.locationBar.toolbar", "clair.locationBar.sidebar"])
    #expect(LocationBarPicker.label == "Location bar")
    #expect(LocationBarPicker.identifier == "clair.locationBar")
  }

  @Test func choosingWritesThePreference() {
    let preference = ToolbarPreference(defaults: defaults)
    let binding = Binding(get: { preference.isOn }, set: { preference.isOn = $0 })
    let picker = LocationBarPicker(showsToolbar: binding)
    picker.choose(.sidebar)
    #expect(!ToolbarPreference(defaults: defaults).isOn)
    #expect(LocationBarPicker.options(showsToolbar: preference.isOn).map(\.isChosen) == [false, true])
    picker.choose(.toolbar)
    #expect(ToolbarPreference(defaults: defaults).isOn)
  }

  /// General binds the same key as the windows read.
  @Test func generalOpensWithTheRow() throws {
    let settings = SettingsWindowController(host: FakeHost(), defaults: defaults)
    settings.show()
    let window = try #require(settings.window)
    defer { window.close() }
    #expect(window.title == "General")
    // The row makes General taller than the default browser row alone.
    let height: CGFloat = window.contentView?.fittingSize.height ?? 0
    let thumbnail: CGFloat = GeneralSettingsView.thumbnailWidth * 0.6
    #expect(height > 2 * thumbnail)
  }
}

/// Every toolbar button but the link is Arc's 32 × 24 (add-page-toolbar): the
/// shared `IconButton` at the toolbar's height.
@MainActor struct ToolbarButtonSizeTests {
  private func size(of view: some View) -> CGSize {
    NSHostingView(rootView: view).fittingSize
  }

  @Test func toolbarButtonsAreArcsSize() {
    let button = IconButton(systemImage: "arrow.clockwise", help: "Reload", height: IconButtonSize.toolbarHeight) {}
    #expect(size(of: button) == CGSize(width: 32, height: 24))
  }

  @Test func theLinkIsAsTallAsTheOthers() {
    let link = IconButton(systemImage: "link", help: "Copy URL", size: 22, height: IconButtonSize.toolbarHeight) {}
    #expect(size(of: link) == CGSize(width: 22, height: 24))
  }

  @Test func sidebarButtonsStaySquare() {
    #expect(size(of: IconButton(systemImage: "arrow.clockwise", help: "Reload") {}) == CGSize(width: 32, height: 32))
    #expect(size(of: IconButton(systemImage: "link", help: "Copy URL", size: IconButtonSize.small) {}) == CGSize(width: 28, height: 28))
  }
}
