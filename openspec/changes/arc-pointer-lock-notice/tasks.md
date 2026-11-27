# Tasks

Wherever a task needs a build, it means the engine that `engine.yml` builds for the branch's key and the CI and quality runs on the pull request's branch.

## 1. The notices

- [ ] 1.1 In `ClairExclusiveAccessContext::UpdateExclusiveAccessBubble`, send "Your cursor is hidden. Press |esc| to show cursor." to `showExclusiveAccessNotice:` for `EXCLUSIVE_ACCESS_BUBBLE_TYPE_POINTERLOCK_EXIT_INSTRUCTION` without a download, and Chromium's text with `u"esc"` as the accelerator for every other type (design D1, D2). Verify that `engine.yml` builds the engine for the branch and that CI's engine check passes.
- [ ] 1.2 Have `NoticePopupView.markingKeys` mark a bare "Esc" as `|esc|`, and update its tests in `StatusCapsuleTests` (design D2). Verify that `ClairUI`'s unit tests pass in CI.
- [ ] 1.3 Add `tests/runtime/pages/pointer-lock.html` (a page whose `lock()` locks the pointer) and a test in `FullscreenTests` that locks the pointer outside full screen, then checks that the `clair.fullscreenNotice` element's label is "Your cursor is hidden. Press esc to show cursor.", and that Esc leaves `document.pointerLockElement` null and the notice gone (spec scenarios "Page locks the pointer" and "Esc shows the cursor"). Verify that the test passes in `quality.yml` on the branch. If Esc doesn't end the lock, apply design D3's fallback and rebuild.
- [ ] 1.4 Extend the same test to lock the pointer in page full screen, and `testPageFullscreenFillsTheScreenAndEndsWithEscape` to check the notice's label, "To exit full screen, press esc" (spec scenarios "Pointer lock in page full screen" and "Full-screen notice"). Verify that both pass in `quality.yml` on the branch.
- [ ] 1.5 Add a Changie fragment (`changie new`) for the new wording. Verify that `changie batch --dry-run` lists it.
- [ ] 1.6 Check by hand with `tests/probe/launch-clair.sh` on a pointer-lock page and on `fullscreen.html` that each popup shows its text with an "esc" key cap, and that Esc brings the cursor back or leaves full screen and hides the popup. Verify with a screenshot of each popup.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks any task its last checks verified, syncs the delta spec into `openspec/specs/browser-window/spec.md` and archives the change.
