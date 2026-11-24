# Design

## Context

Pinned tabs and favorites are records in `ClairPinStore` (`add-pinned-tabs-and-favorites` D1), in the Local State pref `clair.pins`: a Space's pinned section is a flat list of pin IDs, and each record has a `parent` field reserved for folders, always empty. `ClairSpaceTabs` lists a bound pinned tab with its pin and computes the rows the tab commands and the next-tab rule use (D2, D4). `ClairHost.h` gives `ClairUI` a Space's pins as a flat array (`pinsInSpace:`, `pinsDidChange:inSpace:`) and moves them by index (`pinTab:atIndex:`, `movePin:toSpace:atIndex:`).

In `ClairUI`, the pinned rows, the divider with "New Tab" and the Today rows are one SwiftUI `List`, which reorders with `onMove` and takes drops from the grid with `onInsert`. `PinsLogic.listDrop` maps a gap in the list to a section and index (`polish-sidebar-drops` D2). Row menus are AppKit menus from `RowClickCatcher`. The Space header's menu comes from `SpacesLogic.headerMenu`. The collapsed pinned sections are the user default `ClairCollapsedPinnedSpaces`.

Arc's behavior is in `arc-reference/README.md`.

## Goals / Non-Goals

**Goals:**
- The behavior in `specs/`.

**Non-Goals:**
- Folders inside folders, Change Icon…, Copy All Links, the search popover, Share Folder… and Live Folders. The format below leaves room for nesting (a folder is an item like a pin), but nothing reads or writes it.
- Arc's per-window open state. Clair keeps one state per folder (D3).
- Exact sizes and colours, which weren't measured: the folder row uses the pinned row's metrics, and its icon and name are tuned by hand against Arc in task 3.7.

## Decisions

### D1. Folders are records in the pin store, which stays at version 1

```
clair.pins  { "version": 1,
              "spaces":   { "<space uuid>":  ["<pin or folder uuid>", …] },  // the pinned section, in order
              "profiles": { "<profile dir>": ["<pin uuid>", …] },            // favorites, unchanged
              "folders":  { "<folder uuid>": { "name": "…",
                                               "open": true,
                                               "pins": ["<pin uuid>", …] } },
              "items":    { "<pin uuid>": { "url": …, "title": …, "name": … } } }
```

- **A Space's list holds items**, each a pin or a folder ID. A folder's own list holds pin IDs only (one level, the spec's rule). A pin is in exactly one list: a Space's, a folder's or a profile's.
- **`parent` goes.** A folder's `pins` list carries the order a `parent` field couldn't, and two sources of truth could disagree.
- **The version stays 1.** A store written before this change is already valid: its Space lists hold only pin IDs, which are items, and a missing `folders` means none. Loading ignores `parent`, and saving no longer writes it. Clair isn't released, so no older engine reads the new keys, and a version bump would only mark a change that needs no conversion.
- **The open state is in the record** (D3), so the engine, which runs the tab commands, knows which tabs a closed folder hides.
- **`ClairPinStore` gains** `CreateFolder`, `RenameFolder`, `SetFolderOpen`, `MoveItem` (a pin or folder to a Space's list, or a pin into a folder, at an index), `DuplicateFolder` (copies records and icon files), `RemoveFolder(remember)` and `FoldersIn`. `PinContainer` gains a folder ID, so a pin's place is a Space, a folder or a profile. Observers still hear `OnPinsChanged` for the folder's Space.
- **Alternative: folders in `ClairUI`'s user defaults, grouping the store's pin IDs.** Rejected: the order of folders among pins would then live in two stores, the engine's tab commands couldn't skip closed folders, and every move, removal, restore and Space deletion would have to update both.

### D2. The contract: pinned items

- **A new snapshot, `ClairFolder`:** `folderID`, `spaceID`, `name`, `isOpen` and `pins`, its pins' `ClairPin` snapshots in order.
- **A new snapshot, `ClairPinnedItem`:** exactly one of `pin` or `folder`. `pinsInSpace:` becomes `pinnedItemsInSpace:`, and the observer's `pinsDidChange:inSpace:` becomes `pinnedItemsDidChange:inSpace:`.
- **`ClairPin` gains** `folderID`, nil outside a folder.
- **Places:** a top-level index counts items (pins and folders). A folder's index counts its pins. The calls that place a pin gain a nullable folder: `pinTab:inFolder:atIndex:` and `movePin:toSpace:folder:atIndex:` replace `pinTab:atIndex:` and `movePin:toSpace:atIndex:`. Cmd+D passes nil and the end, as now.
- **The host gains:** `createFolderNamed:inSpace:atIndex:` (returns the ID), `renameFolder:to:`, `setFolder:open:`, `moveFolder:toSpace:atIndex:`, `duplicateFolder:`, `deleteFolder:` (D7), `closeTabsInFolder:` (Close This Folder: every bound tab through the close flow, as Clear Today does) and `turnFolderIntoSpace:` (D8, returns the new Space's ID).
- This is a breaking change to the contract, so the engine key changes.
- **Alternative: keep `pinsInSpace:` flat and add `foldersInSpace:`.** An empty folder's place among the pins would then need a separate order, which is what an item list is.

### D3. One open state per folder

A folder's `open` flag is in its record (D1) and applies in every window, across relaunches, as `ClairCollapsedPinnedSpaces` does for pinned sections. A click calls `setFolder:open:`. A new folder and a duplicate are open, and a restored one keeps its flag.

- **Alternative: per window, as Arc (`expandedItems` in `StorableWindows.json`).** Rejected for the same reason the collapse state is per Space: Clair's windows share their tab lists (`share-tabs-across-windows`), and two windows of one Space showing different rows would make Cmd+number differ between them.
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
- **`deleteFolder:`** removes the folder and its pins from the store, remembering them as one removal (the folder record, its pins' records, its Space and index), then closes the bound tabs through the close flow. Removing first leaves each closed tab's own `TabRestoreService` entry newer, as for a removed pin (`add-pinned-tabs-and-favorites` D3).
- **Restore Last Closed Tab** (`ExecuteTabCommand`'s `IDC_RESTORE_TAB`, as for pins):
  - when the newest removal of the profile is newer than Chromium's entry, it puts the folder and its pins back at their index, or at the end when the Space's list is shorter;
  - when Chromium's entry is newer and its tab's `clair_pin` names a pin of a removed folder, the whole folder comes back first, and the restored tab binds to its pin. The folder's other tabs keep their entries in Chromium's list.
- **A removed single pin** remembers its folder and index in it. It goes back there while the folder exists, and to the end of the Space's pinned section otherwise.

### D8. Turning a folder into a Space

`turnFolderIntoSpace:` creates a Space after the last, named after the folder, without an icon, with the folder's Space's profile (`ClairSpaceStore`), moves each pin to the new Space's list in order with `MoveItem`, moving bound tabs as Move to Space does (`add-pinned-tabs-and-favorites` D5, `add-spaces` D7), removes the empty folder unremembered, and returns the new Space's ID. `ClairUI` then shows that Space in the window, with the switching animation. The profile is the same, so pages stay open.

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
- **Duplicate** calls `duplicateFolder:`, which inserts the copy right after the folder, with new pin records copying the URLs, titles, names and icon files, unbound.

## Risks / Trade-offs

- **[A drop on a row may not reach an AppKit view inside a `List` row]** → task 1.1 checks it before anything is built on it, and D5 has a fallback.
- **[A folder dragged in the `List` lifts only its own row]** → its tabs' rows stay in place until the drop, then move with it. Arc's own lifted folder wasn't observed; the hand check compares them.
- **[An older engine reading a store with folders would drop the folders' pins, which are in no Space list]** → Clair isn't released, and an older build isn't run against a newer profile in practice.
- **[A restored folder with several open tabs reopens only the last page]** → the others stay in Chromium's recently closed list, so Restore Last Closed Tab again brings each back, binding to its pin.
- **[The open state is app-wide, unlike Arc's]** → stated in the spec; changing to per window later only moves the flag.
