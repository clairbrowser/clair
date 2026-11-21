# Design

## Context

- **`UpdateController`** is app-wide. `NativeLayer` creates it once.
  - It runs Sparkle with its own user driver. When a download finishes, `updateIsWaiting(_:userInitiated:)` sets `waitingUpdate`, switches the menu item to "Update Available…" and starts the `IdleInstaller`.
  - `offerRestart()` asks with the version alert (`UpdatePrompting.askToRestart`), then calls `host.relaunch()`. Chromium's relaunch warns about active downloads itself and restores the session.
  - `recordRunningVersion(in:)` reads and then overwrites `ClairLastRunVersion`, which holds the short version, and keeps the old value in `previousVersion`. Its comment already reserves it for this banner. `UpdateTests` covers it.
- **Windows.** Each `BrowserWindowController` builds a `BrowserWindowModel`, and `SidebarView` renders from it. App-wide state reaches windows as `SpacesModel` does: an `@Observable` object that the controller takes from `NativeLayer.current` and passes into the model.
- **The sidebar's bottom** is a `VStack`: `SpacePager`, with `maxHeight: .infinity`, then `SidebarFooter`, 50 pt tall. The footer's overlay draws a 1 pt line when the tab list overflows. The sidebar is 164–500 pt wide, 228 by default.
- **Opening a URL in a window:** `ClairBrowser.open(_:disposition:)` with `.newForegroundTab`.
- **Release tags** are `v<CFBundleShortVersionString>`, for example `v0.1.2`.
- **Runtime suite:** `testFoundUpdateInstallsAndRestoresWindows` already serves a local appcast, downloads a real update, relaunches through `ClairHost` and checks the restored session.
- **Arc's measurements** are in `arc-reference/README.md`, taken in Light Mode only. Arc showed no banner in Dark Mode, and it can't again until its next update.

## Goals / Non-Goals

**Goals:**
- One app-wide source of truth for what the banner shows, so every window agrees and a close in one window applies to all.
- The banner and the menu item share one restart path, which differs only in whether it shows the version alert.
- Arc's layout and motion, without its colour animations.

**Non-Goals:**
- Dark Mode measurements from Arc. Clair uses semantic colours and is checked by hand instead (Risks).
- Banners for failed checks, rejected signatures or blocked idle installs.
- Changing Sparkle's behaviour, the idle installer or the menu item.

## Decisions

### D1. `UpdateBannerState`: one observable, owned by `UpdateController`

A new `@Observable final class UpdateBannerState` with one published value:

```
enum UpdateBanner: Equatable {
  case none
  case waiting(version: String)     // "New Clair Version Available"
  case complete(version: String)    // "Update Complete!"
}
```

- `UpdateController` owns the only instance and is the only writer.
- `BrowserWindowController` takes it from `NativeLayer.current?.updates.bannerState` (or a detached instance in tests), as it does `spaces`, and the model exposes it to `SidebarView`.
- **Priority:** `waiting` replaces `complete`. The next launch, of the newer version, shows that version's card instead (D3).
- **Hover is per window.** Whether the waiting card is open is local `@State` in the banner view, not part of the shared state.

*Alternative:* each window observes `UpdateController` directly. That would turn the controller, which talks to Sparkle and AppKit, into a SwiftUI dependency. The small state object keeps it testable on its own.

### D2. Restart and Update: one path with an optional alert

`offerRestart()` becomes `restartToUpdate(confirming: Bool)`:
- The menu item calls it with `true`, which shows the version alert (`askToRestart`) first.
- The banner calls it with `false`, which doesn't.

After that the two paths are identical: both call `host.relaunch()` directly. The incognito question is removed from both, as Arc asks neither. That means `askToCloseIncognitoWindows` goes from `UpdatePrompting` and `UpdateAlerts`, and with it the "Restart Clair and close your incognito windows?" alert. Chromium's download warning and session restore apply unchanged. Incognito windows aren't restored, as after any relaunch. If the user postpones at the download warning, the update stays waiting and the pill stays.

The idle installer still waits while an incognito window is open (`silentRelaunchBlockers`), because nobody is there to choose to lose it. That requirement doesn't change.

*Alternative:* a separate banner-only method that calls `host.relaunch()` directly. That would split the restart path in two, and the next guard added to one would be missed in the other.

### D3. When the "Update Complete!" card shows

The card shows only during the first launch of a newer version. The owner decided that a relaunch never brings it back. No new defaults key is needed.

At start-up, `recordRunningVersion(in:)` already reads `ClairLastRunVersion` into `previousVersion` and overwrites it with the running version. It now also publishes `.complete(version:)` when two things hold: `previousVersion` exists, and Sparkle's `SUStandardVersionComparator` says the running version is newer.

Closing the card, with its close button or See What's New, publishes `.none` for the rest of that run.

- A first launch ever has no `previousVersion`, so it shows nothing.
- A downgrade, or a relaunch of the same version, shows nothing, because `ClairLastRunVersion` already holds the running version.
- An idle install relaunches with nobody watching. The card stays open in that run until the user comes back and closes it, so it isn't missed unless Clair quits first.

*Alternative:* a defaults key that keeps the card until it's closed, across relaunches. The owner rejected it: the card belongs to the launch that follows the update.

### D4. Layout: a fixed slot, with the card overlaid upward

A new `UpdateBannerView` goes between `SpacePager` and `SidebarFooter` in `SidebarView` while the state isn't `.none`.

- **Layout space:** it takes only the pill's slot, 24 pt tall plus 8 pt below it before the footer, inset 8 pt from each side of the sidebar (Arc: 212 × 24 in a 228 pt sidebar). The tab list ends above the slot.
- **The open cards** are drawn in an `.overlay(alignment: .bottom)` of that slot, so they grow upward over the tab list without moving it. The slot sits above `SpacePager` in z-order.
- **Overflow line:** while the banner shows, the line moves to the top of the banner's slot, between the list and the pill.
- **Narrow sidebars:** the title uses `minimumScaleFactor(0.85)` and then truncates at the tail, because at the 164 pt minimum the pill is 148 pt wide.

**Metrics (Light Mode, `arc-reference/README.md`):**

| Part | Look |
|---|---|
| Pill | Capsule 24 pt tall with a 1 pt border. The fill is about 4 % `primary` over the sidebar, and the border about 9 %. The title is 13 pt regular `primary`, centred. |
| Waiting card | 212 pt wide, bottom edge on the pill's bottom edge, corner radius 10, `controlBackgroundColor` with a soft shadow. Rows: the title row (24 pt, the pill's text in the same place); a hairline (`separatorColor`); then the "Restart and Update" button, full width less 8 pt each side, 22 pt tall, corner radius 6, with a plain `Color.accentColor` fill and white 13 pt text, and 8 pt below it. That's about 63 pt in all, against Arc's 87 with the checkbox row. |
| Update Complete card | The same card. The title row reads "Update Complete!", centred, with a close button at the trailing edge: an `xmark` glyph, a 20 × 20 hit area and a rounded hover highlight. Below the hairline is one 22 pt row: a `heart.circle.fill` glyph, then "See What's New", both in plain accent colour, 8 pt from the leading edge, with a hover highlight. About 59 pt in all. |

The button and the row keep fixed colours. Arc's blue-to-purple gradient on the button and its colour-cycling text are deliberately not copied (proposal).

**Accessibility identifiers** for the runtime suite:
- `clair.updateBanner`: the pill or the waiting card;
- `clair.updateBanner.restart`;
- `clair.updateComplete`;
- `clair.updateComplete.close`;
- `clair.updateComplete.whatsNew`.

The title text keeps its visible string as its label.

### D5. Motion

Taken from 60 fps recordings of Arc (`arc-reference/`):

- **Opening on hover:** a spring, `.spring(response: 0.25, dampingFraction: 0.8)`. The card scales from the pill's frame, anchored at the bottom, and its rows fade in. In Arc the card is fully shown within about 120 ms of the pointer arriving, and settles with a slight overshoot by about 300 ms.
- **Collapsing:** `.easeOut(duration: 0.15)` back into the pill.
- **Showing the pill** when an update starts waiting, and **closing the complete card:** the card slides down 15 pt and fades, `.easeIn(duration: 0.12)`, as Arc's does.
- **Sparkles** on the "Update Complete!" header: 3 to 5 small four-point stars (`sparkle` glyph, 5–8 pt, accent colour) at random points along the card's top edge and around the title. Each fades and scales in and out over about 1 s, staggered, for as long as the card shows. A `TimelineView(.animation)` drives them, and they pause while the window isn't visible.
- **Reduce Motion:** no sparkles, and the card's transitions become cross-fades.

### D6. See What's New

The view calls a window action, `updateWhatsNewChosen()`, and the `BrowserWindowController` then:
1. opens `https://github.com/clairbrowser/clair/releases/tag/v<version>` in its own browser with `.newForegroundTab`;
2. tells `UpdateController` to close the card (D3).

The version comes from the `.complete(version:)` value, which is the running short version. A release URL is built only from that string, after checking that it matches `^[0-9]+(\.[0-9]+)*$`. Otherwise the row isn't shown, as for a development package with an unusual version.

## Risks / Trade-offs

- **[Dark Mode not measured in Arc]** → The design uses semantic colours (`primary` opacities, `controlBackgroundColor`, `separatorColor`). Check both cards by hand in Dark Mode, and in the hidden sidebar revealed over a page. Probe Arc's next update in Dark Mode if one arrives during the work.
- **[The card covers the last tabs while open]** → It opens only on hover and closes when the pointer leaves, as in Arc. The "Update Complete!" card stays open but is short (about 59 pt), and its close button is one click.
- **[A slow GitHub page, or no network]** → See What's New only opens a tab. A failed load shows Chromium's error page like any other link, and the card still closes.
- **[The runtime test needs hover]** → XCUITest's `hover()` works on Clair's sidebar (the probe uses it). The test hovers the pill, waits for `clair.updateBanner.restart` and clicks it.
- **[Development packages show the card on every version bump]** → Intended: `run-local.sh` and the test copy use throwaway profiles, so the card shows there only after an update.

## Migration Plan

Nothing to migrate. Installs from before this change already write `ClairLastRunVersion` (change 1), so their first update to this version shows "Update Complete!". Rolling back removes the views and adds no state.
