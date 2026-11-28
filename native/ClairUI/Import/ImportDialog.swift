// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The import dialog (add-browser-import design D9): `ImportFlow`'s steps on
/// a stepped `ClairDialog`, its card the same width on every step.
@MainActor
enum ImportDialog {
  static let width: CGFloat = 520
  static var contentWidth: CGFloat { ClairDialogView.contentWidth(forCardWidth: width) }

  /// Shows the flow on `presenter`'s window. `chooseFile` asks for Safari's
  /// export with a file panel.
  @discardableResult
  static func show(
    _ flow: ImportFlow, on presenter: ClairDialogPresenter, chooseFile: @escaping @MainActor (ImportFlow) -> Void,
    completion: @escaping @MainActor () -> Void = {}
  ) -> ClairDialog {
    let dialog = ClairDialog(page(for: flow, chooseFile: chooseFile))
    follow(flow, in: dialog, chooseFile: chooseFile)
    presenter.show(dialog) { _ in completion() }
    return dialog
  }

  /// Keeps the card's title and buttons following the flow; its content
  /// views follow it themselves.
  private static func follow(
    _ flow: ImportFlow, in dialog: ClairDialog, chooseFile: @escaping @MainActor (ImportFlow) -> Void
  ) {
    withObservationTracking {
      _ = (flow.step, flow.title, flow.defaultButtonTitle, flow.detailsAction, flow.sources.count)
    } onChange: { [weak dialog, weak flow] in
      Task { @MainActor in
        guard let dialog, let flow, dialog.presenter != nil else { return }
        dialog.update { $0 = page(for: flow, chooseFile: chooseFile) }
        follow(flow, in: dialog, chooseFile: chooseFile)
      }
    }
  }

  static func page(for flow: ImportFlow, chooseFile: @escaping @MainActor (ImportFlow) -> Void) -> ClairDialogPage {
    let cancel = ClairDialogButton(title: "Cancel", role: .cancel)
    switch flow.step {
    case .choose:
      return ClairDialogPage(
        title: flow.title, message: ImportFlow.chooseMessage, content: AnyView(SourceCards(flow: flow)),
        buttons: [
          cancel,
          ClairDialogButton(
            title: flow.defaultButtonTitle ?? "Continue", role: .default, isEnabled: !flow.sources.isEmpty,
            action: { _ in flow.continueToDetails() }),
        ],
        width: width, isStepped: true)
    case .details:
      return ClairDialogPage(
        title: flow.title, content: AnyView(DetailsView(flow: flow)),
        buttons: [
          cancel,
          ClairDialogButton(
            title: flow.defaultButtonTitle ?? "Import", role: .default,
            action: { _ in
              switch flow.detailsAction {
              case .chooseFile: chooseFile(flow)
              case .quitSource: flow.quitSource()
              case .importNow: flow.startImport()
              }
            }),
        ],
        width: width, isStepped: true,
        backButton: ClairDialogButton(title: "Back", role: .cancel, action: { _ in flow.back() }))
    case .importing:
      return ClairDialogPage(title: flow.title, content: AnyView(ProgressStep(flow: flow)), buttons: [], width: width, isStepped: true)
    case .summary:
      return ClairDialogPage(
        title: flow.title, content: AnyView(SummaryView(flow: flow)),
        buttons: [ClairDialogButton(title: "Done", role: .default)], width: width, escapePressesDefault: true,
        isStepped: true)
    }
  }

  /// Asks for Safari's export with an open panel on `window`.
  static func chooseSafariFile(for flow: ImportFlow, on window: NSWindow?) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.zip, .folder]
    panel.message = "Choose the .zip Safari exported, or the folder it unpacks to."
    let done: (NSApplication.ModalResponse) -> Void = { response in
      if response == .OK, let url = panel.url {
        flow.chooseSafariFile(url)
      }
    }
    if let window = window?.attachedSheet ?? window {
      panel.beginSheetModal(for: window, completionHandler: done)
    } else {
      panel.begin(completionHandler: done)
    }
  }
}

// MARK: Step 1: choosing a browser

/// The browser cards, two per row (design D9): the app icon at 40 pt, its name
/// and a trailing radio; the selected card's border in the accent colour.
private struct SourceCards: View {
  @Bindable var flow: ImportFlow
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    LazyVGrid(columns: columns, spacing: 10) {
      ForEach(Array(flow.sources.enumerated()), id: \.offset) { index, source in
        card(source, selected: index == flow.selectedIndex)
          .contentShape(Rectangle())
          .onTapGesture { flow.selectedIndex = index }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(source.name)
          .accessibilityAddTraits(.isButton)
          .accessibilityAddTraits(index == flow.selectedIndex ? .isSelected : [])
          .accessibilityIdentifier("clair.importSource.\(source.id)")
          .accessibilityAction { flow.selectedIndex = index }
      }
    }
    .padding(.top, 8)
  }

  private func card(_ source: any ImportSource, selected: Bool) -> some View {
    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    return HStack(spacing: 12) {
      Image(nsImage: source.icon)
        .resizable()
        .interpolation(.high)
        .frame(width: 40, height: 40)
      Text(source.name)
        .font(.system(size: 14, weight: .medium))
      Spacer(minLength: 4)
      Image(systemName: selected ? "largecircle.fill.circle" : "circle")
        .font(.system(size: 15))
        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
    }
    .padding(.horizontal, 14)
    .frame(height: 64)
    .background(shape.fill(ClairDialogView.listBackground(colorScheme)))
    .overlay(
      shape.strokeBorder(
        selected ? Color.accentColor : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.1)),
        lineWidth: selected ? 2 : 1))
  }
}

// MARK: Step 2: what comes over, and where

private struct DetailsView: View {
  @Bindable var flow: ImportFlow

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if flow.needsSafariFile {
        SafariInstructions(flow: flow)
      } else {
        if let note = flow.privacyNote {
          Text(note)
            .font(.system(size: 13))
            .foregroundStyle(Color(nsColor: ClairDialogView.secondaryTextColor))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("clair.importPrivacyNote")
        }
        ItemsList(kinds: flow.source.items)
        ProfileRows(flow: flow)
        if let notice = flow.quitNotice {
          Label(notice, systemImage: "exclamationmark.circle")
            .font(.system(size: 13, weight: .medium))
            .accessibilityIdentifier("clair.importQuitNotice")
        }
      }
    }
    .padding(.top, 4)
  }
}

/// What the source brings, each with its icon, two per row, with no counts
/// and nothing to leave out.
private struct ItemsList: View {
  let kinds: [ImportItemKind]
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
      ForEach(kinds, id: \.self) { kind in
        Label(kind.title, systemImage: kind.symbol)
          .font(.system(size: 13))
          .accessibilityIdentifier("clair.importItem.\(kind.rawValue)")
      }
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ClairDialogView.listBackground(colorScheme)))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.importItems")
  }
}

/// A row per source profile with its "Import into" popup.
private struct ProfileRows: View {
  @Bindable var flow: ImportFlow

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(flow.rows.enumerated()), id: \.offset) { index, row in
        HStack {
          Text(row.profile.name)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer(minLength: 12)
          Picker(
            "Import into",
            selection: Binding(get: { flow.rows[index].destination }, set: { flow.setDestination($0, forRow: index) })
          ) {
            ForEach(flow.profiles, id: \.id) { profile in
              Text(profile.name).tag(ImportFlow.Destination.profile(profile.id))
            }
            Divider()
            Text("New Profile").tag(ImportFlow.Destination.newProfile)
          }
          .pickerStyle(.menu)
          .fixedSize()
          .accessibilityIdentifier("clair.importDestination.\(index)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clair.importRow.\(index)")
      }
    }
  }
}

/// Safari's export steps and the area that takes the file (design D6; Dia's
/// steps, in Clair's words).
private struct SafariInstructions: View {
  @Bindable var flow: ImportFlow
  @State private var isTargeted = false

  static let steps = [
    "Open Safari.",
    "Choose File › Export Browsing Data to File…",
    "Export your bookmarks and history, and save the file.",
    "Drop the file here, or choose it.",
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Safari keeps its data where only Safari can read it, so export it first:")
        .font(.system(size: 13))
        .foregroundStyle(Color(nsColor: ClairDialogView.secondaryTextColor))
        .fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(index + 1).")
              .monospacedDigit()
              .foregroundStyle(.secondary)
            Text(step)
          }
          .font(.system(size: 13))
        }
      }
      let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
      VStack(spacing: 6) {
        Image(systemName: "doc.zipper")
          .font(.system(size: 22))
          .foregroundStyle(.secondary)
        Text("Drop Safari's .zip here")
          .font(.system(size: 13, weight: .medium))
        if let error = flow.safariError {
          Text(error)
            .font(.system(size: 12))
            .foregroundStyle(Color(nsColor: .systemRed))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("clair.importFileError")
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, minHeight: 96)
      .background(shape.fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.clear))
      .overlay(shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(.secondary))
      .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
          guard let url else { return }
          Task { @MainActor in flow.chooseSafariFile(url) }
        }
        return true
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("clair.importDropArea")
    }
  }
}

// MARK: Importing and the summary

private struct ProgressStep: View {
  let flow: ImportFlow

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ProgressView(value: flow.progress)
        .progressViewStyle(.linear)
        .accessibilityIdentifier("clair.importProgress")
      Text(flow.phaseText)
        .font(.system(size: 13))
        .foregroundStyle(Color(nsColor: ClairDialogView.secondaryTextColor))
    }
    .padding(.top, 8)
  }
}

private struct SummaryView: View {
  let flow: ImportFlow
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(flow.summaryLines, id: \.self) { line in
          Text(line)
            .font(.system(size: 13))
            .accessibilityIdentifier("clair.importCount")
        }
      }
      if !flow.skippedLines.isEmpty {
        Text("Not imported")
          .font(.system(size: 13, weight: .semibold))
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(flow.skippedLines.enumerated()), id: \.offset) { _, line in
              Text(line)
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: ClairDialogView.secondaryTextColor))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("clair.importSkipped")
            }
          }
          .padding(10)
        }
        .frame(maxHeight: 140)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ClairDialogView.listBackground(colorScheme)))
      }
    }
    .padding(.top, 4)
  }
}

// MARK: The menu item

/// Clair › Import from Another Browser… (browser-import "Import menu item"):
/// the dialog on the frontmost window, on a new window when none is open,
/// and one dialog at a time.
@MainActor
final class ImportMenu: NSObject {
  static let title = "Import from Another Browser…"

  let item = NSMenuItem(title: ImportMenu.title, action: #selector(choose), keyEquivalent: "")
  private let host: any ClairHost
  private let environment: () -> ImportEnvironment
  /// The dialog showing, and the window it shows on.
  private(set) weak var dialog: ClairDialog?
  private weak var dialogWindow: NSWindow?
  /// Set while a new window opens for the dialog.
  private var waitingForWindow = false

  init(host: any ClairHost, environment: @escaping () -> ImportEnvironment = { .current }) {
    self.host = host
    self.environment = environment
    super.init()
    item.target = self
  }

  /// Adds the item to the Clair menu where Chromium's "Import Bookmarks and
  /// Settings…" stood, after Clear Browsing Data…, or else after Settings….
  func install(in mainMenu: NSMenu?) {
    guard let appMenu = mainMenu?.items.first?.submenu, appMenu.index(of: item) < 0 else { return }
    appMenu.insertItem(item, at: Self.insertionIndex(in: appMenu))
  }

  static func insertionIndex(in appMenu: NSMenu) -> Int {
    let titles = appMenu.items.map(\.title)
    if let index = titles.firstIndex(where: { $0.hasPrefix("Import Bookmarks") }) {
      return index + 1
    }
    if let index = titles.firstIndex(where: { $0.hasPrefix("Clear Browsing Data") }) {
      return index + 1
    }
    if let index = titles.firstIndex(where: { $0.hasPrefix("Settings") }) {
      return index + 1
    }
    return min(1, appMenu.numberOfItems)
  }

  @objc func choose() {
    if let dialog, dialog.presenter != nil, let window = dialogWindow {
      window.makeKeyAndOrderFront(nil)
      return
    }
    if let controller = BrowserWindowController.main {
      show(on: controller)
    } else if !waitingForWindow {
      waitingForWindow = true
      BrowserWindowController.whenNextOpens { [weak self] controller in
        guard let self else { return }
        waitingForWindow = false
        show(on: controller)
      }
      // Chromium's File › New Window, which opens a window with no other one
      // open.
      let newWindow = NSMenuItem()
      newWindow.tag = Self.newWindowCommand
      NSApp.sendAction(NSSelectorFromString("commandDispatch:"), to: nil, from: newWindow)
    }
  }

  /// Chromium's IDC_NEW_WINDOW.
  static let newWindowCommand = 34000

  func show(on controller: BrowserWindowController) {
    guard dialog?.presenter == nil else { return }
    let flow = ImportFlow(
      host: host, environment: environment(), shownProfile: controller.model.shownSpace?.profileID)
    let window = controller.window
    dialog = ImportDialog.show(flow, on: controller.dialogs) { flow in
      ImportDialog.chooseSafariFile(for: flow, on: window)
    }
    dialogWindow = window
  }
}
