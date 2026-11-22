# Proposal

## Why

The idle install decides whether relaunching would interrupt the user with a list of its own: a download in progress, an incognito window, an audible tab, or a tab using the camera, microphone or screen. Chromium already makes the same decision for its own unattended restarts, in `smart_restart::RestartabilityMonitor`, and keeps that check current as Chromium changes. Its default check also covers a case Clair's list misses: a page that would ask "Leave site?" before closing. Today such a page doesn't stop the idle relaunch; it puts its dialog on screen, which stays there until someone answers it.

Following Chromium's check means one fewer list to keep in step with Chromium, and pages that ask before leaving hold the update instead of being asked.

## What Changes

- **The idle install waits on Chromium's default restart check** and nothing else. That check holds the relaunch while:
  - a download is in progress;
  - an incognito or guest window is open;
  - audio is playing;
  - a web app window is open;
  - a page could ask "Leave site?" before closing: it has a `beforeunload` handler and the user has interacted with it.

  As before, a held install tries again at the next idle period.
- **New:** a page that could ask before leaving now holds the idle install. It no longer shows its dialog over an unattended Clair.
- **New:** an open web app window, a site installed as an app and opened in its own window, holds it too.
- **Removed:** a tab using the camera, microphone or screen no longer holds the idle install on its own. Chromium's check has no such case, since it was built for a browser with no windows open.
- **Unchanged:** text a page keeps without asking before it's left. After the relaunch, session restore refills ordinary form fields; other unsaved state is lost, as it is today.
- **BREAKING (`ClairHost.h`):** `ClairRelaunchBlockers` takes Chromium's reasons in place of Clair's: the audible-tab and capturing-tab bits go, and bits for audio playing, a page that could ask before leaving and a web app window take their place. `ClairUI` and the engine ship together in one app, and `ClairUI` only checks whether any reason is set.
- "Restart and Update" doesn't change: it never consulted these reasons.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `software-updates`: "Downloaded update installs while the user is idle" lists Chromium's default reasons in place of Clair's own.

## Impact

- **Engine:** `silentRelaunchBlockers` in `overlay/chrome/browser/clair/clair_native_layer.mm` reports what `RestartabilityMonitor::ComputeCurrentState()` reports. `//chrome/browser/lifetime` already exports that header to `chrome/browser`'s target, so no build file changes. The engine key changes (`overlay/`, `native/ClairHost.h`), so the PR needs an engine build and a patch check.
- **Contract:** `native/ClairHost.h`'s `ClairRelaunchBlockers`.
- **`ClairUI`:** no change beyond the renamed bits, in the unit tests and their fakes.
- **Tests:** the runtime suite's `IdleInstallTests` gains a page that asks before leaving and drops nothing else, since it never covered capture.
- **Docs:** `docs/updates.md`'s account of the idle install and of "Leave site?" pages. A Changie fragment.
