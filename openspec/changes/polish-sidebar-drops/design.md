# Design

## Context

The sidebar has two kinds of drop target (`add-pinned-tabs-and-favorites` D11):

- **The tab list:** the pinned rows, the divider, "New Tab" and the Today rows, all in one SwiftUI `List`. Rows move inside it with `onMove`, and tiles dropped on it arrive through `onInsert`.
- **Everything else:** the favorites grid and the "Drag to add Favorites" box used SwiftUI `onDrop`.

Each drag carries a `SidebarDragItem` (`tab:<id>` or `pin:<id>`) under its own type, `dev.joshuapark.clair.sidebar-item`, so a page's text dropped on the sidebar is ignored.

On macOS, the `List` is an `NSTableView`, which starts row drags and owns every drag over its rows, so SwiftUI drop targets inside the rows never see them. Probing with real mouse events (`tests/probe/tools/drag.swift`), with logging in `onMove`, `onInsert` and `drop(_:on:)`, showed:

- **No insertion point beside unmovable rows.** The divider and "New Tab" were `moveDisabled`, and the list didn't offer every insertion point beside them. With no pinned rows, dropping above the divider or between it and "New Tab" reached nothing. With one pinned row, both worked. A pinned row dragged down was never offered the place between "New Tab" and the first Today row, so it could only land after that row, though a Today row dragged up was offered it. With "New Tab" movable, the pinned row was offered it too.
- **No drop on the favorites from a list row.** The drag pasteboard held the item, plus file-promise metadata, because the type conformed only to `public.data`. No drop target outside the list accepted it, and declaring the type in `Info.plist` alone didn't change that. A type conforming to `public.utf8-plain-text` arrived as plain data, and the favorites took it.

## Goals / Non-Goals

**Goals:**
- The behavior in `specs/`, with the list's own reordering and its insertion line left as they are.

**Non-Goals:**
- Arc's live shrink of the row toward the tile. The image changes at once when the drag enters the favorites.
- Centring the tile on the pointer. AppKit keeps the pointer where it held the original image, at the same fraction across, so a row grabbed by its icon shows the tile to the right of the pointer, as Finder's drags do.
- Dropping on a header of a Space the window doesn't show, such as one sliding out, or on the footer's Space switcher.

## Decisions

### D1. The drag type is text of Clair's own type

`SidebarDragItem.type` stays `dev.joshuapark.clair.sidebar-item`, now conforming to `public.utf8-plain-text`. `package.sh` adds it to `UTExportedTypeDeclarations`, ahead of the engine's own types, because Apple expects an exported type to be declared.

Plain text doesn't conform to Clair's type, so a page's text still matches no sidebar drop target. The item provider stays `.ownProcess`, so no other app sees it.

- **Alternative: plain `public.utf8-plain-text`.** Every text drag from a page would then light up the sidebar's targets, and one reading `tab:7` would move a tab.
- **Alternative: declaring the type as data.** The drag still carried a file promise, and no drop worked.

### D2. The divider and "New Tab" are one row that isn't `moveDisabled`

The divider (while it shows) and "New Tab" are one list row. That row can be lifted, so the list offers both places around it:

- **Above it:** the end of the pinned section, or the only place in an empty or collapsed one.
- **Below it:** the top of Today, also for a pinned row dragged down.

As one row, they leave no place between the divider and "New Tab", where a drop would belong to neither section. `onMove` ignores a drag that starts on the row, so lifting it moves nothing. "New Tab" is a button, which takes the press itself, so a click still opens the command bar.

`PinsLogic.listDrop` maps the places with one boundary row: above it is `.pinned(pinCount)`, and below it `.today(0)`. `TabList.target(of:visiblePins:)` maps a pinned index in a collapsed section to its end, as it does for any index past the visible rows.

- **Alternative: two movable rows.** The list then offered the place between them, which a drop reached as the top of Today, with the insertion line above "New Tab".
- **Alternative: `moveDisabled` only while it matters**, such as the divider only while no pinned row shows. Which insertion points the list drops beside an unmovable row depends on the direction of the drag, so any such row left a hole somewhere.
- **Alternative: a drop target on the divider row.** The table view takes the drag first, so it was never called.
- **Alternative: a placeholder row in the empty section.** It would change the list's height arithmetic and the rows the runtime suite counts.

### D3. An AppKit drop target over the favorites

SwiftUI's `DropInfo` doesn't expose the drag, and `NSHostingView` doesn't publish its drop methods to override. So the grid and the box each get a `FavoritesDropArea` overlay in place of their SwiftUI drop handlers. It's an `NSView`, registered for the type, whose `hitTest` returns nil, so clicks, hovers and menus still reach the tiles. AppKit still finds it as the drop target, which the probe confirmed.

It works as follows:

- **Entering:** reads the `SidebarDragItem` from the drag pasteboard.
- **On each update:**
  - It reports the slot under the pointer, so the grid keeps making room.
  - It replaces each dragging item's image with a rendered tile, using `enumerateDraggingItems(options:for:classes:searchOptions:using:)` and `setDraggingFrame(_:contents:)`.
  - It answers `.move`.
- **Leaving:** puts back each item's image components and its offset from the pointer.
- **Dropping:** calls `SidebarActions.drop(_:on: .favorites(slot))`.

The tile is `DraggedTile`: a selected favorite tile with the item's icon, rendered with `ImageRenderer` at the window's scale. It's cached per size.

- **Size:** a slot of the grid with one more tile, as the room it makes. For the box, the box's width at the tile height.
- **Icon:** `BrowserWindowModel.icon(of:)`, which is a Today tab's favicon, or a pin's or favorite's icon as its tile shows it.

Alternatives:

- **Overriding the hosting view's drop methods through the Objective-C runtime.** It would work for one hosting view only, rely on SwiftUI's private methods, and still not reach drags over the table view.
- **Drawing a fake tile inside the grid, keeping the system image.** The row's image would still follow the pointer, which isn't what Arc shows.

### D4. The Space header is a SwiftUI drop target

The header sits outside the `List`, so SwiftUI's `onDrop` reaches it. A `PinningDropDelegate` does the following:

- It validates only for the window's shown Space in a window with pins, so not incognito or guest.
- It sets `isDropTarget` on `SpaceHeaderView`, which draws the same pill as hover.
- It proposes `.move`.
- On drop, it calls `drop(_:on: .pinned(pins.count))`.

`drop(_:on:)` already handles each case:

- A Today tab pins (`pin(tab:at:)`).
- A favorite moves to the pinned section (`movePin(_:toSpace:at:)`).
- A pinned tab moves to the end.

Pinning last matches Pin Tab and Cmd+D (`pinned-tabs`, "Pinning and unpinning").

## Risks / Trade-offs

- **[A later SwiftUI changes how `List` offers insertion points or bridges item providers]** → D1 and D2 rest on observed behavior. Unit tests cover the type's conformance and `listDrop`'s mapping of an empty section, and the hand checks in `tasks.md` cover the drags.
- **[An AppKit view over SwiftUI content]** → `hitTest` nil keeps it out of clicks. The probe checks that clicks, tile selection and reordering still work.
- **[The runtime suite doesn't drag]** → hand checks with the probe tooling cover the drags, and the quality checks confirm the views it drives still work.
