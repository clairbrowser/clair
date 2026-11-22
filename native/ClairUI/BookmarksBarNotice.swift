// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit

/// The Bookmarks Bar notice (add-bookmarks-menu design D6): the dialog the
/// engine asks for, once for the whole app, the first time it moves
/// bookmarks out of a Bookmarks Bar. One OK button, which Return and Esc
/// choose.
@MainActor
enum BookmarksBarNotice {
  static let title = "Heads Up"
  static let message =
    "Clair doesn't have a bookmarks bar, so bookmarks saved or imported there are moved to the Bookmarks menu."
  static let ok = "OK"

  static func page() -> ClairDialogPage {
    ClairDialogPage(
      title: title, message: message,
      buttons: [ClairDialogButton(title: ok, role: .default)],
      escapePressesDefault: true)
  }

  /// Shows the notice on `dialogs`, behind any other dialog there, unless it
  /// already shows or waits there.
  static func show(on dialogs: ClairDialogPresenter) {
    guard !dialogs.contains(where: { $0.page.title == title }) else { return }
    dialogs.show(ClairDialog(page())) { _ in }
  }
}
