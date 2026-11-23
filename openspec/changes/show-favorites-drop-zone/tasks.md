# Tasks

## 1. Probe tooling

- [ ] 1.1 Let the probe's `drag` take an optional hold in seconds after its four coordinates, and describe it in `tests/probe/README.md`'s command table. Verify that the probe builds and a `drag … 1` runs.

## 2. The drop zone (D1–D4)

- [ ] 2.1 Add `FavoritesDropTrigger` (D1), the drop zone's style and square tile on `FavoritesHintBox` (D3, D4), and in `SidebarView` the trigger above the header, the zone in the favorites' place, and its closing when the mouse button is up (D2). Verify that ClairUI builds and its tests pass, and by hand with the probe's real-mouse `drag` tool, in a profile with no favorites whose box was dismissed, screenshotting mid-drag with the pointer (`screencapture -C`):
  - a Today tab dragged above the header opens the zone, and the Space moves down;
  - over the zone, its border turns solid, its contents fade, the drag shows a square tile, and the pointer shows no "+";
  - dragged back down and dropped among the Today tabs, the tab moves there and the zone goes;
  - dropped on the zone, a Today tab and a pinned tab each become the only favorite;
  - dropped on the URL field while the zone is open, a Today tab becomes the only favorite;
  - a drag that stays below the header opens nothing;
  - with the dismissable box showing, a drag above the header changes nothing, and with favorites, the grid behaves as before;
  - clicks on the top row and the URL field still work, and the top row's empty space still moves the window;
  - an incognito window's sidebar opens no zone.

## 3. Release notes and checks

- [ ] 3.1 Add a Changie fragment: with no favorites, dragging a tab above the Space header shows where favorites go. Verify that it's in the PR.
- [ ] 3.2 Run the merge gate and the quality checks on the branch (`gh workflow run quality.yml --ref <branch>`). Verify that CI and the quality checks pass.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.
