# Tasks

Groups 1 and 2 change the engine key, so build the engine first and push docs afterwards, as `CLAUDE.md` describes. "CI" is the merge gate in `ci.yml`. D-numbers are `design.md`'s decisions, and `arc-reference/README.md` has Arc's behavior. `quality.yml` runs on the branch before merging (`gh workflow run quality.yml --ref <branch>`), since the change alters views the runtime suite drives.

Suggested order: 1.1 first, since D5 depends on it; then 1.2 and 1.3; then 2 and 3 in parallel, with group 3 against `FakeHost` while the engine builds. Group 4 is last.

## 1. Spike, contract and fakes

- [ ] 1.1 Check D5 before building on it: in a scratch branch of `ClairUI`, put an AppKit drop view registered for `SidebarDragItem.type`, with `hitTest` returning nil, inside one pinned row of the `List`, and run it with `scripts/run-local.sh` against the published engine. Verify by hand with `build/probe/bin/drag` that a Today tab dropped on that row's middle reaches the view's `performDragOperation`, and a drop near the row's edges still reaches the list's gaps. If it doesn't, switch D5 to its spring-loading fallback and update `tab-folders`' "Dragging tabs into a folder" and the design before going on.
- [ ] 1.2 Change `native/ClairHost.h` as D2 lists: the `ClairFolder` and `ClairPinnedItem` snapshots, `ClairPin.folderID`, `pinnedItemsInSpace:` and `pinnedItemsDidChange:inSpace:` in place of the pin-only ones, the folder-aware `pinTab:inFolder:atIndex:` and `movePin:toSpace:folder:atIndex:`, and the folder calls. Document each as the header documents the rest. Verify that the header compiles in `ClairHostObjCxxTests.mm` in CI.
- [ ] 1.3 Update `FakeHost` and `FakeBrowser`: folders in a Space's items, places with a folder, the folder calls, the open flag, the rows of D9 and Turn into Space. Verify with new cases in `FakeBrowserTests` in CI.

## 2. Engine

- [ ] 2.1 Extend `ClairPinStore` (D1): format version 2 with `folders` and item lists, version 1 loaded as 2, `PinContainer` with a folder, and `CreateFolder`, `RenameFolder`, `SetFolderOpen`, `MoveItem`, `DuplicateFolder` (with icon files), `RemoveFolder` and `FoldersIn`. Verify with the runtime tests in 3.9: folders, their order, names, tabs and open state survive a relaunch and a crash, and a version 1 store from before the change loads with its pins.
- [ ] 2.2 Bridge the D2 calls and snapshots, and send `pinnedItemsDidChange:inSpace:` for every folder change. Verify with the runtime tests in 3.9.
- [ ] 2.3 Make `ClairSpaceTabs`' rows and the next-tab rule follow D9, and Ctrl+Shift+PageUp/Down stay within a folder. Verify with the runtime tests in 3.9: Cmd+number and Opt+Cmd+Down skip a closed folder's tabs and count an open one's, and closing a tab passes over a closed folder's tabs.
- [ ] 2.4 Implement `deleteFolder:`, `closeTabsInFolder:` and the restores of D7, in the store's removals and `ExecuteTabCommand`'s `IDC_RESTORE_TAB`. Verify with the runtime tests in 3.9: a deleted folder with no open tab comes back in place; one with an open tab comes back with that page; a pin removed from a folder comes back into it, and to the end of the section once the folder is gone.
- [ ] 2.5 Implement `turnFolderIntoSpace:` (D8), `moveFolder:toSpace:atIndex:` within and across profiles, and `duplicateFolder:` (D11). Remove a Space's folders with it, and count them in the deletion's confirmation. Verify with the runtime tests in 3.9.
- [ ] 2.6 Build the engine with `gh workflow run engine.yml -f ref=<branch>`. Verify that `chromium-engine-<key>` is published and CI's engine check passes.
- [ ] 2.7 Update `docs/native-window.md`'s "Pins and favorites" section with folders: the store's version 2 format, items and places, the open flag, the rows, and folder removals. Verify that every file and decision it names exists.

## 3. ClairUI

- [ ] 3.1 Carry pinned items in `SpacesModel` and `BrowserWindowModel`, and flatten them into rows with depths and places, open and closed, collapsed or not (D4). Verify with `ClairUI` unit tests in CI for the rows of an open folder, a closed one with and without its selected tab, an empty one, and a collapsed section.
- [ ] 3.2 Add the folder row (D4): the icon's three states, the name, the hover pill, a click calling `setFolder:open:`, and the − button with "Close This Folder" while a tab is bound, calling `closeTabsInFolder:`. Verify with unit tests in CI for the icon state and when − shows.
- [ ] 3.3 Extend `PinsLogic.listDrop` with the gaps of D4, refuse a folder anywhere but the top level, and add the row drop view of D5 (or its fallback). Verify with unit tests in CI for every gap around an open, closed and empty folder, and by hand in 3.8.
- [ ] 3.4 Add creating and naming (D6): New Folder in the plus menu and `SpacesLogic.headerMenu`, the edit mode for the new folder and for Rename…, Tabs › New Folder… in `PinsMenu` with its validation, and the New Folder dialog. Verify with unit tests in CI for the two menus' items in order, the plus menu in incognito, commit, Esc and an empty name, Create's enabled state, and the menu item disabled in private windows.
- [ ] 3.5 Add the folder menu and its actions: Turn into Space (showing the new Space), Rename…, Duplicate, Move to Space with "Folder was moved to", and Delete with the confirmation of D7. Verify with unit tests in CI for the menu's items with one and two Spaces, and the dialog's wording and buttons.
- [ ] 3.6 Add the sidebar's own menu (D10) behind the list and on the "New Tab" row, absent in private windows. Verify with unit tests in CI that it offers the header's items, and by hand in 3.8.
- [ ] 3.7 Tune the folder row against Arc in Light and Dark Mode: icon, name weight and colour, indent and hover pill. Verify by comparing screenshots of Clair's test copy and Arc side by side with `tests/probe/`.
- [ ] 3.8 Check the flow by hand against `arc-reference/` with `tests/probe/`, using `build/probe/bin/drag` for drags:
  - New Folder from the plus menu, the header menu, the empty sidebar and the "New Tab" row, and Tabs › New Folder…;
  - opening and closing, the selected tab under a closed folder, and the "•••" icon;
  - Close This Folder;
  - drops on an open and a closed folder's row, between its tabs, below its last tab, and a tab dragged out above it and into Today;
  - reordering a folder, and a folder dropped below the divider;
  - Rename…, Duplicate, Move to Space, Turn into Space, and Delete with and without tabs, then Restore Last Closed Tab;
  - an incognito window: no New Folder and no sidebar menu.

  Verify that each matches the spec, and record anything that differs from Arc in the design.
- [ ] 3.9 Add runtime tests to `tests/runtime/` (`FoldersTests.swift`) for creating through the plus menu and Tabs › New Folder…, renaming, opening and closing across a relaunch, the tab commands over closed and open folders, Delete with its confirmation and Restore Last Closed Tab, Duplicate, Move to Space, Turn into Space, and Space deletion with a folder. Verify that they pass in `quality.yml` on the branch.

## 4. Release notes and checks

- [ ] 4.1 Add a Changie fragment (Added): folders in the pinned section, created from the + menu, the Space's menu or Tabs › New Folder…, which can be turned into Spaces. Verify that it's in the PR.
- [ ] 4.2 Run `openspec validate --all --strict` and the merge gate, and start `quality.yml` on the branch with the last push. Verify that CI and the quality checks pass.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.
