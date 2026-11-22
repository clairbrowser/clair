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

  // MARK: Pins (add-pinned-tabs-and-favorites design D1 to D6)

  /// A pin as the engine's store keeps it.
  struct PinRecord {
    let id: PinID
    /// A pinned tab's Space, or nil for a favorite.
    var spaceID: SpaceID?
    var profileID: ProfileID
    var url: String
    var title: String
    var name: String?
  }

  private var records: [PinID: PinRecord] = [:]
  private var pinOrder: [SpaceID: [PinID]] = [:]
  private var favoriteOrder: [ProfileID: [PinID]] = [:]
  /// Each open pin's tab.
  private var bound: [PinID: FakeTab] = [:]
  /// Pins removed, newest first, for Restore Last Closed Tab (D3).
  private(set) var removedPins: [(record: PinRecord, index: Int)] = []
  private var nextPin = 1

  func pinRecord(_ pinID: PinID) -> PinRecord? { records[pinID] }

  func pinRecords(inSpace spaceID: SpaceID) -> [PinRecord] {
    (pinOrder[spaceID] ?? []).compactMap { records[$0] }
  }

  func favoriteRecords(ofProfile profileID: ProfileID) -> [PinRecord] {
    (favoriteOrder[profileID] ?? []).compactMap { records[$0] }
  }

  func boundTab(of pinID: PinID) -> FakeTab? { bound[pinID] }

  func isFavoriteTab(_ tabID: TabID) -> Bool {
    guard let tab = tab(tabID), let pinID = tab.pinID, bound[pinID]?.tabID == tabID else { return false }
    return records[pinID]?.spaceID == nil
  }

  /// Adds a pin as the engine's store would, without a tab, and returns it.
  @discardableResult
  func addPin(
    url: String, title: String, name: String? = nil, inSpace spaceID: SpaceID? = FakeHost.homeID,
    profile profileID: ProfileID = FakeHost.defaultProfileID
  ) -> PinID {
    let pinID = "pin-\(nextPin)"
    nextPin += 1
    records[pinID] = PinRecord(id: pinID, spaceID: spaceID, profileID: profileID, url: url, title: title, name: name)
    if let spaceID {
      pinOrder[spaceID, default: []].append(pinID)
    } else {
      favoriteOrder[profileID, default: []].append(pinID)
    }
    pinsChanged(of: pinID)
    return pinID
  }

  private func snapshot(_ record: PinRecord) -> FakePin {
    let tab = bound[record.id]
    let atPinnedURL = tab.map { ($0.url?.absoluteString ?? $0.urlText) == record.url } ?? true
    return FakePin(
      id: record.id, isFavorite: record.spaceID == nil, spaceID: record.spaceID, profileID: record.profileID,
      url: record.url, title: record.title, name: record.name, tab: tab, isAtPinnedURL: atPinnedURL)
  }

  private func pinsChanged(of pinID: PinID) {
    guard let record = records[pinID] else { return }
    containerChanged(spaceID: record.spaceID, profileID: record.profileID)
  }

  private func containerChanged(spaceID: SpaceID?, profileID: ProfileID) {
    if let spaceID {
      let pins = self.pins(inSpace: spaceID)
      for observer in allObservers {
        observer.pinsDidChange(pins, inSpace: spaceID)
      }
    } else {
      let favorites = self.favorites(ofProfile: profileID)
      for observer in allObservers {
        observer.favoritesDidChange(favorites, ofProfile: profileID)
      }
    }
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

  /// Takes the record out of the store; returns its index.
  @discardableResult
  private func removeRecord(_ pinID: PinID) -> Int? {
    guard let record = records.removeValue(forKey: pinID) else { return nil }
    if let spaceID = record.spaceID {
      let index = pinOrder[spaceID]?.firstIndex(of: pinID)
      pinOrder[spaceID]?.removeAll { $0 == pinID }
      return index
    }
    let index = favoriteOrder[record.profileID]?.firstIndex(of: pinID)
    favoriteOrder[record.profileID]?.removeAll { $0 == pinID }
    return index
  }

  private func insertRecord(_ record: PinRecord, at index: Int) {
    records[record.id] = record
    if let spaceID = record.spaceID {
      var order = pinOrder[spaceID] ?? []
      order.insert(record.id, at: max(0, min(index, order.count)))
      pinOrder[spaceID] = order
    } else {
      var order = favoriteOrder[record.profileID] ?? []
      order.insert(record.id, at: max(0, min(index, order.count)))
      favoriteOrder[record.profileID] = order
    }
  }

  /// D3: Restore Last Closed Tab puts the newest removed pin back in place.
  @discardableResult
  func restoreRemovedPin() -> PinID? {
    guard !removedPins.isEmpty else { return nil }
    let (record, index) = removedPins.removeFirst()
    insertRecord(record, at: index)
    pinsChanged(of: record.id)
    return record.id
  }

  // MARK: ClairHost: pins

  func pins(inSpace spaceID: SpaceID) -> [any ClairPin] {
    pinRecords(inSpace: spaceID).map(snapshot)
  }

  func favorites(ofProfile profileID: ProfileID) -> [any ClairPin] {
    favoriteRecords(ofProfile: profileID).map(snapshot)
  }

  /// D5: a Today tab becomes a pin of its Space, or of its profile's
  /// favorites, keeping its page and name.
  private func pin(tab tabID: TabID, at index: Int, favorite: Bool) {
    guard let tab = tab(tabID), tab.pinID == nil, isSpace(tab.spaceID), tab.peekParentID == ClairTabIDNone,
      let profileID = profile(ofSpace: tab.spaceID)
    else { return }
    let pinID = "pin-\(nextPin)"
    nextPin += 1
    let record = PinRecord(
      id: pinID, spaceID: favorite ? nil : tab.spaceID, profileID: profileID,
      url: tab.url?.absoluteString ?? tab.urlText, title: tab.title, name: tab.name)
    insertRecord(record, at: index)
    setList(list(tab.spaceID).filter { $0.tabID != tabID && $0.peekParentID != tabID }, inSpace: tab.spaceID)
    bind(pinID, to: tab)
  }

  func pin(tab tabID: TabID, at index: Int) {
    commands.append("pin \(tabID) \(index)")
    pin(tab: tabID, at: index, favorite: false)
  }

  func favorite(tab tabID: TabID, at index: Int) {
    commands.append("favorite \(tabID) \(index)")
    pin(tab: tabID, at: index, favorite: true)
  }

  func movePin(_ pinID: PinID, toSpace spaceID: SpaceID, at index: Int) {
    commands.append("movePin \(pinID) \(spaceID) \(index)")
    guard var record = records[pinID], isSpace(spaceID), let profileID = profile(ofSpace: spaceID) else { return }
    let from = (record.spaceID, record.profileID)
    removeRecord(pinID)
    record.spaceID = spaceID
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
    containerChanged(spaceID: from.0, profileID: from.1)
    pinsChanged(of: pinID)
  }

  func movePin(_ pinID: PinID, toFavoritesAt index: Int) {
    commands.append("movePinToFavorites \(pinID) \(index)")
    guard var record = records[pinID] else { return }
    let from = (record.spaceID, record.profileID)
    removeRecord(pinID)
    record.spaceID = nil
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
    // add-pinned-tabs-and-favorites D9: its pinned tabs go, for good.
    for pinID in pinOrder[spaceID] ?? [] {
      if let tab = bound[pinID] {
        browser(tab.browserID)?.closeTabNow(tab.tabID)
      }
      records[pinID] = nil
      bound[pinID] = nil
    }
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
      movePin(pinID, toSpace: spaceID, at: Int.max)
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
