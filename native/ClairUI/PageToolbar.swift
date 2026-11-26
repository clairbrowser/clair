// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// Which of the toolbar's groups a page header shows (add-page-toolbar D4,
/// add-split-view D9).
enum PageHeaderContent: Equatable {
  /// The tab's toolbar: everything, with the split button at the trailing
  /// end.
  case tab
  /// A Peek's: back, forward, reload, the link icon and the host.
  case peek
  /// A split's pane's header: the sidebar toggle in the leading pane, back,
  /// forward, the link icon, the host and ×; with `expanded`, while the pane
  /// is focused or under the pointer, also reload, the split button, site
  /// controls, pinned extensions and indicators.
  case pane(leading: Bool, expanded: Bool)

  /// The leading controls that always show before reload.
  var leadingCount: Int {
    switch self {
    case .tab: 3
    case .peek: 2
    case .pane(let leading, _): leading ? 3 : 2
    }
  }
  var showsSidebarToggle: Bool { leadingCount == 3 }
  var showsReload: Bool {
    if case .pane(_, let expanded) = self { return expanded }
    return true
  }
  private var showsAll: Bool {
    switch self {
    case .tab: true
    case .peek: false
    case .pane(_, let expanded): expanded
    }
  }
  var showsSiteControls: Bool { showsAll }
  var showsExtensions: Bool { showsAll }
  var showsIndicators: Bool { showsAll }
  var showsSplitButton: Bool { showsAll }
  var showsClose: Bool {
    if case .pane = self { return true }
    return false
  }
  /// The trailing controls that always show, from the trailing edge: ×, the
  /// split button and the site controls, as each shows.
  var trailingFixedCount: Int {
    (showsClose ? 1 : 0) + (showsSplitButton ? 1 : 0) + (showsSiteControls ? 1 : 0)
  }

  var identifier: String {
    switch self {
    case .tab: "clair.toolbar"
    case .peek: "clair.peekToolbar"
    case .pane(let leading, _): "clair.paneToolbar.\(leading ? 0 : 1)"
    }
  }
}

/// Which page header a toolbar host shows: a page's, which is a split's pane
/// while split, or a Peek's.
enum PageHeaderSlot: Equatable {
  /// The card of a split's pane by its index; the first is the single
  /// page's card outside a split.
  case pane(Int)
  case peek
}

/// The toolbar's coordinate space, which its hosting view's is.
let toolbarCoordinateSpace = "clair.toolbar"

/// The toolbar's fills (add-page-toolbar D4): Arc's fixed grey, and the line
/// over the page's top row, about 5% black.
enum ToolbarFill {
  static let background = NSColor(name: "clair.toolbar") { appearance in
    appearance.isDark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 238 / 255, alpha: 1)
  }
  static let line = NSColor(name: "clair.toolbarLine") { appearance in
    appearance.isDark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.05)
  }
  /// The host's background under the pointer.
  static func hostHover(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.07)
  }
}

/// The toolbar above a page (add-page-toolbar D2, D4): the sidebar's browser
/// controls, moved. Its blank areas move the window and act as a title bar
/// whatever the window dragging preference, and right-clicking them, or the
/// host, offers Copy URL and Hide Toolbar.
struct PageToolbar: View {
  let model: BrowserWindowModel
  let slot: PageHeaderSlot
  weak var actions: (any SidebarActions)?

  @State private var width: CGFloat = 0
  @State private var isHostHovered = false
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// What the toolbar shows: a page's toolbar, a split's pane's header,
  /// expanded while focused or under the pointer, or a Peek's.
  var content: PageHeaderContent {
    switch slot {
    case .peek: return .peek
    case .pane(let index):
      guard let split = model.shownSplit else { return .tab }
      return .pane(leading: index == 0, expanded: split.focusedIndex == index || model.hoveredPane == index)
    }
  }

  /// The pane's tab while split, or nil.
  private var paneTabID: TabID? {
    guard case .pane(let index) = slot, let split = model.shownSplit else { return nil }
    return split.paneIDs[index]
  }

  /// Whether the pane isn't the focused one: its controls focus it first.
  private var isOtherPane: Bool {
    guard case .pane(let index) = slot, let split = model.shownSplit else { return false }
    return split.focusedIndex != index
  }

  /// Runs `action` on the pane's tab: the pane is focused first.
  private func onPane(_ action: @escaping () -> Void) -> () -> Void {
    { [weak actions] in
      if isOtherPane, let paneTabID { actions?.focusPane(paneTabID) }
      action()
    }
  }

  /// The tab whose state the toolbar shows: the parent page's behind a Peek,
  /// or the Peek's own, or the pane's.
  private var tab: (any ClairTab)? {
    switch slot {
    case .peek: return model.peekTab
    case .pane(let index): return model.shownSplit == nil ? model.toolbarTab : model.paneTab(index)
    }
  }

  var body: some View {
    let content = self.content
    let tab = self.tab
    let display = URLDisplay.text(for: tab)
    let hostText = display ?? URLDisplay.placeholder
    let notSecure = URLDisplay.showsNotSecure(for: tab)
    let indicators =
      content.showsIndicators ? URLField.indicatorSymbols.filter { tab?.indicators.contains($0.0) == true } : []
    let extensions = content.showsExtensions ? model.pinnedExtensionActions : []
    let layoutContent = ToolbarArrangement.Content(
      leadingCount: content.leadingCount, hasReload: content.showsReload, hasLink: display != nil,
      hasNotSecure: notSecure, hostWidth: ToolbarArrangement.hostWidth(for: hostText),
      trailingFixedCount: content.trailingFixedCount, extensionCount: extensions.count,
      indicatorCount: indicators.count)
    let arrangement = ToolbarArrangement(width: width, content: layoutContent)
    // The trailing slots, from the edge: ×, then the split button, then the
    // site controls (add-split-view D9).
    let closeSlot = 0
    let splitSlot = content.showsClose ? 1 : 0
    let siteSlot = splitSlot + (content.showsSplitButton ? 1 : 0)
    ToolbarLayout(content: layoutContent) {
      leadingControls(content: content, tab: tab, arrangement: arrangement)
      if arrangement.notSecure != nil {
        Image(systemName: "lock.slash.fill")
          .font(.system(size: 11))
          .foregroundStyle(Color.red)
          .frame(width: ToolbarArrangement.notSecureWidth, height: ToolbarArrangement.hostHeight)
          .tooltip("Site is not secure")
          .accessibilityLabel("Site is not secure")
          .accessibilityIdentifier("clair.notSecure")
          .toolbarRole(.notSecure)
      }
      host(text: hostText, isPlaceholder: display == nil)
        .toolbarRole(.host)
      if arrangement.link != nil {
        IconButton(
          systemImage: "link", help: "Copy URL", shortcut: ["⇧", "⌘", "C"], size: 22,
          height: IconButtonSize.toolbarHeight, glyphSize: IconButtonSize.toolbarLinkGlyph
        ) { onPane { actions?.copyURL() }() }
          .accessibilityIdentifier("clair.copyURL")
          .toolbarRole(.link)
      }
      ForEach(Array(indicators.enumerated()), id: \.element.0.rawValue) { index, element in
        let (indicator, symbol, label) = element
        IconButton(
          systemImage: symbol, help: label, height: IconButtonSize.toolbarHeight, glyphSize: IconButtonSize.toolbarIndicatorGlyph,
          glyphWeight: .regular, foreground: .red
        ) {
          onPane { actions?.showSiteControls(indicator: indicator) }()
        }
        .anchorFrame(.indicator(indicator.rawValue))
        .toolbarRole(.indicator(index))
      }
      ForEach(Array(extensions.enumerated()), id: \.element.extensionID) { index, action in
        if arrangement.extensions.indices.contains(index), arrangement.extensions[index] != nil {
          ToolbarExtensionButton(
            action: action, contextMenu: { actions?.contextMenu(forExtension: action.extensionID) }
          ) { onPane { actions?.runExtension(action.extensionID, pinned: true) }() }
            .anchorFrame(.extensionAction(action.extensionID))
            .toolbarRole(.pinnedExtension(index))
        }
      }
      if content.showsSiteControls {
        siteControls(enabled: tab != nil)
          .toolbarRole(.trailingFixed(siteSlot))
      }
      if content.showsSplitButton {
        splitButton(tab: tab)
          .toolbarRole(.trailingFixed(splitSlot))
      }
      if content.showsClose, let paneTabID {
        IconButton(
          systemImage: "xmark", help: "Close tab", shortcut: ["⌘", "W"], height: IconButtonSize.toolbarHeight,
          glyphSize: IconButtonSize.toolbarGlyph
        ) { actions?.close(tab: paneTabID) }
          .accessibilityIdentifier("clair.closePane")
          .toolbarRole(.trailingFixed(closeSlot))
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: ToolbarArrangement.height)
    .background { background }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    .environment(\.isWindowKey, model.isWindowKey)
    .environment(\.anchorCoordinateSpace, toolbarCoordinateSpace)
    .coordinateSpace(name: toolbarCoordinateSpace)
    .onPreferenceChange(AnchorFramesKey.self) { frames in
      MainActor.assumeIsolated {
        if case .pane(let index) = slot {
          actions?.toolbarControlFramesChanged(frames, pane: index)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(slot == .peek ? "Peek toolbar" : (content == .tab ? "Toolbar" : "Pane toolbar"))
    .accessibilityIdentifier(content.identifier)
  }

  /// The split button: Split with Tab on a single page, the pane's moves in
  /// a split (add-split-view D9).
  private func splitButton(tab: (any ClairTab)?) -> some View {
    let tabID = paneTabID ?? tab?.tabID ?? ClairTabIDNone
    let entries =
      paneTabID != nil
      ? SplitLogic.paneMenu(isLeading: slot == .pane(0))
      : SplitLogic.singlePageMenu(shown: tabID, today: model.tabs)
    let favicons = Dictionary(model.allTabs.map { ($0.tabID, $0) }, uniquingKeysWith: { first, _ in first })
    return SplitButton(entries: entries, icon: { favicons[$0]?.favicon }) { entry in
      if isOtherPane { actions?.focusPane(tabID) }
      switch entry {
      case .tab(let other, _): actions?.split(tab: tabID, with: other, side: .trailing)
      case .newTab: actions?.splitWithNewTab(tabID)
      case .moveLeft, .moveRight: actions?.swapSplit(of: tabID)
      case .separateTabs: actions?.separateSplit(of: tabID)
      case .closeThisTab: actions?.close(tab: tabID)
      case .heading, .separator: break
      }
    }
  }

  /// The sidebar toggle, back, forward and reload, at their slots.
  @ViewBuilder
  private func leadingControls(content: PageHeaderContent, tab: (any ClairTab)?, arrangement: ToolbarArrangement)
    -> some View
  {
    let reloadStop = model.reloadStop.mode
    let isLoading = reloadStop.visible == .stop
    let canGoBack = tab?.canGoBack ?? false
    let canGoForward = tab?.canGoForward ?? false
    let first = content.showsSidebarToggle ? 1 : 0
    if content.showsSidebarToggle {
      // Clair keeps the toggle first, with the sidebar shown or hidden, as
      // Dia does (dia-reference/).
      IconButton(
        systemImage: "sidebar.left", help: model.sidebar.isHidden ? "Show sidebar" : "Hide sidebar",
        shortcut: ["⌘", "S"], height: IconButtonSize.toolbarHeight, glyphSize: IconButtonSize.toolbarGlyph
      ) { actions?.toggleSidebar() }
        .accessibilityIdentifier("clair.hideSidebar")
        .toolbarRole(.leading(0))
    }
    IconButton(
      systemImage: "arrow.left", help: "Go back", shortcut: ["⌘", "["], isEnabled: canGoBack,
      height: IconButtonSize.toolbarHeight, glyphSize: IconButtonSize.toolbarGlyph
    ) {
      onPane { actions?.goBack() }()
    }
    .overlay(HistoryButtonCatcher(isEnabled: canGoBack, makeMenu: { actions?.historyMenu(.back) }))
    .accessibilityIdentifier("clair.back")
    .toolbarRole(.leading(first))
    IconButton(
      systemImage: "arrow.right", help: "Go forward", shortcut: ["⌘", "]"], isEnabled: canGoForward,
      height: IconButtonSize.toolbarHeight, glyphSize: IconButtonSize.toolbarGlyph
    ) {
      onPane { actions?.goForward() }()
    }
    .overlay(HistoryButtonCatcher(isEnabled: canGoForward, makeMenu: { actions?.historyMenu(.forward) }))
    .accessibilityIdentifier("clair.forward")
    .toolbarRole(.leading(first + 1))
    if arrangement.reload != nil {
      IconButton(
        help: isLoading ? "Stop loading this page" : "Reload this page",
        shortcut: isLoading ? ["esc"] : ["⌘", "R"], isEnabled: tab != nil && reloadStop.isEnabled,
        height: IconButtonSize.toolbarHeight
      ) {
        onPane { actions?.reloadOrStop() }()
      } label: {
        ZStack {
          SymbolGlyph(systemImage: "arrow.clockwise", size: IconButtonSize.toolbarGlyph).opacity(isLoading ? 0 : 1)
          SymbolGlyph(systemImage: "xmark", size: IconButtonSize.toolbarGlyph).opacity(isLoading ? 1 : 0)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.1), value: isLoading)
      }
      .onHover { actions?.reloadButtonHovered($0) }
      .accessibilityIdentifier("clair.reload")
      .toolbarRole(.reload)
    }
  }

  /// The host, as the URL field shows it, with Arc's rounded background
  /// under the pointer. A click opens the command bar.
  private func host(text: String, isPlaceholder: Bool) -> some View {
    Text(text)
      .font(.system(size: ToolbarArrangement.hostFontSize, weight: .medium))
      .lineLimit(1)
      .truncationMode(.tail)
      .foregroundStyle(isPlaceholder ? Color.secondary : Color.primary.opacity(0.75))
      .padding(.horizontal, ToolbarArrangement.hostPadding)
      .frame(height: ToolbarArrangement.hostHeight)
      .background(
        ToolbarFill.hostHover(colorScheme).opacity(isHostHovered ? 1 : 0), in: .rect(cornerRadius: 6))
      .contentShape(Rectangle())
      .onHover { hovering in withAnimation(sidebarHoverFade) { isHostHovered = hovering } }
      .onTapGesture { onPane { actions?.editURL() }() }
      .overlay(RowClickCatcher(onMiddleClick: {}, menuItems: menuItems(canCopy: !isPlaceholder)))
      .accessibilityElement()
      .accessibilityLabel(text)
      .accessibilityAddTraits(.isButton)
      .accessibilityIdentifier("clair.urlField")
  }

  /// The site-controls button, always shown, with the Site Control Center
  /// hanging below it.
  private func siteControls(enabled: Bool) -> some View {
    @Bindable var model = model
    return IconButton(
      systemImage: "slider.horizontal.2.square", help: "Site Control Center", isEnabled: enabled,
      height: IconButtonSize.toolbarHeight, glyphSize: IconButtonSize.toolbarSiteControlsGlyph,
      glyphWeight: .regular
    ) {
      onPane { model.isSiteControlCenterOpen = true }()
    }
    // A click while the popover is open only closes it (arc-site-control-center
    // design D2).
    .allowsHitTesting(!model.isSiteControlCenterOpen)
    // Only the focused pane's button holds the popover (add-split-view D9).
    .popover(isPresented: isOtherPane ? .constant(false) : $model.isSiteControlCenterOpen, arrowEdge: .bottom) {
      SiteControlCenter(model: model, actions: actions) { model.isSiteControlCenterOpen = false }
    }
    .anchorFrame(.siteControls)
    .accessibilityIdentifier("clair.siteControls")
  }

  /// Arc's grey, which moves the window, zooms it on a double-click, and
  /// offers the toolbar's menu.
  private var background: some View {
    ZStack {
      Color(nsColor: ToolbarFill.background)
      TitleBarArea { actions?.titleBarDoubleClicked() }
      RowClickCatcher(onMiddleClick: {}, menuItems: menuItems(canCopy: URLDisplay.text(for: tab) != nil))
    }
  }

  /// The toolbar's context menu: Copy URL and Hide Toolbar, as in Arc.
  private func menuItems(canCopy: Bool) -> [RowClickCatcher.Item] {
    var items: [RowClickCatcher.Item] = []
    if canCopy {
      items.append(.action("Copy URL") { [weak actions] in actions?.copyURL() })
      items.append(.separator)
    }
    items.append(.action(ToolbarPreference.menuTitle(isOn: true)) { [weak actions] in actions?.setToolbarShown(false) })
    return items
  }
}
