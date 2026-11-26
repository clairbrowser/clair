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
- The pane that isn't focused shows its hidden controls when the pointer comes near its header. Clair shows them while the pointer is anywhere over that pane.

## To probe (tasks.md 1.1)

- The drag-onto-page UI: the portrait card's size, the drop zone's tint and border, and the slide's timing.
- The split row with long titles at the default sidebar width.
- Closing one pane of a pinned split.
- With a Peek open from one pane, what a click on the other pane does.

## Peek in a split

Only the Peek's parent pane shrinks, is covered and washes out; the other pane stays as it is (the owner, in PR #259).
