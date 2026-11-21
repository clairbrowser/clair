// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Observation
import Sparkle
import Testing

@testable import ClairUI

struct UpdateConfigurationTests {
  private let environment = [UpdateConfiguration.feedURLOverrideVariable: "http://localhost:8000/appcast.xml"]

  @Test func releasePackageIgnoresTheOverride() {
    let configuration = UpdateConfiguration(infoDictionary: [:], environment: environment)
    #expect(configuration.feedURLOverride == nil)
  }

  @Test func onlyATrueMarkerCounts() {
    for marker: Any in [false, "YES", 1] {
      let configuration = UpdateConfiguration(
        infoDictionary: [UpdateConfiguration.nonOfficialPackageKey: marker], environment: environment)
      #expect(configuration.feedURLOverride == nil)
    }
  }

  @Test func nonOfficialPackageReadsTheOverride() {
    let configuration = UpdateConfiguration(
      infoDictionary: [UpdateConfiguration.nonOfficialPackageKey: true], environment: environment)
    #expect(configuration.feedURLOverride == "http://localhost:8000/appcast.xml")
  }

  @Test func nonOfficialPackageWithoutAnOverrideUsesInfoPlist() {
    let configuration = UpdateConfiguration(
      infoDictionary: [UpdateConfiguration.nonOfficialPackageKey: true],
      environment: [UpdateConfiguration.feedURLOverrideVariable: ""])
    #expect(configuration.feedURLOverride == nil)
  }
}

struct IdleThresholdConfigurationTests {
  private let environment = [UpdateConfiguration.idleThresholdOverrideVariable: "20"]

  @Test func releasePackageWaitsThirtyMinutes() {
    let configuration = UpdateConfiguration(infoDictionary: [:], environment: environment)
    #expect(configuration.idleThreshold == 30 * 60)
  }

  @Test func nonOfficialPackageReadsTheOverride() {
    let configuration = UpdateConfiguration(
      infoDictionary: [UpdateConfiguration.nonOfficialPackageKey: true], environment: environment)
    #expect(configuration.idleThreshold == 20)
  }

  @Test func aNonsenseOverrideIsIgnored() {
    for value in ["", "soon", "0", "-5"] {
      let configuration = UpdateConfiguration(
        infoDictionary: [UpdateConfiguration.nonOfficialPackageKey: true],
        environment: [UpdateConfiguration.idleThresholdOverrideVariable: value])
      #expect(configuration.idleThreshold == 30 * 60)
    }
  }
}

struct IdleInstallScheduleTests {
  /// What the schedule answers for each idle time in turn.
  private func attempts(_ idleTimes: [TimeInterval]) -> [Bool] {
    var schedule = IdleInstallSchedule(threshold: 1800)
    return idleTimes.map { schedule.shouldAttempt(idleFor: $0) }
  }

  @Test func nothingHappensBeforeTheThreshold() {
    #expect(attempts([0, 1799]) == [false, false])
  }

  @Test func itTriesOnceAtTheThreshold() {
    #expect(attempts([1800, 1830]) == [true, false])
  }

  @Test func aBlockedTryWaitsAnotherThreshold() {
    #expect(attempts([1800, 3599, 3600]) == [true, false, true])
  }

  @Test func inputStartsThePeriodOver() {
    #expect(attempts([1800, 5, 1799, 1800]) == [true, false, false, true])
  }
}

struct UpdateUserDriverTests {
  @Test func everyUpdateNotYetInstallingIsAccepted() {
    #expect(UpdateUserDriver.choice(forStage: .notDownloaded, informationOnly: false) == .install)
    #expect(UpdateUserDriver.choice(forStage: .downloaded, informationOnly: false) == .install)
  }

  /// "Install" at this stage would make Sparkle quit Clair right away.
  @Test func anUpdateAlreadyInstallingIsLeftToInstallOnQuit() {
    #expect(UpdateUserDriver.choice(forStage: .installing, informationOnly: false) == .dismiss)
  }

  @Test func informationOnlyUpdatesAreNotInstalled() {
    #expect(UpdateUserDriver.choice(forStage: .notDownloaded, informationOnly: true) == .dismiss)
  }
}

struct UpdateMenuTests {
  private func appMenu() -> (NSMenu, NSMenu) {
    let main = NSMenu()
    let app = NSMenu(title: "Clair")
    app.addItem(withTitle: "About Clair", action: nil, keyEquivalent: "")
    app.addItem(.separator())
    app.addItem(withTitle: "Quit Clair", action: nil, keyEquivalent: "q")
    main.addItem(withTitle: "Clair", action: nil, keyEquivalent: "").submenu = app
    return (main, app)
  }

  @Test func theItemGoesBelowAboutClair() {
    let (main, app) = appMenu()
    let menu = UpdateMenu {}
    menu.install(in: main)
    #expect(app.items.map(\.title) == ["About Clair", "Check for Updates…", "", "Quit Clair"])
  }

  @Test func theItemReadsCheckWithNoBadgeUntilAnUpdateWaits() {
    let menu = UpdateMenu {}
    #expect(menu.item.title == "Check for Updates…")
    #expect(menu.item.badge == nil)
    menu.setUpdateWaiting(true)
    #expect(menu.item.title == "Update Available…")
    #expect(menu.item.badge?.stringValue == "1 update")
    menu.setUpdateWaiting(false)
    #expect(menu.item.title == "Check for Updates…")
    #expect(menu.item.badge == nil)
  }

  @Test func choosingTheItemRunsTheAction() {
    var chosen = 0
    let menu = UpdateMenu { chosen += 1 }
    menu.install(in: appMenu().0)
    NSApplication.shared.sendAction(menu.item.action!, to: menu.item.target, from: menu.item)
    #expect(chosen == 1)
  }
}

final class FakePrompts: UpdatePrompting {
  var restartAnswer = true
  private(set) var log: [String] = []

  func showUpToDate(version: String) { log.append("up to date") }
  func showCheckFailed(reason: String) { log.append("failed: \(reason)") }
  func askToRestart(forVersion version: String) -> Bool {
    log.append("restart \(version)")
    return restartAnswer
  }
}

struct UpdateControllerTests {
  private let host = FakeHost()
  private let prompts = FakePrompts()
  private let item = SUAppcastItem.empty()

  private func controller() -> UpdateController {
    UpdateController(
      host: host, configuration: UpdateConfiguration(infoDictionary: [:], environment: [:]),
      prompts: prompts)
  }

  @Test func aBackgroundUpdateChangesTheMenuAndAsksNothing() {
    let updates = controller()
    updates.updateIsWaiting(item, userInitiated: false)
    #expect(updates.menuItemForTesting.title == "Update Available…")
    #expect(updates.menuItemForTesting.badge?.stringValue == "1 update")
    #expect(prompts.log.isEmpty)
    #expect(host.relaunchCount == 0)
  }

  @Test func chromiumHearsOfAWaitingUpdateOnce() {
    let updates = controller()
    updates.updateIsWaiting(item, userInitiated: false)
    updates.updateIsWaiting(item, userInitiated: false)
    #expect(host.updateWillInstallOnQuitCount == 1)
  }

  @Test func aCheckTheUserAskedForOffersTheRestart() {
    let updates = controller()
    prompts.restartAnswer = false
    updates.updateIsWaiting(item, userInitiated: true)
    #expect(prompts.log.count == 1)
    #expect(prompts.log[0].hasPrefix("restart"))
  }

  @Test func laterKeepsTheUpdateWaiting() {
    let updates = controller()
    prompts.restartAnswer = false
    updates.updateIsWaiting(item, userInitiated: false)
    updates.chooseUpdateItem()
    #expect(host.relaunchCount == 0)
    #expect(updates.waitingUpdate != nil)
    #expect(updates.menuItemForTesting.title == "Update Available…")
  }

  @Test func restartAndUpdateGoesThroughChromium() {
    let updates = controller()
    updates.updateIsWaiting(item, version: "0.1.3", userInitiated: false)
    updates.chooseUpdateItem()
    #expect(prompts.log == ["restart 0.1.3"])
    #expect(host.relaunchCount == 1)
  }

  /// The banner's click is the confirmation, and incognito windows close
  /// without a question, as in Arc (add-update-banners D2).
  @Test func theBannerRelaunchesWithoutAnyPrompt() {
    let updates = controller()
    host.blockers = [.incognitoWindow]
    updates.updateIsWaiting(item, version: "0.1.3", userInitiated: false)
    updates.restartToUpdate(confirming: false)
    #expect(prompts.log.isEmpty)
    #expect(host.relaunchCount == 1)
  }

  /// The menu item asks only with the version alert, incognito windows or not.
  @Test func theMenuItemAsksOnlyWithTheVersionAlert() {
    let updates = controller()
    host.blockers = [.incognitoWindow]
    updates.updateIsWaiting(item, version: "0.1.3", userInitiated: false)
    prompts.restartAnswer = false
    updates.restartToUpdate(confirming: true)
    #expect(prompts.log == ["restart 0.1.3"])
    #expect(host.relaunchCount == 0)

    prompts.restartAnswer = true
    updates.restartToUpdate(confirming: true)
    #expect(prompts.log == ["restart 0.1.3", "restart 0.1.3"])
    #expect(host.relaunchCount == 1)
  }

  @Test func nothingRestartsWithoutAWaitingUpdate() {
    let updates = controller()
    updates.restartToUpdate(confirming: false)
    #expect(host.relaunchCount == 0)
  }

  /// Chromium's quit flow asks about downloads itself.
  @Test func otherBlockersDontAsk() {
    let updates = controller()
    host.blockers = [.downloadInProgress, .audibleTab, .capturingTab]
    updates.updateIsWaiting(item, version: "0.1.3", userInitiated: false)
    updates.chooseUpdateItem()
    #expect(prompts.log == ["restart 0.1.3"])
    #expect(host.relaunchCount == 1)
  }

  /// Nobody is there to choose to lose an incognito window (add-update-banners
  /// D2).
  @Test func anIdleInstallStillWaitsForIncognitoWindows() {
    let updates = controller()
    host.blockers = [.incognitoWindow]
    updates.updateIsWaiting(item, version: "0.1.3", userInitiated: false)
    updates.installWhileIdle()
    #expect(host.relaunchCount == 0)
  }

  @Test func anIdleInstallRelaunchesWhenNothingBlocksIt() {
    let updates = controller()
    updates.installWhileIdle()
    #expect(host.relaunchCount == 1)
    #expect(prompts.log.isEmpty)
  }

  @Test func anIdleInstallWaitsForEveryBlocker() {
    let updates = controller()
    let blockers: [RelaunchBlockers] = [.downloadInProgress, .incognitoWindow, .audibleTab, .capturingTab]
    for blocker in blockers {
      host.blockers = blocker
      updates.installWhileIdle()
      #expect(host.relaunchCount == 0)
      #expect(prompts.log.isEmpty)
    }
    host.blockers = []
    updates.installWhileIdle()
    #expect(host.relaunchCount == 1)
  }

  @Test func aCheckWithNoUpdaterReportsAFailure() {
    let updates = controller()
    updates.chooseUpdateItem()
    #expect(prompts.log.count == 1)
    #expect(prompts.log[0].hasPrefix("failed"))
  }

  @Test func shortVersionDropsTheBuild() {
    #expect(UpdateController.shortVersion(fromDisplayString: "0.1.1 (101)") == "0.1.1")
    #expect(UpdateController.shortVersion(fromDisplayString: "0.1.1") == "0.1.1")
  }

  // MARK: The banner (add-update-banners D1, D3)

  @Test func aWaitingUpdatePublishesItsShortVersion() {
    let updates = controller()
    #expect(updates.bannerState.banner == .none)
    updates.updateIsWaiting(item, version: "0.1.3", userInitiated: false)
    #expect(updates.bannerState.banner == .waiting(version: "0.1.3"))
  }

  @Test func aWaitingUpdateReplacesUpdateComplete() throws {
    let defaults = try throwawayDefaults()
    defaults.set("0.1.2", forKey: "ClairLastRunVersion")
    let updates = controller()
    updates.recordRunningVersion(in: defaults, running: "0.1.3")
    #expect(updates.bannerState.banner == .complete(version: "0.1.3"))
    updates.updateIsWaiting(item, version: "0.1.4", userInitiated: false)
    #expect(updates.bannerState.banner == .waiting(version: "0.1.4"))
  }

  @Test func aSecondWaitingCallPublishesNothing() {
    let updates = controller()
    updates.updateIsWaiting(item, version: "0.1.3", userInitiated: false)
    let changed = ChangeFlag()
    withObservationTracking {
      _ = updates.bannerState.banner
    } onChange: {
      changed.set()
    }
    updates.updateIsWaiting(item, version: "0.1.3", userInitiated: false)
    #expect(!changed.value)
    #expect(updates.bannerState.banner == .waiting(version: "0.1.3"))
  }

  private func throwawayDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "ClairUITests.\(UUID())"))
  }

  @Test func theFirstLaunchEverShowsNothing() throws {
    let updates = controller()
    updates.recordRunningVersion(in: try throwawayDefaults(), running: "0.1.3")
    #expect(updates.bannerState.banner == .none)
  }

  @Test func aNewerVersionShowsUpdateComplete() throws {
    let defaults = try throwawayDefaults()
    defaults.set("0.1.2", forKey: "ClairLastRunVersion")
    let updates = controller()
    updates.recordRunningVersion(in: defaults, running: "0.1.10")
    #expect(updates.bannerState.banner == .complete(version: "0.1.10"))
  }

  @Test func anOlderVersionShowsNothing() throws {
    let defaults = try throwawayDefaults()
    defaults.set("0.1.3", forKey: "ClairLastRunVersion")
    let updates = controller()
    updates.recordRunningVersion(in: defaults, running: "0.1.2")
    #expect(updates.bannerState.banner == .none)
  }

  /// The card belongs to the launch after the update, closed or not.
  @Test func theNextLaunchOfTheNewVersionShowsNothing() throws {
    let defaults = try throwawayDefaults()
    defaults.set("0.1.2", forKey: "ClairLastRunVersion")
    controller().recordRunningVersion(in: defaults, running: "0.1.3")
    let relaunched = controller()
    relaunched.recordRunningVersion(in: defaults, running: "0.1.3")
    #expect(relaunched.bannerState.banner == .none)
  }

  @Test func closingUpdateCompleteClearsTheBanner() throws {
    let defaults = try throwawayDefaults()
    defaults.set("0.1.2", forKey: "ClairLastRunVersion")
    let updates = controller()
    updates.recordRunningVersion(in: defaults, running: "0.1.3")
    updates.closeUpdateComplete()
    #expect(updates.bannerState.banner == .none)
  }

  @Test func closingUpdateCompleteLeavesAWaitingUpdate() {
    let updates = controller()
    updates.updateIsWaiting(item, version: "0.1.3", userInitiated: false)
    updates.closeUpdateComplete()
    #expect(updates.bannerState.banner == .waiting(version: "0.1.3"))
  }

  @Test func releaseURLs() {
    #expect(
      UpdateBanner.releaseURL(forVersion: "0.1.3")?.absoluteString
        == "https://github.com/clairbrowser/clair/releases/tag/v0.1.3")
    for version in ["unknown", "", "0.1.3-dev", "0..1", "v0.1.3", "0.1.3 (120)", "١.٢"] {
      #expect(UpdateBanner.releaseURL(forVersion: version) == nil)
    }
  }

  @Test func theLastRunVersionIsKept() throws {
    let defaults = try #require(UserDefaults(suiteName: "ClairUITests.\(UUID())"))
    let first = controller()
    first.recordRunningVersion(in: defaults)
    #expect(first.previousVersion == nil)
    let second = controller()
    second.recordRunningVersion(in: defaults)
    #expect(second.previousVersion != nil)
  }
}

/// Whether an observed value changed, set from Observation's `onChange`.
nonisolated final class ChangeFlag: @unchecked Sendable {
  private(set) var value = false
  func set() { value = true }
}

/// The banner's state in windows (add-update-banners D1, D6).
@MainActor
struct UpdateBannerWindowTests {
  private let host = FakeHost()

  private func window(_ state: UpdateBannerState) -> (FakeBrowser, BrowserWindowController) {
    let browser = FakeBrowser(host: host)
    let controller = BrowserWindowController(
      browser: browser, spaces: browser.spaces, updateBanner: state,
      preferences: SidebarPreferences(defaults: UserDefaults(suiteName: "UpdateBannerWindowTests")!))
    browser.clairWindow = controller
    return (browser, controller)
  }

  @Test func everyWindowSeesTheOneBanner() {
    let state = UpdateBannerState()
    let first = window(state).1
    let second = window(state).1
    let flags = [first.model, second.model].map { model in
      let flag = ChangeFlag()
      withObservationTracking {
        _ = model.updateBanner.banner
      } onChange: {
        flag.set()
      }
      return flag
    }
    state.banner = .waiting(version: "0.1.3")
    #expect(flags.map { $0.value } == [true, true])
    #expect(first.model.updateBanner.banner == .waiting(version: "0.1.3"))
    #expect(second.model.updateBanner.banner == .waiting(version: "0.1.3"))
  }

  @Test func seeWhatsNewOpensTheReleaseInANewForegroundTab() {
    let state = UpdateBannerState()
    state.banner = .complete(version: "0.1.3")
    let (browser, controller) = window(state)
    controller.updateWhatsNewChosen()
    #expect(
      browser.commands.last
        == "open https://github.com/clairbrowser/clair/releases/tag/v0.1.3 \(OpenDisposition.newForegroundTab.rawValue)"
    )
  }

  @Test func seeWhatsNewOpensNothingWithoutARelease() {
    let state = UpdateBannerState()
    state.banner = .complete(version: "unknown")
    let (browser, controller) = window(state)
    let before = browser.commands
    controller.updateWhatsNewChosen()
    #expect(browser.commands == before)
  }
}
