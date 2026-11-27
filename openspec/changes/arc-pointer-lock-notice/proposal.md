# Proposal

## Why

When a page hides the cursor by locking the pointer (the Pointer Lock API, as games and 3D viewers use), Arc says so in its top-trailing popup: "Your cursor is hidden. Press [esc] to show cursor." Clair already uses that popup for the pointer lock, but with Chromium's wording, "Press Esc to show your cursor".

## What Changes

- While a page holds the pointer lock outside page full screen, the popup in the card's top-trailing corner reads "Your cursor is hidden. Press [esc] to show cursor.", with esc drawn as a key cap.
- Pointer lock inside page full screen keeps the full-screen notice, which Chromium also shows for that case.
- Every notice in the popup labels its key cap "esc", as Arc writes it: the full-screen notice becomes "To exit full screen, press [esc]" (it was [Esc]).
- Esc still ends the pointer lock and shows the cursor.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `browser-window`: adds a requirement for the notice a pointer lock shows, and changes "Full screen" so its notice's key cap reads "esc".

## Impact

- `engine/overlay/chrome/browser/clair/window/clair_browser_window.mm` (`ClairExclusiveAccessContext`): the pointer-lock notice gets Arc's text, and every notice's key is "esc". This changes the engine key, so it needs an engine build.
- `native/ClairUI/NoticePopup.swift`: a bare "Esc" in a notice is drawn as an "esc" key cap too, with its unit tests. No change to `ClairHost.h`.
- `tests/runtime/`: a pointer-lock page and a test in `FullscreenTests`.
- A Changie fragment (user-facing).
