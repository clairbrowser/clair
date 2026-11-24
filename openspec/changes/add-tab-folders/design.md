# Design

## Context

Pinned tabs and favorites are records in `ClairPinStore` (`add-pinned-tabs-and-favorites` D1), in the Local State pref `clair.pins`: a Space's pinned section and a profile's favorites are each a flat list of pin IDs, and each record has a `parent` field reserved for folders, always empty. iCloud sync is planned after the MVP. `ClairSpaceTabs` lists a bound pinned tab with its pin and computes the rows the tab commands and the next-tab rule use (D2, D4). `ClairHost.h` gives `ClairUI` a Space's pins as a flat array (`pinsInSpace:`, `pinsDidChange:inSpace:`) and moves them by index (`pinTab:atIndex:`, `movePin:toSpace:atIndex:`).

In `ClairUI`, the pinned rows, the divider with "New Tab" and the Today rows are one SwiftUI `List`, which reorders with `onMove` and takes drops from the grid with `onInsert`. `PinsLogic.listDrop` maps a gap in the list to a section and index (`polish-sidebar-drops` D2). Row menus are AppKit menus from `RowClickCatcher`. The Space header's menu comes from `SpacesLogic.headerMenu`. The collapsed pinned sections are the user default `ClairCollapsedPinnedSpaces`.

Arc's behavior is in `arc-reference/README.md`.

## Goals / Non-Goals

**Goals:**
- The behavior in `specs/`.

**Non-Goals:**
- Folders inside folders, Change Icon…, Copy All Links, the search popover, Share Folder… and Live Folders. The format below could express nesting (a folder's parent naming a folder), but the store refuses to write it.
- Syncing. iCloud sync comes after the MVP, so D1 shapes the store as per-item records a sync layer can send one by one, and D3 keeps the per-Mac state out of them. The sync itself, its record types and a profile ID that is the same on every Mac are left to that change.
- Arc's per-window open state. Clair keeps one state per folder on each Mac (D3).
- Converting stores written before this change. Clair isn't released, so a store in the old shape loads empty.
- Exact sizes and colours, which weren't measured: the folder row uses the pinned row's metrics, and its icon and name are tuned by hand against Arc in task 3.7.

## Decisions

### D1. Every pinned tab, favorite and folder is a record with a parent and a sort key

```
clair.pins  { "version": 1,
              "items": {
                "<uuid>": { "kind": "folder", "parent": "space:<space uuid>",   "order": "a0", "name": "Trip" },
                "<uuid>": { "kind": "pin",    "parent": "folder:<folder uuid>", "order": "a0",
                            "url": "https://…", "title": "…", "name": "…" },
                "<uuid>": { "kind": "pin",    "parent": "space:<space uuid>",   "order": "a1", … },
                "<uuid>": { "kind": "pin",    "parent": "profile:<profile dir>", "order": "a0", … } } }
```

- **Each record says where it is.** `parent` is a Space (its pinned section), a folder, or a profile (its favorites). `order` is a fractional index: a string that sorts between its neighbours, so a record can always get a key between any two others. A container's items are its children sorted by `order`, then by ID.
- **A move changes one record.** Pinning, reordering, moving into or out of a folder, Move to Space and Restore each rewrite only the record that moved, never its siblings. That is what lets a later sync send and merge records one by one: two Macs editing different items can't overwrite each other's edits, as they would with an ordered list per container.
- **One fact, one place.** There is no list of children next to the parent pointer, as Arc has (`childrenIds` with `parentID`), so the two can't disagree. The `spaces` and `profiles` lists of the first pin store go, with `parent`'s old meaning.
- **One level is checked on write.** A folder's parent must be a Space, and a folder's children must be pins. The store refuses any other write, and on load drops records whose parent is missing or not allowed, with their icons.
- **The sort keys** come from a small helper in the overlay, `clair_order_key.{h,mm}`: base-62 digit strings with the key between two neighbours, before the first and after the last, as in the common fractional-indexing scheme. Keys grow only when inserts keep landing in the same gap, which a sidebar's edits don't do often. The runtime suite covers repeated inserts in one gap and at both ends (task 3.9).
- **Indices stay in the contract** (D2): the engine turns "index 2 in this container" into a key between that place's neighbours.
- **The old shape isn't converted.** Clair isn't released, so no installed copy has data to keep, and a store in the old shape loads empty.
- **`ClairPinStore` gains** `CreateFolder`, `RenameFolder`, `MoveItem` (a pin or folder to a container at an index), `DuplicateFolder` (copies records and icon files), `RemoveFolder(remember)` and `ChildrenOf(container)`, and keeps one index of children per container in memory, rebuilt on load and updated on each write. `PinContainer` gains a folder ID. Observers still hear `OnPinsChanged` for the Space or profile that changed.
- **Alternative: ordered lists per container, with folders inside a Space's list.** Simplest for local use, but a container's whole list is then one value, so under sync a reorder on one Mac and an addition on another collide and one is lost.
- **Alternative: Arc's tree, with `childrenIds` and `parentID` on every node.** It stores each item's place twice, and its generality serves nesting, Live Folders and Easels, which Clair doesn't have.
- **Alternative: folders in `ClairUI`'s user defaults, grouping the store's pin IDs.** Rejected: folders would live in two stores, and the engine's tab commands couldn't skip closed folders.

### D2. The contract: pinned items

- **A new snapshot, `ClairFolder`:** `folderID`, `spaceID`, `name`, `isOpen` and `pins`, its pins' `ClairPin` snapshots in order.
- **A new snapshot, `ClairPinnedItem`:** exactly one of `pin` or `folder`. `pinsInSpace:` becomes `pinnedItemsInSpace:`, and the observer's `pinsDidChange:inSpace:` becomes `pinnedItemsDidChange:inSpace:`.
- **`ClairPin` gains** `folderID`, nil outside a folder.
- **Places:** a top-level index counts items (pins and folders). A folder's index counts its pins. The calls that place a pin gain a nullable folder: `pinTab:inFolder:atIndex:` and `movePin:toSpace:folder:atIndex:` replace `pinTab:atIndex:` and `movePin:toSpace:atIndex:`. Cmd+D passes nil and the end, as now.
- **The host gains:** `createFolderNamed:inSpace:atIndex:` (returns the ID), `renameFolder:to:`, `setFolder:open:`, `moveFolder:toSpace:atIndex:`, `duplicateFolder:`, `deleteFolder:` (D7), `closeTabsInFolder:` (Close This Folder: every bound tab through the close flow, as Clear Today does) and `turnFolderIntoSpace:` (D8, returns the new Space's ID).
- This is a breaking change to the contract, so the engine key changes.
- **Alternative: keep `pinsInSpace:` flat and add `foldersInSpace:`.** An empty folder's place among the pins would then need a separate order, which is what an item list is.

### D3. Each folder's open state, on each Mac

Whether a folder is open isn't in its record: it's the Local State pref `clair.closed_folders`, a list of the closed folders' IDs, which `ClairPinStore` reads and writes beside `clair.pins` and prunes when a folder is removed. A sync layer leaves it out, so opening a folder on one Mac doesn't open it on another, as Arc keeps `expandedItems` out of its sidebar file. A click calls `setFolder:open:`. A folder is open unless it's listed, so a new folder and a duplicate are open. A removed folder remembers whether it was closed (D7).

- **Applies in every window**, as `ClairCollapsedPinnedSpaces` does for pinned sections. Per window, as Arc (`expandedItems` in `StorableWindows.json`), was rejected for the same reason the collapse state is per Space: Clair's windows share their tab lists (`share-tabs-across-windows`), and two windows of one Space showing different rows would make Cmd+number differ between them.
- **Alternative: an `open` field in the folder's record.** Syncing it would open and close folders on every Mac at once.
- **Alternative: a user default in `ClairUI`.** Rejected, because the engine's tab commands need it (D9).

### D4. Folder rows in the pinned list

`ClairUI` flattens the pinned items into the `List`'s rows: a folder row, then its pins' rows indented 16 pt when the folder is open, or only its selected pin's row when it's closed. Each row knows its depth and its place (Space and index, or folder and index).

- **The folder row** has the icon (SF Symbols' `folder` drawn open while open, closed otherwise, with an ellipsis badge while closed with a bound tab), the name in the pinned row's font at semibold, the hover pill, and the − button with "Close This Folder" while any of its pins is bound.
- **Gaps** map to places in `PinsLogic.listDrop`, extended:
  - between a folder row and its first visible tab, between its tabs, and after an open folder's last tab: in the folder, at that index, as Arc does (`drop-below-last-tab*.jpg`);
  - after an open, empty folder's row: first in it;
  - after a closed folder's row: the top level, after the folder.
- **A dragged folder row** may land only on top-level gaps; elsewhere `onMove` ignores it, so it stays where it was. Its tabs' rows move with it once the store changes.
- **Collapsed sections** (`Folders in a collapsed pinned section`) show only the active row, flattened, without its folder.
- **Alternative: `OutlineGroup` or `DisclosureGroup` in the list.** `onMove` doesn't move rows between disclosure groups, and the list's height arithmetic and the runtime suite's row counts assume flat rows.

### D5. Dropping on a folder's row

A drop on the row itself, rather than in a gap, makes the item the folder's first tab, for a closed folder too. `polish-sidebar-drops` D2 found that the table view takes drags first, so a SwiftUI drop target on a row is never called. The row therefore carries an AppKit drop view, like `FavoritesDropArea` (`polish-sidebar-drops` D3): an `NSView` registered for `SidebarDragItem.type` whose `hitTest` returns nil, covering the row's middle half, so drags near its edges still reach the table's gaps. It shows the row's hover pill while the drag is over it and answers `.move`.

Task 1.1 checks first that an AppKit view inside a row's hosting view receives the drag before the table does.

- **Fallback, if it doesn't:** spring-loading. A drag held over a closed folder's row for 0.6 s opens it, so its first gap takes the drop, and a drop on an open folder's row maps to its first gap. The spec then changes for closed folders, and the design records it.

### D6. Creating and naming a folder

- **New Folder** (footer, header menu, sidebar menu) calls `createFolderNamed:inSpace:atIndex:` with "Untitled" and the end. When the item arrives through `pinnedItemsDidChange`, `ClairUI` puts that folder's row in edit mode with the name selected, using the rename field the rows already have (`add-pinned-tabs-and-favorites` D11), with the placeholder "Folder Title". Return and focus loss call `renameFolder:to:`; Esc and an empty name leave "Untitled". Rename… in the folder menu uses the same field.
- **Tabs › New Folder…** is a `PinsMenu` item after Pin Tab, with a Clair tag and no shortcut, validated on the key window's controller like the others and disabled in private windows. It opens a `ClairDialog` titled "New Folder…" whose content is a text field with the placeholder "What are you organizing?", and Cancel and Create; Create is disabled while the field is empty once trimmed. Create calls `createFolderNamed:` with the trimmed name, and no edit mode follows.
- **The footer's plus menu** gains New Folder after New Space…, then a divider. `SpacesLogic.headerMenu` gains New Folder between dividers after Set Profile, so the header, its More button and the sidebar's own menu (D10) all get it.

### D7. Deleting and restoring a folder

- **`ClairUI`** deletes an empty folder at once, and otherwise shows a `ClairDialog`: "Delete your "<name>" folder?", "Deleting this folder will remove the tabs inside it.", Cancel and the destructive Delete Folder (`dialogs`, "Destructive dialog buttons").
- **`deleteFolder:`** removes the folder and its pins from the store, remembering them as one removal (the folder's record with its parent and sort key, its pins' records, and whether it was closed), then closes the bound tabs through the close flow. Removing first leaves each closed tab's own `TabRestoreService` entry newer, as for a removed pin (`add-pinned-tabs-and-favorites` D3).
- **Restore Last Closed Tab** (`ExecuteTabCommand`'s `IDC_RESTORE_TAB`, as for pins):
  - when the newest removal of the profile is newer than Chromium's entry, it puts the records back with their sort keys, so the folder returns between the neighbours it had, or at the end of the section when its Space is gone or a key now collides;
  - when Chromium's entry is newer and its tab's `clair_pin` names a pin of a removed folder, the whole folder comes back first, and the restored tab binds to its pin. The folder's other tabs keep their entries in Chromium's list.
- **A removed single pin** keeps its parent and sort key. It goes back there while the folder exists, and to the end of the Space's pinned section otherwise.

### D8. Turning a folder into a Space

`turnFolderIntoSpace:` creates a Space after the last, named after the folder, without an icon, with the folder's Space's profile (`ClairSpaceStore`), moves each pin to the new Space in order with `MoveItem`, moving bound tabs as Move to Space does (`add-pinned-tabs-and-favorites` D5, `add-spaces` D7), removes the empty folder unremembered, and returns the new Space's ID. `ClairUI` then shows that Space in the window, with the switching animation. The profile is the same, so pages stay open.

### D9. Tab commands and the next tab

`ClairSpaceTabs`' rows (`add-pinned-tabs-and-favorites` D4) become: the Space's items in order, each pin, and for a folder its pins when it's open, or only the window's active tab when it's closed and the tab is in it; then the Today tabs. The next-tab rule passes over unbound pins as now, and over pins a closed folder hides. Ctrl+Shift+PageUp/Down move a folder's pin within the folder, stopping at its ends.

### D10. The sidebar's own menu

Right-clicks that land on no row reach the list's table view, or the sidebar below the list when the list is shorter than the sidebar. Two catchers, built on `RowClickCatcher`, show the header's menu items:

- behind the `List`, as its background, for clicks between and after rows;
- on the "New Tab" row's own catcher, which today has no menu, which also keeps its hover pill while the menu shows, as rows do.

Both are absent in incognito and guest windows, which show no Space header. The menu items come from the same function as the header's (`SpaceHeaderView`'s `menuItems`), moved to where both can use it.

- **Alternative: `contextMenu(forSelectionType:)` on the `List`,** which reports an empty selection for empty space. Rejected to keep one mechanism: the rows' menus are AppKit menus from `RowClickCatcher`, and it's untested how the two interact on the same table.

### D11. Moving and duplicating folders

- **Move to Space ›** calls `moveFolder:toSpace:atIndex:` with the end. Bound tabs move as Move to Space moves a pinned tab's, across profiles with `add-profiles` D9. As for a tab, a window whose active tab was in the folder follows it, and otherwise `ClairUI` shows "Folder was moved to <Space>" in the notice Move to Space uses.
- **Duplicate** calls `duplicateFolder:`, which inserts the copy right after the folder, with a key between the folder and its next sibling, and new pin records, keeping their keys, copying the URLs, titles, names and icon files, unbound.

## Risks / Trade-offs

- **[A drop on a row may not reach an AppKit view inside a `List` row]** → task 1.1 checks it before anything is built on it, and D5 has a fallback.
- **[A folder dragged in the `List` lifts only its own row]** → its tabs' rows stay in place until the drop, then move with it. Arc's own lifted folder wasn't observed; the hand check compares them.
- **[Pins saved by builds before this change are lost]** → Clair isn't released; developers re-pin after updating.
- **[Sort keys grow when items keep landing in one gap]** → each insert adds at most one digit, so a sidebar needs thousands of such moves before a key is long; a later change can rebalance a container's keys if it ever matters.
- **[A restored folder with several open tabs reopens only the last page]** → the others stay in Chromium's recently closed list, so Restore Last Closed Tab again brings each back, binding to its pin.
- **[The open state is per Mac and shared by its windows, unlike Arc's per window]** → stated in the spec; changing to per window later only changes `clair.closed_folders`.
