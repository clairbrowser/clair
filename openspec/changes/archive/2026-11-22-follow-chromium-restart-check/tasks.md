# Tasks

This change edits `overlay/` and `native/ClairHost.h`, so the engine key changes: the PR needs an engine build (`engine.yml`) and passes the patch check once that engine is published.

- **"CI"** is the merge gate in `ci.yml`: `ClairUI`'s build and unit tests, `openspec validate --all --strict`, and the engine check.
- **"Quality"** is `quality.yml` run on the branch (`gh workflow run quality.yml --ref <branch>`), which packages the app from the branch's engine and runs the runtime suite.
- **D-numbers** are `design.md`'s decisions.

## 1. Contract and engine

- [x] 1.1 Renumber `ClairRelaunchBlockers` in `native/ClairHost.h` to Chromium's reasons and values (D1): `IncognitoWindow`, `UnloadPrompt`, `DownloadInProgress`, `AudioPlaying`, `AppWindow`, with a comment that the values are Chromium's `SmartRestartStateFactor`. Update `FakeHost.swift`, `ClairHostObjCxxTests.mm`, `EntryPointTests.swift` and `UpdateTests.swift` to the new names; `anIdleInstallWaitsForEveryBlocker` covers all five. Verify: `ClairUI` builds and its unit tests pass locally and in CI.
- [x] 1.2 Make `silentRelaunchBlockers` in `clair_native_layer.mm` return `RestartabilityMonitor::ComputeCurrentState().GetRestartabilityStateFactor()` without `kTotalBrowserCountZero`, with a `static_assert` for each of the five values (D1). Remove the window and tab walk and any include only it used. Verify: the engine builds in `engine.yml`, and the PR's patch check and engine check pass.

## 2. Runtime test and docs

- [x] 2.1 In `IdleInstallTests.testIdleInstallWaitsForEveryBlocker`, add a phase for a page that would ask before leaving (D3): open `pages/beforeunload.html`, give it a user gesture through the DevTools protocol (no real input, which would restart the idle clock), start it before the previous phase ends, hold for three idle periods, and stop it before the last phase ends by setting `window.guard = false` and leaving the page: Chromium counts a registered handler whatever it would return. Check that no "Leave site?" dialog appears while it holds. Raise `executionTimeAllowance` to cover the extra phase. Verify: Quality passes on the branch.
- [x] 2.2 Update `docs/updates.md`: the idle install's reasons in "How an update reaches a user" step 5, and the paragraph on "Leave site?" pages, which now hold an idle install instead of stopping it with a dialog. Verify: both read as the spec's requirement does.
- [x] 2.3 Add a Changie fragment (`changie new`) for the idle install waiting on pages that would ask before leaving, and no longer on silent captures. Verify that the fragment exists under `.changes/unreleased/`.

## Workflow follow-up

- After the implementation PR merges, a docs-only PR ticks any task its last checks verified, syncs the delta spec and archives the change.
