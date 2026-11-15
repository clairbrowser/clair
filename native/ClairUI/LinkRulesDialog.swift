// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import Observation
import SwiftUI

/// The Link Rules dialog (add-link-rules design D5): Dia's controls and
/// layout on a Clair dialog. The rows are its content, "Add Rule" its leading
/// button, and Cancel, which turns into "Discard Changes" over unsaved edits,
/// and Done its buttons.
enum LinkRulesDialog {
  /// Dia's dialog is 640 pt wide.
  static let width: CGFloat = 640
  static let doneTitle = "Done"
  static let cancelTitle = "Cancel"

  /// Reads the rules from `host` and shows them on `presenter`'s window.
  /// Done saves them all through the host. `completion` says whether it did.
  @discardableResult
  static func show(
    on presenter: ClairDialogPresenter, host: any ClairHost, spaces: SpacesModel,
    completion: @escaping @MainActor (Bool) -> Void = { _ in }
  ) -> (ClairDialog, LinkRulesState) {
    let state = LinkRulesState(host: host, spaces: spaces)
    let dialog = ClairDialog(page(state: state))
    keepButtons(of: dialog, for: state)
    // Return in a row's field chooses Done, as Return elsewhere does.
    state.onSubmit = { [weak dialog] in
      guard let dialog, let done = dialog.page.buttons.first(where: \.isDefault) else { return }
      dialog.press(done)
    }
    presenter.show(dialog) { answer in
      completion(answer == .accepted)
    }
    return (dialog, state)
  }

  static func page(state: LinkRulesState) -> ClairDialogPage {
    ClairDialogPage(
      title: LinkRulesState.title,
      content: AnyView(LinkRulesList(state: state, width: ClairDialogView.contentWidth(forCardWidth: width))),
      buttons: buttons(for: state),
      leadingButton: addRuleButton(for: state),
      width: width)
  }

  /// Cancel, or the red Discard Changes, then Done. Neither answers by
  /// itself: Cancel asks the state first, and Done saves first.
  static func buttons(for state: LinkRulesState) -> [ClairDialogButton] {
    [
      ClairDialogButton(
        title: state.showsDiscard ? LinkRulesState.discardChanges : cancelTitle, role: .cancel,
        isDestructive: state.showsDiscard,
        action: { dialog in
          if state.cancel() {
            dialog.answer(.cancelled)
          }
        }),
      ClairDialogButton(
        title: doneTitle, role: .default,
        action: { dialog in
          if state.save() {
            dialog.answer(.accepted)
          }
        }),
    ]
  }

  static func addRuleButton(for state: LinkRulesState) -> ClairDialogButton {
    ClairDialogButton(
      title: LinkRulesState.addRule, role: .cancel, isEnabled: state.canAddRule,
      action: { _ in state.addRule() })
  }

  /// Keeps the page's buttons following the state: Cancel turning into
  /// Discard Changes and back, and Add Rule as Spaces come and go.
  private static func keepButtons(of dialog: ClairDialog, for state: LinkRulesState) {
    let (buttons, leading) = withObservationTracking {
      (buttons(for: state), addRuleButton(for: state))
    } onChange: { [weak dialog, weak state] in
      Task { @MainActor in
        guard let dialog, let state, dialog.presenter != nil else { return }
        keepButtons(of: dialog, for: state)
      }
    }
    dialog.update { page in
      page.buttons = buttons
      page.leadingButton = leading
    }
  }
}

/// The list area: Dia's grey rounded area holding a row per rule, separated
/// by inset hairlines, or the empty state's message, then the error line.
struct LinkRulesList: View {
  let state: LinkRulesState
  let width: CGFloat
  @Environment(\.colorScheme) private var colorScheme
  @FocusState private var focusedField: LinkRulesState.Row.ID?

  /// Dia's rows are about 48.5 pt tall, and its list area at least 146.
  static let rowHeight: CGFloat = 48
  static let minHeight: CGFloat = 146
  /// Beyond this the list scrolls, so the dialog fits on the Settings
  /// window's screen.
  static let maxHeight: CGFloat = 340

  static func listHeight(rows: Int) -> CGFloat {
    min(max(minHeight, CGFloat(rows) * rowHeight), maxHeight)
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    VStack(alignment: .leading, spacing: 0) {
      Group {
        if let message = state.emptyMessage {
          Text(message)
            .font(.system(size: 13))
            .foregroundStyle(Color(nsColor: ClairDialogView.secondaryTextColor))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("clair.linkRulesEmpty")
        } else {
          rows
        }
      }
      .frame(width: width, height: Self.listHeight(rows: state.rows.count))
      .background(shape.fill(ClairDialogView.listBackground(colorScheme)))
      .clipShape(shape)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("clair.linkRulesList")
      if let error = state.error {
        Text(error)
          .font(.system(size: 13))
          .foregroundStyle(Color(nsColor: .systemOrange))
          .frame(height: 25, alignment: .bottom)
          .accessibilityIdentifier("clair.linkRulesError")
      }
    }
    .onChange(of: state.focusedRow) { _, row in
      focusedField = row
    }
  }

  private var rows: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical) {
        VStack(spacing: 0) {
          ForEach(Array(state.rows.enumerated()), id: \.element.id) { index, row in
            if index > 0 {
              Rectangle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.08))
                .frame(height: 1)
                .padding(.horizontal, 12)
            }
            LinkRuleRow(state: state, row: row, focusedField: $focusedField)
              .frame(height: Self.rowHeight - (index > 0 ? 1 : 0))
              .id(row.id)
          }
        }
      }
      .scrollBounceBehavior(.basedOnSize)
      .onChange(of: state.rows.count) { old, new in
        if new > old, let last = state.rows.last {
          proxy.scrollTo(last.id, anchor: .bottom)
        }
      }
    }
  }
}

/// `Open [match ⌃] [text field] in [Space ⌃] ×`, as Dia's row.
private struct LinkRuleRow: View {
  let state: LinkRulesState
  let row: LinkRulesState.Row
  var focusedField: FocusState<LinkRulesState.Row.ID?>.Binding

  var body: some View {
    HStack(spacing: 8) {
      Text("Open")
        .foregroundStyle(Color(nsColor: ClairDialogView.secondaryTextColor))
      Picker(
        "Match",
        selection: Binding(get: { row.match }, set: { state.setMatch($0, of: row.id) })
      ) {
        ForEach(LinkRuleMatch.menuOrder, id: \.self) { match in
          Text(match.title).tag(match)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .buttonStyle(.borderless)
      .frame(width: 142, alignment: .leading)
      .accessibilityIdentifier("clair.linkRuleMatch")
      TextField(
        LinkRulesState.placeholder,
        text: Binding(get: { row.text }, set: { state.setText($0, of: row.id) })
      )
      .textFieldStyle(.roundedBorder)
      .frame(width: 186)
      .focused(focusedField, equals: row.id)
      .onSubmit { state.onSubmit?() }
      .accessibilityLabel("Domain or URL")
      .accessibilityIdentifier("clair.linkRuleText")
      Text("in")
        .foregroundStyle(Color(nsColor: ClairDialogView.secondaryTextColor))
      Spacer(minLength: 4)
      spacePicker
      Button {
        state.remove(row.id)
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 22, height: 22)
          .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .help(LinkRulesState.removeLabel)
      .accessibilityLabel(LinkRulesState.removeLabel)
      .accessibilityIdentifier("clair.linkRuleRemove")
    }
    .font(.system(size: 13))
    .padding(.leading, 11)
    .padding(.trailing, 8)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clair.linkRule")
  }

  /// The Spaces, under their profiles' names when there's more than one
  /// profile. A row whose Space was deleted while the dialog is open shows
  /// "Choose a Space".
  private var spacePicker: some View {
    let current = state.space(of: row)?.spaceID ?? ""
    return Picker(
      "Space",
      selection: Binding(
        get: { current },
        set: { spaceID in
          if !spaceID.isEmpty {
            state.setSpace(spaceID, of: row.id)
          }
        })
    ) {
      if current.isEmpty {
        Text(LinkRulesState.chooseSpace).tag("")
      }
      ForEach(Array(state.spaceSections.enumerated()), id: \.offset) { _, section in
        if let title = section.title {
          Section(title) {
            spaceItems(section.spaces)
          }
        } else {
          spaceItems(section.spaces)
        }
      }
    }
    .labelsHidden()
    .pickerStyle(.menu)
    .buttonStyle(.borderless)
    .fixedSize()
    .accessibilityIdentifier("clair.linkRuleSpace")
  }

  private func spaceItems(_ spaces: [any ClairSpace]) -> some View {
    ForEach(spaces, id: \.spaceID) { space in
      Text(space.icon.map { "\($0)  \(space.name)" } ?? space.name).tag(space.spaceID)
    }
  }
}
