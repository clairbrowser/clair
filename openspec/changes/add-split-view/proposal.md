# Proposal

## Why

Split view is on the MVP list in `ship-plain-ungoogled-build`'s roadmap ("split view (2 panes for the MVP)"), and Arc stops working on 2026-12-22. `add-page-toolbar` built the page header as one view per page, and `PageHeaderPolicy` already takes a pane count, so split view can reuse both.

Clair takes split view from two browsers:
- **Arc:** how a split shows in the sidebar (one row with a chip per page), pinned and favorited splits, the pane headers, and the drop UI when a tab is dragged onto the page.
- **Dia:** side-by-side panes only; Option+click opens a link in a split; a tab dragged to the left or right side of the page makes a split, never a tab dropped on another tab; and the split button's menu.

## What Changes

- **Two panes, side by side,** for the MVP, built on Chromium's own split tabs (`TabStripModel`'s split collections), which allow exactly two tabs. Each pane is an ordinary tab. Clair draws the split natively: two pane cards with a gap and a divider between them, a header on each pane, and the focused pane ringed in the accent colour.
- **Making a split:**
  - **Dragging a tab onto the page**, with Arc's drop UI: the dragged tab turns into a portrait card, and the half under the pointer becomes a drop zone while the page slides to the other half. On a page that's already split, the dropped tab replaces the pane under the pointer, and the replaced tab returns to the sidebar.
  - **Option+click on a link** opens it in a new pane to the right of the page it was clicked in, which takes focus. While the page is already split, it loads the link in the other pane as a new navigation, so Back returns there, and creates no tab. This replaces Chromium's Option+click download. While Option is held over a link, the link status reads "Open <URL> in Split View".
  - **The split button:** at the toolbar's trailing end, and just before the close button in a pane's header, as in Arc. Its menu, as in Dia, offers "Split with Tab" (the Space's Today tabs, then New Tab). On a split page, it offers Move Left or Move Right, Separate Tabs and Close This Tab.
  - **Menus:** Tabs › Split with Tab › and a Split with Tab › submenu in the menus of Today tabs, pinned tabs and favorites, listing the Space's Today tabs in the sidebar's order, with their favicons. View gains Add Split View (⌃⇧=), Close Split Pane (⌃⇧−) and Separate Tabs. A link's context menu gains Open Link in Split View.
  - **A Peek's Open in Split View button**, as in Arc, beside Close and Expand, shown while the Peek's parent isn't split.
- **Panes:** each pane's × closes only that pane's tab. The focused pane's header shows the split button, site controls, pinned extensions and indicators; the other pane's shows them while the pointer is over it. Dragging the divider resizes the panes down to a page of about 210 points, as in Dia, and the split keeps the ratio. Clicking in a pane focuses it, and the window's commands (URL, back, find, DevTools, Copy URL…) act on the focused pane. The command bar opens centred on the focused pane. A Peek from either pane is centred over the whole page area, and only its parent's pane shrinks and washes out, as in Arc. Dragging the divider near the centre snaps it to equal panes.
- **The sidebar:** a split is one row with a chip per page, as in Arc. Selecting the row shows the split; chips aren't selected one at a time. The row's × closes both tabs. Its menu adds Separate Tabs. Tab commands count the row as one stop.
- **Pinned and favorited splits,** as in Arc: a split can be pinned or favorited as one item, shown as the chip row in the pinned section (folders included) or as one favorite tile divided into a segment per page. Separating it leaves both pages pinned, or both favorited, in its place. A pinned split has no Back to Pinned URL.
- **Splits are saved:** they come back after a relaunch, with Reopen Closed Window and with Restore Last Closed Tab, and they move between windows and Spaces as one.
- **BREAKING (`ClairHost.h`):** tabs report their split, the browser gains split calls, and a pinned section or favorites list can hold a split item.
- **BREAKING (saved data):** the pin store gains split records. Clair isn't released, so nothing is converted.
- **Supersedes:** `add-page-toolbar`'s decision that site controls take the toolbar's trailing slot, where Arc has its split button. The split button takes it, as in Arc, and site controls, extensions and indicators move one slot left.

**Out of scope:**
- **More than two panes.** Dia allows four and adds a pane where a tab is dropped; Chromium's split model allows only two. `design.md` ("Beyond two panes") and `dia-reference/` keep what was learned for a later change.
- Vertical (stacked) splits, and Arc's grid of four.
- Arc's Expand Current Split and Easel.

## Capabilities

### New Capabilities

- `split-view`: splitting the page into two panes: making a split (dragging onto the page, Option+click, the split button, menus, a Peek), the pane layout, headers, focus and divider, replacing, swapping, separating and closing panes, the split row in the sidebar and its menu, tab commands, Peeks in a split, pinned and favorited splits, and splits across windows, Spaces and relaunches.

### Modified Capabilities

- `page-toolbar`: "Toolbar controls": the split button takes the trailing slot, and site controls, extensions and indicators move one slot left.
- `sidebar`:
  - "Navigation controls" and "URL field": while the page is split, the controls move to the pane headers, as when the toolbar shows.
  - "Today tab menu" adds Split with Tab ›.
- `pinned-tabs`:
  - "Pinned section" lists pinned splits.
  - "Pinned tab menu" adds Split with Tab ›.
- `favorites`:
  - "Favorites grid": a favorited split takes one tile.
  - "Favorite menu" adds Split with Tab ›.
- `tab-folders`: "Folders hold pinned tabs" lets a folder hold pinned splits.
- `peek`:
  - "Peek layout": in a split, the Peek is centred over the page area, and only its parent's pane shrinks and washes out.
  - "The link status names the Peek" is added: holding Shift over a link shows "Open <URL> in Peek".
  - "Peek buttons" adds Open in Split View, hidden while the parent is in a split.
- `browser-window`: "Both pages of a split are visible" is added.

## Impact

- **`native/ClairHost.h`** changes, so the engine key changes and the engine is rebuilt.
- **Overlay:** a `ClairSplits` per window over Chromium's split collections:
  - making, replacing, swapping, separating and closing splits;
  - Option+click and the link menu item;
  - keeping both pages visible;
  - the split's place in Clair's tab order and Spaces;
  - moving splits between windows.

  The pin store gains split records. Session restore and tab restore get the splits Chromium saves, which needs verifying against Clair's Space session.
- **Patches:** probably a small one so Option+click reaches the browser rather than starting a download (`design.md` D6). `clair_window_hooks.mm` stops removing Open Link in Split View from the page's context menu. `clair_native_window.mm` keeps `IDC_NEW_SPLIT_TAB` hidden, since Clair's own items replace it (`design.md` D9).
- **`ClairUI`:**
  - `PageCardView` lays out a list of panes with a divider;
  - `PageToolbar` gains the pane variants and the split button;
  - the split row and the favorite split tile;
  - drag-onto-page drop zones;
  - the new menu items;
  - `PageHeaderPolicy` gets the real pane count.
- **Runtime suite:** new coverage for splits. Views the suite drives change, so the quality checks run on the branch before merging.
- **References:** `arc-reference/` and `dia-reference/`, probed on 2026-11-25 from the owner's Arc and Dia.
