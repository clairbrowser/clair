// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// Which of the toolbar's groups a page header shows (add-page-toolbar D4).
/// Split view will add its pane variants here.
enum PageHeaderContent {
  /// The tab's toolbar: everything.
  case tab
  /// A Peek's: back, forward, reload, the link icon and the host.
  case peek

  /// The leading controls that always show before reload.
  var leadingCount: Int { self == .tab ? 3 : 2 }
  var showsSidebarToggle: Bool { self == .tab }
  var showsSiteControls: Bool { self == .tab }
  var showsExtensions: Bool { self == .tab }
  var showsIndicators: Bool { self == .tab }

  var identifier: String { self == .tab ? "clair.toolbar" : "clair.peekToolbar" }
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
  let content: PageHeaderContent
  weak var actions: (any SidebarActions)?

  @State private var width: CGFloat = 0
  @State private var isHostHovered = false
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// The tab whose state the toolbar shows: the parent page's behind a Peek,
  /// or the Peek's own.
  private var tab: (any ClairTab)? { content == .tab ? model.toolbarTab : model.peekTab }

  var body: some View {
    let tab = self.tab
    let display = URLDisplay.text(for: tab)
    let hostText = display ?? URLDisplay.placeholder
    let notSecure = URLDisplay.showsNotSecure(for: tab)
    let indicators =
      content.showsIndicators ? URLField.indicatorSymbols.filter { tab?.indicators.contains($0.0) == true } : []
    let extensions = content.showsExtensions ? model.pinnedExtensionActions : []
    let layoutContent = ToolbarArrangement.Content(
      leadingCount: content.leadingCount, hasLink: display != nil, hasNotSecure: notSecure,
      hostWidth: ToolbarArrangement.hostWidth(for: hostText),
      trailingFixedCount: content.showsSiteControls ? 1 : 0, extensionCount: extensions.count,
      indicatorCount: indicators.count)
    let arrangement = ToolbarArrangement(width: width, content: layoutContent)
    ToolbarLayout(content: layoutContent) {
      leadingControls(tab: tab, arrangement: arrangement)
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
        ) { actions?.copyURL() }
          .accessibilityIdentifier("clair.copyURL")
          .toolbarRole(.link)
      }
      ForEach(Array(indicators.enumerated()), id: \.element.0.rawValue) { index, element in
        let (indicator, symbol, label) = element
        IconButton(
          systemImage: symbol, help: label, height: IconButtonSize.toolbarHeight, glyphSize: IconButtonSize.toolbarIndicatorGlyph,
          glyphWeight: .regular, foreground: .red
        ) {
          actions?.showSiteControls(indicator: indicator)
        }
        .anchorFrame(.indicator(indicator.rawValue))
        .toolbarRole(.indicator(index))
      }
      ForEach(Array(extensions.enumerated()), id: \.element.extensionID) { index, action in
        if arrangement.extensions.indices.contains(index), arrangement.extensions[index] != nil {
          ToolbarExtensionButton(
            action: action, contextMenu: { actions?.contextMenu(forExtension: action.extensionID) }
          ) { actions?.runExtension(action.extensionID, pinned: true) }
            .anchorFrame(.extensionAction(action.extensionID))
            .toolbarRole(.pinnedExtension(index))
        }
      }
      if content.showsSiteControls {
        siteControls(enabled: tab != nil)
          .toolbarRole(.trailingFixed(0))
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
        if content == .tab { actions?.toolbarControlFramesChanged(frames) }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(content == .tab ? "Toolbar" : "Peek toolbar")
    .accessibilityIdentifier(content.identifier)
  }

  /// The sidebar toggle, back, forward and reload, at their slots.
  @ViewBuilder
  private func leadingControls(tab: (any ClairTab)?, arrangement: ToolbarArrangement) -> some View {
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
      actions?.goBack()
    }
    .overlay(HistoryButtonCatcher(isEnabled: canGoBack, makeMenu: { actions?.historyMenu(.back) }))
    .accessibilityIdentifier("clair.back")
    .toolbarRole(.leading(first))
    IconButton(
      systemImage: "arrow.right", help: "Go forward", shortcut: ["⌘", "]"], isEnabled: canGoForward,
      height: IconButtonSize.toolbarHeight, glyphSize: IconButtonSize.toolbarGlyph
    ) {
      actions?.goForward()
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
        actions?.reloadOrStop()
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
      .onTapGesture { actions?.editURL() }
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
      model.isSiteControlCenterOpen = true
    }
    // A click while the popover is open only closes it (arc-site-control-center
    // design D2).
    .allowsHitTesting(!model.isSiteControlCenterOpen)
    .popover(isPresented: $model.isSiteControlCenterOpen, arrowEdge: .bottom) {
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
