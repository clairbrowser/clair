// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Observation

/// What one native window shows, as Chromium last reported it through
/// `ClairWindow`, plus the window's own state (sidebar, overlays). SwiftUI
/// views observe it; only `BrowserWindowController` changes what came from
/// Chromium.
@Observable
final class BrowserWindowModel {
  let profileKind: ProfileKind
  /// The window's ID, which its tabs carry.
  let browserID: BrowserID
  /// Every Space and its tabs, app-wide (add-spaces design D10).
  let spaces: SpacesModel
  /// The sidebar's update banner, app-wide (add-update-banners D1).
  let updateBanner: UpdateBannerState

  /// The Space the window shows (add-spaces design D3).
  private(set) var shownSpaceID: SpaceID

  /// The tabs of the Space the window shows, in the Space's order, which is
  /// the sidebar's, Peeks included: every window's in a regular window
  /// (share-tabs-across-windows D1), its own in an incognito or guest one.
  private(set) var tabs: [any ClairTab] = []
  private(set) var activeTabID: TabID = ClairTabIDNone

  /// The pinned items of the Space the window shows, pinned tabs and
  /// folders, and the favorites of its profile, in their order
  /// (add-pinned-tabs-and-favorites D11, add-tab-folders D2); none in an
  /// incognito or guest window.
  private(set) var pinnedItems: [any ClairPinnedItem] = []
  /// Every pinned tab of the shown Space, its folders' included, in order.
  private(set) var pins: [any ClairPin] = []
  /// The profile's favorites and favorited splits, as the grid's tiles
  /// (add-split-view D10).
  private(set) var favoriteItems: [any ClairPinnedItem] = []
  /// Every favorite, a favorited split's two included.
  private(set) var favorites: [any ClairPin] = []
  /// The latest snapshot of each open pin's tab and its Peek, by tab ID.
  private(set) var pinTabs: [TabID: any ClairTab] = [:]

  /// The tabs of the window's pins and favorites, each followed by its Peek,
  /// then its Today tabs: every tab its rows and tiles stand for.
  var allTabs: [any ClairTab] {
    pinFamilies(favorites) + pinFamilies(pins) + tabs
  }

  private func pinFamilies(_ pins: [any ClairPin]) -> [any ClairTab] {
    pins.flatMap { pin in pin.tabs.compactMap { pinTabs[$0.tabID] ?? $0 } }
  }

  /// The bound tab of `pin`, as last reported, or nil.
  func tab(ofPin pin: any ClairPin) -> (any ClairTab)? {
    guard pin.tabID != ClairTabIDNone else { return nil }
    return pinTabs[pin.tabID] ?? PinsLogic.tab(of: pin)
  }

  /// The icon of a dragged row or tile: its tab's favicon, or its pin's
  /// icon.
  func icon(of item: SidebarDragItem) -> NSImage? {
    switch item {
    case .tab(let tabID):
      return tabs.first { $0.tabID == tabID }?.favicon
    case .pin(let pinID):
      guard let pin = (pins + favorites).first(where: { $0.pinID == pinID }) else { return nil }
      return PinsLogic.icon(of: pin, tab: tab(ofPin: pin))
    case .folder:
      return nil
    }
  }

  /// The icons of a dragged row or tile: both pages' for a split, in pane
  /// order, as its favorite tile shows them.
  func icons(of item: SidebarDragItem) -> [NSImage?] {
    switch item {
    case .tab(let tabID):
      if let tab = allTabs.first(where: { $0.tabID == tabID }),
        let (leading, trailing) = TabListLogic.panes(of: tab, in: allTabs)
      {
        return [leading.favicon, trailing.favicon]
      }
    case .pin(let pinID):
      if let split = PinsLogic.split(containing: pinID, in: pinnedItems + favoriteItems) {
        return split.pins.map { PinsLogic.icon(of: $0, tab: tab(ofPin: $0)) }
      }
    case .folder:
      break
    }
    return [icon(of: item)]
  }

  /// The pin `tabID` is bound to, among the window's.
  func pin(ofTab tabID: TabID) -> (any ClairPin)? {
    guard tabID != ClairTabIDNone else { return nil }
    return pins.first { $0.tabID == tabID } ?? favorites.first { $0.tabID == tabID }
  }

  /// The favorites' profile: the shown Space's.
  var profileID: ProfileID? { shownSpace?.profileID }

  /// Whether the window shows pinned tabs and favorites: not in incognito
  /// and guest windows.
  var showsPins: Bool { showsSpaces }

  /// The tab another window took, whose dimmed still the card shows, or none
  /// (share-tabs-across-windows D2). Its row stays highlighted.
  private(set) var stillTabID: TabID = ClairTabIDNone
  /// The page as it was when it left, or nil when the copy failed: the card
  /// then dims its background alone.
  private(set) var stillImage: NSImage?

  /// Whether the card shows a still over the hidden placeholder tab.
  var isShowingStill: Bool { stillTabID != ClairTabIDNone }

  /// The Space the window shows, or nil in an incognito or guest window,
  /// whose Space isn't one of the user's.
  var shownSpace: (any ClairSpace)? {
    spaces.space(shownSpaceID)
  }

  /// Whether the window shows the user's Spaces: not in incognito and guest
  /// windows.
  var showsSpaces: Bool {
    profileKind == .regular
  }

  /// The tab whose page the card shows, which the URL field and the
  /// navigation buttons follow: none while the card shows a still.
  var activeTab: (any ClairTab)? {
    isShowingStill ? nil : allTabs.first { $0.tabID == activeTabID }
  }

  /// The row highlighted in `tabs`: the still's while there's one, else the
  /// active tab's, or its parent's while a Peek shows.
  func highlightedRow(in tabs: [any ClairTab]) -> TabID {
    isShowingStill ? stillTabID : TabListLogic.highlightedRow(activeTabID: activeTabID, in: tabs)
  }

  /// The row or tile highlighted among every tab the window lists.
  var highlightedTab: TabID { highlightedRow(in: allTabs) }

  /// The tab the main menu's pin commands act on: the still's, or the
  /// active tab, or its parent while a Peek shows. A split's trailing pane
  /// is itself, not its row's leading pane, as it has a pin of its own.
  var commandTab: TabID {
    if isShowingStill { return stillTabID }
    if let active = activeTab, active.peekParentID != ClairTabIDNone { return active.peekParentID }
    return activeTabID
  }

  /// The pin or favorite whose row or tile is highlighted, if one is.
  var activePin: (any ClairPin)? { pin(ofTab: highlightedTab) }

  /// Each row's Peek, whose favicon the row shows as a badge; the still's
  /// row shows none, as the still shows the page without its Peek.
  func rowPeeks(in tabs: [any ClairTab]) -> [TabID: any ClairTab] {
    var peeks = TabListLogic.peeksByRow(tabs)
    if isShowingStill {
      peeks[stillTabID] = nil
    }
    return peeks
  }

  // --- where the browser controls show (add-page-toolbar D1) ---
  /// The toolbar preference, as the window last read it.
  var showsToolbar = true
  /// The panes the card shows: two while the active tab, or the active
  /// Peek's parent, is in a split (add-split-view D3).
  var paneCount: Int { shownSplit == nil ? 1 : 2 }

  /// The split the window shows, if any (add-split-view D2).
  var shownSplit: ShownSplit? {
    isShowingStill ? nil : SplitLogic.shownSplit(activeTabID: activeTabID, in: allTabs)
  }
  /// The pane under the pointer, whose header shows all its controls
  /// (add-split-view spec, "Controls of the other pane").
  var hoveredPane: Int?
  /// The ratio while the divider is dragged, before the engine has it, and
  /// the panes of the split it's dragged in.
  var liveSplitRatio: Double?
  var liveSplitPanes: [TabID]?
  /// The dragged ratio of `split`, only while it's the split dragged.
  func liveRatio(of split: ShownSplit) -> Double? {
    liveSplitPanes == split.paneIDs ? liveSplitRatio : nil
  }
  /// The modifier keys held while the link status shows (D13a).
  var statusModifiers: NSEvent.ModifierFlags = []
  /// A tab dragged over the page, and the zone under it (D8).
  var pageDrop: SplitLogic.DropZone?

  /// The tab a pane shows: a split's pane's, or the toolbar's tab outside a
  /// split.
  func paneTab(_ index: Int) -> (any ClairTab)? {
    guard let split = shownSplit else { return index == 0 ? toolbarTab : nil }
    return allTabs.first { $0.tabID == split.paneIDs[index] }
  }

  /// What the link status reads, worded with the modifier keys held.
  var wordedStatus: String? {
    guard let statusText else { return nil }
    guard statusIsLink else { return statusText }
    let inPeek = allTabs.first { $0.tabID == statusTabID }.map(TabListLogic.isPeek) ?? false
    return SplitLogic.linkStatus(
      url: statusText, modifiers: statusModifiers, opensPeekOnShiftClick: opensPeekOnShiftClick, inPeek: inPeek)
  }
  /// The Peek preference, as the window last read it.
  var opensPeekOnShiftClick = true
  var headerPolicy: PageHeaderPolicy { PageHeaderPolicy(showsToolbar: showsToolbar, paneCount: paneCount) }
  /// Whether the page shows its header, the toolbar. Views read this, not
  /// the preference.
  var showsPageHeader: Bool { headerPolicy.panesShowHeader }
  /// Whether the sidebar shows its full top row, the URL field and the
  /// pinned extensions.
  var sidebarShowsControls: Bool { headerPolicy.sidebarShowsControls }
  /// Whether the sidebar's top row shows back, forward and reload.
  var sidebarShowsNavigation: Bool { headerPolicy.sidebarShowsNavigation }

  /// The Peek the card shows over its parent, if any (add-peek D4).
  var shownPeek: TabListLogic.ShownPeek?

  /// The tab whose state the tab's toolbar shows: the parent while a Peek
  /// covers it, else the active tab.
  var toolbarTab: (any ClairTab)? {
    guard let shownPeek, !isShowingStill else { return activeTab }
    return allTabs.first { $0.tabID == shownPeek.parentID }
  }

  /// The Peek's tab, which its own toolbar shows.
  var peekTab: (any ClairTab)? {
    guard let shownPeek else { return nil }
    return allTabs.first { $0.tabID == shownPeek.peekID }
  }

  /// What the URL field shows, or nil for its placeholder.
  var urlFieldText: String? { URLDisplay.text(for: activeTab) }
  /// Whether back, forward and reload can act on the page the card shows.
  var canGoBack: Bool { activeTab?.canGoBack ?? false }
  var canGoForward: Bool { activeTab?.canGoForward ?? false }
  var canReload: Bool { activeTab != nil }

  private(set) var extensionActions: [any ClairExtensionAction] = []
  private(set) var downloads: [any ClairDownload] = []
  /// The whole app's download progress, as the Dock shows it.
  private(set) var appDownloadProgress = DownloadProgress()

  var pinnedExtensionActions: [any ClairExtensionAction] {
    extensionActions.filter(\.isPinned)
  }

  /// Whether the downloads button shows a finished download the user hasn't
  /// looked at.
  var hasUnseenDownloads: Bool {
    downloads.contains { $0.state == .complete && !$0.isSeen }
  }

  /// The progress ring's value, 0 to 1, as the Dock shows it: every
  /// profile's running downloads, and no ring when none runs or any has an
  /// unknown size.
  var downloadProgress: Double? {
    let progress = appDownloadProgress
    guard progress.count > 0, !progress.isIndeterminate else { return nil }
    return min(max(progress.fraction, 0), 1)
  }

  // --- the window's own state ---
  /// What the Space header is editing (add-spaces D10).
  var spaceHeaderEdit: SpaceHeaderEdit?
  /// The row whose title is a field, and where its caret goes
  /// (add-pinned-tabs-and-favorites D11).
  var renaming: RowRename?
  /// Whether the shown Space's pinned section is collapsed.
  var isPinnedSectionCollapsed = false
  /// Whether the empty favorites box shows, for a profile with none.
  var showsFavoritesHint = false
  /// The New Space form, while it shows in place of the header and list.
  var newSpaceForm: NewSpaceFormState?
  /// The slide from the Space shown before, while it runs.
  var spaceSlide: SpaceSlide?
  var sidebar: SidebarState
  var commandBar: CommandBarModel?
  var find: FindState?
  /// Bumped when Cmd+F asks for the find field again while it shows.
  var findFocusRequest = 0
  var statusText: String?
  /// Whether `statusText` is a link's URL, which the capsule words with the
  /// modifier keys held, and the page it's in (add-split-view D13a).
  var statusIsLink = false
  var statusTabID: TabID = ClairTabIDNone
  var toast: Toast?
  var exclusiveAccessNotice: String?
  /// The popup in the card's top-trailing corner (design D18).
  let notice = NoticeState()
  /// Confirm on the Peek's Close button (add-peek design D6).
  let peekConfirm = PeekConfirmState()
  var isPageFullscreen = false
  var isSiteControlCenterOpen = false
  var isDownloadsListOpen = false
  /// Whether the user last used the sidebar's controls rather than a pane
  /// header's, while both show them: a split with the toolbar off.
  var usedSidebarControls = false
  /// Whether Chromium's bubbles, extension popups and the Site Control
  /// Center attach to the sidebar's controls rather than the page header's.
  var bubblesInSidebar: Bool { sidebarShowsControls && (!showsPageHeader || usedSidebarControls) }
  /// A revealed sidebar stays revealed while one of its popovers is open
  /// (arc-site-control-center design D8).
  var isSidebarPopoverOpen: Bool { isSiteControlCenterOpen || isDownloadsListOpen }
  var isWindowKey = true
  /// Whether the window is in macOS full screen, where the top row has no
  /// window controls to make room for.
  var isWindowFullscreen = false
  var windowControls = WindowControlsMetrics.macOS27
  /// What the reload button shows (arc-navigation-feedback design D2).
  let reloadStop = ReloadStopState(doubleClickInterval: NSEvent.doubleClickInterval)

  init(
    profileKind: ProfileKind, sidebar: SidebarState, browserID: BrowserID = 0, shownSpaceID: SpaceID = "",
    spaces: SpacesModel = .detached, updateBanner: UpdateBannerState = .detached, showsToolbar: Bool = true
  ) {
    self.profileKind = profileKind
    self.showsToolbar = showsToolbar
    self.sidebar = sidebar
    self.browserID = browserID
    self.shownSpaceID = shownSpaceID
    self.spaces = spaces
    self.updateBanner = updateBanner
  }

  /// Shows another Space's rows, read from `spaces`.
  func setShownSpace(_ spaceID: SpaceID) {
    shownSpaceID = spaceID
    reloadTabs()
  }

  /// Whether the window lists only the tabs it holds: an incognito or guest
  /// window, whose tabs never leave it.
  var listsOwnTabsOnly: Bool { profileKind != .regular }

  /// Reads the window's rows of its Space again from `spaces`.
  func reloadTabs() {
    tabs =
      listsOwnTabsOnly
      ? spaces.tabs(inSpace: shownSpaceID, browser: browserID) : spaces.tabs(inSpace: shownSpaceID)
    reloadPins()
  }

  /// Reads the Space's pinned tabs and the profile's favorites again.
  func reloadPins() {
    guard showsPins else {
      pinnedItems = []
      pins = []
      favoriteItems = []
      favorites = []
      pinTabs = [:]
      return
    }
    pinnedItems = spaces.pinnedItems(inSpace: shownSpaceID)
    pins = PinsLogic.allPins(pinnedItems)
    favoriteItems = profileID.map { spaces.favoriteItems(ofProfile: $0) } ?? []
    favorites = PinsLogic.allPins(favoriteItems)
    var latest: [TabID: any ClairTab] = [:]
    for pin in pins + favorites {
      for tab in pin.tabs {
        latest[tab.tabID] = tab
      }
    }
    pinTabs = latest
  }

  /// The window shows a still of `tabID`, with `image`, or none.
  func setStill(_ tabID: TabID, image: NSImage?) {
    stillTabID = tabID
    stillImage = tabID == ClairTabIDNone ? nil : image
  }

  /// Replaces the snapshot of one tab; a tab the list doesn't have is ignored,
  /// since the list update that adds it carries its state.
  func updateTab(_ tab: any ClairTab) {
    if pinTabs[tab.tabID] != nil {
      pinTabs[tab.tabID] = tab
      return
    }
    guard let index = tabs.firstIndex(where: { $0.tabID == tab.tabID }) else {
      return
    }
    tabs[index] = tab
  }

  /// Whether `tab` is one of the window's: a Today tab of its Space, or an
  /// open pin's.
  func lists(_ tab: any ClairTab) -> Bool {
    pinTabs[tab.tabID] != nil
      || (tab.spaceID == shownSpaceID && (!listsOwnTabsOnly || tab.browserID == browserID))
  }

  func setActiveTab(_ tabID: TabID) {
    activeTabID = tabID
  }

  func setExtensionActions(_ actions: [any ClairExtensionAction]) {
    extensionActions = actions
  }

  func setDownloads(_ downloads: [any ClairDownload], progress: DownloadProgress) {
    self.downloads = downloads
    setDownloadProgress(progress)
  }

  /// Takes the app-wide progress, leaving the model alone when nothing
  /// changed, so the sidebar doesn't redraw for nothing.
  func setDownloadProgress(_ progress: DownloadProgress) {
    let current = appDownloadProgress
    guard
      progress.count != current.count || progress.isIndeterminate != current.isIndeterminate
        || progress.fraction != current.fraction
    else { return }
    appDownloadProgress = progress
  }
}

/// A row being renamed in place (tab-names spec, "Renaming a row in place").
struct RowRename: Equatable {
  enum Row: Equatable {
    case tab(TabID)
    case pin(PinID)
    /// A folder's name (add-tab-folders D6).
    case folder(FolderID)
  }

  let row: Row
  /// Rename… selects the whole name; a double-click puts the caret where it
  /// clicked, at this offset in the title.
  var selectsAll: Bool
  var caret: Int?
  let id = UUID()
}

/// A slide from one Space to another (add-spaces D10): the earlier Space's
/// header and rows, as they were, slide out while the new Space's slide in.
struct SpaceSlide: Identifiable {
  let id = UUID()
  let fromSpace: (any ClairSpace)?
  let fromTabs: [any ClairTab]
  /// Whether the new Space comes in from the trailing side, being later in
  /// the order.
  let fromTrailing: Bool
  /// Its pinned items (add-pinned-tabs-and-favorites D11, add-tab-folders).
  var fromItems: [any ClairPinnedItem] = []
}

/// A toast at the bottom of the card. Each has its own ID, so the same
/// message twice still shows twice.
struct Toast: Equatable, Identifiable {
  let id = UUID()
  let message: String
}

/// The sidebar's state in one window (design D12).
struct SidebarState: Equatable {
  static let defaultWidth: CGFloat = 228
  /// Arc's limits. The window controls can raise the lower one
  /// (`WindowControlsMetrics.narrowestSidebar`).
  static let widthRange: ClosedRange<CGFloat> = 164...500

  var width: CGFloat
  var isHidden: Bool
  /// Shown as a floating overlay over the page while hidden.
  var isRevealed = false

  init(width: CGFloat = SidebarState.defaultWidth, isHidden: Bool = false) {
    self.width = Self.clamp(width)
    self.isHidden = isHidden
  }

  static func clamp(_ width: CGFloat) -> CGFloat {
    min(max(width, widthRange.lowerBound), widthRange.upperBound)
  }

  /// Whether the sidebar takes its place beside the card, so its controls are
  /// where Chromium's bubbles attach.
  var isShownInPlace: Bool { !isHidden }
}

/// Where the window controls landed, relative to the sidebar's top-leading
/// corner, as accessibility reads them (place-traffic-lights-with-appkit D3b).
/// The top row is laid out from them, so the two line up on any macOS.
struct WindowControlsMetrics: Equatable {
  /// macOS 27's, which match Arc's, until the buttons are first read.
  static let macOS27 = WindowControlsMetrics(centreY: 24, trailingX: 74)
  /// In full screen, where there are no window controls: Arc keeps the top
  /// row where it is and starts hide-sidebar 13 pt in.
  static let fullScreen = WindowControlsMetrics(centreY: 24, trailingX: 13 - topRowGap)

  /// The close button's vertical centre.
  var centreY: CGFloat
  /// The zoom button's trailing edge.
  var trailingX: CGFloat

  /// The gap between the zoom button and the top row's first button: 4 pt
  /// more than Arc's 3, which the owner found too tight.
  static let topRowGap: CGFloat = 7

  /// Where the top row's first button may start. 81 on macOS 27.
  var topRowLeading: CGFloat { trailingX + Self.topRowGap }

  /// Below this sidebar width the top row is compact, as in Arc: back,
  /// forward and a menu holding reload and Hide Sidebar. 218 on macOS 27.
  var compactBelow: CGFloat { topRowLeading + 137 }

  /// The narrowest sidebar, where the compact row's back button (90 pt from
  /// the trailing edge) starts at the zoom button's edge. 164 on macOS 27.
  var narrowestSidebar: CGFloat { max(SidebarState.widthRange.lowerBound, trailingX + 90) }

  func hasCompactTopRow(width: CGFloat) -> Bool { width < compactBelow }

  /// Whether `other` differs by half a point or more.
  func differs(from other: WindowControlsMetrics) -> Bool {
    abs(centreY - other.centreY) >= 0.5 || abs(trailingX - other.trailingX) >= 0.5
  }
}

/// Find in page, while the find field is open.
struct FindState: Equatable {
  var text: String
  var result = FindResult(activeMatch: 0, matchCount: 0, finished: true)

  static func == (lhs: FindState, rhs: FindState) -> Bool {
    lhs.text == rhs.text && lhs.result.activeMatch == rhs.result.activeMatch
      && lhs.result.matchCount == rhs.result.matchCount && lhs.result.finished == rhs.result.finished
  }

  /// "1 of 3", or nothing before there's a result.
  var resultText: String {
    if text.isEmpty { return "" }
    if result.matchCount == 0 { return result.finished ? "0 of 0" : "" }
    return "\(result.activeMatch) of \(result.matchCount)"
  }
}
