# Proposal

## Why

Dragging is how Arc's sidebar pins tabs and makes favorites, and in Clair it mostly didn't work. A Today tab couldn't be dragged into a Space's empty pinned section, a pinned tab dragged out couldn't land at the top of Today, and no row could be dropped on the favorites at all. Where a drop did work, the drag still looked like a row with a "+" on the pointer, though Arc shows the tile the row will become. A Space with no pinned tabs, or a collapsed section, also left the user no large place to drop a tab to pin it.

## What Changes

- **Rows drop on the favorites.** The type a dragged row carries is declared as text, in ClairUI and in the app's `Info.plist`. As plain data, a row dragged out of the tab list carried a file promise, which the favorites never accepted.
- **Every place around the divider and "New Tab" takes a drop.** The tab list left out some places beside rows that can't move, which the divider and "New Tab" were. So a Today tab couldn't be dropped into an empty pinned section, and a pinned tab dragged out could land only after the first Today tab, never at the top of Today. The two are now one row that can be lifted, though dragging it moves nothing, so the places above and below it take drops and there's none between them.
- **The drag becomes a tile over the favorites, as in Arc.** Over the grid or the "Drag to add Favorites" box, a dragged Today tab, pinned tab or favorite shows the tile it would make, the size of the slot it would take, with its icon. The tiles keep making room. Leaving the favorites brings back the row's own image.
- **Sidebar drags are moves.** No drop target in the sidebar shows "+" on the pointer.
- **The Space header takes drops.** Dropping a Today tab, a pinned tab or a favorite on the shown Space's header pins it last, as Pin Tab does, whether the pinned section is empty, expanded or collapsed. While a drag is over the header, it shows its hover pill. Arc doesn't do this. It's Clair's, at the owner's request.
- **Probe tooling:** `tests/probe/tools/drag.swift` takes waypoints and a hold time, so a drag can go somewhere and back, and be screenshotted mid-drag.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `favorites`: a new requirement says what a drag looks like over the grid and the empty box, and that it's a move.
- `pinned-tabs`: "Reordering and dragging pinned tabs" covers dropping into an empty pinned section and at the top of Today, and a new requirement covers dropping on the Space header.

## Impact

- **`ClairUI`:**
  - `PinsViews.swift`: the drag type, and the header's drop delegate.
  - A new `FavoritesDropArea.swift`: the AppKit drop target over the grid and the box. It replaces their SwiftUI drop handlers.
  - `SidebarView.swift`: the divider and the header.
  - `SpaceHeaderView.swift`: the drop highlight.
  - `BrowserWindowModel.swift`: a dragged item's icon.
- **Packaging:** `package.sh` adds the type to `UTExportedTypeDeclarations`, and `package.test.sh` checks it. The engine key doesn't change.
- **Runtime suite:** the tab list and the header are views it drives, so the quality checks run on the branch before merging.
- **`ClairHost.h` and the engine:** no change.
