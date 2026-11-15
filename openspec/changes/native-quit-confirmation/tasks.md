# Tasks

Groups 1 and 2 change the engine key, so build the engine first and push docs afterwards, as `CLAUDE.md` describes. "CI" is the merge gate in `ci.yml`. "By hand" means a test build from `tests/probe/launch-clair.sh` compared with `dia-reference/`. D-numbers are `design.md`'s decisions.

## 1. Contract and ClairUI

- [ ] 1.1 Add `-[ClairHost quitWithoutWarning]` and `-[ClairWindow showQuitConfirmation]` to `native/ClairHost.h` (D4), and fix `warnsBeforeQuitting`'s comment. Verify that the header compiles in `ClairHostObjCxxTests.mm` in CI.
- [ ] 1.2 Add `ClairDialogPage.leadingButton` (D5) and `ClairDialogPresenter.contains(where:)`. Verify with `ClairDialogTests` in CI: the leading button answers only through its action, and the existing cases pass.
- [ ] 1.3 Add `QuitConfirmation.swift` and `BrowserWindowController.showQuitConfirmation()` (D4). Verify with `ClairDialogTests` in CI: the wording and layout, Cancel, Quit, Always quit, and a second request adding nothing.

## 2. Engine

- [ ] 2.1 Add `clair::MaybeConfirmQuit`, `clair::MaybeConfirmKeyboardQuit` and `quitWithoutWarning` to `clair_native_layer.mm` (D2, D4), and `clair::ShowQuitConfirmation` to `clair_window_hooks.mm` (D3). Verify with the runtime test in 3.1.
- [ ] 2.2 Add `patches/clair/quit-confirmation.patch` (the `-terminate:` and `-confirmQuitIfNeeded` hooks, D1) to `patches/series`. Verify that the patch check applies it.
- [ ] 2.3 Build the engine with `gh workflow run engine.yml -f ref=<branch>`. Verify that `chromium-engine-<key>` is published and CI's engine check passes.

## 3. Tests, docs and release notes

- [ ] 3.1 Add `testWarnBeforeQuittingAsks` to `tests/runtime/ClairRuntimeTests/ProfilesTests.swift`: Cmd+Q shows the dialog, Cancel keeps Clair running, Clair › Quit Clair shows it, "Always quit" quits and stores the setting off. Verify with a `quality.yml` run on the branch.
- [ ] 3.2 Check the dialog by hand against `dia-reference/`, in Light and Dark Mode, with Cmd+Q and the menu item, and that the Dock's Quit doesn't ask.
- [ ] 3.3 Update `docs/native-window.md`'s note on Warn Before Quitting, and add a Changie fragment. Verify that `openspec validate --all --strict` passes in CI.
