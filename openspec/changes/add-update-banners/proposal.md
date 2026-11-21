# Proposal

## Why

Clair downloads updates silently and installs them on quit or while the user is idle, and the only sign that an update is waiting is the Clair menu's "Update Available…" item, which few people open. Arc also shows the waiting update at the bottom of the sidebar, and after an update it says so there. Change 1's roadmap lists these banners among the MVP features. Both of Arc's banners were probed on 2026-11-20 (`arc-reference/`).

## What Changes

- **Waiting update.** While a downloaded update waits, a pill reading "New Clair Version Available" sits at the bottom of every window's sidebar, directly above the footer. On hover it grows upward into a card with the title and a **Restart and Update** button. Moving the pointer away collapses it again.
- **Restart and Update** relaunches Clair into the new version straight away. Clicking the button is the confirmation, so it doesn't show the version alert that the menu item shows. As in Arc, it doesn't ask about incognito windows either: they close, and they don't come back. Chromium still warns before cancelling an active download.
- **The menu's Restart and Update matches the banner's.** After its version alert, the Clair menu's Restart and Update no longer asks about incognito windows either. The two buttons then behave identically. The idle install still waits while an incognito window is open.
- **After an update.** The first launch of a newer version shows an "Update Complete!" card in the same place, with a close button and a **See What's New** row. See What's New opens the version's GitHub release page (`https://github.com/clairbrowser/clair/releases/tag/v<version>`) in a new tab and closes the card. The close button closes it. Either way it closes in every window. It shows only during that first launch: a later relaunch doesn't show it again, even if it was never closed. Small sparkles twinkle along the card's header.
- **Differences from Arc**, all deliberate:
  - The card has no "Automatic Updates" checkbox, because Clair has no update settings (`software-updates`).
  - It has no "Gift Arc" row.
  - Arc's button and its "See What's New" text change colour as they animate. Clair's don't: the button is a plain accent fill and the row is plain text. The header's sparkles are the only animation that keeps running.
- The Clair menu's update item is unchanged: the banner is an addition to it.

**Out of scope:** update settings; release notes shown inside Clair (See What's New opens the web page); a banner for a failed or blocked update; Arc's "Gift Arc".

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `software-updates`: adds the sidebar's waiting-update banner, its Restart and Update, and the "Update Complete!" card after an update. "Relaunch preserves the browsing session" no longer asks about incognito windows after any Restart and Update. The existing requirement that Clair adds no other update item applies only to the application menu, so it stays as it is.

## Impact

- **`ClairUI` only:**
  - a new app-wide observable update state, owned by `UpdateController`, which every window's `BrowserWindowModel` reads;
  - a new banner view in `SidebarView`, between the Space pager and the footer;
  - `UpdateController` gains a restart path without the version alert, and decides from the version it last ran whether to show the "Update Complete!" card.
- **No engine change.** See What's New uses `ClairBrowser.open(_:disposition:)`, which exists already. The engine key and `ClairHost.h` don't change.
- **Tests:**
  - unit tests in `UpdateTests` for the state;
  - runtime tests extending `testFoundUpdateInstallsAndRestoresWindows`, whose local appcast already drives a real update and relaunch.

  The banner adds views the runtime suite drives, so the PR also runs `quality.yml` on its branch.
- **Docs:** a Changie fragment.
