# Arc's tab switcher: reference screenshots

Probed on 2026-11-26 with `tests/probe/` in the owner's Arc, Light Mode, a 963 × 976 pt window at the screen's top left (1920 × 1080 pt screen), 2 px per point. Real key events came from a small tool that holds Ctrl across Tab presses (design D8); XCUITest's `typeKey` releases its modifiers after each key.

Set-up (by the owner):
- **Space "Probe A":**
  - Favorites: Reuters and Ars Technica.
  - Pinned: AP News (open) and AccuWeather (page closed).
  - Today: a split of The New York Times and The Verge, then Apple, GitHub, Hacker News, Wikipedia "Cat", MDN, Example Domain and BBC.
- **Space "Probe B":** Weather.com and IMDb.

Keep these screenshots. They move with the change when it's archived.

## What Arc does

- **Contents.** Ctrl+Tab shows the window's 5 most recently shown tabs, the shown tab first, the second selected. Seven visited tabs gave five cards.
- **Scope.** Recents span Spaces: from "Probe A", Weather.com of "Probe B" was listed, and choosing it switched the window to "Probe B". Favorites (Reuters) and open pinned tabs (AP News) are listed.
- **Closed pages.** Closing a pinned tab's page (Cmd+W, Close and Keep Pinned) took it off the list.
- **Splits.** A split is one card: both pages side by side in one preview, and both favicons with no title.
- **Stepping.** Each Tab, Ctrl held, selects the next card. Tab on the last card wraps to the first. Ctrl+Shift+Tab opens with the last card selected, and Tab then wraps to the first.
- **Committing.** Releasing Ctrl shows the selected tab, and a quick Ctrl+Tab shows the previous tab.
- **Cancelling.** Esc, Ctrl still held, closes the panel and keeps the tab.
- **The pointer.** A click on a card, Ctrl held (so a Ctrl-click), did nothing.
- **Animation.** None. In a 60 fps recording, the panel appears in one frame (already there 80 ms after the key), the selection moves in one frame, and the panel is gone in the frame after Ctrl is released.

## Measurements (points)

| What | Value |
|---|---|
| Panel, five cards | 938 × 189, x 41–979, y 424–612 on screen. The window spans x 0–963, y 30–1006, so the panel is vertically centred on the window, but sits about 29 pt right of the window's centre and overhangs its right edge. |
| Panel padding | 27 to a card's preview; the selection highlight comes 15–16 from the panel's edges |
| Panel corners | about 22, hairline grey border, soft shadow, background #F2F2F2 |
| Card preview | 157.5 × 105 (3:2), the page's top edge, fitted to width, corners about 5 |
| Card pitch | 181.5 (24 between previews) |
| Label | 16 favicon, then the title in about the sidebar's title size, one line, with an ellipsis. Selected: darker and bolder. |
| Selection highlight | 181.5 × 157.5, 12 around the preview, about 12 corners, the Space's light accent (lavender here) |

## Screenshots

| File | Shows |
|---|---|
| switcher-first-press.jpg | Window, 0.7 s after Ctrl+Tab: BBC (shown), Example Domain selected, MDN, Cat, Hacker News |
| switcher-whole-panel.jpg | The whole panel from a screen capture, overhanging the window's right edge, with MDN selected |
| switcher-second-press.jpg | After a second Tab: MDN selected |
| switcher-shift-tab.jpg | Ctrl+Shift+Tab: the last card (Hacker News) selected |
| switcher-across-spaces.jpg | From "Probe A": the split's card (two favicons), Weather.com of "Probe B" selected, AP News (pinned), Reuters (favorite), BBC |
| switcher-pinned-page-closed.jpg | After AP News's page was closed: it's gone from the list |
| switcher-frames.jpg | Recording frames around opening, stepping and closing, 16.7 ms apart: no transition frames |
