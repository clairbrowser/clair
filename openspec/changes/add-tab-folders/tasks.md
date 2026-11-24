# Tasks

Groups 1 and 2 change the engine key, so build the engine first and push docs afterwards, as `CLAUDE.md` describes. "CI" is the merge gate in `ci.yml`. D-numbers are `design.md`'s decisions, and `arc-reference/README.md` has Arc's behavior. `quality.yml` runs on the branch before merging (`gh workflow run quality.yml --ref <branch>`), since the change alters views the runtime suite drives.

Suggested order: 1.1 first, since D5 depends on it; then 1.2 and 1.3; then 2 and 3 in parallel, with group 3 against `FakeHost` while the engine builds. Group 4 is last.

## 1. Spike, contract and fakes

- [ ] 1.1 Check D5 before building on it: in a scratch branch of `ClairUI`, put an AppKit drop view registered for `SidebarDragItem.type`, with `hitTest` returning nil, inside one pinned row of the `List`, and run it with `scripts/run-local.sh` against the published engine. Verify by hand with `build/probe/bin/drag` that a Today tab dropped on that row's middle reaches the view's `performDragOperation`, and a drop near the row's edges still reaches the list's gaps. If it doesn't, switch D5 to its spring-loading fallback and update `tab-folders`' "Dragging tabs into a folder" and the design before going on.
- [ ] 1.2 Change `native/ClairHost.h` as D2 lists: the `ClairFolder` and `ClairPinnedItem` snapshots, `ClairPin.folderID`, `pinnedItemsInSpace:` and `pinnedItemsDidChange:inSpace:` in place of the pin-only ones, the folder-aware `pinTab:inFolder:atIndex:` and `movePin:toSpace:folder:atIndex:`, and the folder calls. Document each as the header documents the rest. Verify that the header compiles in `ClairHostObjCxxTests.mm` in CI.
- [ ] 1.3 Update `FakeHost` and `FakeBrowser`: folders in a Space's items, places with a folder, the folder calls, the open flag, the rows of D9 and Turn into Space. Verify with new cases in `FakeBrowserTests` in CI.

## 2. Engine

- [ ] 2.1 Add `overlay/chrome/browser/clair/clair_order_key.{h,mm}` (D1): keys between two neighbours, before the first and after the last. Verify with the runtime tests in 3.9: twenty pins dropped one after another into the same gap, and twenty at each end, keep their order after a relaunch.
- [ ] 2.2 Give profiles their IDs (D13): the Local State pref `clair.profiles`, an ID for each profile without one at start and when one is added, the entry dropped when its profile is removed and at start when its profile is gone, and `ClairProfiles::StoredIDOf` and `DirectoryOf`. Update `clair_profiles.h`'s comment, which says Clair stores nothing about a profile. Verify with the runtime tests in 3.9: after creating a profile and relaunching, `clair.profiles` in `Local State` has one entry per profile, the same IDs as before the relaunch, removing the profile drops its entry, and an entry added to `Local State` for a directory that doesn't exist is gone after the next launch.
- [ ] 2.3 Order Spaces by sort keys and save their profile's ID (D12, D13): `clair.spaces` without its `order` list, `Move` and `Create` by key, and `profile` translated on load and save. Verify with the runtime tests in 3.9 and the existing Spaces and profiles tests: reordered Spaces keep their order after a relaunch, moving one Space rewrites only its own record, a Space of a second profile still uses it after a relaunch, and `clair.spaces` names no profile directory (each read from `Local State` after quitting).
- [ ] 2.4 Rewrite `ClairPinStore`'s format as D1 lists: one record per pinned tab, favorite and folder with `kind`, `order`, and its `space`, `folder` or `profile` (the ID of D13); the per-container index; the one-level checks on write; on load, a pinned tab whose folder is missing listed at its Space's top level; a folder's move to another Space rewriting its pins' `space`; `PinContainer` with a folder; and `CreateFolder`, `RenameFolder`, `MoveItem`, `DuplicateFolder` (with icon files), `RemoveFolder` and `ChildrenOf`. Add `clair.closed_folders` with `setFolder:open:` (D3). Update `add-pinned-tabs-and-favorites`' existing calls to place pins by key. Verify with the runtime tests in 3.9 and the existing pins and favorites tests: pins, favorites and folders, their order, names and tabs, and closed folders survive a relaunch and a crash; a second profile's favorites come back in that profile; moving one item rewrites only its own record, and moving a folder to another Space its own and its pins' (read from `Local State` after quitting); and a pinned tab whose folder's record was taken out of `Local State` while Clair was quit lists at its Space's top level.
- [ ] 2.5 Bridge the D2 calls and snapshots, and send `pinnedItemsDidChange:inSpace:` for every folder change. Verify with the runtime tests in 3.9.
- [ ] 2.6 Make `ClairSpaceTabs`' rows and the next-tab rule follow D9, and Ctrl+Shift+PageUp/Down stay within a folder. Verify with the runtime tests in 3.9: Cmd+number and Opt+Cmd+Down skip a closed folder's tabs and count an open one's, and closing a tab passes over a closed folder's tabs.
- [ ] 2.7 Implement `deleteFolder:`, `closeTabsInFolder:` and the restores of D7, in the store's removals and `ExecuteTabCommand`'s `IDC_RESTORE_TAB`. Verify with the runtime tests in 3.9: a deleted folder with no open tab comes back in place; one with an open tab comes back with that page; a pin removed from a folder comes back into it, and to the end of the section once the folder is gone.
- [ ] 2.8 Implement `turnFolderIntoSpace:` (D8), `moveFolder:toSpace:atIndex:` within and across profiles, and `duplicateFolder:` (D11). Remove a Space's folders with it, and count them in the deletion's confirmation. Verify with the runtime tests in 3.9.
- [ ] 2.9 Build the engine with `gh workflow run engine.yml -f ref=<branch>`. Verify that `chromium-engine-<key>` is published and CI's engine check passes.
- [ ] 2.10 Update `docs/native-window.md`: "Pins and favorites" with folders (the store's records with their Space, folder or profile and their sort keys, the order-key helper, `clair.closed_folders`, items and places, the rows, and folder removals), "Spaces" with the Spaces' sort keys, and "Profiles" with `clair.profiles` and the IDs the stores save. Verify that every file and decision it names exists.

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
- [ ] 3.9 Add runtime tests to `tests/runtime/` (`FoldersTests.swift`) for creating through the plus menu and Tabs › New Folder…, renaming, opening and closing across a relaunch, the tab commands over closed and open folders, Delete with its confirmation and Restore Last Closed Tab, Duplicate, Move to Space, Turn into Space, Space deletion with a folder, and what 2.1 to 2.4 name: the stores' order keys and single-record moves for pins, folders and Spaces, the profile IDs in `clair.profiles`, `clair.spaces` and `clair.pins`, and a pinned tab whose folder is missing. Verify that they pass in `quality.yml` on the branch.

## 4. Release notes and checks

- [ ] 4.1 Add a Changie fragment (Added): folders in the pinned section, created from the + menu, the Space's menu or Tabs › New Folder…, which can be turned into Spaces. Verify that it's in the PR.
- [ ] 4.2 Run `openspec validate --all --strict` and the merge gate, and start `quality.yml` on the branch with the last push. Verify that CI and the quality checks pass.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.
