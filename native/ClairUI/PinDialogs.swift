// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost
import SwiftUI

/// The favorite's "Rename Tab…" dialog and Edit Pinned URL
/// (add-pinned-tabs-and-favorites design D6, D11), as `ClairDialog`s worded
/// as Arc's sheets.
@MainActor
enum PinDialogs {
  // MARK: Wording

  static let renameTitle = "Rename Tab…"
  static let renamePlaceholder = "Keep it short and sweet!"
  static let renameButton = "Rename"

  static let editTitle = "Edit Pinned URL"
  static let editMessage = "This is what opens first when you click this tab or its favicon."
  static let editPlaceholder = "Enter a URL…"
  static let editButton = "Save"

  // MARK: Pages

  static func renamePage(state: ProfileNameState) -> ClairDialogPage {
    ClairDialogPage(
      title: renameTitle,
      content: AnyView(
        PinTextField(state: state, placeholder: renamePlaceholder, identifier: "clair.renameFavoriteField")),
      buttons: [
        ClairDialogButton(title: "Cancel", role: .cancel),
        ClairDialogButton(title: renameButton, role: .default),
      ])
  }

  static func editPage(state: ProfileNameState, icon: NSImage?) -> ClairDialogPage {
    ClairDialogPage(
      icon: icon, title: editTitle, message: editMessage,
      content: AnyView(PinTextField(state: state, placeholder: editPlaceholder, identifier: "clair.pinnedURLField")),
      buttons: [
        ClairDialogButton(title: "Cancel", role: .cancel),
        ClairDialogButton(title: editButton, role: .default, isEnabled: canSave(state.text)),
      ])
  }

  /// Save needs a URL (pinned-tabs spec, "Editing the pinned URL").
  static func canSave(_ text: String) -> Bool {
    PinsLogic.fixedUpURL(text) != nil
  }

  // MARK: Showing

  /// Asks for a favorite's name; an empty one clears it.
  @discardableResult
  static func showRename(of pin: any ClairPin, on presenter: ClairDialogPresenter, spaces: SpacesModel)
    -> ClairDialog
  {
    let state = ProfileNameState(text: pin.name ?? pin.title)
    let dialog = ClairDialog(renamePage(state: state))
    bind(state, to: dialog, enabled: { _ in true })
    let pinID = pin.pinID
    let current = pin.name
    presenter.show(dialog) { answer in
      guard answer == .accepted else { return }
      switch PinsLogic.nameChange(draft: state.text, current: current) {
      case .unchanged: break
      case .rename(let name): spaces.setName(name, forPin: pinID)
      case .clear: spaces.setName(nil, forPin: pinID)
      }
    }
    return dialog
  }

  /// Asks for a pin's URL, with the current one selected.
  @discardableResult
  static func showEditURL(of pin: any ClairPin, on presenter: ClairDialogPresenter, spaces: SpacesModel)
    -> ClairDialog
  {
    let state = ProfileNameState(text: pin.url.absoluteString)
    let dialog = ClairDialog(editPage(state: state, icon: pin.icon))
    bind(state, to: dialog, enabled: canSave)
    let pinID = pin.pinID
    presenter.show(dialog) { answer in
      if answer == .accepted, let url = PinsLogic.fixedUpURL(state.text) {
        spaces.setPinnedURL(url, forPin: pinID)
      }
    }
    return dialog
  }

  /// Keeps the default button enabled by `enabled`, and makes Return in the
  /// field press it.
  private static func bind(_ state: ProfileNameState, to dialog: ClairDialog, enabled: @escaping (String) -> Bool) {
    states.setObject(state, forKey: dialog)
    state.onChange = { [weak dialog, weak state] in
      guard let dialog, let state else { return }
      dialog.update { page in
        for index in page.buttons.indices where page.buttons[index].isDefault {
          page.buttons[index].isEnabled = enabled(state.text)
        }
      }
    }
    state.onSubmit = { [weak dialog] in
      guard let dialog, let button = dialog.page.buttons.first(where: \.isDefault) else { return }
      dialog.press(button)
    }
  }

  private static let states = NSMapTable<ClairDialog, ProfileNameState>.weakToStrongObjects()
}

/// A pin dialog's field, its text selected when it appears.
struct PinTextField: View {
  @Bindable var state: ProfileNameState
  let placeholder: String
  let identifier: String

  var body: some View {
    TextField(placeholder, text: $state.text)
      .textFieldStyle(.roundedBorder)
      .font(.system(size: 14))
      .onSubmit { state.onSubmit?() }
      .accessibilityIdentifier(identifier)
  }
}
