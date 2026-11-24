# Proposal

## Why

In Arc, people group the pinned tabs of a Space into folders. Clair's pinned section is one flat list, so a Space with many pinned tabs has no structure. "Vertical sidebar with folders" is on the MVP list in `ship-plain-ungoogled-build`'s roadmap, and `add-pinned-tabs-and-favorites` left room for folders in the pin store. Arc stops working on 2026-12-22.

This builds on `add-pinned-tabs-and-favorites`, `polish-sidebar-drops` and `show-favorites-drop-zone`, all merged, as built.

## What Changes

- **Folders in the pinned section.** A Space's pinned section holds pinned tabs and folders, in the user's order. A folder holds pinned tabs only: one level, no folders inside folders. Favorites and Today hold no folders.
- **Creating a folder**, as in Arc (`arc-reference/`):
  - the footer's + menu gains New Folder, after New Space…;
  - the Space header's menu gains New Folder, between dividers after Set Profile;
  - right-clicking the sidebar where there's no row or control, or on the "New Tab" row, opens the header's menu.

  Each adds an open folder named "Untitled" at the end of the pinned section, with its name selected in a field. Tabs › New Folder… opens a dialog, "What are you organizing?", with Cancel and Create.
- **Opening and closing.** A click on a folder opens or closes it. Each folder remembers whether it's open, in every window and across launches. A closed folder still lists its selected tab, and its icon shows "•••" while any of its tabs is open. Hovering a folder with open tabs shows "Close This Folder" (−), which closes their pages and keeps them in the folder.
- **Dragging.** A tab dropped on a folder becomes its first tab. Tabs move into, within and out of a folder by dragging, and folders reorder within the pinned section. A drop just below an open folder's last tab lands in the folder, as in Arc.
- **The folder menu:** Turn "<name>" into Space, Rename…, Duplicate, Move to Space › (with more than one Space) and Delete.
  - **Turn into Space** makes a new Space named after the folder, using the same profile, with the folder's tabs as its pinned tabs, and shows it.
  - **Delete** removes an empty folder at once. A folder with tabs asks first, "Delete your "<name>" folder?", and then removes its tabs too. Clair has no archive, so the message says the tabs will be removed. Restore Last Closed Tab brings the folder back with its tabs.
- **Existing behavior that reaches into folders:**
  - a tab removed from a folder comes back into it with Restore Last Closed Tab;
  - deleting a Space removes its folders;
  - the tab commands (Cmd+1 to Cmd+9, Next and Previous Tab, Ctrl+Tab) skip tabs hidden in a closed folder;
  - collapsing the pinned section hides folders with the pinned tabs.
- **Incognito and guest windows** have no folders, as they have no pinned section.
- **BREAKING (`ClairHost.h`):** a Space's pinned section becomes a list of items, each a pinned tab or a folder, with calls to create, rename, move, duplicate, delete and turn folders into Spaces. The pin store's format gains folders.

**Out of scope, after the MVP:**
- Change Icon…, Copy All Links and the folder's search popover.
- Share Folder…, New Nested Folder… and folders inside folders.
- Live Folders.

## Capabilities

### New Capabilities

- `tab-folders`: folders in a Space's pinned section. Creating, naming, opening and closing them, the folder row and its states, folders in a collapsed pinned section, Close This Folder, dragging tabs into and out of folders, the folder menu, Turn into Space, deleting and restoring folders, and folders after a relaunch.

### Modified Capabilities

- `sidebar`:
  - "Sidebar footer" leaves the plus button's items to a new "Plus menu" requirement, which adds New Folder. The footer requirement is at the length limit, so the menu gets its own requirement.
  - "The sidebar's own menu" is added: right-clicking the sidebar outside rows and controls, or the "New Tab" row, opens the Space header's menu.
- `spaces`:
  - "Space header" adds New Folder to the menu.
  - "Deleting a Space" removes its folders.
  - "Tab commands and folders" is added: the tab commands skip tabs hidden in closed folders.
- `pinned-tabs`:
  - "Reordering and dragging pinned tabs" refers to `tab-folders` for folders.
  - "Removing a pin" restores a pinned tab into its folder.
  - "Pinned tabs after a relaunch" keeps the tabs in their folders.

## Impact

- **`native/ClairHost.h`** changes, so the engine key changes and the engine is rebuilt.
- **Overlay:** `ClairPinStore` gains folder records in its existing format, which a store written before the change already satisfies. Pinned sections list items, folders hold pin IDs, and removals remember a pin's folder or a whole folder. `ClairSpaceTabs`' rows and next-tab rules, Space deletion and Move to Space change. Turn into Space creates a Space and moves the folder's pins and bound tabs into it.
- **`ClairUI`:** folder rows in the pinned list, the open state in user defaults, the inline name field, the New Folder dialog and the delete confirmation, Close This Folder, drag targets for folders, the new menu items, and the sidebar's own menu.
- **Runtime suite:** new coverage for folders. Views the suite drives change, so the quality checks run on the branch before merging.
- **Arc references:** probed on 2026-11-23, in `arc-reference/`.
