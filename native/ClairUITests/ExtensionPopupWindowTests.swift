// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Testing

@testable import ClairUI

/// An extension's popup window (arc-extension-experience D6).
@MainActor
struct ExtensionPopupWindowTests {
  func popup(onDismiss: @escaping () -> Void) -> ExtensionPopupWindow {
    let parent = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered,
      defer: false)
    let popup = ExtensionPopupWindow(
      page: NSView(), size: NSSize(width: 200, height: 200), name: "Extension", parent: parent, anchor: .zero,
      onDismiss: onDismiss)
    popup.present()
    return popup
  }

  /// The close button tells Chromium the popup closed, as Esc does: the
  /// button closes the window without performClose(_:).
  @Test func theCloseButtonDismisses() throws {
    var dismissals = 0
    let window = popup { dismissals += 1 }
    try #require(window.standardWindowButton(.closeButton)).performClick(nil)
    #expect(dismissals == 1)
    #expect(!window.isVisible)
  }

  @Test func dismissingTellsChromiumOnce() {
    var dismissals = 0
    let window = popup { dismissals += 1 }
    window.dismiss()
    window.close()
    window.dismiss()
    #expect(dismissals == 1)
  }

  @Test func closingForChromiumDoesntTellIt() {
    var dismissals = 0
    let window = popup { dismissals += 1 }
    window.dismiss(notify: false)
    #expect(dismissals == 0)
    #expect(!window.isVisible)
  }
}
