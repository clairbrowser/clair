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
- **Committing.** Releasing Ctrl shows the selected tab, and a quick Ctrl+Tab shows the previous tab without the panel. Recorded at 60 fps with Ctrl released about 50, 90, 130, 180 and 280 ms after Tab: no panel at 50 or 90 ms; at 130 ms it showed for 3 frames, at 180 ms for 5, at 280 ms for 13. The delay is therefore between 90 and 130 ms.
- **Cancelling.** Esc, Ctrl still held, closes the panel and keeps the tab.
- **The pointer.** Clicking a card chooses it (the owner checked by hand). The probe's synthetic XCUITest click on a card did nothing, so don't trust the probe for this.
- **Animation.** None. In a 60 fps recording, the panel appears in one frame, the selection moves in one frame, and the panel is gone in the frame after Ctrl is released.
- **Two tabs.** In a window with two recent tabs, the panel held two cards and was centred on the window.

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

Only two are kept. The rest of what was probed (stepping, Shift+Tab, Esc, a closed pinned page leaving the list, the recording's frames) is described above.

| File | Shows |
|---|---|
| switcher-whole-panel.jpg | The whole panel from a screen capture, overhanging the window's right edge, with MDN selected: corners, border, highlight and the full card row |
| switcher-across-spaces.jpg | From "Probe A": the split's card (two favicons, no title), Weather.com of "Probe B" selected, AP News (pinned), Reuters (favorite), BBC |

## Clair

Checked on 2026-11-27 with `tests/probe/launch-clair.sh` and the `keys` tool, Light Mode, a 1200 × 932 pt window at (22, 52) on the same 1920 × 1080 pt screen, 2 px per point, with Apple, GitHub, Hacker News, Wikipedia "Cat", MDN, Example Domain and BBC opened in that order (engine `chromium-engine-a6215d3cdeceef07`).

| What | Clair | Arc |
|---|---|---|
| Panel, five cards | 937 × 189, centred on the window (the window's and the panel's centres within 0.5) | 938 × 189, about 29 right of centre |
| Panel padding | 27 to a preview; the highlight 15 from the panel's edges | 27; 15–16 |
| Panel background | #F2F2F2, hairline border, shadow | #F2F2F2 |
| Card preview | 157.5 × 105, the page's top, fitted to width | 157.5 × 105 |
| Card pitch | 181.5 | 181.5 |
| Selection highlight | 181.5 × 157.5, 12 around the preview, the accent colour at 18 % | 181.5 × 157.5, the Space's light accent |
| Label | 16 favicon, the title at 14 pt; selected semibold and primary, others medium and secondary | the same, selected darker and bolder |

- **Previews.** Background tabs show their page as they were left, the shown tab its page as it is, and a split both pages side by side with both favicons and no title.
- **Keys.** Each Tab selects the next card, Tab on the last wraps to the first, and Esc with Ctrl held closes the panel and keeps the tab.
- **Timing.** In 60 fps recordings, Ctrl released right after Tab (about 60 ms) showed no panel in any frame; held about 165 ms, the panel showed.
- **Animation.** None: the panel appears at full size and opacity between two frames, the highlight moves between two frames, and the panel is gone in the frame after Ctrl is released.

The hand check found two differences, both fixed: the panel's background was white (macOS 27's light `windowBackgroundColor`), and background tabs had no preview, because a hidden page stopped painting before its copy (design D4).
