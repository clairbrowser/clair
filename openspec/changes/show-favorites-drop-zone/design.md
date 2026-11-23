# Design

## Context

The sidebar's favorites slot shows the grid while a profile has favorites, and the "Drag to add Favorites" box while it has none and the box was never dismissed (`favorites`, "No favorites yet"). Otherwise it's empty, and nothing above the Space header takes a drop. The grid and the box each carry a `FavoritesDropArea`, the AppKit drop view that turns the drag into a tile (`polish-sidebar-drops` D3).

Arc's behavior, from the owner's recordings (`arc-reference/`):

- The box appears in one frame once the pointer goes above the Space header, pushing the Space down. Before that, the top row accepts the drag, with "+" on the pointer.
- It stays while the drag goes anywhere else, and goes in one frame when the drag ends.
- It has the dismissable box's layout without the ×, a fainter border and no accent tint. With the drag over it, the border turns solid and the contents fade.
- The drag over it shows a square tile.

## Goals / Non-Goals

**Goals:**
- The behavior in `specs/`.

**Non-Goals:**
- Arc's animated shrink from row to tile, as in `polish-sidebar-drops`.
- Dark Mode measurements: Arc's weren't recorded. Clair uses the Light Mode opacities of white, which read as faint in Dark Mode too.
- Changing the dismissable box, its look or its drag tile.

## Decisions

### D1. An AppKit trigger above the header opens the zone

`FavoritesDropTrigger` is an `NSView`, registered for `SidebarDragItem.type`, whose `hitTest` returns nil, like `FavoritesDropArea`. `SidebarView` lays it over the sidebar from its top down to the Space header (the top row, the URL field, the extensions and the gap below them) while the zone can show: the window shows pins, no New Space form shows, the profile has no favorites and the dismissable box doesn't show.

- **Entering** opens the zone (`SidebarView`'s `showsFavoritesDropZone`) and answers `.move`, so the pointer shows no "+", as elsewhere in the sidebar.
- **A drop** on it makes the profile's first favorite, `drop(_:on: .favorites(0))`, as on the box.

While the zone shows, the trigger ends at the box's top inset, and the box's own `FavoritesDropArea` takes the drag below.

- **Alternative: a SwiftUI `onDrop` overlay.** It covers the gap above the header only as a view that takes hits, which would block clicks on the top row and the URL field, and the window drag of the empty space. An AppKit view whose `hitTest` returns nil still gets drags (`polish-sidebar-drops` D3).
- **Alternative: open the zone when any sidebar drag starts.** Arc waits until the pointer goes above the header, and the rows' drags start in SwiftUI's `List`, which doesn't report them.

### D2. The zone closes when the mouse button is up

The drags start in SwiftUI (`List` rows and `onDrag` tiles), which report no end, and AppKit tells a destination that a drag ended only if it was the last one under the pointer. So while the zone shows, a task on the main actor checks `NSEvent.pressedMouseButtons` every 100 ms and closes the zone once the left button is up. The main queue runs in the drag's event-tracking run loop mode, so the check runs during the drag. A drop on the zone or the trigger also makes a favorite, which hides the favorites' empty states anyway.

- **Alternative: `draggingEnded` on the trigger and the box.** Neither is told when the drag ends over the tab list, which is where most drags end.

### D3. The drop zone is the hint box in another style

`FavoritesHintBox` takes `isDropZone`. As the zone, it has no × and:

| | Border | Fill | Contents |
|---|---|---|---|
| Not under the drag | dashed, accent at 30 % | white at 12 % | as the box |
| Under the drag | solid, accent at 30 % | white at 30 % | at 50 % opacity |

Its layout, size and insets stay the box's, which Arc's match. `SidebarView` counts it as the favorites section for the Space's top padding, as it does the box.

### D4. A square tile over the zone

The zone's `FavoritesDropArea` reports a tile of `FavoritesLayout.tileHeight` on each side, 47 pt, about the 45 pt Arc's measured. The dismissable box keeps its row-wide tile.

## Risks / Trade-offs

- **[A drag that ends without the button going up, such as Esc]** → the zone stays until the button is released, which is when the user lets go.
- **[The zone moves the Space down mid-drag]** → as in Arc. The pointer is then over the zone or the trigger, so the drop still lands in the favorites.
- **[The runtime suite doesn't drag]** → the hand checks in `tasks.md` cover it, with the probe's real-mouse `drag` tool.
