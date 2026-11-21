# Tasks

This change touches only `ClairUI`, so the engine key doesn't change and no engine build is needed.

- **"CI"** is the merge gate in `ci.yml`: `ClairUI`'s build and unit tests, and `openspec validate --all --strict`.
- **"By hand"** means checking a test copy from `tests/probe/launch-clair.sh`, driven with the probe and compared with `arc-reference/`, in Light and Dark Mode. The test copy is pointed at a local appcast through `CLAIR_TEST_FEED_URL`, as the runtime suite does.
- **D-numbers** are `design.md`'s decisions.

## 1. Arc reference

- [x] 1.1 Probe Arc's waiting banner, its hover card and the "Update Complete!" card after updating, with 60 fps recordings. Verify: the screenshots are in `arc-reference/screenshots/`, and `arc-reference/README.md` lists and measures them.

## 2. Update state

- [ ] 2.1 Add `UpdateBannerState` and its `UpdateBanner` value (D1). Have `UpdateController` publish `.waiting(version:)` when an update starts waiting. Verify with new `UpdateTests` cases in CI:
  - a waiting update publishes `.waiting` with the short version;
  - a waiting update replaces `.complete`;
  - a second `updateIsWaiting` call publishes nothing new.
- [ ] 2.2 Publish `.complete(version:)` from `recordRunningVersion(in:)` when the running version is newer than `previousVersion` by `SUStandardVersionComparator`, and add `closeUpdateComplete()` (D3). Verify with `UpdateTests` cases in CI, each against a throwaway `UserDefaults` suite:
  - first launch ever: `.none`;
  - newer version: `.complete`;
  - older version: `.none`;
  - a second launch of the newer version, with the card never closed: `.none`;
  - `closeUpdateComplete()`: `.none`.
- [ ] 2.3 Replace `offerRestart()` with `restartToUpdate(confirming:)` (D2). The menu item passes `true` and the banner `false`. Verify with `UpdateTests` cases in CI, using the existing fake prompts and host:
  - `false` with an incognito window open relaunches without calling `askToRestart` or `askToCloseIncognitoWindows`;
  - `true` still shows the version alert, then asks about the incognito window, and declining doesn't relaunch.

## 3. Banner views

- [ ] 3.1 Pass the state into each window: `BrowserWindowController` takes it from `NativeLayer.current`, or a detached instance, as it does `spaces`, and `BrowserWindowModel` exposes it (D1). Verify with a unit test in CI that two window models built with one state both see a change to it.
- [ ] 3.2 Add `UpdateBannerView` with the pill and the waiting card, and place it between `SpacePager` and `SidebarFooter`, with the card in a bottom-aligned overlay and the overflow line above the slot (D4). Include the hover spring, the collapse and the identifiers (D4, D5). The button calls a new `SidebarActions` method that `BrowserWindowController` sends to `restartToUpdate(confirming: false)`. Verify in CI that it builds and the existing tests pass. By hand:
  - the pill and the card match `banner-pill.jpg` and `banner-hover.jpg` within 1 pt, apart from the missing checkbox row;
  - the tabs don't move when the card opens;
  - the pill shows in a second window, an incognito window and the revealed hidden sidebar;
  - at the 164 pt minimum width the title fits or truncates;
  - Restart and Update relaunches with no version alert.
- [ ] 3.3 Add the "Update Complete!" card to `UpdateBannerView`: the close button, the See What's New row, and the sparkles with their Reduce Motion fallback (D4, D5). Add the `updateWhatsNewChosen()` action, which opens the release page in a new foreground tab and closes the card (D6). Verify with a unit test in CI of the release-URL builder: `0.1.3` gives `…/releases/tag/v0.1.3`, and a version that isn't numeric gives no URL. By hand:
  - the card matches `update-complete.jpg` in layout, apart from the Gift row and the colour cycling;
  - the sparkles twinkle, and stop with Reduce Motion on;
  - the close button closes the card in two windows;
  - See What's New opens the release page and closes the card;
  - Dark Mode is legible.

## 4. Runtime tests and notes

- [ ] 4.1 Add `testBannerRestartsAndShowsUpdateComplete` to the update tests:
  1. With a background update waiting, `clair.updateBanner` exists in each window.
  2. Hover it, click `clair.updateBanner.restart`, and Clair relaunches with no alert into `fixture.updateVersion`.
  3. `clair.updateComplete` shows after the relaunch.
  4. `clair.updateComplete.whatsNew` opens a page target whose URL ends `/releases/tag/v<updateVersion>`.
  5. The card is gone.
  6. Relaunch, and it doesn't come back.

  Verify by running the test locally (this Mac may run the suite), and it passes.
- [ ] 4.2 Add a Changie fragment (`changie new`) for both banners. Verify that the fragment exists under `.changes/unreleased/`.

## 5. Integration

- [ ] 5.1 Push the branch, then start CI and `gh workflow run quality.yml --ref <branch>` together on the last push. Verify that CI and the quality checks pass on the branch.

## Workflow follow-up

- After the implementation PR merges, a docs-only PR ticks any tasks its last checks verified, syncs the delta spec and archives the change, as `CLAUDE.md` describes.
