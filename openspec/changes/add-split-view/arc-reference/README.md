# Arc's split view: reference screenshots

Seen on 2026-11-25 in the owner's Arc, from window screenshots and the owner's own captures, at 2 px per point, Light Mode. Change 1's `arc-reference/look-and-behaviour.md` ("Split view") has the earlier notes: pane headers, the 10 pt gap, the drag-to-split drop zone and Ctrl+Shift+= and Ctrl+Shift+−.

Clair takes from Arc how a split shows in the sidebar, pinned and favorited splits, the pane headers and focus ring, the drop UI when a tab is dragged onto the page, and Peek's Open in Split View.

Keep these screenshots. They move with the change when it's archived.

| File | Shows |
|---|---|
| split-two-panes-toolbar.jpg | Toolbar on. A split of example.com and wikipedia.org. The focused, leading pane has a 2 pt accent ring and a header with back, forward, reload, the host, pinned extensions, a reader button, the split button and ×. The other pane's header has back, forward, the link icon, the host and ×: no reload. A grabber sits in the gap. The sidebar shows one row with a chip per page, highlighted. |
| today-split-hover.jpg | Toolbar off. A Today split that isn't shown, under the pointer: the two chips separated by a thin divider, and × at the row's trailing end. |
| pinned-split-selected-hover.jpg | A pinned split that is shown, under the pointer: the row is white, each chip is a grey pill, and − (Close and Keep Pinned) sits at the trailing end. The sidebar keeps its URL field: in Arc, a split with the toolbar off keeps it, and back, forward and reload move to the pane headers. Clair moves the URL field to the pane headers too (`add-page-toolbar` D1). |
| favorite-split.jpg | A favorited split that isn't shown: one tile divided into two segments, each with its page's icon, beside a single favorite. |
| favorite-split-selected.jpg | The favorited split shown: the tile is white, with a ring blending from the leading page's icon colour (purple) to the trailing page's (salmon). |

## What the owner checked

- A split can be pinned or favorited as one item, and shows as one in both places.
- Separating a pinned or favorited split leaves both pages pinned, or both favorited.
- A pinned or favorited split offers no Back to Pinned URL.
- Esc in the command bar of Add Split View's empty pane closes the pane. Clair keeps the new tab page in it for now, to keep the first version simple (the owner, in PR #259).
- The pane that isn't focused shows its hidden controls when the pointer comes near its header. Clair shows them while the pointer is anywhere over that pane.

## Probed (tasks.md 1.1)

Probed on 2026-11-25 with `tests/probe/` in the owner's Arc, Light Mode, a 1920 × 976 pt window with the toolbar on (`localhost` pages show Arc's Developer Mode toolbar). Arc takes the drag from real mouse events (`build/probe/bin/drag`); the probe's XCUITest `drag` doesn't start one.

| File | Shows |
|---|---|
| drag-onto-page.jpg | A pinned tab dragged over the trailing half of a page that isn't split, mid-drag. |
| drag-across-sheet.jpg | Frames of one drag, 133 ms apart: over the leading half, across to the trailing half, and back to the sidebar. |
| split-with-pinned-tab.jpg | That drop: a Today split row of "colour" and "Ars Tec…", selected, the trailing pane focused, the pinned tab's row still in its folder. |
| today-split-pinned-pane-closed.jpg | The pinned tab's pane of that split closed: "colour" shows alone, the pin stays in its folder. |
| peek-in-split.jpg | A Peek opened from the leading pane of a split. |
| peek-in-split-other-pane-clicked.jpg | Then a click on the part of the trailing pane the Peek doesn't cover. |
| pinned-split-shown.jpg | Two Today tabs made a split, then Cmd+D: the pinned split row, selected. |
| pinned-split-pane-closed.jpg | Its trailing pane closed with the pane's ×. |
| pinned-split-pane-restored.jpg | Then Restore Last Closed Tab. |
| pinned-split-row-menu.jpg | The pinned split row's menu. |

**Dragging a tab onto the page** (drag-onto-page.jpg, drag-across-sheet.jpg):
- The drag becomes a white portrait card with rounded corners, about **216 × 250 pt**, with the favicon centred above the title in bold, up to three lines, centred under the pointer.
- The drop zone is the half under the pointer: exactly the place the pane would take, half the page area less the 10 pt gap. It has a **2 pt border in the accent colour** with rounded corners, and a fill of the accent colour at very low opacity over the window background (about 4%: 216, 202, 207 outside and 206, 199, 213 inside, with a purple accent).
- The page slides to the other half, with its card and toolbar, 10 pt from the zone: here from 228–1910 pt to 228–1064 pt. The slide takes about **200 ms, ease-out** (most of the distance in the first 100 ms).
- Moving to the other half moves the zone at once, and the page slides across through its full width, again in about 200 ms.
- Back over the sidebar, the zone goes, the page slides back to full width in about 200 ms, and the card turns back into the tab's row.

**The split row** (split-with-pinned-tab.jpg, pinned-split-shown.jpg): at this sidebar width (about 228 pt), the row is inset about 4 pt, and each chip takes half of it, about 99 pt, 3 pt apart, its title truncated with "…" ("Counte…", "Ars Tec…"). With the − button of a selected pinned split, the trailing chip narrows to make room ("col…").

**Closing one pane of a pinned split** (pinned-split-pane-closed.jpg, pinned-split-pane-restored.jpg): this differs from what the spec said before the probe.
- The closed page **leaves the pinned item**: the pinned split becomes a single pinned tab of the other page, in the split's place, selected, with its − button. Clicking it doesn't bring the closed page back.
- Restore Last Closed Tab brings the page back, and the item is a pinned split again with both pages.
- Closing the pane of a *pinned tab in a Today split* is different: the pin stays as it was, and the Today tab shows alone (today-split-pinned-pane-closed.jpg).

The spec (“Closing a pane of a pinned split”) and design D10 now follow Arc.

**A Peek in a split** (peek-in-split.jpg, peek-in-split-other-pane-clicked.jpg):
- The Peek is centred over the whole page area, and only its parent's pane washes out, as noted below.
- Clicking the uncovered part of the other pane closes the Peek, as a click outside a Peek does, and the parent's pane stays focused: the click doesn't focus the other pane.
- Arc shows Close, Expand **and** Open in Split View on a Peek whose parent is in a split, since it allows more panes. Clair hides the last, as its splits hold two tabs.

**Other things seen:**
- The split button's tooltip is "Split View Options". The spec keeps "Split view".
- Cmd+D on a Today split pins it as one row at the end of the pinned section.
- The pinned split row's menu: Share Split View…, Separate All Tabs, Add Tab…, Convert to Vertical Split View, a "Tab Options" heading with a submenu per page, Change Icon…, Rename…, Duplicate, Move to ›, Archive Item and Close (⌘W). Clair's row menu is the tab menu of the chip under the pointer (spec "The split row's menu").

## Peek in a split

Only the Peek's parent pane shrinks, is covered and washes out; the other pane stays as it is (the owner, in PR #259).
