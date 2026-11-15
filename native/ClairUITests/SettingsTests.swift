// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Testing

@testable import ClairUI

@MainActor
struct SettingsWindowTests {
  private let defaults: UserDefaults = {
    let name = "ClairUITests.Settings.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }()

  /// Chromium's application menu, with its Settings item as main_menu_builder.mm makes it.
  private func appMenu(settingsTag: Int = SettingsWindowController.menuTag) -> (NSMenu, NSMenuItem) {
    let main = NSMenu()
    let app = NSMenu(title: "Clair")
    app.addItem(withTitle: "About Clair", action: nil, keyEquivalent: "")
    app.addItem(.separator())
    let settings = app.addItem(
      withTitle: "Preferences...", action: NSSelectorFromString("showPreferences:"), keyEquivalent: ",")
    settings.tag = settingsTag
    app.addItem(withTitle: "Quit Clair", action: nil, keyEquivalent: "q")
    main.addItem(withTitle: "Clair", action: nil, keyEquivalent: "").submenu = app
    return (main, settings)
  }

  private func choose(_ item: NSMenuItem) throws {
    NSApplication.shared.sendAction(try #require(item.action), to: item.target, from: item)
  }

  @Test func settingsOpensClairsWindow() throws {
    let (main, item) = appMenu()
    let settings = SettingsWindowController(host: FakeHost(), defaults: defaults)
    #expect(settings.install(in: main))
    #expect(item.title == "Settings…")
    #expect(item.keyEquivalent == ",")
    #expect(item.target === settings)

    #expect(settings.window == nil)
    try choose(item)
    let window = try #require(settings.window)
    #expect(window.isVisible)
    #expect(window.title == "General")

    window.close()
    try choose(item)
    #expect(settings.window === window)
    #expect(window.isVisible)
    window.close()
  }

  @Test func aMenuWithoutTheItemIsLeftToChromium() throws {
    let (main, item) = appMenu(settingsTag: 0)
    let settings = SettingsWindowController(host: FakeHost(), defaults: defaults)
    #expect(!settings.install(in: main))
    #expect(item.title == "Preferences...")
    #expect(item.target == nil)
  }

  /// add-profiles D12: the window opens on General each time, whichever page
  /// it showed when it closed.
  @Test func opensOnGeneralEachTime() throws {
    let settings = SettingsWindowController(host: FakeHost(), defaults: defaults)
    settings.show()
    let window = try #require(settings.window)
    #expect(window.title == "General")
    let tabs = try #require(window.contentViewController as? NSTabViewController)
    #expect(tabs.tabViewItems.map(\.label) == ["General", "Profiles", "Links", "Advanced"])

    tabs.selectedTabViewItemIndex = 3
    #expect(window.title == "Advanced")
    window.close()
    settings.show()
    #expect(window.title == "General")
    #expect(defaults.object(forKey: "ClairSettingsPage") == nil)
    window.close()
  }

  @Test func profilesSitsBetweenGeneralAndLinks() {
    #expect(SettingsPage.allCases == [.general, .profiles, .links, .advanced])
    #expect(SettingsPage.profiles.label == "Profiles")
    #expect(SettingsPage.links.label == "Links")
  }

  @Test func peekOnShiftClickIsOnUntilTurnedOff() {
    #expect(PeekPreference(defaults: defaults).isEnabled)
    defaults.set(false, forKey: PeekPreference.key)
    #expect(!PeekPreference(defaults: defaults).isEnabled)
    defaults.set(true, forKey: PeekPreference.key)
    #expect(PeekPreference(defaults: defaults).isEnabled)
  }

  @Test func theWindowAnswersFromThePreferenceLive() {
    let browser = FakeBrowser()
    let controller = BrowserWindowController(
      browser: browser, spaces: browser.spaces, preferences: SidebarPreferences(defaults: defaults),
      peekPreference: PeekPreference(defaults: defaults))
    #expect(controller.opensPeekOnShiftClick)
    defaults.set(false, forKey: PeekPreference.key)
    #expect(!controller.opensPeekOnShiftClick)
  }

  @Test func theProfilesPageIsWider() throws {
    let settings = SettingsWindowController(host: FakeHost(), defaults: defaults)
    settings.show()
    let window = try #require(settings.window)
    let tabs = try #require(window.contentViewController as? NSTabViewController)
    tabs.selectedTabViewItemIndex = 1
    #expect(window.title == "Profiles")
    #expect(ProfilesSettingsView.width > SettingsWindowController.width)
    window.close()
  }

  @Test func moreSettingsOpensChromiumsSettingsAndCloses() throws {
    let host = FakeHost()
    let settings = SettingsWindowController(host: host, defaults: defaults)
    settings.show()
    let window = try #require(settings.window)
    settings.openMoreSettings()
    #expect(host.openedURLs.map(\.absoluteString) == ["chrome://settings"])
    #expect(!window.isVisible)
  }
}

// MARK: Link rules (add-link-rules)

/// FakeHost keeps the rules as the engine's store does (add-link-rules D1,
/// D3, D4).
@MainActor
struct LinkRuleHostTests {
  @Test func replaceLinkRulesReplacesInOrderAndDropsWhatTheStoreWouldnt() {
    let host = FakeHost()
    let work = host.addSpaces("Work")[0]
    host.replaceLinkRules([
      LinkRuleValue(match: .contains, text: " example.com ", spaceID: work),
      LinkRuleValue(match: .prefix, text: "github.com/acme", spaceID: FakeHost.homeID),
      LinkRuleValue(match: .exact, text: "example.org", spaceID: "gone"),
      LinkRuleValue(match: .contains, text: "not a url", spaceID: work),
      LinkRuleValue(match: .contains, text: "example.com", spaceID: FakeHost.homeID),
    ])
    #expect(host.linkRules.map(\.text) == ["example.com", "github.com/acme"])
    #expect(host.linkRules.map(\.match) == [.contains, .prefix])
    #expect(host.linkRules.map(\.spaceID) == [work, FakeHost.homeID])
    host.replaceLinkRules([])
    #expect(host.linkRules.isEmpty)
  }

  @Test func readsATextAsD3Does() {
    let host = FakeHost()
    for valid in [
      "example.com", "meet.google", "https://example.com/inbox", "http://EXAMPLE.com", "example.com:8080/a",
      "github.com/acme", " example.com\n",
    ] {
      #expect(host.isValidLinkRuleText(valid), "\(valid)")
    }
    for invalid in ["", "   ", "not a url", "ftp://example.com", "javascript:alert(1)", "https://", "file:///tmp"] {
      #expect(!host.isValidLinkRuleText(invalid), "\(invalid)")
    }
  }

  @Test func deletingASpaceRemovesItsRules() {
    let host = FakeHost()
    let work = host.addSpaces("Work")[0]
    host.replaceLinkRules([
      LinkRuleValue(match: .contains, text: "example.com", spaceID: work),
      LinkRuleValue(match: .contains, text: "example.org", spaceID: FakeHost.homeID),
    ])
    host.renameSpace(work, to: "Office")
    #expect(host.linkRules.count == 2)
    host.deleteSpace(work)
    #expect(host.linkRules.map(\.text) == ["example.org"])
  }
}

/// The Link Rules dialog (add-link-rules D5), one case per scenario of the
/// link-rules spec from "Link Rules dialog" to "Discarding edits".
@MainActor
final class LinkRulesDialogTests {
  private let host = FakeHost()
  private var answers: [Bool] = []
  private let presenter = ClairDialogPresenter(host: .init(begin: { _ in }, end: { _ in }))

  private func open() -> (ClairDialog, LinkRulesState) {
    LinkRulesDialog.show(on: presenter, host: host, spaces: host.spacesModel) { [unowned self] saved in
      answers.append(saved)
    }
  }

  private func cancel(_ dialog: ClairDialog) {
    dialog.press(dialog.page.buttons[0])
  }

  private func done(_ dialog: ClairDialog) {
    dialog.press(dialog.page.buttons[1])
  }

  @Test func opensWithTheRulesInOrder() throws {
    let work = host.addSpaces("Work")[0]
    host.storeLinkRules([
      FakeLinkRule(.contains, "docs.google.com", in: work),
      FakeLinkRule(.contains, "google.com", in: FakeHost.homeID),
    ])
    let (dialog, state) = open()
    #expect(presenter.showing === dialog)
    #expect(dialog.page.title == "Link Rules")
    #expect(dialog.page.width == 640)
    #expect(state.rows.map(\.text) == ["docs.google.com", "google.com"])
    #expect(state.rows.map(\.spaceID) == [work, FakeHost.homeID])
    #expect(dialog.page.leadingButton?.title == "Add Rule")
    #expect(dialog.page.buttons.map(\.title) == ["Cancel", "Done"])
    #expect(state.emptyMessage == nil)
  }

  @Test func addRuleAppendsAFocusedEmptyRowOnTheFirstSpace() throws {
    host.addSpaces("Work")
    host.storeLinkRules([FakeLinkRule(.exact, "example.com/inbox", in: FakeHost.homeID)])
    let (dialog, state) = open()
    dialog.pressLeading()
    let row = try #require(state.rows.last)
    #expect(state.rows.count == 2)
    #expect(row.match == .contains)
    #expect(row.text == "")
    #expect(row.spaceID == FakeHost.homeID)
    #expect(state.focusedRow == row.id)
  }

  @Test func removingARowKeepsTheOthersInOrder() {
    let work = host.addSpaces("Work")[0]
    host.storeLinkRules([
      FakeLinkRule(.contains, "a.com", in: work), FakeLinkRule(.contains, "b.com", in: work),
      FakeLinkRule(.contains, "c.com", in: work),
    ])
    let (_, state) = open()
    state.remove(state.rows[1].id)
    #expect(state.rows.map(\.text) == ["a.com", "c.com"])
  }

  @Test func spacesAreGroupedByProfileWithSeveral() {
    let workProfile = host.addProfile("Work")
    let home = FakeHost.homeID
    let work = host.createSpace(named: "Work", icon: "💼", profile: workProfile)!
    let (_, state) = open()
    let sections = state.spaceSections
    #expect(sections.map(\.title) == ["Default", "Work"])
    #expect(sections.map { $0.spaces.map(\.spaceID) } == [[home], [work]])
    #expect(sections[1].spaces[0].icon == "💼")
  }

  @Test func oneProfileHasOneUntitledSection() {
    host.addSpaces("Work")
    let (_, state) = open()
    #expect(state.spaceSections.map(\.title) == [nil])
    #expect(state.spaceSections[0].spaces.map(\.name) == ["Home", "Work"])
  }

  @Test func noRulesSaysSo() {
    host.addSpaces("Work")
    let (dialog, state) = open()
    #expect(state.emptyMessage == "No link rules yet")
    #expect(dialog.page.leadingButton?.isEnabled == true)
  }

  @Test func oneSpaceDisablesAddRule() {
    let (dialog, state) = open()
    #expect(state.emptyMessage == LinkRulesState.needsTwoSpaces)
    #expect(dialog.page.leadingButton?.isEnabled == false)
    dialog.pressLeading()
    #expect(state.rows.isEmpty)
  }

  @Test func oneSpaceStillShowsItsRules() {
    host.storeLinkRules([FakeLinkRule(.contains, "example.com", in: FakeHost.homeID)])
    let (_, state) = open()
    #expect(state.emptyMessage == nil)
    #expect(!state.canAddRule)
    state.remove(state.rows[0].id)
    #expect(state.emptyMessage == LinkRulesState.needsTwoSpaces)
  }

  @Test func doneSavesTheRulesAndCloses() throws {
    let work = host.addSpaces("Work")[0]
    let (dialog, state) = open()
    dialog.pressLeading()
    let row = try #require(state.rows.last)
    state.setText("example.com", of: row.id)
    state.setSpace(work, of: row.id)
    done(dialog)
    #expect(answers == [true])
    #expect(presenter.showing == nil)
    #expect(host.linkRules.map(\.text) == ["example.com"])
    #expect(host.linkRules.map(\.spaceID) == [work])
    #expect(host.linkRules.map(\.match) == [.contains])
  }

  @Test func doneDropsEmptyRows() {
    host.addSpaces("Work")
    let (dialog, _) = open()
    dialog.pressLeading()
    done(dialog)
    #expect(answers == [true])
    #expect(host.linkRules.isEmpty)
    #expect(host.linkRuleSaves == 1)
  }

  @Test func anInvalidTextKeepsTheDialogOpen() throws {
    host.addSpaces("Work")
    let (dialog, state) = open()
    dialog.pressLeading()
    state.setText("not a url", of: try #require(state.rows.last).id)
    done(dialog)
    #expect(answers == [])
    #expect(presenter.showing === dialog)
    #expect(state.error == "Enter a valid domain or URL.")
    #expect(host.linkRuleSaves == 0)
  }

  @Test func aDuplicateKeepsTheDialogOpen() throws {
    host.addSpaces("Work")
    host.storeLinkRules([FakeLinkRule(.contains, "example.com", in: FakeHost.homeID)])
    let (dialog, state) = open()
    dialog.pressLeading()
    state.setText(" example.com", of: try #require(state.rows.last).id)
    done(dialog)
    #expect(state.error == "Each domain or URL and matching option can only appear once.")
    #expect(presenter.showing === dialog)
    // Another match option is another rule.
    state.setMatch(.prefix, of: try #require(state.rows.last).id)
    done(dialog)
    #expect(answers == [true])
    #expect(host.linkRules.map(\.match) == [.contains, .prefix])
  }

  @Test func aSpaceDeletedWhileOpenNeedsAnother() throws {
    let work = host.addSpaces("Work", "Personal")[0]
    host.storeLinkRules([FakeLinkRule(.contains, "example.com", in: work)])
    let (dialog, state) = open()
    host.deleteSpace(work)
    let row = try #require(state.rows.first)
    #expect(state.space(of: row) == nil)
    done(dialog)
    #expect(state.error == "Choose a Space for each rule.")
    #expect(presenter.showing === dialog)
    state.setSpace(FakeHost.homeID, of: row.id)
    #expect(state.error == nil)
    done(dialog)
    #expect(host.linkRules.map(\.spaceID) == [FakeHost.homeID])
  }

  @Test func theChecksRunInOrder() throws {
    let work = host.addSpaces("Work", "Personal")[0]
    host.storeLinkRules([
      FakeLinkRule(.contains, "example.com", in: work), FakeLinkRule(.contains, "example.org", in: work),
    ])
    let (dialog, state) = open()
    host.deleteSpace(work)
    state.setText("example.com", of: state.rows[1].id)
    dialog.pressLeading()
    state.setText("not a url", of: try #require(state.rows.last).id)
    done(dialog)
    #expect(state.error == LinkRulesState.invalidText)
    state.remove(try #require(state.rows.last).id)
    done(dialog)
    #expect(state.error == LinkRulesState.noSpace)
    for row in state.rows {
      state.setSpace(FakeHost.homeID, of: row.id)
    }
    done(dialog)
    #expect(state.error == LinkRulesState.duplicate)
  }

  @Test func anEditClearsTheError() throws {
    host.addSpaces("Work")
    let (dialog, state) = open()
    dialog.pressLeading()
    let row = try #require(state.rows.last)
    state.setText("not a url", of: row.id)
    done(dialog)
    #expect(state.error != nil)
    state.setText("example.com", of: row.id)
    #expect(state.error == nil)
  }

  @Test func cancelWithoutEditsCloses() {
    host.addSpaces("Work")
    host.storeLinkRules([FakeLinkRule(.contains, "example.com", in: FakeHost.homeID)])
    let (dialog, _) = open()
    cancel(dialog)
    #expect(answers == [false])
    #expect(presenter.showing == nil)
    #expect(host.linkRuleSaves == 0)
  }

  @Test func cancelWithEditsTurnsIntoDiscardChanges() async {
    host.addSpaces("Work")
    let (dialog, state) = open()
    dialog.pressLeading()
    #expect(state.hasUnsavedEdits)
    cancel(dialog)
    #expect(answers == [])
    #expect(presenter.showing === dialog)
    #expect(state.showsDiscard)
    for _ in 0..<5 { await Task.yield() }
    let discard = dialog.page.buttons[0]
    #expect(discard.title == "Discard Changes")
    #expect(discard.isDestructive)
    #expect(discard.role == .cancel)
    #expect(discard.shortcut == .cancelAction)
    #expect(dialog.page.buttons[1].title == "Done")
  }

  @Test func discardingClosesWithoutSaving() {
    let work = host.addSpaces("Work")[0]
    host.storeLinkRules([FakeLinkRule(.contains, "example.com", in: work)])
    let (dialog, state) = open()
    state.setMatch(.exact, of: state.rows[0].id)
    cancel(dialog)
    #expect(presenter.showing === dialog)
    cancel(dialog)
    #expect(answers == [false])
    #expect(presenter.showing == nil)
    #expect(host.linkRuleSaves == 0)
    #expect(host.linkRules.map(\.match) == [.contains])
  }

  @Test func undoingTheEditsTurnsDiscardBackIntoCancel() {
    host.addSpaces("Work")
    host.storeLinkRules([FakeLinkRule(.contains, "example.com", in: FakeHost.homeID)])
    let (dialog, state) = open()
    let row = state.rows[0]
    state.setText("example.org", of: row.id)
    cancel(dialog)
    #expect(state.showsDiscard)
    state.setText("example.com ", of: row.id)
    #expect(!state.hasUnsavedEdits)
    #expect(!state.showsDiscard)
    #expect(LinkRulesDialog.buttons(for: state)[0].title == "Cancel")
    cancel(dialog)
    #expect(answers == [false])
  }

  @Test func addRuleFollowsTheSpaces() async {
    let (dialog, state) = open()
    #expect(dialog.page.leadingButton?.isEnabled == false)
    host.addSpaces("Work")
    #expect(state.canAddRule)
    for _ in 0..<5 { await Task.yield() }
    #expect(dialog.page.leadingButton?.isEnabled == true)
  }
}

/// Settings › Links' "Link Rules…" (add-link-rules D7).
@MainActor
struct LinkRulesButtonTests {
  private let defaults: UserDefaults = {
    let name = "ClairUITests.LinkRules.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }()

  @Test func theButtonOpensTheDialogOnTheSettingsWindow() throws {
    let host = FakeHost()
    host.addSpaces("Work")
    let settings = SettingsWindowController(host: host, defaults: defaults)
    settings.show()
    let window = try #require(settings.window)
    let tabs = try #require(window.contentViewController as? NSTabViewController)
    tabs.selectedTabViewItemIndex = 2
    #expect(window.title == "Links")
    #expect(LinksSettingsView.linkRulesLabel == "Choose where links open inside Clair.")
    #expect(LinksSettingsView.linkRulesButton == "Link Rules…")
    let dialog = try #require(settings.showLinkRules())
    #expect(settings.dialogs?.showing === dialog)
    #expect(dialog.page.title == "Link Rules")
    // Only one at a time.
    #expect(settings.showLinkRules() == nil)
    dialog.press(dialog.page.buttons[0])
    #expect(settings.dialogs?.showing == nil)
    window.close()
  }
}
