// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import Testing

@testable import ClairUI

/// The popup in the card's top-trailing corner (browser-window spec, "Notice
/// popup", "Zoom notice"; arc-popup-notices D4, D6).
@MainActor
struct NoticeTests {
  /// Replaces the popup's clock: each notice's wait is recorded, and ends when
  /// the test ends it.
  final class Clock {
    var waits: [Duration] = []
    var timers: [AsyncStream<Void>.Continuation] = []
  }

  private func install(_ state: NoticeState) -> Clock {
    let clock = Clock()
    state.wait = { duration in
      let (elapsed, done) = AsyncStream.makeStream(of: Void.self)
      clock.waits.append(duration)
      clock.timers.append(done)
      for await _ in elapsed { return }
    }
    return clock
  }

  /// Waits for `condition`, for up to about 2 s: the popup springs in and
  /// leaves on the real clock.
  private func settle(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test func everyNoticeHidesAfterTheSameTime() async throws {
    let (_, _, controller) = spacesWindow()
    let state = controller.model.notice
    let clock = install(state)

    controller.showExclusiveAccessNotice("To exit full screen, press |esc|")
    await settle { state.isShown && clock.timers.count == 1 }
    #expect(state.notice?.identifier == BrowserWindowController.fullscreenNoticeID)
    clock.timers[0].yield()
    await settle { state.notice == nil }
    #expect(state.notice == nil, "The exclusive-access notice didn't hide after its time")

    controller.copyURL(of: try #require(controller.model.allTabs.first).tabID)
    await settle { state.isShown && clock.timers.count == 2 }
    #expect(state.notice?.text == "Copied Current URL")
    clock.timers[1].yield()
    await settle { state.notice == nil }
    #expect(state.notice == nil, "Copy URL's notice didn't hide after its time")

    #expect(clock.waits == [NoticeState.duration, NoticeState.duration])
  }

  @Test func nilHidesOnlyTheExclusiveAccessNotice() async throws {
    let (_, _, controller) = spacesWindow()
    let state = controller.model.notice
    _ = install(state)

    controller.showExclusiveAccessNotice("To exit full screen, press |esc|")
    controller.copyURL(of: try #require(controller.model.allTabs.first).tabID)
    controller.showExclusiveAccessNotice(nil)
    await settle { state.isShown }
    #expect(state.notice?.text == "Copied Current URL", "The end of full screen hid Copy URL's notice")

    controller.showExclusiveAccessNotice("To exit full screen, press |esc|")
    await settle { state.isShown }
    controller.showExclusiveAccessNotice(nil)
    #expect(!state.isShown)
    await settle { state.notice == nil }
    #expect(state.notice == nil, "The end of full screen left its notice")
  }

  @Test func zoomShowsTheLevelInThePopupAndNoToast() async {
    let (_, _, controller) = spacesWindow()
    let state = controller.model.notice
    let clock = install(state)

    controller.showZoomLevel(110)
    #expect(state.notice?.text == "110%")
    #expect(state.notice?.identifier == BrowserWindowController.zoomNoticeID)
    #expect(controller.model.toast == nil)
    await settle { state.isShown }

    // A second zoom updates the popup showing, with a time of its own.
    controller.showZoomLevel(125)
    #expect(state.notice?.text == "125%")
    #expect(state.isShown, "The second zoom hid the popup")
    await settle { clock.timers.count == 2 }
    clock.timers[0].yield()
    try? await Task.sleep(for: .milliseconds(50))
    #expect(state.notice?.text == "125%", "The first zoom's time hid the second's")
    #expect(controller.model.toast == nil)
  }
}
