// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Sparkle
import os

/// Runs Sparkle for the app (design D4): it checks and downloads on its own
/// with no window, a downloaded update installs when Clair quits, and the Clair
/// menu's update item reports and installs it.
///
/// Info.plist turns on the automatic checks and downloads and sets their
/// interval (package.sh), so Sparkle asks the user nothing.
///
/// Clair always reopens through Chromium's relaunch, never Sparkle's. Chromium
/// asks about downloads, restores the session and stays in the background when
/// Clair was, and its relauncher waits for the installer. So Sparkle is never
/// told to install: Autoupdate does that when it sees Clair quit.
final class UpdateController: NSObject, SPUUpdaterDelegate {
  private static let logger = Logger(subsystem: "com.clairbrowser.clair", category: "Updates")
  private static let lastRunVersionKey = "ClairLastRunVersion"

  private let host: any ClairHost
  private let configuration: UpdateConfiguration
  private let prompts: any UpdatePrompting
  private let userDriver = UpdateUserDriver()
  private var updater: SPUUpdater?
  private var startError: (any Error)?
  private lazy var menu = UpdateMenu { [weak self] in
    self?.chooseUpdateItem()
  }
  private lazy var idleInstaller = IdleInstaller(threshold: configuration.idleThreshold) { [weak self] in
    self?.installWhileIdle()
  }

  /// The update that's downloaded and waiting to install, if any.
  private(set) var waitingUpdate: SUAppcastItem?
  /// The waiting update's short version, "0.1.3".
  private var waitingVersion: String?

  /// The version Clair last ran, which decides the "Update Complete!" card.
  /// Nil on the first launch.
  private(set) var previousVersion: String?

  /// What every window's sidebar banner shows (add-update-banners D1). This
  /// controller is its only writer.
  let bannerState = UpdateBannerState()

  init(
    host: any ClairHost, configuration: UpdateConfiguration,
    prompts: any UpdatePrompting = UpdateAlerts()
  ) {
    self.host = host
    self.configuration = configuration
    self.prompts = prompts
    super.init()
    userDriver.onUpdateWaiting = { [weak self] item, userInitiated in
      self?.updateIsWaiting(item, userInitiated: userInitiated)
    }
    userDriver.onNoUpdate = { [weak self] in
      self?.prompts.showUpToDate(version: Self.runningVersion)
    }
    userDriver.onCheckFailed = { [weak self] error in
      self?.prompts.showCheckFailed(reason: error.localizedDescription)
    }
  }

  /// Adds the menu item and starts Sparkle for the running app. If Sparkle
  /// can't start, for example in a package with no public key, Clair logs that
  /// and the item reports it.
  func start() {
    menu.install(in: NSApp.mainMenu)
    recordRunningVersion(in: .standard)

    let bundle = Bundle.main
    let updater = SPUUpdater(
      hostBundle: bundle, applicationBundle: bundle, userDriver: userDriver, delegate: self)
    self.updater = updater
    do {
      try updater.start()
    } catch {
      startError = error
      Self.logger.error("Sparkle didn't start: \(error.localizedDescription, privacy: .public)")
      return
    }
    Self.logger.info(
      "Sparkle started: feed \(updater.feedURL?.absoluteString ?? "none", privacy: .public), automatic checks \(updater.automaticallyChecksForUpdates), automatic downloads \(updater.automaticallyDownloadsUpdates), every \(updater.updateCheckInterval) s"
    )
  }

  /// The version from an appcast item's display string, "0.1.1 (101)".
  static func shortVersion(fromDisplayString display: String) -> String {
    display.split(separator: " ").first.map(String.init) ?? display
  }

  static var runningVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
  }

  /// Keeps the version Clair last ran and records the running one. The first
  /// launch of a newer version shows "Update Complete!" for that run only
  /// (add-update-banners D3).
  func recordRunningVersion(in defaults: UserDefaults, running: String = UpdateController.runningVersion) {
    previousVersion = defaults.string(forKey: Self.lastRunVersionKey)
    defaults.set(running, forKey: Self.lastRunVersionKey)
    if let previousVersion,
      SUStandardVersionComparator.default.compareVersion(previousVersion, toVersion: running) == .orderedAscending
    {
      Self.logger.info("Updated from \(previousVersion, privacy: .public) to \(running, privacy: .public)")
      bannerState.banner = .complete(version: running)
    }
  }

  /// Closes the "Update Complete!" card in every window, for the rest of this
  /// run (add-update-banners D3).
  func closeUpdateComplete() {
    if case .complete = bannerState.banner {
      bannerState.banner = .none
    }
  }

  func updateIsWaiting(_ item: SUAppcastItem, userInitiated: Bool) {
    updateIsWaiting(
      item, version: Self.shortVersion(fromDisplayString: item.displayVersionString), userInitiated: userInitiated)
  }

  /// `version` is the item's short version, which tests give directly.
  func updateIsWaiting(_ item: SUAppcastItem, version: String, userInitiated: Bool) {
    let alreadyWaiting = waitingUpdate != nil
    waitingUpdate = item
    waitingVersion = version
    if !alreadyWaiting {
      Self.logger.info("Update \(item.displayVersionString, privacy: .public) is waiting to install on quit")
      host.updateWillInstallOnQuit()
      menu.setUpdateWaiting(true)
      idleInstaller.start()
      // The waiting update replaces "Update Complete!" (add-update-banners D1).
      bannerState.banner = .waiting(version: version)
    }
    if userInitiated {
      restartToUpdate(confirming: true)
    }
  }

  func chooseUpdateItem() {
    if waitingUpdate != nil {
      restartToUpdate(confirming: true)
    } else if let updater, startError == nil {
      updater.checkForUpdates()
    } else {
      prompts.showCheckFailed(reason: startError?.localizedDescription ?? "The updater isn't running.")
    }
  }

  /// Relaunches into the waiting update, the one path behind both Restart and
  /// Update buttons (add-update-banners D2). The menu item confirms with the
  /// version alert first; the banner's click is the confirmation. Neither asks
  /// about incognito windows, as in Arc: they close and don't come back.
  /// Chromium's relaunch still warns before cancelling a download, and
  /// restores the session.
  func restartToUpdate(confirming: Bool) {
    guard waitingUpdate != nil, let waitingVersion else {
      return
    }
    if confirming, !prompts.askToRestart(forVersion: waitingVersion) {
      return
    }
    host.relaunch()
  }

  /// The user has been away long enough. Installs the waiting update unless
  /// that would interrupt something, and if so tries again later. Chromium's
  /// relauncher keeps Clair in the background if another app was active.
  func installWhileIdle() {
    let blockers = host.silentRelaunchBlockers()
    guard blockers.isEmpty else {
      Self.logger.info("Not installing the update while idle: blockers \(blockers.rawValue)")
      return
    }
    Self.logger.info("Installing the update while idle")
    host.relaunch()
  }

  var menuItemForTesting: NSMenuItem {
    menu.item
  }

  // MARK: - SPUUpdaterDelegate

  func feedURLString(for updater: SPUUpdater) -> String? {
    configuration.feedURLOverride
  }

  /// A background download has finished, and Autoupdate is waiting for Clair
  /// to quit. Returning true keeps this cycle open, so Sparkle starts no more
  /// checks and never brings the update up with the user driver on its own.
  func updater(
    _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
    immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
  ) -> Bool {
    updateIsWaiting(item, userInitiated: false)
    return true
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
    Self.logger.info("No update: \(error.localizedDescription, privacy: .public)")
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
    Self.logger.error("Update stopped: \(error.localizedDescription, privacy: .public)")
  }
}
