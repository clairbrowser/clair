# Tasks

## 1. Probe tooling

- [x] 1.1 Let `tests/probe/tools/drag.swift` take waypoints after the first two points, and a trailing hold in seconds (0.3 by default), and describe both in its header and in `tests/probe/README.md`'s "Drags in Clair". Verify that `build/probe/bin/drag` builds with `tests/probe/tools/build.sh`, and that a drag through three points with a 2 s hold can be screenshotted mid-drag.

## 2. The drag type (D1)

- [x] 2.1 Make `SidebarDragItem.type` conform to `public.utf8-plain-text`, and have `package.sh` add `dev.joshuapark.clair.sidebar-item`, conforming to `public.utf8-plain-text`, ahead of the engine's entries in `UTExportedTypeDeclarations`. Add a `package.test.sh` check that the declaration is written and the engine's own types stay, and a `PinsTests` test that the type conforms to plain text, plain text doesn't conform to it, and payloads round-trip. Verify that CI's `package.test.sh` and ClairUI tests pass.

## 3. Places beside the divider and "New Tab" (D2)

- [x] 3.1 Make the divider and "New Tab" one list row, without `moveDisabled`, which `onMove` ignores as a source, and count it as one boundary row in `listDrop`. Update `PinsTests` for one boundary row, and add tests that, with no pinned rows, destination 0 is `.pinned(0)` and 1 is `.today(0)`, and that a pinned tab dropped below the row is `.today(0)`. Verify with the ClairUI tests, and by hand with the probe:
  - a Today tab and a favorite dragged above the divider of an empty section are pinned;
  - with Today tabs, a pinned tab dragged just below "New Tab" becomes the first Today tab;
  - a Today tab dragged just above the divider, below the last pinned tab, is pinned last;
  - no insertion line shows between the divider and "New Tab";
  - dragging the divider or "New Tab" moves nothing, a click on "New Tab" opens the command bar, and Clear still works.

## 4. The favorites drop target (D3)

- [x] 4.1 Add `FavoritesDropArea`, the AppKit drop view with the `DraggedTile` image, and `BrowserWindowModel.icon(of:)`. Use it in place of the SwiftUI drop handlers of `FavoritesGrid` and `FavoritesHintBox`, and remove `FavoritesDropDelegate`. Verify by hand with the probe, screenshotting mid-drag with the pointer (`screencapture -C`):
  - over the box, a Today tab's drag shows a tile as wide as the box, the box highlights, and the pointer shows no "+";
  - over a grid of one, the drag shows a half-row tile and the favorite makes room;
  - dragging on past the grid and back to the Today tabs shows the row again;
  - drops make favorites where they land, from a Today tab and a pinned tab;
  - clicking a tile still shows its page, and dragging a tile within the grid reorders it.

## 5. Dropping on the Space header (D4)

- [x] 5.1 Add `PinningDropDelegate` and `SpaceHeaderView.isDropTarget`, and attach the delegate to the shown Space's header in `SpacePage`, pinning last. Verify by hand with the probe:
  - the header shows its pill and no "+" under a drag;
  - a Today tab dropped on it in an empty Space is pinned, and a second one lands after it;
  - a favorite dropped on it becomes the last pinned tab;
  - in a collapsed section, the dropped tab is pinned last;
  - an incognito window's header takes no drop.

## 6. Release notes and checks

- [x] 6.1 Add a Changie fragment: dragging a tab into an empty pinned section, onto the favorites or onto the Space header pins it or makes it a favorite, and over the favorites the drag shows the tile. Verify that it's in the PR.
- [x] 6.2 Run the merge gate and the quality checks on the branch (`gh workflow run quality.yml --ref <branch>`), since the tab list and the header are views the runtime suite drives. Verify that CI and the quality checks pass.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.
