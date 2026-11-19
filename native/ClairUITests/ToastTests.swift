// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import Testing

@testable import ClairUI

/// Toasts at the bottom of the card (browser-window spec, "Toasts").
@MainActor
struct ToastTests {
  /// Copy Link on a row says so in a toast, until its time is up.
  @Test func copyLinkShowsAToastUntilItsTimeIsUp() async throws {
    let (_, _, controller) = spacesWindow()
    var waited: [Duration] = []
    let (elapsed, done) = AsyncStream.makeStream(of: Void.self)
    controller.toastWait = { duration in
      waited.append(duration)
      for await _ in elapsed { return }
    }
    controller.copyLink(of: try #require(controller.model.allTabs.first).tabID)
    #expect(controller.model.toast?.message == "Copied Link")
    await Task.yield()
    #expect(controller.model.toast?.message == "Copied Link")
    done.yield()
    for _ in 0..<100 where controller.model.toast != nil {
      await Task.yield()
    }
    #expect(waited == [BrowserWindowController.toastDuration])
    #expect(controller.model.toast == nil)
  }

  /// A newer toast replaces the one showing and gets its own time: the older
  /// one's running out doesn't take it away.
  @Test func aNewerToastOutlastsTheOlder() async {
    let (_, _, controller) = spacesWindow()
    var timers: [AsyncStream<Void>.Continuation] = []
    controller.toastWait = { _ in
      let (elapsed, done) = AsyncStream.makeStream(of: Void.self)
      timers.append(done)
      for await _ in elapsed { return }
    }
    controller.showToast("Copied Link")
    for _ in 0..<100 where timers.isEmpty {
      await Task.yield()
    }
    controller.showToast("Image copied")
    for _ in 0..<100 where timers.count < 2 {
      await Task.yield()
    }
    #expect(controller.model.toast?.message == "Image copied")
    timers[0].yield()
    for _ in 0..<20 {
      await Task.yield()
    }
    #expect(controller.model.toast?.message == "Image copied")
    timers[1].yield()
    for _ in 0..<100 where controller.model.toast != nil {
      await Task.yield()
    }
    #expect(controller.model.toast == nil)
  }
}
