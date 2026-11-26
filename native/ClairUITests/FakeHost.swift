// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Foundation

@testable import ClairUI

/// A stand-in for a Space snapshot.
final class FakeSpace: NSObject, ClairSpace {
  let spaceID: SpaceID
  let name: String
  let icon: String?
  let profileID: ProfileID

  init(id: SpaceID, name: String, icon: String? = nil, profile: ProfileID = FakeHost.defaultProfileID) {
    spaceID = id
    self.name = name
    self.icon = icon
    profileID = profile
  }

  /// A copy with some fields changed, as the engine posts after a change.
  func with(name: String? = nil, icon: String?? = nil, profile: ProfileID? = nil) -> FakeSpace {
    FakeSpace(id: spaceID, name: name ?? self.name, icon: icon ?? self.icon, profile: profile ?? profileID)
  }
}

/// A stand-in for a profile snapshot.
final class FakeProfile: NSObject, ClairProfile {
  let profileID: ProfileID
  let name: String

  init(id: ProfileID, name: String) {
    profileID = id
    self.name = name
  }
}

/// A link rule as the engine keeps it: a copy of what ClairUI handed over
/// (add-link-rules design D4).
final class FakeLinkRule: NSObject, ClairLinkRule {
  let match: LinkRuleMatch
  let text: String
  let spaceID: SpaceID

  init(_ match: LinkRuleMatch, _ text: String, in spaceID: SpaceID) {
    self.match = match
    self.text = text
    self.spaceID = spaceID
  }
}

/// A stand-in for Chromium's implementation of `ClairHost`. It keeps the
/// Spaces and each Space's tab list, as `ClairSpaceStore` and `ClairSpaceTabs`
/// do (add-spaces design D1, D2), and the profiles, as `ClairProfiles` does
/// (add-profiles design D1), and tells its observers at once, in the order
/// the engine guarantees: a Space's list before a window hears of the active
/// tab.
///
/// A `FakeBrowser` stands for what the user sees as one window, which in the
/// engine is a group of browsers, one per profile (add-profiles design D3):
/// it shows a Space of any profile. A tab reopened in another profile gets a
/// new ID, as a new tab in Chromium does (D9).
final class FakeHost: NSObject, ClairHost {
  let chromiumVersion: String
  let ungoogledChromiumVersion: String
  var blockers: RelaunchBlockers = []
  private(set) var relaunchCount = 0
  private(set) var updateWillInstallOnQuitCount = 0

  /// The first Space, which a new host has alone.
  static let homeID: SpaceID = "home"
  /// The default profile, which a new host has alone.
  static let defaultProfileID: ProfileID = "Default"

  private(set) var spaces: [any ClairSpace] = [FakeSpace(id: FakeHost.homeID, name: "Home")]
  private(set) var profiles: [any ClairProfile] = [FakeProfile(id: FakeHost.defaultProfileID, name: "Default")]
  private var nextProfile = 1
  /// Whether -createProfile(named:completion:) answers at once, as when the
  /// profile is created quickly; otherwise `finishCreatingProfiles()` does.
  var createsProfilesAtOnce = true
  private var pendingProfileCompletions: [() -> Void] = []
  /// Each profile's download folder and whether it asks where to save.
  private(set) var downloadSettings: [ProfileID: (directory: URL, asks: Bool)] = [:]
  var warnsBeforeQuitting = true
  private(set) var quitCount = 0
  private(set) var openedURLsInProfiles: [(url: URL, profileID: ProfileID)] = []
  /// Each Space's tabs, in order, private Spaces of incognito windows
  /// included.
  private var lists: [SpaceID: [FakeTab]] = [:]
  private let observers = NSHashTable<AnyObject>.weakObjects()
  private let browsers = NSHashTable<FakeBrowser>.weakObjects()
  private var nextSpace = 1
  /// The Space last shown, which a new window shows (D3).
  var lastShownSpaceID: SpaceID = FakeHost.homeID
  /// Every Space command ClairUI sent, in order, such as "rename work Work".
  private(set) var commands: [String] = []
  /// The link rules, in order, as `ClairLinkRuleStore` keeps them
  /// (add-link-rules design D1).
  private var rules: [FakeLinkRule] = []
  /// The profile's bookmarks, as Chromium's `BookmarkModel` keeps them
  /// (add-bookmarks-menu design D3, D6).
  let bookmarks = FakeBookmarkStore()
  /// How many times ClairUI replaced the rules.
  private(set) var linkRuleSaves = 0

  /// The model ClairUI keeps for this host, as `NativeLayer` keeps one.
  private(set) lazy var spacesModel = SpacesModel(host: self)

  init(chromiumVersion: String = "156.0.8078.73", ungoogledChromiumVersion: String = "156.0.8078.73-1") {
    self.chromiumVersion = chromiumVersion
    self.ungoogledChromiumVersion = ungoogledChromiumVersion
  }

  func silentRelaunchBlockers() -> RelaunchBlockers {
    blockers
  }

  func relaunch() {
    relaunchCount += 1
  }

  func quitWithoutWarning() {
    quitCount += 1
  }

  func updateWillInstallOnQuit() {
    updateWillInstallOnQuitCount += 1
  }

  private(set) var openedURLs: [URL] = []

  func open(_ url: URL) {
    openedURLs.append(url)
  }

  // MARK: Helpers for tests and FakeBrowser

  /// Adds Spaces named `names` after the existing ones and returns their IDs,
  /// as the engine would for -createSpaceNamed:icon:.
  @discardableResult
  func addSpaces(_ names: String...) -> [SpaceID] {
    names.compactMap { createSpace(named: $0, icon: nil) }
  }

  func register(_ browser: FakeBrowser) {
    browsers.add(browser)
    activated(browser)
  }

  // MARK: Tabs shared across windows (share-tabs-across-windows D1 to D4)

  /// Every tab's page view, which moves with it between windows.
  var pageViews: [TabID: NSView] = [:]
  /// Unique across browsers, as Chromium's tab handles are.
  private var nextTabID: TabID = 1
  /// When each tab was last active, as a count.
  private var stamps: [TabID: Int] = [:]
  private var clock = 0
  /// Browsers, most recently active first.
  private var activationOrder: [BrowserID] = []

  func newTabID() -> TabID {
    defer { nextTabID += 1 }
    return nextTabID
  }

  /// A tab became active.
  func stamp(_ tabID: TabID) {
    clock += 1
    stamps[tabID] = clock
  }

  /// When the user last looked at a row or its Peek.
  func lastActive(row: TabID) -> Int {
    let peek = tab(row)?.peekID ?? ClairTabIDNone
    return max(stamps[row] ?? 0, stamps[peek] ?? 0)
  }

  /// Whether a window other than `browser` shows the row.
  func isShown(_ row: TabID, except browser: FakeBrowser) -> Bool {
    guard let tab = tab(row), tab.browserID != browser.browserID, let holder = self.browser(tab.browserID) else {
      return false
    }
    return holder.isActiveRow(row)
  }

  /// A window became the most recently active.
  func activated(_ browser: FakeBrowser) {
    activationOrder.removeAll { $0 == browser.browserID }
    activationOrder.insert(browser.browserID, at: 0)
  }

  /// The most recently active other regular window, open.
  func mostRecentBrowser(except browser: FakeBrowser) -> FakeBrowser? {
    activationOrder.lazy.compactMap { self.browser($0) }.first {
      $0 !== browser && $0.profileKind == .regular && !$0.isClosed
    }
  }

  /// What runs once the current operation is done, as the engine posts it.
  private var posted: [() -> Void] = []
  private var depth = 0

  /// Runs `body` as one operation: what it posts runs once it's done.
  func operation(_ body: () -> Void) {
    depth += 1
    body()
    depth -= 1
    guard depth == 0 else { return }
    while !posted.isEmpty {
      let task = posted.removeFirst()
      depth += 1
      task()
      depth -= 1
    }
  }

  /// D2: `row` stopped showing in its window. Once the current operation is
  /// done, if no window shows it, the most recently active window with a
  /// still of it takes it back, in the Space it shows.
  func giveBack(_ row: TabID) {
    posted.append { [weak self] in self?.giveBackNow(row) }
    if depth == 0 {
      operation {}
    }
  }

  private func giveBackNow(_ row: TabID) {
    guard let tab = tab(row), let holder = browser(tab.browserID), !holder.isActiveRow(row),
      let target = activationOrder.lazy.compactMap({ self.browser($0) }).first(where: {
        $0 !== holder && $0.stillTabID == row
      }), target.shownSpaceID == tab.spaceID
    else { return }
    target.takeBack(row)
  }

  /// A tab closed: a window showing a still of it shows a new tab page.
  func tabClosed(_ tabID: TabID) {
    for browser in allBrowsers where browser.stillTabID == tabID {
      browser.stillTabClosedForHost()
    }
  }

  var allBrowsers: [FakeBrowser] { browsers.allObjects }

  func browser(_ browserID: BrowserID) -> FakeBrowser? {
    browsers.allObjects.first { $0.browserID == browserID }
  }

  func list(_ spaceID: SpaceID) -> [FakeTab] {
    lists[spaceID] ?? []
  }

  func isSpace(_ spaceID: SpaceID) -> Bool {
    spaces.contains { $0.spaceID == spaceID }
  }

  /// The profile a Space uses, or nil for an unknown Space.
  func profile(ofSpace spaceID: SpaceID) -> ProfileID? {
    spaces.first { $0.spaceID == spaceID }?.profileID
  }

  /// Adds a profile named `name` and returns its ID, as the engine would for
  /// -createProfileNamed:completion:.
  @discardableResult
  func addProfile(_ name: String) -> ProfileID {
    var created: ProfileID?
    let atOnce = createsProfilesAtOnce
    createsProfilesAtOnce = true
    createProfile(named: name) { created = $0 }
    createsProfilesAtOnce = atOnce
    return created ?? ""
  }

  /// Answers the -createProfile calls waiting, as Chromium does once the
  /// profiles exist.
  func finishCreatingProfiles() {
    let completions = pendingProfileCompletions
    pendingProfileCompletions = []
    for completion in completions {
      completion()
    }
  }

  /// The tab with `tabID`, in whichever Space it is, or bound to a pin.
  func tab(_ tabID: TabID) -> FakeTab? {
    for tabs in lists.values {
      if let tab = tabs.first(where: { $0.tabID == tabID }) {
        return tab
      }
    }
    return bound.values.first { $0.tabID == tabID }
  }

  /// Every tab a window holds, in each Space's order, Spaces in order, then
  /// its pins' tabs.
  func tabs(ofBrowser browserID: BrowserID) -> [FakeTab] {
    let order = spaces.map(\.spaceID) + lists.keys.filter { !isSpace($0) }.sorted()
    return order.flatMap { list($0).filter { $0.browserID == browserID } }
      + bound.values.filter { $0.browserID == browserID }.sorted { $0.tabID < $1.tabID }
  }

  // MARK: Pins (add-pinned-tabs-and-favorites design D1 to D6) and folders
  // (add-tab-folders design D1 to D3, D7, D8, D11)

  /// A pin as the engine's store keeps it.
  struct PinRecord {
    let id: PinID
    /// A pinned tab's Space, or nil for a favorite.
    var spaceID: SpaceID?
    var profileID: ProfileID
    var url: String
    var title: String
    var name: String?
    /// The folder holding a pinned tab, or nil.
    var folderID: FolderID?
    /// add-split-view D10: the split holding it, and its pane there. A
    /// split's pin has the split's place.
    var splitID: PinnedSplitID? = nil
    var splitIndex = 0
  }

  /// A pinned or favorited split as the engine's store keeps it.
  struct SplitRecord {
    let id: PinnedSplitID
    var spaceID: SpaceID?
    var profileID: ProfileID
    var folderID: FolderID?
    var ratio: Double
  }

  /// A folder as the engine's store keeps it.
  struct FolderRecord {
    let id: FolderID
    var spaceID: SpaceID
    var name: String
  }

  private var records: [PinID: PinRecord] = [:]
  private var folderRecords: [FolderID: FolderRecord] = [:]
  private var splitRecords: [PinnedSplitID: SplitRecord] = [:]
  private var nextSplit = 1
  /// Each Space's items, pins and folders, in order.
  private var pinOrder: [SpaceID: [String]] = [:]
  /// Each folder's pins, in order.
  private var folderOrder: [FolderID: [PinID]] = [:]
  private var favoriteOrder: [ProfileID: [PinID]] = [:]
  /// The folders closed on this Mac (D3).
  private(set) var closedFolders: Set<FolderID> = []
  /// Each open pin's tab.
  private var bound: [PinID: FakeTab] = [:]
  /// Pins removed, newest first, for Restore Last Closed Tab (D3), each with
  /// its index in its folder or section.
  private(set) var removedPins: [(record: PinRecord, index: Int)] = []
  /// Folders removed, newest first, with their pins (D7).
  private(set) var removedFolders: [(folder: FolderRecord, pins: [PinRecord], index: Int, wasClosed: Bool)] = []
  private var nextPin = 1
  private var nextFolder = 1

  func pinRecord(_ pinID: PinID) -> PinRecord? { records[pinID] }

  func folderRecord(_ folderID: FolderID) -> FolderRecord? { folderRecords[folderID] }

  /// The pins an item of an order list stands for: a pin, a split's two or
  /// a folder's.
  private func pinRecords(ofItem id: String) -> [PinRecord] {
    if let record = records[id] { return [record] }
    if splitRecords[id] != nil { return pinRecords(ofSplit: id) }
    return (folderOrder[id] ?? []).flatMap { pinRecords(ofItem: $0) }
  }

  /// Every pin of a Space, its folders' and splits' included, in the
  /// sidebar's order.
  func pinRecords(inSpace spaceID: SpaceID) -> [PinRecord] {
    (pinOrder[spaceID] ?? []).flatMap { pinRecords(ofItem: $0) }
  }

  /// A folder's pins, in order.
  func pinRecords(inFolder folderID: FolderID) -> [PinRecord] {
    (folderOrder[folderID] ?? []).flatMap { pinRecords(ofItem: $0) }
  }

  /// A split's pins, leading pane first.
  func pinRecords(ofSplit splitID: PinnedSplitID) -> [PinRecord] {
    records.values.filter { $0.splitID == splitID }.sorted { $0.splitIndex < $1.splitIndex }
  }

  func splitRecord(_ splitID: PinnedSplitID) -> SplitRecord? { splitRecords[splitID] }

  /// A Space's folders, in order.
  func folderRecords(inSpace spaceID: SpaceID) -> [FolderRecord] {
    (pinOrder[spaceID] ?? []).compactMap { folderRecords[$0] }
  }

  func favoriteRecords(ofProfile profileID: ProfileID) -> [PinRecord] {
    (favoriteOrder[profileID] ?? []).flatMap { pinRecords(ofItem: $0) }
  }

  func boundTab(of pinID: PinID) -> FakeTab? { bound[pinID] }

  func isFolderOpen(_ folderID: FolderID) -> Bool { !closedFolders.contains(folderID) }

  func isFavoriteTab(_ tabID: TabID) -> Bool {
    guard let tab = tab(tabID), let pinID = tab.pinID, bound[pinID]?.tabID == tabID else { return false }
    return records[pinID]?.spaceID == nil
  }

  /// Adds a pin as the engine's store would, without a tab, and returns it.
  @discardableResult
  func addPin(
    url: String, title: String, name: String? = nil, inSpace spaceID: SpaceID? = FakeHost.homeID,
    folder folderID: FolderID? = nil, profile profileID: ProfileID = FakeHost.defaultProfileID
  ) -> PinID {
    let pinID = "pin-\(nextPin)"
    nextPin += 1
    let spaceID = folderID.flatMap { folderRecords[$0]?.spaceID } ?? spaceID
    let record = PinRecord(
      id: pinID, spaceID: spaceID, profileID: profileID, url: url, title: title, name: name,
      folderID: spaceID == nil ? nil : folderID)
    insertRecord(record, at: Int.max)
    pinsChanged(of: pinID)
    return pinID
  }

  /// Adds a folder as the engine's store would, and returns it.
  @discardableResult
  func addFolder(_ name: String, inSpace spaceID: SpaceID = FakeHost.homeID, open: Bool = true) -> FolderID {
    let folderID = createFolder(named: name, inSpace: spaceID, at: Int.max) ?? ""
    if !open {
      setFolder(folderID, open: false)
    }
    return folderID
  }

  private func snapshot(_ record: PinRecord) -> FakePin {
    let tab = bound[record.id]
    let atPinnedURL = tab.map { ($0.url?.absoluteString ?? $0.urlText) == record.url } ?? true
    return FakePin(
      id: record.id, isFavorite: record.spaceID == nil, spaceID: record.spaceID, profileID: record.profileID,
      url: record.url, title: record.title, name: record.name, tab: tab, isAtPinnedURL: atPinnedURL,
      folderID: record.folderID, pinnedSplitID: record.splitID)
  }

  private func snapshot(_ split: SplitRecord) -> FakePinnedSplit {
    FakePinnedSplit(
      id: split.id, isFavorite: split.spaceID == nil, spaceID: split.spaceID, folderID: split.folderID,
      profileID: split.profileID, pins: pinRecords(ofSplit: split.id).map(snapshot), ratio: split.ratio)
  }

  /// The snapshot of an order list's item.
  private func itemSnapshot(_ id: String) -> FakePinnedItem? {
    if let record = records[id] { return FakePinnedItem(pin: snapshot(record)) }
    if let split = splitRecords[id] { return FakePinnedItem(split: snapshot(split)) }
    if let folder = folderRecords[id] { return FakePinnedItem(folder: snapshot(folder)) }
    return nil
  }

  private func snapshot(_ folder: FolderRecord) -> FakeFolder {
    FakeFolder(
      id: folder.id, spaceID: folder.spaceID, name: folder.name, isOpen: isFolderOpen(folder.id),
      items: (folderOrder[folder.id] ?? []).compactMap(itemSnapshot))
  }

  private func pinsChanged(of pinID: PinID) {
    guard let record = records[pinID] else { return }
    containerChanged(spaceID: record.spaceID, profileID: record.profileID)
  }

  private func containerChanged(spaceID: SpaceID?, profileID: ProfileID) {
    if let spaceID {
      let items = self.pinnedItems(inSpace: spaceID)
      for observer in allObservers {
        observer.pinnedItemsDidChange(items, inSpace: spaceID)
      }
    } else {
      let favorites = self.favorites(ofProfile: profileID)
      for observer in allObservers {
        observer.favoritesDidChange(favorites, ofProfile: profileID)
      }
    }
  }

  private func spaceChanged(_ spaceID: SpaceID) {
    containerChanged(spaceID: spaceID, profileID: profile(ofSpace: spaceID) ?? Self.defaultProfileID)
  }

  /// Binds `tab` to the pin, as the engine does when it opens or restores it.
  func bind(_ pinID: PinID, to tab: FakeTab) {
    bound[pinID] = tab.with(spaceID: records[pinID]?.spaceID ?? "", pinID: .some(pinID), name: .some(nil))
    pinsChanged(of: pinID)
  }

  /// Keeps a bound tab's new snapshot, as when it moves window.
  func rebind(_ pinID: PinID, to tab: FakeTab) {
    bound[pinID] = tab
    pinsChanged(of: pinID)
  }

  /// The pin's tab closed; the pin stays.
  func unbind(_ pinID: PinID) {
    bound[pinID] = nil
    pinsChanged(of: pinID)
  }

  /// D5: the pin goes, and its tab, or a new one in `browser`, joins its
  /// Space's Today tabs at `index`, with its name.
  func unpin(_ pinID: PinID, toIndex index: Int, in browser: FakeBrowser) {
    guard let record = records[pinID] else { return }
    // D10: a pinned split becomes a Today split, its pages opening when they
    // aren't.
    if let splitID = record.splitID, let split = splitRecords.removeValue(forKey: splitID) {
      let spaceID = split.spaceID ?? browser.shownSpaceID
      let pins = pinRecords(ofSplit: splitID)
      let tabs = pins.map { pin in
        bound[pin.id]?.with(spaceID: spaceID, pinID: .some(nil), name: .some(pin.name))
          ?? FakeTab(
            id: newTabID(), title: pin.title, url: pin.url, spaceID: spaceID, browserID: browser.browserID,
            name: pin.name)
      }
      for tab in tabs where pageViews[tab.tabID] == nil {
        pageViews[tab.tabID] = NSView()
      }
      withOrder(spaceID: split.spaceID, profileID: split.profileID, folderID: split.folderID) {
        $0.removeAll { $0 == splitID }
      }
      for pin in pins {
        records[pin.id] = nil
        bound[pin.id] = nil
      }
      var list = self.list(spaceID)
      list.insert(contentsOf: tabs, at: max(0, min(index, list.count)))
      setList(list, inSpace: spaceID)
      if tabs.count == 2 {
        setSplit(tabs[0].tabID, tabs[1].tabID, ratio: split.ratio)
      }
      containerChanged(spaceID: split.spaceID, profileID: split.profileID)
      return
    }
    let spaceID = record.spaceID ?? browser.shownSpaceID
    let tab =
      bound[pinID]?.with(spaceID: spaceID, pinID: .some(nil), name: .some(record.name))
      ?? FakeTab(
        id: newTabID(), title: record.title, url: record.url, spaceID: spaceID, browserID: browser.browserID,
        name: record.name)
    if pageViews[tab.tabID] == nil {
      pageViews[tab.tabID] = NSView()
    }
    removeRecord(pinID)
    bound[pinID] = nil
    var tabs = list(spaceID)
    tabs.insert(tab, at: max(0, min(index, tabs.count)))
    setList(tabs, inSpace: spaceID)
    containerChanged(spaceID: record.spaceID, profileID: record.profileID)
  }

  /// Takes the record out of the store; returns its index in its folder or
  /// section.
  @discardableResult
  private func removeRecord(_ pinID: PinID) -> Int? {
    guard let record = records.removeValue(forKey: pinID) else { return nil }
    if let folderID = record.folderID {
      let index = folderOrder[folderID]?.firstIndex(of: pinID)
      folderOrder[folderID]?.removeAll { $0 == pinID }
      return index
    }
    if let spaceID = record.spaceID {
      let index = pinOrder[spaceID]?.firstIndex(of: pinID)
      pinOrder[spaceID]?.removeAll { $0 == pinID }
      return index
    }
    let index = favoriteOrder[record.profileID]?.firstIndex(of: pinID)
    favoriteOrder[record.profileID]?.removeAll { $0 == pinID }
    return index
  }

  private static func insert<T>(_ element: T, into list: inout [T], at index: Int) {
    list.insert(element, at: max(0, min(index, list.count)))
  }

  private func insertRecord(_ record: PinRecord, at index: Int) {
    records[record.id] = record
    if let folderID = record.folderID {
      Self.insert(record.id, into: &folderOrder[folderID, default: []], at: index)
    } else if let spaceID = record.spaceID {
      Self.insert(record.id, into: &pinOrder[spaceID, default: []], at: index)
    } else {
      Self.insert(record.id, into: &favoriteOrder[record.profileID, default: []], at: index)
    }
  }

  /// D3: Restore Last Closed Tab puts the newest removed pin back in place,
  /// in its folder while it exists, or else at the end of its Space's
  /// section (add-tab-folders D7).
  @discardableResult
  func restoreRemovedPin() -> PinID? {
    guard !removedPins.isEmpty else { return nil }
    var (record, index) = removedPins.removeFirst()
    if let folderID = record.folderID, folderRecords[folderID] == nil {
      record.folderID = nil
      index = Int.max
    }
    insertRecord(record, at: index)
    pinsChanged(of: record.id)
    return record.id
  }

  /// D7: Restore Last Closed Tab puts the newest deleted folder back in
  /// place, with its pins, open or closed as it was.
  @discardableResult
  func restoreRemovedFolder() -> FolderID? {
    guard !removedFolders.isEmpty else { return nil }
    let (folder, pins, index, wasClosed) = removedFolders.removeFirst()
    guard isSpace(folder.spaceID) else { return nil }
    folderRecords[folder.id] = folder
    Self.insert(folder.id, into: &pinOrder[folder.spaceID, default: []], at: index)
    if wasClosed {
      closedFolders.insert(folder.id)
    }
    for pin in pins {
      insertRecord(pin, at: Int.max)
    }
    spaceChanged(folder.spaceID)
    return folder.id
  }

  // MARK: ClairHost: pins

  func pinnedItems(inSpace spaceID: SpaceID) -> [any ClairPinnedItem] {
    (pinOrder[spaceID] ?? []).compactMap(itemSnapshot)
  }

  /// Every pinned tab of a Space, its folders' included, as snapshots.
  func pins(inSpace spaceID: SpaceID) -> [any ClairPin] {
    pinRecords(inSpace: spaceID).map(snapshot)
  }

  func favorites(ofProfile profileID: ProfileID) -> [any ClairPinnedItem] {
    (favoriteOrder[profileID] ?? []).compactMap(itemSnapshot)
  }

  /// Every favorite of a profile, a favorited split's two included.
  func favoritePins(ofProfile profileID: ProfileID) -> [any ClairPin] {
    favoriteRecords(ofProfile: profileID).map(snapshot)
  }

  // MARK: Pinned and favorited splits (add-split-view design D10)

  /// The order list holding a split's or pin's place.
  private func withOrder(
    spaceID: SpaceID?, profileID: ProfileID, folderID: FolderID?, _ body: (inout [String]) -> Void
  ) {
    if let folderID {
      body(&folderOrder[folderID, default: []])
    } else if let spaceID {
      body(&pinOrder[spaceID, default: []])
    } else {
      body(&favoriteOrder[profileID, default: []])
    }
  }

  /// Adds a pinned or favorited split of two new pins, as the store would,
  /// without tabs, and returns its pins' IDs.
  @discardableResult
  func addSplit(
    _ leading: (url: String, title: String), _ trailing: (url: String, title: String),
    inSpace spaceID: SpaceID? = FakeHost.homeID, folder folderID: FolderID? = nil,
    profile profileID: ProfileID = FakeHost.defaultProfileID, ratio: Double = 0.5, at index: Int = Int.max
  ) -> [PinID] {
    let splitID = "split-\(nextSplit)"
    nextSplit += 1
    let spaceID = folderID.flatMap { folderRecords[$0]?.spaceID } ?? spaceID
    splitRecords[splitID] = SplitRecord(
      id: splitID, spaceID: spaceID, profileID: profileID, folderID: spaceID == nil ? nil : folderID, ratio: ratio)
    var ids: [PinID] = []
    for (pane, page) in [leading, trailing].enumerated() {
      let pinID = "pin-\(nextPin)"
      nextPin += 1
      records[pinID] = PinRecord(
        id: pinID, spaceID: spaceID, profileID: profileID, url: page.url, title: page.title,
        folderID: spaceID == nil ? nil : folderID, splitID: splitID, splitIndex: pane)
      ids.append(pinID)
    }
    withOrder(spaceID: spaceID, profileID: profileID, folderID: spaceID == nil ? nil : folderID) {
      Self.insert(splitID, into: &$0, at: index)
    }
    containerChanged(spaceID: spaceID, profileID: profileID)
    return ids
  }

  /// D10: Separate Tabs on a pinned or favorited split: its pins take its
  /// place, in pane order.
  func separatePinnedSplit(_ splitID: PinnedSplitID) {
    commands.append("separatePinnedSplit \(splitID)")
    guard let split = splitRecords.removeValue(forKey: splitID) else { return }
    let pins = pinRecords(ofSplit: splitID)
    for pin in pins {
      records[pin.id]?.splitID = nil
      records[pin.id]?.splitIndex = 0
    }
    withOrder(spaceID: split.spaceID, profileID: split.profileID, folderID: split.folderID) { order in
      guard let at = order.firstIndex(of: splitID) else { return }
      order.replaceSubrange(at...at, with: pins.map(\.id))
    }
    // Their open tabs leave the split.
    if pins.count == 2, let lead = bound[pins[0].id], let trail = bound[pins[1].id], lead.splitPartnerID == trail.tabID {
      clearSplit(lead.tabID)
    }
    containerChanged(spaceID: split.spaceID, profileID: split.profileID)
  }

  /// D10, Arc: one pane of a pinned split closed: the other pin takes the
  /// split's place, and `pinID` goes.
  func takeOutOfSplit(_ pinID: PinID) {
    guard let splitID = records[pinID]?.splitID, let split = splitRecords.removeValue(forKey: splitID),
      let other = pinRecords(ofSplit: splitID).first(where: { $0.id != pinID })
    else { return }
    records[pinID] = nil
    records[other.id]?.splitID = nil
    records[other.id]?.splitIndex = 0
    withOrder(spaceID: split.spaceID, profileID: split.profileID, folderID: split.folderID) { order in
      if let at = order.firstIndex(of: splitID) { order[at] = other.id }
    }
    containerChanged(spaceID: split.spaceID, profileID: split.profileID)
  }

  /// D10: pins a split of two Today tabs as one item.
  private func pinSplit(lead: FakeTab, trail: FakeTab, folder folderID: FolderID?, at index: Int, favorite: Bool) {
    guard let profileID = profile(ofSpace: lead.spaceID) else { return }
    let ids = addSplit(
      (lead.url?.absoluteString ?? lead.urlText, lead.title), (trail.url?.absoluteString ?? trail.urlText, trail.title),
      inSpace: favorite ? nil : lead.spaceID, folder: favorite ? nil : folderID, profile: profileID,
      ratio: lead.splitRatio, at: index)
    setList(
      list(lead.spaceID).filter { ![lead.tabID, trail.tabID, lead.peekID, trail.peekID].contains($0.tabID) },
      inSpace: lead.spaceID)
    bind(ids[0], to: lead)
    bind(ids[1], to: trail)
  }

  // MARK: Open splits (add-split-view design D1, D2)

  /// Makes `lead` and `trail` a split with `ratio`: their snapshots name
  /// each other, and in a Today list the trailing pane and its Peek follow
  /// the leading pane and its Peek.
  func setSplit(_ leadID: TabID, _ trailID: TabID, ratio: Double = 0.5) {
    guard let lead = tab(leadID), let trail = tab(trailID) else { return }
    replaceSilently(lead.with(splitPartnerID: trailID, isLeadingPane: true, splitRatio: ratio))
    replaceSilently(trail.with(splitPartnerID: leadID, isLeadingPane: false, splitRatio: ratio))
    keepTogether(leadID, trailID)
  }

  /// Ends a tab's split: both tabs stay where they are.
  func clearSplit(_ tabID: TabID) {
    guard let tab = tab(tabID) else { return }
    let partner = self.tab(tab.splitPartnerID)
    replaceSilently(tab.unsplit())
    if let partner {
      replaceSilently(partner.unsplit())
    }
    spaceOrPinsChanged(tab)
    if let partner { spaceOrPinsChanged(partner) }
  }

  /// Sets a split's ratio.
  func setSplitRatio(_ ratio: Double, of tabID: TabID) {
    guard let tab = tab(tabID), let partner = self.tab(tab.splitPartnerID) else { return }
    replaceSilently(tab.with(splitRatio: ratio))
    replaceSilently(partner.with(splitRatio: ratio))
    spaceOrPinsChanged(tab)
    spaceOrPinsChanged(partner)
  }

  /// Swaps a split's panes.
  func swapSplit(of tabID: TabID) {
    guard let tab = tab(tabID), let partner = self.tab(tab.splitPartnerID) else { return }
    let lead = tab.isLeadingPane ? tab : partner
    let trail = tab.isLeadingPane ? partner : tab
    // A pinned split's pins follow their panes.
    if let a = lead.pinID, let b = trail.pinID, let split = records[a]?.splitID, records[b]?.splitID == split {
      records[a]?.splitIndex = 1
      records[b]?.splitIndex = 0
    }
    setSplit(trail.tabID, lead.tabID, ratio: lead.splitRatio)
  }

  /// Replaces a tab's snapshot in its list or binding without a push.
  private func replaceSilently(_ tab: FakeTab) {
    if let pinID = tab.pinID, bound[pinID]?.tabID == tab.tabID {
      bound[pinID] = tab
      return
    }
    replaceQuietly(tab)
  }

  /// Pushes the list or pins showing a tab.
  private func spaceOrPinsChanged(_ tab: FakeTab) {
    if let pinID = tab.pinID, bound[pinID]?.tabID == tab.tabID {
      pinsChanged(of: pinID)
    } else {
      setList(list(tab.spaceID), inSpace: tab.spaceID)
    }
  }

  /// D7: a Today split is one row: the trailing pane's family right after
  /// the leading pane's.
  private func keepTogether(_ leadID: TabID, _ trailID: TabID) {
    guard let lead = tab(leadID), let trail = tab(trailID) else { return }
    let leadToday = list(lead.spaceID).contains { $0.tabID == leadID }
    let trailToday = list(trail.spaceID).contains { $0.tabID == trailID }
    if leadToday && trailToday && lead.spaceID == trail.spaceID {
      var tabs = list(lead.spaceID)
      let family = tabs.filter { $0.tabID == trailID || ($0.peekParentID == trailID && trail.peekID == $0.tabID) }
      tabs.removeAll { candidate in family.contains { $0.tabID == candidate.tabID } }
      if let at = tabs.firstIndex(where: { $0.tabID == leadID }) {
        let after = lead.peekID != ClairTabIDNone && tabs.indices.contains(at + 1) && tabs[at + 1].tabID == lead.peekID
        tabs.insert(contentsOf: family, at: at + (after ? 2 : 1))
      }
      setList(tabs, inSpace: lead.spaceID)
    } else {
      spaceOrPinsChanged(lead)
      spaceOrPinsChanged(trail)
    }
  }

  /// D5: a Today tab becomes a pin of its Space, in `folderID`, or of its
  /// profile's favorites, keeping its page and name.
  private func pin(tab tabID: TabID, inFolder folderID: FolderID?, at index: Int, favorite: Bool) {
    guard let tab = tab(tabID), tab.pinID == nil, isSpace(tab.spaceID), tab.peekParentID == ClairTabIDNone,
      let profileID = profile(ofSpace: tab.spaceID)
    else { return }
    // A folder of another Space is ignored.
    if let folderID, folderRecords[folderID]?.spaceID != tab.spaceID || favorite { return }
    // add-split-view D10: a split of two Today tabs is pinned as one; a split
    // with a pinned tab or favorite isn't.
    if let partner = self.tab(tab.splitPartnerID) {
      guard partner.pinID == nil, partner.spaceID == tab.spaceID else { return }
      let lead = tab.isLeadingPane ? tab : partner
      pinSplit(lead: lead, trail: lead === tab ? partner : tab, folder: folderID, at: index, favorite: favorite)
      return
    }
    let pinID = "pin-\(nextPin)"
    nextPin += 1
    let record = PinRecord(
      id: pinID, spaceID: favorite ? nil : tab.spaceID, profileID: profileID,
      url: tab.url?.absoluteString ?? tab.urlText, title: tab.title, name: tab.name, folderID: folderID)
    insertRecord(record, at: index)
    setList(list(tab.spaceID).filter { $0.tabID != tabID && $0.peekParentID != tabID }, inSpace: tab.spaceID)
    bind(pinID, to: tab)
  }

  func pin(tab tabID: TabID, inFolder folderID: FolderID?, at index: Int) {
    commands.append(folderID.map { "pin \(tabID) \($0) \(index)" } ?? "pin \(tabID) \(index)")
    pin(tab: tabID, inFolder: folderID, at: index, favorite: false)
  }

  func favorite(tab tabID: TabID, at index: Int) {
    commands.append("favorite \(tabID) \(index)")
    pin(tab: tabID, inFolder: nil, at: index, favorite: true)
  }

  func movePin(_ pinID: PinID, toSpace spaceID: SpaceID, folder folderID: FolderID?, at index: Int) {
    commands.append(
      folderID.map { "movePin \(pinID) \(spaceID) \($0) \(index)" } ?? "movePin \(pinID) \(spaceID) \(index)")
    guard var record = records[pinID], isSpace(spaceID), let profileID = profile(ofSpace: spaceID) else { return }
    if let folderID, folderRecords[folderID]?.spaceID != spaceID { return }
    if let splitID = record.splitID {
      moveSplit(splitID, toSpace: spaceID, folder: folderID, profile: profileID, at: index)
      return
    }
    let from = (record.spaceID, record.profileID)
    removeRecord(pinID)
    record.spaceID = spaceID
    record.folderID = folderID
    let changedProfile = record.profileID != profileID
    record.profileID = profileID
    insertRecord(record, at: index)
    if var tab = bound[pinID] {
      if changedProfile {
        // add-profiles D9: reopened in the other profile, with a new ID.
        tab = FakeTab(
          id: newTabID(), title: tab.title, url: tab.url?.absoluteString, spaceID: spaceID, browserID: tab.browserID,
          pinID: pinID)
        pageViews[tab.tabID] = NSView()
      }
      bound[pinID] = tab.with(spaceID: spaceID)
    }
    if from.0 != spaceID {
      containerChanged(spaceID: from.0, profileID: from.1)
    }
    pinsChanged(of: pinID)
  }

  /// D10: a split moves whole, in the same profile.
  private func moveSplit(
    _ splitID: PinnedSplitID, toSpace spaceID: SpaceID?, folder folderID: FolderID?, profile profileID: ProfileID,
    at index: Int
  ) {
    guard var split = splitRecords[splitID] else { return }
    let from = (split.spaceID, split.profileID)
    withOrder(spaceID: split.spaceID, profileID: split.profileID, folderID: split.folderID) {
      $0.removeAll { $0 == splitID }
    }
    split.spaceID = spaceID
    split.folderID = spaceID == nil ? nil : folderID
    split.profileID = profileID
    splitRecords[splitID] = split
    withOrder(spaceID: split.spaceID, profileID: profileID, folderID: split.folderID) {
      Self.insert(splitID, into: &$0, at: index)
    }
    for pin in pinRecords(ofSplit: splitID) {
      records[pin.id]?.spaceID = spaceID
      records[pin.id]?.folderID = split.folderID
      records[pin.id]?.profileID = profileID
      if let tab = bound[pin.id] {
        bound[pin.id] = tab.with(spaceID: spaceID ?? "")
      }
    }
    if from.0 != spaceID {
      containerChanged(spaceID: from.0, profileID: from.1)
    }
    containerChanged(spaceID: spaceID, profileID: profileID)
  }

  func movePin(_ pinID: PinID, toFavoritesAt index: Int) {
    commands.append("movePinToFavorites \(pinID) \(index)")
    guard var record = records[pinID] else { return }
    if let splitID = record.splitID {
      moveSplit(splitID, toSpace: nil, folder: nil, profile: record.profileID, at: index)
      return
    }
    let from = (record.spaceID, record.profileID)
    removeRecord(pinID)
    record.spaceID = nil
    record.folderID = nil
    insertRecord(record, at: index)
    if let tab = bound[pinID] {
      bound[pinID] = tab.with(spaceID: "")
    }
    if from.0 != nil {
      containerChanged(spaceID: from.0, profileID: from.1)
    }
    pinsChanged(of: pinID)
  }

  func removePin(_ pinID: PinID) {
    commands.append("removePin \(pinID)")
    // D10: a split's pin goes with its split and the other pin.
    if let splitID = records[pinID]?.splitID, let split = splitRecords.removeValue(forKey: splitID) {
      let pins = pinRecords(ofSplit: splitID)
      withOrder(spaceID: split.spaceID, profileID: split.profileID, folderID: split.folderID) {
        $0.removeAll { $0 == splitID }
      }
      let tabs = pins.compactMap { bound.removeValue(forKey: $0.id) }
      for pin in pins { records[pin.id] = nil }
      containerChanged(spaceID: split.spaceID, profileID: split.profileID)
      for tab in tabs {
        guard let browser = browser(tab.browserID) else { continue }
        let today = tab.with(spaceID: split.spaceID ?? browser.shownSpaceID, pinID: .some(nil))
        setList([today] + list(today.spaceID), inSpace: today.spaceID)
        browser.close(tab: tab.tabID)
      }
      return
    }
    guard let record = records[pinID], let index = removeRecord(pinID) else { return }
    removedPins.insert((record, index), at: 0)
    let tab = bound.removeValue(forKey: pinID)
    containerChanged(spaceID: record.spaceID, profileID: record.profileID)
    // Its page closes through the close flow, as a Today tab.
    if let tab, let browser = browser(tab.browserID) {
      let today = tab.with(spaceID: record.spaceID ?? browser.shownSpaceID, pinID: .some(nil))
      setList([today] + list(today.spaceID), inSpace: today.spaceID)
      browser.close(tab: tab.tabID)
    }
  }

  // MARK: ClairHost: folders (add-tab-folders design D2)

  func createFolder(named name: String, inSpace spaceID: SpaceID, at index: Int) -> FolderID? {
    commands.append("createFolder \(name) \(spaceID) \(index)")
    let name = SpacesLogic.cleanName(name)
    guard !name.isEmpty, isSpace(spaceID) else { return nil }
    let folderID = "folder-\(nextFolder)"
    nextFolder += 1
    folderRecords[folderID] = FolderRecord(id: folderID, spaceID: spaceID, name: name)
    folderOrder[folderID] = []
    Self.insert(folderID, into: &pinOrder[spaceID, default: []], at: index)
    spaceChanged(spaceID)
    return folderID
  }

  func renameFolder(_ folderID: FolderID, to name: String) {
    commands.append("renameFolder \(folderID) \(name)")
    let name = SpacesLogic.cleanName(name)
    guard !name.isEmpty, var folder = folderRecords[folderID] else { return }
    folder.name = name
    folderRecords[folderID] = folder
    spaceChanged(folder.spaceID)
  }

  func setFolder(_ folderID: FolderID, open: Bool) {
    commands.append("setFolder \(folderID) \(open)")
    guard let folder = folderRecords[folderID] else { return }
    if open {
      closedFolders.remove(folderID)
    } else {
      closedFolders.insert(folderID)
    }
    spaceChanged(folder.spaceID)
  }

  func moveFolder(_ folderID: FolderID, toSpace spaceID: SpaceID, at index: Int) {
    commands.append("moveFolder \(folderID) \(spaceID) \(index)")
    guard var folder = folderRecords[folderID], isSpace(spaceID), let profileID = profile(ofSpace: spaceID)
    else { return }
    let from = folder.spaceID
    pinOrder[from]?.removeAll { $0 == folderID }
    folder.spaceID = spaceID
    folderRecords[folderID] = folder
    Self.insert(folderID, into: &pinOrder[spaceID, default: []], at: index)
    // D1, D11: its pins follow it, and their tabs as Move to Space moves them.
    for pinID in folderOrder[folderID] ?? [] {
      guard var record = records[pinID] else { continue }
      let changedProfile = record.profileID != profileID
      record.spaceID = spaceID
      record.profileID = profileID
      records[pinID] = record
      if var tab = bound[pinID] {
        if changedProfile {
          tab = FakeTab(
            id: newTabID(), title: tab.title, url: tab.url?.absoluteString, spaceID: spaceID,
            browserID: tab.browserID, pinID: pinID)
          pageViews[tab.tabID] = NSView()
        }
        bound[pinID] = tab.with(spaceID: spaceID)
        if let browser = browser(tab.browserID), browser.isActiveRow(tab.tabID) {
          browser.followActiveTab()
        }
      }
    }
    if from != spaceID {
      spaceChanged(from)
    }
    spaceChanged(spaceID)
  }

  func duplicateFolder(_ folderID: FolderID) {
    commands.append("duplicateFolder \(folderID)")
    guard let folder = folderRecords[folderID], let index = pinOrder[folder.spaceID]?.firstIndex(of: folderID)
    else { return }
    let copyID = "folder-\(nextFolder)"
    nextFolder += 1
    folderRecords[copyID] = FolderRecord(id: copyID, spaceID: folder.spaceID, name: folder.name)
    folderOrder[copyID] = []
    Self.insert(copyID, into: &pinOrder[folder.spaceID, default: []], at: index + 1)
    for record in pinRecords(inFolder: folderID) {
      let copy = PinRecord(
        id: "pin-\(nextPin)", spaceID: record.spaceID, profileID: record.profileID, url: record.url,
        title: record.title, name: record.name, folderID: copyID)
      nextPin += 1
      insertRecord(copy, at: Int.max)
    }
    spaceChanged(folder.spaceID)
  }

  func deleteFolder(_ folderID: FolderID) {
    commands.append("deleteFolder \(folderID)")
    guard let folder = folderRecords.removeValue(forKey: folderID),
      let index = pinOrder[folder.spaceID]?.firstIndex(of: folderID)
    else { return }
    pinOrder[folder.spaceID]?.remove(at: index)
    let pins = (folderOrder.removeValue(forKey: folderID) ?? []).compactMap { records.removeValue(forKey: $0) }
    removedFolders.insert((folder, pins, index, closedFolders.remove(folderID) != nil), at: 0)
    let tabs = pins.compactMap { bound.removeValue(forKey: $0.id) }
    spaceChanged(folder.spaceID)
    // D7: then their pages close through the close flow, as Today tabs.
    for tab in tabs {
      guard let browser = browser(tab.browserID) else { continue }
      let today = tab.with(spaceID: folder.spaceID, pinID: .some(nil))
      setList([today] + list(today.spaceID), inSpace: today.spaceID)
      browser.close(tab: tab.tabID)
    }
  }

  func closeTabs(inFolder folderID: FolderID) {
    commands.append("closeTabsInFolder \(folderID)")
    for record in pinRecords(inFolder: folderID) {
      if let tab = bound[record.id] {
        browser(tab.browserID)?.close(tab: tab.tabID)
      }
    }
  }

  func turnFolderIntoSpace(_ folderID: FolderID) -> SpaceID? {
    commands.append("turnFolderIntoSpace \(folderID)")
    guard let folder = folderRecords[folderID], let profileID = profile(ofSpace: folder.spaceID),
      let spaceID = createSpace(named: folder.name, icon: nil, profile: profileID)
    else { return nil }
    // D8: its pins become the new Space's, in order, with their tabs.
    for record in pinRecords(inFolder: folderID) {
      movePin(record.id, toSpace: spaceID, folder: nil, at: Int.max)
      if let tab = bound[record.id], let browser = browser(tab.browserID), browser.isActiveRow(tab.tabID) {
        browser.followActiveTab()
      }
    }
    folderRecords[folderID] = nil
    folderOrder[folderID] = nil
    closedFolders.remove(folderID)
    pinOrder[folder.spaceID]?.removeAll { $0 == folderID }
    spaceChanged(folder.spaceID)
    return spaceID
  }

  func returnToPinnedURL(_ pinID: PinID) {
    commands.append("returnToPinnedURL \(pinID)")
    guard let record = records[pinID], let tab = bound[pinID] else { return }
    bound[pinID] = tab.with(title: record.title, url: record.url, canGoBack: true)
    pinsChanged(of: pinID)
  }

  func replacePinnedURLWithCurrent(_ pinID: PinID) {
    commands.append("replacePinnedURL \(pinID)")
    guard var record = records[pinID], let tab = bound[pinID] else { return }
    record.url = tab.url?.absoluteString ?? tab.urlText
    record.title = tab.title
    records[pinID] = record
    pinsChanged(of: pinID)
  }

  func setPinnedURL(_ url: URL, forPin pinID: PinID) {
    commands.append("setPinnedURL \(pinID) \(url.absoluteString)")
    guard var record = records[pinID] else { return }
    record.url = url.absoluteString
    records[pinID] = record
    pinsChanged(of: pinID)
  }

  func setName(_ name: String?, forTab tabID: TabID) {
    commands.append("nameTab \(tabID) \(name ?? "-")")
    guard let tab = tab(tabID) else { return }
    if let pinID = tab.pinID, bound[pinID]?.tabID == tabID {
      setName(name, forPin: pinID)
      return
    }
    replace(tab.with(name: .some(name?.isEmpty == true ? nil : name)))
  }

  func setName(_ name: String?, forPin pinID: PinID) {
    commands.append("namePin \(pinID) \(name ?? "-")")
    guard var record = records[pinID] else { return }
    record.name = name?.isEmpty == true ? nil : name
    records[pinID] = record
    pinsChanged(of: pinID)
  }

  func clearToday(inSpace spaceID: SpaceID) {
    commands.append("clearToday \(spaceID)")
    for row in TabListLogic.rows(list(spaceID)) {
      browser(row.browserID)?.close(tab: row.tabID)
    }
  }

  /// Replaces a Space's list and tells the observers.
  func setList(_ tabs: [FakeTab], inSpace spaceID: SpaceID) {
    lists[spaceID] = tabs
    for observer in allObservers {
      observer.tabsDidChange(tabs, inSpace: spaceID)
    }
  }

  /// Replaces a tab's snapshot in its list and tells the observers.
  func replace(_ tab: FakeTab) {
    if let pinID = tab.pinID, bound[pinID]?.tabID == tab.tabID {
      bound[pinID] = tab
      for observer in allObservers {
        observer.tabDidChange(tab)
      }
      return
    }
    guard var tabs = lists[tab.spaceID], let index = tabs.firstIndex(where: { $0.tabID == tab.tabID }) else {
      return
    }
    tabs[index] = tab
    lists[tab.spaceID] = tabs
    for observer in allObservers {
      observer.tabDidChange(tab)
    }
  }

  /// Replaces a tab's snapshot without telling anyone, as when a Peek's
  /// parent changes in the same list update.
  func replaceQuietly(_ tab: FakeTab) {
    guard var tabs = lists[tab.spaceID], let index = tabs.firstIndex(where: { $0.tabID == tab.tabID }) else {
      return
    }
    tabs[index] = tab
    lists[tab.spaceID] = tabs
  }

  private var allObservers: [any ClairSpacesObserver] {
    observers.allObjects.compactMap { $0 as? any ClairSpacesObserver }
  }

  private func spacesChanged() {
    for observer in allObservers {
      observer.spacesDidChange(spaces)
    }
  }

  private func profilesChanged() {
    for observer in allObservers {
      observer.profilesDidChange(profiles)
    }
  }

  // MARK: ClairHost: Spaces

  func tabs(inSpace spaceID: SpaceID) -> [any ClairTab] {
    list(spaceID)
  }

  func addObserver(_ observer: any ClairSpacesObserver) {
    observers.add(observer)
  }

  func createSpace(named name: String, icon: String?, profile profileID: ProfileID) -> SpaceID? {
    commands.append(profileID == Self.defaultProfileID ? "create \(name)" : "create \(name) \(profileID)")
    guard !name.isEmpty, isProfile(profileID) else { return nil }
    let spaceID = "space-\(nextSpace)"
    nextSpace += 1
    spaces.append(FakeSpace(id: spaceID, name: name, icon: icon, profile: profileID))
    spacesChanged()
    return spaceID
  }

  /// Creates a Space on the default profile, as the tests that predate
  /// profiles do.
  func createSpace(named name: String, icon: String?) -> SpaceID? {
    createSpace(named: name, icon: icon, profile: Self.defaultProfileID)
  }

  private func update(_ spaceID: SpaceID, _ change: (FakeSpace) -> FakeSpace) {
    guard let index = spaces.firstIndex(where: { $0.spaceID == spaceID }), let space = spaces[index] as? FakeSpace
    else { return }
    spaces[index] = change(space)
    spacesChanged()
  }

  func renameSpace(_ spaceID: SpaceID, to name: String) {
    commands.append("rename \(spaceID) \(name)")
    guard !name.isEmpty else { return }
    update(spaceID) { $0.with(name: name) }
  }

  func setIcon(_ icon: String?, forSpace spaceID: SpaceID) {
    commands.append("icon \(spaceID) \(icon ?? "-")")
    update(spaceID) { $0.with(icon: .some(icon)) }
  }

  func moveSpace(_ spaceID: SpaceID, to index: Int) {
    commands.append("moveSpace \(spaceID) \(index)")
    guard let from = spaces.firstIndex(where: { $0.spaceID == spaceID }) else { return }
    let space = spaces.remove(at: from)
    spaces.insert(space, at: max(0, min(index, spaces.count)))
    spacesChanged()
  }

  func deleteSpace(_ spaceID: SpaceID) {
    commands.append("delete \(spaceID)")
    guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.spaceID == spaceID }) else { return }
    // D7: each window showing it shows the Space before it, or after it.
    let neighbour = spaces[index > 0 ? index - 1 : 1].spaceID
    for browser in allBrowsers where browser.shownSpaceID == spaceID {
      browser.showSpace(neighbour)
    }
    for tab in list(spaceID) {
      browser(tab.browserID)?.closeTabNow(tab.tabID)
    }
    // add-pinned-tabs-and-favorites D9: its pinned tabs go, for good, and
    // its folders with them (add-tab-folders).
    for record in pinRecords(inSpace: spaceID) {
      if let tab = bound[record.id] {
        browser(tab.browserID)?.closeTabNow(tab.tabID)
      }
      records[record.id] = nil
      bound[record.id] = nil
    }
    for folder in folderRecords(inSpace: spaceID) {
      folderRecords[folder.id] = nil
      folderOrder[folder.id] = nil
      closedFolders.remove(folder.id)
    }
    removedFolders.removeAll { $0.folder.spaceID == spaceID }
    pinOrder[spaceID] = nil
    // add-link-rules D1: its link rules go with it.
    rules.removeAll { $0.spaceID == spaceID }
    spaces.remove(at: index)
    lists[spaceID] = nil
    if lastShownSpaceID == spaceID {
      lastShownSpaceID = neighbour
    }
    spacesChanged()
  }

  func move(tab tabID: TabID, toSpace spaceID: SpaceID) {
    commands.append("moveToSpace \(tabID) \(spaceID)")
    if let tab = tab(tabID), let pinID = tab.pinID, bound[pinID]?.tabID == tabID {
      // add-pinned-tabs-and-favorites D5: at the end of its pinned tabs.
      movePin(pinID, toSpace: spaceID, folder: nil, at: Int.max)
      if let browser = browser(tab.browserID), browser.isActiveRow(tabID) {
        browser.followActiveTab()
      }
      return
    }
    guard isSpace(spaceID), var tab = tab(tabID), isSpace(tab.spaceID), let browser = browser(tab.browserID)
    else { return }
    // A Peek moves with its parent.
    if tab.peekParentID != ClairTabIDNone, let parent = self.tab(tab.peekParentID) {
      tab = parent
    }
    guard tab.spaceID != spaceID else { return }
    operation {
      let wasActive = browser.isActiveRow(tab.tabID)
      if profile(ofSpace: tab.spaceID) != profile(ofSpace: spaceID) {
        // add-profiles D9: a page can't change profile; it reopens at its URL
        // at the top of the other Space, without its Peek.
        let reopened = reopen(tab, inSpace: spaceID, at: 0, by: browser)
        if wasActive {
          browser.setActive(reopened.tabID)
        }
        browser.closeReopened(tab.tabID)
      } else {
        // The tab and its Peek go to the top of the other list (add-spaces D7).
        let source = tab.spaceID
        let family = list(source).filter { $0.tabID == tab.tabID || ($0.peekParentID == tab.tabID && tab.peekID == $0.tabID) }
        let moved = family.map { $0.with(spaceID: spaceID) }
        setList(list(source).filter { candidate in !family.contains { $0.tabID == candidate.tabID } }, inSpace: source)
        setList(moved + list(spaceID), inSpace: spaceID)
        // add-profiles D9: the window follows its active tab; a window with a
        // still of it picks its next tab, as if it had closed there.
        if wasActive {
          browser.followActiveTab()
        }
        tabClosed(tab.tabID)
      }
    }
  }

  /// D9: opens `tab`'s URL as a new tab of `spaceID` at `index` in its list,
  /// in the window holding it, and returns it.
  private func reopen(_ tab: FakeTab, inSpace spaceID: SpaceID, at index: Int, by browser: FakeBrowser) -> FakeTab {
    let reopened = FakeTab(
      id: newTabID(), title: tab.title, url: tab.url?.absoluteString, spaceID: spaceID, browserID: browser.browserID)
    pageViews[reopened.tabID] = NSView()
    var tabs = list(spaceID)
    tabs.insert(reopened, at: min(index, tabs.count))
    setList(tabs, inSpace: spaceID)
    return reopened
  }

  // MARK: ClairHost: Profiles (add-profiles design D1, D9, D11)

  func isProfile(_ profileID: ProfileID) -> Bool {
    profiles.contains { $0.profileID == profileID }
  }

  func createProfile(named name: String, completion: @escaping (ProfileID?) -> Void) {
    commands.append("createProfile \(name)")
    let name = SpacesLogic.cleanName(name)
    guard !name.isEmpty else {
      completion(nil)
      return
    }
    let create = { [weak self] in
      guard let self else { return }
      let profileID = "Profile \(nextProfile)"
      nextProfile += 1
      profiles.append(FakeProfile(id: profileID, name: name))
      profilesChanged()
      completion(profileID)
    }
    if createsProfilesAtOnce {
      create()
    } else {
      pendingProfileCompletions.append(create)
    }
  }

  func renameProfile(_ profileID: ProfileID, to name: String) {
    commands.append("renameProfile \(profileID) \(name)")
    let name = SpacesLogic.cleanName(name)
    guard !name.isEmpty, let index = profiles.firstIndex(where: { $0.profileID == profileID }) else { return }
    profiles[index] = FakeProfile(id: profileID, name: name)
    profilesChanged()
  }

  func deleteProfile(_ profileID: ProfileID) {
    commands.append("deleteProfile \(profileID)")
    // D7: only a profile no Space uses.
    guard !spaces.contains(where: { $0.profileID == profileID }) else { return }
    profiles.removeAll { $0.profileID == profileID }
    downloadSettings[profileID] = nil
    for pinID in favoriteOrder[profileID] ?? [] {
      records[pinID] = nil
      bound[pinID] = nil
    }
    favoriteOrder[profileID] = nil
    profilesChanged()
  }

  func setProfile(_ profileID: ProfileID, forSpace spaceID: SpaceID) {
    commands.append("setProfile \(spaceID) \(profileID)")
    guard isProfile(profileID), let current = profile(ofSpace: spaceID), current != profileID else { return }
    operation {
      update(spaceID) { $0.with(profile: profileID) }
      // D9: each tab reopens at its URL, in order, without its Peek; the tab
      // reopened from a window's active row becomes its active tab.
      let rows = TabListLogic.rows(list(spaceID)).compactMap { tab($0.tabID) }
      for (index, row) in rows.enumerated() {
        guard let browser = browser(row.browserID) else { continue }
        let wasActive = browser.isActiveRow(row.tabID)
        let reopened = reopen(row, inSpace: spaceID, at: index, by: browser)
        if wasActive {
          browser.setActive(reopened.tabID)
        }
        browser.closeReopened(row.tabID)
      }
    }
  }

  private static let downloadsFolder = URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)

  func downloadSettings(forProfile profileID: ProfileID, completion: @escaping (URL?, Bool) -> Void) {
    guard isProfile(profileID) else {
      completion(nil, false)
      return
    }
    let settings = downloadSettings[profileID] ?? (Self.downloadsFolder, false)
    completion(settings.directory, settings.asks)
  }

  func setDownloadDirectory(_ directory: URL, forProfile profileID: ProfileID) {
    commands.append("downloadDirectory \(profileID) \(directory.path)")
    guard isProfile(profileID) else { return }
    downloadSettings[profileID] = (directory, false)
  }

  func setAsksWhereToSave(_ asks: Bool, forProfile profileID: ProfileID) {
    commands.append("asksWhereToSave \(profileID) \(asks)")
    guard isProfile(profileID) else { return }
    let directory = downloadSettings[profileID]?.directory ?? Self.downloadsFolder
    downloadSettings[profileID] = (directory, asks)
  }

  func open(_ url: URL, inProfile profileID: ProfileID) {
    openedURLsInProfiles.append((url, profileID))
  }

  // MARK: ClairHost: Link rules (add-link-rules design D1, D3, D4)

  var linkRules: [any ClairLinkRule] { rules }

  /// Replaces the rules with copies, keeping their order and dropping those
  /// the store wouldn't keep: an invalid text, an unknown Space, or a repeat
  /// of an earlier rule's match and text.
  func replaceLinkRules(_ newRules: [any ClairLinkRule]) {
    linkRuleSaves += 1
    var kept: [FakeLinkRule] = []
    for rule in newRules {
      let text = rule.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard isValidLinkRuleText(text), isSpace(rule.spaceID),
        !kept.contains(where: { $0.match == rule.match && $0.text == text })
      else { continue }
      kept.append(FakeLinkRule(rule.match, text, in: rule.spaceID))
    }
    rules = kept
  }

  /// D3's "reading a text", with `URLComponents` in place of `GURL`: trimmed,
  /// not empty and without whitespace, then, with `https://` in front when it
  /// has no scheme, an http or https URL with a host.
  func isValidLinkRuleText(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
    let hasScheme = trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil
    guard let url = URLComponents(string: hasScheme ? trimmed : "https://" + trimmed),
      let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
      let host = url.host, !host.isEmpty
    else { return false }
    return true
  }

  /// Sets the rules directly, as rules stored by an earlier launch.
  func storeLinkRules(_ stored: [FakeLinkRule]) {
    rules = stored
  }
}

/// A stand-in for Chromium's bookmark snapshot.
final class FakeBookmark: NSObject, ClairBookmark {
  let bookmarkID: BookmarkID
  let title: String
  let url: URL?
  let folderID: BookmarkFolderID
  let isNew: Bool

  init(id: BookmarkID, title: String, url: String?, folderID: BookmarkFolderID, isNew: Bool = false) {
    bookmarkID = id
    self.title = title
    self.url = url.flatMap(URL.init(string:))
    self.folderID = folderID
    self.isNew = isNew
  }
}

/// A stand-in for Chromium's bookmark folder snapshot.
final class FakeBookmarkFolder: NSObject, ClairBookmarkFolder {
  let folderID: BookmarkFolderID
  let title: String
  let depth: Int

  init(id: BookmarkFolderID, title: String, depth: Int) {
    folderID = id
    self.title = title
    self.depth = depth
  }
}

/// A stand-in for a profile's `BookmarkModel`, with the rules of
/// add-bookmarks-menu design D3: Other Bookmarks and its folders are the
/// folders a bookmark can be saved in, new folders go at the end of Other
/// Bookmarks, and an unknown ID does nothing. Tests seed it with `add`.
final class FakeBookmarkStore {
  /// Chromium's IDs for its permanent folders.
  static let barID: BookmarkFolderID = 1
  static let otherID: BookmarkFolderID = 2

  struct Node {
    let id: Int64
    var title: String
    /// A bookmark's URL, or nil for a folder.
    var url: String?
    var parent: Int64
  }

  private(set) var nodes: [Int64: Node] = [:]
  private var children: [Int64: [Int64]] = [barID: [], otherID: []]
  private var nextID: Int64 = 3
  /// Every change ClairUI asked for, in order, such as "remove 4".
  private(set) var commands: [String] = []

  /// Adds a bookmark at the end of `folder` and returns its ID.
  @discardableResult
  func add(_ title: String, url: String, in folder: BookmarkFolderID = otherID) -> BookmarkID {
    insert(Node(id: nextID, title: title, url: url, parent: folder))
  }

  /// Adds a folder at the end of `folder` and returns its ID.
  @discardableResult
  func addFolder(_ title: String, in folder: BookmarkFolderID = otherID) -> BookmarkFolderID {
    let id = insert(Node(id: nextID, title: title, url: nil, parent: folder))
    children[id] = []
    return id
  }

  private func insert(_ node: Node) -> Int64 {
    nodes[node.id] = node
    children[node.parent, default: []].append(node.id)
    nextID += 1
    return node.id
  }

  /// A bookmark's snapshot, or nil for an unknown ID or a folder.
  func bookmark(_ id: BookmarkID, isNew: Bool = false) -> FakeBookmark? {
    guard let node = nodes[id], let url = node.url else { return nil }
    return FakeBookmark(id: id, title: node.title, url: url, folderID: node.parent, isNew: isNew)
  }

  /// The children of a folder, in order: titles of bookmarks and folders.
  func titles(in folder: BookmarkFolderID) -> [String] {
    (children[folder] ?? []).compactMap { nodes[$0]?.title }
  }

  /// D3's `bookmarkFolders`: Other Bookmarks, then its folders depth-first.
  var folders: [any ClairBookmarkFolder] {
    var result: [any ClairBookmarkFolder] = []
    func walk(_ id: Int64, depth: Int, title: String) {
      result.append(FakeBookmarkFolder(id: id, title: title, depth: depth))
      for child in children[id] ?? [] where nodes[child]?.url == nil {
        walk(child, depth: depth + 1, title: nodes[child]?.title ?? "")
      }
    }
    walk(Self.otherID, depth: 0, title: "Other bookmarks")
    return result
  }

  /// D3's -updateBookmark:title:folder:. `pageTitle` is what an empty title
  /// becomes.
  func update(_ id: BookmarkID, title: String, folder: BookmarkFolderID, pageTitle: String) {
    commands.append("update \(id) \(title) \(folder)")
    guard var node = nodes[id], node.url != nil else { return }
    node.title = title.isEmpty ? pageTitle : title
    if folder != node.parent, folders.contains(where: { $0.folderID == folder }) {
      children[node.parent]?.removeAll { $0 == id }
      children[folder, default: []].append(id)
      node.parent = folder
    }
    nodes[id] = node
  }

  /// D3's -removeBookmark:.
  func remove(_ id: BookmarkID) {
    commands.append("remove \(id)")
    guard let node = nodes[id], node.url != nil else { return }
    children[node.parent]?.removeAll { $0 == id }
    nodes[id] = nil
  }

  /// D3's -addBookmarkFolder:.
  func addFolderAsClair(_ title: String) -> BookmarkFolderID {
    commands.append("addFolder \(title)")
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return ClairBookmarkFolderIDNone }
    return addFolder(trimmed)
  }
}
