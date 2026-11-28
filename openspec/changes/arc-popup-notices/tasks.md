# Tasks

Wherever a task needs a build, it means the engine that `engine.yml` builds for the branch's key and the CI and quality runs on the pull request's branch.

## 1. Exclusive-access notices

- [x] 1.1 In `ClairExclusiveAccessContext::UpdateExclusiveAccessBubble`, send "Your cursor is hidden. Press |esc| to show cursor." for `POINTERLOCK_EXIT_INSTRUCTION`, pass `u"esc"` as the accelerator for every other type, stop hiding the browser and extension full-screen types, and leave out download notices, keeping the popup as it is for a download alone (design D1–D3, D7). Verify that `engine.yml` builds the engine for the branch and that CI's engine check passes.
- [ ] 1.2 Add `clair/esc-double-tap.patch`, turning `kPressAndHoldEscToExitBrowserFullscreen` off by default, and count Esc taps in the window's own full screen from `ClairBrowserWindow::PreHandleKeyboardEvent` and `ClairNativeWindow`'s `cancelOperation:`, once per event: the first shows "|esc| again to exit fullscreen", a second within 0.23 s leaves full screen, and `cancelOperation:` no longer leaves it on one tap. Remove the press-and-hold forwarding from `HandleExclusiveAccessKey` (design D3). Verify with task 1.5's test.
- [x] 1.3 Have `NoticePopupView.markingKeys` mark a bare "Esc" as `|esc|`, and update its tests in `StatusCapsuleTests` (design D2). Verify that `ClairUI`'s unit tests pass in CI.
- [x] 1.4 Add `tests/runtime/pages/pointer-lock.html` (a page whose `lock()` locks the pointer) and tests in `FullscreenTests`: outside full screen, the `clair.fullscreenNotice` label is "Your cursor is hidden. Press esc to show cursor.", and Esc leaves `document.pointerLockElement` null and the notice gone; in page full screen, the label is "To exit full screen, press esc", also checked in `testPageFullscreenFillsTheScreenAndEndsWithEscape` (spec "Hidden cursor notice", "Full screen"). Verify that they pass in `quality.yml` on the branch.
- [ ] 1.5 Rewrite the window full-screen test in `FullscreenTests`: it enters from View › Enter Full Screen and checks the notice "To exit full screen, press esc"; one Esc on the page shows "esc again to exit fullscreen" and the window is still in full screen 1 s later; a quick Esc with the command bar open closes it, shows no "again" notice and stays; two Escs typed together leave full screen (spec "Window full-screen notice", "Double tap to leave full screen"). Verify that it passes in `quality.yml` on the branch.

- [x] 1.6 Give `NoticeState` one duration for every notice (design D6): rename `copiedDuration` to `duration`, drop `show`'s duration argument, show exclusive-access notices with it, and stop `ClairExclusiveAccessContext` from hiding the notice when `kShowTime` runs out while keeping its bookkeeping. Verify with `ClairUI` unit tests that an exclusive-access notice and Copy URL's hide after the same duration, that nil hides only the exclusive-access notice, and that they pass in CI.

## 2. Zoom notice

- [x] 2.1 Add `showZoomLevel:` to `ClairWindow` in `native/ClairHost.h`, call it from `ClairBrowserWindow::ZoomChanged` in place of the toast, and implement it in `BrowserWindowController` as a `clair.zoomNotice` popup notice, with `FakeBrowser` updated (design D4). Verify with a `ClairUI` unit test that a zoom shows "110%" in the popup and no toast, and that a second zoom updates the same notice, passing in CI.
- [x] 2.2 Add a runtime test that presses Cmd+= on a page and checks that the `clair.zoomNotice` label is "110%" and that no `clair.toast` shows (spec "Zoom notice"). Verify that it passes in `quality.yml` on the branch.

## 3. Runtime suite

- [ ] 3.1 Have `tests/runtime/run.sh prepare` take the test selection `test` gets and package the update, its DMG and the test appcasts only when it selects `AppTests`, `UpdateMenuTests` or `IdleInstallTests`, with `quality.yml` passing each group's tests and `docs/building.md` saying so. Verify that every group passes in `quality.yml` on the branch and that only group 1's log packages the update.

## 4. Release

- [x] 4.1 Add a Changie fragment (`changie new`) for the notices. Verify that `changie batch --dry-run` lists it.
- [ ] 4.2 Check by hand with `tests/probe/launch-clair.sh` on a pointer-lock page, on `fullscreen.html`, in window full screen and while zooming that each popup shows its text with an "esc" key cap where it has a key, and that Esc, or two quick taps of it in window full screen, does what each says, with the focus on the page and in the sidebar. Verify with a screenshot of each popup.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks any task its last checks verified, syncs the delta spec into `openspec/specs/browser-window/spec.md` and archives the change.
