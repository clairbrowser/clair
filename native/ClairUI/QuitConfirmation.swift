// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import ClairHost

/// "Warn before quitting" (settings-window spec): the dialog Cmd+Q and
/// Clair › Quit Clair show while the setting is on, worded and laid out as
/// Dia's (`dia-reference/README.md` of the native-quit-confirmation
/// change): "Always quit" alone at the leading edge, Cancel and Quit at the
/// trailing one.
@MainActor
enum QuitConfirmation {
  static let title = "Are you sure you want to quit Clair?"
  static let message = "You may lose unsaved work in your tabs."
  static let alwaysQuit = "Always quit"
  static let quit = "Quit"

  /// `alwaysQuit` runs for "Always quit", which answers only through it.
  static func page(
    icon: NSImage? = NSApp.applicationIconImage, alwaysQuit: (@MainActor (ClairDialog) -> Void)? = nil
  ) -> ClairDialogPage {
    ClairDialogPage(
      icon: icon, title: title, message: message,
      buttons: [
        ClairDialogButton(title: "Cancel", role: .cancel),
        ClairDialogButton(title: quit, role: .destructive),
      ],
      leadingButton: ClairDialogButton(title: Self.alwaysQuit, role: .cancel, action: alwaysQuit))
  }

  /// Shows the dialog on `dialogs`, unless it already shows or waits there.
  /// Quit quits; Always quit turns the warning off first; Cancel, Esc or the
  /// window closing keep Clair running.
  static func show(on dialogs: ClairDialogPresenter, host: any ClairHost, icon: NSImage? = NSApp.applicationIconImage) {
    guard !dialogs.contains(where: { $0.page.title == title }) else { return }
    let page = Self.page(icon: icon) { dialog in
      host.warnsBeforeQuitting = false
      dialog.answer(.accepted)
    }
    dialogs.show(ClairDialog(page)) { answer in
      if answer == .accepted {
        host.quitWithoutWarning()
      }
    }
  }
}
