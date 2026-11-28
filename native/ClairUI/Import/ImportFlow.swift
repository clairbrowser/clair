// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Foundation
import Observation

/// Whether a source browser runs, and asking it to quit (design D14); a fake
/// in tests.
@MainActor
protocol ImportAppWatcher: AnyObject {
  func isRunning(_ bundleID: String) -> Bool
  /// Asks the app to quit, as its own Quit command does.
  func terminate(_ bundleID: String)
  /// Called whenever an app launches or quits.
  var onChange: (() -> Void)? { get set }
}

/// `NSWorkspace`'s running apps and their launch and quit notifications.
@MainActor
final class WorkspaceAppWatcher: ImportAppWatcher {
  var onChange: (() -> Void)?
  nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

  init() {
    let center = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.onChange?() }
        })
    }
  }

  deinit {
    for observer in observers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
  }

  func isRunning(_ bundleID: String) -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
  }

  func terminate(_ bundleID: String) {
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
      app.terminate()
    }
  }
}

/// Runs an import: makes the plan off the main thread, hands it to the engine
/// and reports its progress and summary (design D1). The import dialog and a
/// later onboarding dialog share it.
@MainActor
final class ImportCoordinator {
  let host: any ClairHost
  let environment: ImportEnvironment

  init(host: any ClairHost, environment: ImportEnvironment) {
    self.host = host
    self.environment = environment
  }

  /// Reads `source` into a plan for `destinations` and applies it. `progress`
  /// gets the fraction done and the phase; the summary includes what the
  /// reader skipped.
  func run(
    _ source: any ImportSource, destinations: [String: ImportPlan.Destination],
    progress: @escaping @MainActor (Double, String) -> Void
  ) async -> ImportSummary {
    progress(0, ImportFlow.readingPhase)
    let environment = environment
    let made = await Task.detached { () -> Result<ImportPlan, any Error> in
      let folder: ImportWorkFolder
      do {
        folder = try ImportWorkFolder.create(in: environment.temporaryDirectory)
      } catch {
        return .failure(error)
      }
      do {
        let context = ImportContext(destinations: destinations, folder: folder, keychain: environment.keychain)
        return .success(try source.makePlan(context))
      } catch {
        folder.remove()
        return .failure(error)
      }
    }.value
    guard case .success(let plan) = made, let json = try? plan.json() else {
      return ImportSummary(skipped: [ImportSkip(reason: .importFailed, name: source.name)])
    }
    let readerSkips = plan.profiles.flatMap(\.skipped)
    return await withCheckedContinuation { continuation in
      host.applyImportPlan(json) { fraction, phase in
        MainActor.assumeIsolated { progress(fraction, phase) }
      } completion: { data in
        MainActor.assumeIsolated {
          var summary = (try? ImportSummary(json: data)) ?? ImportSummary(skipped: [ImportSkip(reason: .importFailed, name: source.name)])
          summary.skipped = readerSkips + summary.skipped
          continuation.resume(returning: summary)
        }
      }
    }
  }
}

/// The import's steps and state (design D9, D14): choose a source, then its
/// items, destinations and requirement, then the import's progress and its
/// summary. It knows nothing of the window, so the import dialog and a later
/// onboarding dialog can both present it.
@MainActor
@Observable
final class ImportFlow {
  enum Step: Equatable {
    case choose
    case details
    case importing
    case summary
  }

  /// A Clair profile a row can import into, or a new one.
  enum Destination: Hashable {
    case profile(ProfileID)
    case newProfile
  }

  /// A row of the second step: one of the source's profiles.
  struct Row: Equatable {
    var profile: ImportSourceProfile
    var destination: Destination
  }

  static let readingPhase = "reading"
  static let chooseTitle = "Import from your old browser"
  static let chooseMessage = "Import everything you need from your old browser to hit the ground running with Clair."
  static let diaNote =
    "Clair reads your Dia data only on this Mac, to import it into Clair. Nothing is sent anywhere. Your Mac will ask to let Clair use “Dia Safe Storage” from your keychain: Clair needs it only to read Dia's tabs."
  static let wrongFile = "This file isn't a Safari export. Choose the .zip Safari saved, or the folder it unpacks to."
  static let summaryTitle = "Import Complete"

  /// The sources on this Mac, in the first step's order.
  let sources: [any ImportSource]
  private(set) var step: Step = .choose
  /// The selected card.
  var selectedIndex = 0
  private(set) var rows: [Row] = []
  /// Every Clair profile, for the "Import into" popups.
  private(set) var profiles: [(id: ProfileID, name: String)] = []
  /// The chosen Safari export, once it checked out.
  private(set) var safariExport: SafariExport?
  /// Why the chosen Safari file was refused.
  private(set) var safariError: String?
  /// Whether the selected source is running, so the step asks to quit it.
  private(set) var isSourceRunning = false
  private(set) var progress: Double = 0
  private(set) var phase = ImportFlow.readingPhase
  private(set) var summary: ImportSummary?
  /// The import running, for tests to wait on.
  @ObservationIgnored private(set) var importTask: Task<Void, Never>?

  @ObservationIgnored private let host: any ClairHost
  @ObservationIgnored private let coordinator: ImportCoordinator
  @ObservationIgnored private let apps: any ImportAppWatcher
  /// The profile of the Space the window shows.
  @ObservationIgnored private let shownProfile: ProfileID?

  init(
    host: any ClairHost, environment: ImportEnvironment, shownProfile: ProfileID?,
    apps: any ImportAppWatcher = WorkspaceAppWatcher(), sources: [any ImportSource]? = nil
  ) {
    self.host = host
    self.sources = sources ?? ImportSources.present(environment)
    coordinator = ImportCoordinator(host: host, environment: environment)
    self.apps = apps
    self.shownProfile = shownProfile
    apps.onChange = { [weak self] in self?.refreshRunning() }
  }

  var source: any ImportSource { sources[min(selectedIndex, sources.count - 1)] }

  // MARK: Steps

  /// Continue on the first step.
  func continueToDetails() {
    guard step == .choose, !sources.isEmpty else { return }
    profiles = host.profiles.map { ($0.profileID, $0.name) }
    let sourceProfiles = source.profiles()
    rows = sourceProfiles.enumerated().map { index, profile in
      Row(profile: profile, destination: index == 0 ? defaultDestination : .newProfile)
    }
    safariExport = nil
    safariError = nil
    step = .details
    refreshRunning()
  }

  /// The first row's destination: the shown Space's profile, or the first
  /// profile when it's unknown.
  private var defaultDestination: Destination {
    if let shownProfile, profiles.contains(where: { $0.id == shownProfile }) {
      return .profile(shownProfile)
    }
    return profiles.first.map { .profile($0.id) } ?? .newProfile
  }

  /// Back on the second step: the first step, the source still selected.
  func back() {
    guard step == .details else { return }
    step = .choose
  }

  func setDestination(_ destination: Destination, forRow index: Int) {
    guard rows.indices.contains(index) else { return }
    rows[index].destination = destination
  }

  /// Checks the Safari file the user dropped or chose.
  func chooseSafariFile(_ url: URL) {
    do {
      safariExport = try SafariExport.check(url)
      safariError = nil
    } catch {
      safariExport = nil
      safariError = Self.wrongFile
    }
  }

  /// Whether the step needs Safari's file before it can import.
  var needsSafariFile: Bool { source.requirement == .exportFile && safariExport == nil }

  /// What the default button does on the second step.
  enum DetailsAction: Equatable {
    case chooseFile
    case quitSource
    case importNow
  }

  var detailsAction: DetailsAction {
    if needsSafariFile { return .chooseFile }
    if isSourceRunning { return .quitSource }
    return .importNow
  }

  /// Asks the running source to quit. Its own confirmations still apply, so
  /// the step changes only once it has quit.
  func quitSource() {
    apps.terminate(source.bundleID)
  }

  private func refreshRunning() {
    // Safari's data comes from a file, so it may keep running.
    isSourceRunning = source.requirement != .exportFile && apps.isRunning(source.bundleID)
  }

  /// Import on the second step: reads the source, now that the user asked,
  /// and applies the plan.
  func startImport() {
    guard step == .details, detailsAction == .importNow else { return }
    var importing = source
    if var safari = importing as? SafariExportSource {
      safari.export = safariExport
      importing = safari
    }
    let destinations = Dictionary(
      uniqueKeysWithValues: rows.map { row -> (String, ImportPlan.Destination) in
        switch row.destination {
        case .profile(let id): (row.profile.key, .profile(id))
        case .newProfile: (row.profile.key, .newProfile(row.profile.newProfileName))
        }
      })
    step = .importing
    progress = 0
    phase = Self.readingPhase
    importTask = Task { [weak self, coordinator] in
      let summary = await coordinator.run(importing, destinations: destinations) { fraction, phase in
        self?.progress = fraction
        self?.phase = phase
      }
      self?.summary = summary
      self?.step = .summary
    }
  }

  // MARK: Words

  var title: String {
    switch step {
    case .choose: Self.chooseTitle
    case .details: "Import from \(source.name)"
    case .importing: "Importing from \(source.name)…"
    case .summary: Self.summaryTitle
    }
  }

  var defaultButtonTitle: String? {
    switch step {
    case .choose: "Continue"
    case .details:
      switch detailsAction {
      case .chooseFile: "Choose File…"
      case .quitSource: "Quit \(source.name)"
      case .importNow: "Import"
      }
    case .importing: nil
    case .summary: "Done"
    }
  }

  /// Said above the rows while the source runs.
  var quitNotice: String? {
    step == .details && isSourceRunning && !needsSafariFile ? "Quit \(source.name) to import from it." : nil
  }

  /// Dia's privacy note, above the rows.
  var privacyNote: String? {
    if case .keychain = source.requirement { return Self.diaNote }
    return nil
  }

  /// What the progress line says.
  var phaseText: String {
    switch phase {
    case Self.readingPhase: "Reading \(source.name)…"
    case "profiles": "Creating profiles…"
    case "sidebar": "Adding Spaces and tabs…"
    case "bookmarks": "Adding bookmarks…"
    case "history": "Adding history…"
    case "favicons": "Adding icons…"
    case "extensions": "Installing extensions…"
    default: "Importing…"
    }
  }

  /// The summary's lines: a count per kind imported, in the second step's
  /// order, then what was already in Clair.
  var summaryLines: [String] {
    guard let summary else { return [] }
    let kinds: [(ImportItemKind, KeyPath<ImportSummary.Counts, Int>, String, String)] = [
      (.spaces, \.spaces, "Space", "Spaces"),
      (.favorites, \.favorites, "favorite", "favorites"),
      (.pinnedTabs, \.pinnedTabs, "pinned tab", "pinned tabs"),
      (.todayTabs, \.todayTabs, "Today tab", "Today tabs"),
      (.bookmarks, \.bookmarks, "bookmark", "bookmarks"),
      (.history, \.history, "history entry", "history entries"),
      (.extensions, \.extensions, "extension", "extensions"),
    ]
    var lines: [String] = []
    for (kind, path, one, many) in kinds where source.items.contains(kind) {
      let count = summary.imported[keyPath: path]
      lines.append("\(count.formatted()) \(count == 1 ? one : many)")
    }
    let already = kinds.compactMap { _, path, one, many -> String? in
      let count = summary.alreadyInClair[keyPath: path]
      return count == 0 ? nil : "\(count.formatted()) \(count == 1 ? one : many)"
    }
    if !already.isEmpty {
      lines.append("Already in Clair: " + already.joined(separator: ", "))
    }
    return lines
  }

  /// The summary's skipped items, each with why.
  var skippedLines: [String] {
    (summary?.skipped ?? []).map { skip in
      switch skip.reason {
      case .notFromWebStore: "\(skip.name): not from the Chrome Web Store"
      case .themeOrApp: "\(skip.name): a theme or an app"
      case .alreadyInstalled: "\(skip.name): already installed"
      case .storeFailed: "\(skip.name): the Chrome Web Store couldn't provide it"
      case .unsupportedItem: "\(skip.name): Clair has no place for it"
      case .sidebarUnreadable:
        source.requirement == .keychain(service: "Dia Safe Storage")
          ? "\(skip.name) couldn't be read without access to “Dia Safe Storage”, or in this version of \(source.name)"
          : "\(skip.name) couldn't be read"
      case .unreadableData: "\(skip.name): couldn't be read"
      case .invalidURL: "\(skip.name): not a web address"
      case .importFailed: "The import from \(skip.name) couldn't run"
      }
    }
  }
}
