# Design

## Context

Change 1's design D4 has `ClairUI` ask `ClairHost`'s `silentRelaunchBlockers` after 30 minutes without input, and relaunch only when it reports no reason to wait. The host builds that answer itself in `clair_native_layer.mm`: one pass over the windows and tabs for incognito, audible and capturing tabs, plus Chromium's count of downloads that would stop a quit. It reports a set of reasons rather than a yes or no so that `ClairUI` can log why an install waited.

Chromium has its own answer to the same question. `smart_restart::RestartabilityMonitor` (`chrome/browser/lifetime/restartability_monitor.h`) serves `SmartRestartManager`, which restarts Chromium to apply an update once its last window closes. `ComputeCurrentState()` returns a `RestartabilityState`, and its `GetRestartabilityStateFactor()` turns that into a mask of `SmartRestartStateFactor` reasons:

| Factor | Holds while |
|---|---|
| `kIncognito` | an off-the-record window is open: incognito or guest |
| `kBeforeUnloadHandler` | a tab's frame has a `beforeunload` handler and sticky user activation, so it could show "Leave site?" |
| `kDownload` | a download would stop a quit (`DownloadCoreService::BlockingShutdownCountAllProfiles`) |
| `kMedia` | audio is playing in any tab (`DesktopSessionDurationTracker`) |
| `kAppWindow` | a web app or app popup window is open |
| `kTotalBrowserCountZero` | no window is open; not a reason to wait (`HasAnyActiveBlockers()` ignores it) |

`SmartRestartManager` itself never fires in Clair. It starts on `UpgradeDetector`'s upgrade notice, which comes from Google's updater, and Clair updates with Sparkle. The monitor is plain code with no state, so it can be called directly. Its header is in `//chrome/browser/lifetime`'s public list, which `chrome/browser`'s target already depends on.

Chromium also has `ComputeExtendedRestartabilityState()`, for its lock-screen restart behind a feature that is off by default. It weighs some 30 reasons, user edits among them, against a disruption threshold. That is not Chromium's default, so this change doesn't use it.

## Goals / Non-Goals

**Goals:**
- The idle install waits for exactly the reasons Chromium's default check reports, with no reason of Clair's own.
- When Chromium changes that check, Clair follows with the next engine update and no code of its own.

**Non-Goals:**
- Reasons from the extended check, user edits and capture among them.
- Changes to Restart and Update, the idle threshold or the retry schedule.

## Decisions

### D1. The host returns Chromium's mask

`silentRelaunchBlockers` calls `RestartabilityMonitor::ComputeCurrentState()`, takes `GetRestartabilityStateFactor()`, clears `kTotalBrowserCountZero`, and returns the rest as `ClairRelaunchBlockers`. It no longer walks windows or tabs.

`ClairRelaunchBlockers` lists the same reasons with the same values as `SmartRestartStateFactor`: `IncognitoWindow` (`1 << 0`), `UnloadPrompt` (`1 << 1`), `DownloadInProgress` (`1 << 2`), `AudioPlaying` (`1 << 3`) and `AppWindow` (`1 << 4`). `clair_native_layer.mm` `static_assert`s each value against Chromium's, so a renumbering in Chromium breaks the engine build instead of mislabelling a log line. Any bit Chromium adds later passes through unnamed, and `ClairUI` still waits on it, since it checks only that the set is empty.

- *Map each factor by hand to Clair's existing bits.* Rejected: it keeps a translation table of Clair's own that has to follow Chromium's, which is what this change removes.
- *Return a yes or no.* Rejected: D4 of change 1 keeps a set of reasons for the log, and Chromium's mask already is one.

### D2. Capture no longer holds the install

Chromium's default check was written for a restart with no windows open, where nothing can be capturing, so it has no capture reason. A call usually plays audio and keeps holding the install through `kMedia`; a capture with no sound, such as a silent screen recording in a tab, no longer does. The owner chose Chromium's default over a reason of Clair's own.

### D3. A page that would ask before leaving holds the install

Before, an idle relaunch went ahead and Chromium's quit flow showed that page's "Leave site?" dialog, which then sat over an unattended Clair until someone answered it, and the update waited for the next quit. Now the install waits instead, and tries again at each idle period. A page counts only with sticky user activation, the condition under which Chromium would show the dialog at all, so a page that registers the handler but was never touched doesn't hold the install.

## Risks / Trade-offs

- **[Risk] A silent capture is cut off by an idle install.** → It needs 30 minutes with no input during a capture that makes no sound. The session comes back after the relaunch. Accepted as Chromium's default (D2).
- **[Risk] A page that keeps a "Leave site?" handler for good holds idle installs until its tab closes.** → The update still installs on the next quit, or from Restart and Update, as it does today for such a page.
- **[Risk] Text a page holds without a "Leave site?" handler is lost.** → Unchanged from today. Session restore refills ordinary form fields; editors such as `contenteditable` ones lose what they held.
- **[Trade-off] A future reason Chromium adds to its default check holds the install without a name in Clair's log.** → The log prints the raw mask, which can be read against `SmartRestartStateFactor`.

## Migration Plan

`ClairUI` and the engine ship together in one `Clair.app`, so renumbering `ClairRelaunchBlockers` needs no compatibility step. Rolling back means shipping a newer build with the old check.
