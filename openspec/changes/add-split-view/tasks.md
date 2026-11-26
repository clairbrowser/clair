# Tasks

Groups 1 and 2 change the engine key, so build the engine first and push docs afterwards, as `CLAUDE.md` describes. "CI" is the merge gate in `ci.yml`. D-numbers are `design.md`'s decisions. `arc-reference/README.md` and `dia-reference/README.md` hold the two browsers' behavior. `quality.yml` runs on the branch before merging (`gh workflow run quality.yml --ref <branch>`), since the change alters views the runtime suite drives.

Suggested order:
1. 1.1 and 2.1 first: they can change the design.
2. Then 1.2 and 1.3.
3. Then groups 2 and 3 in parallel, with group 3 working against `FakeHost` while the engine builds.
4. Group 4 last.

## 1. References, contract and fakes

- [x] 1.1 Probe Arc with `tests/probe/` for D8's open values, and add the screenshots and numbers to `arc-reference/README.md`:
  - a 60 fps recording of a tab dragged onto the page and across it: the portrait card's size, the drop zone's tint and border, and the slide's timing;
  - the split row with three-word titles at the default sidebar width;
  - closing one pane of a pinned split;
  - with a Peek open from one pane, a click on the other pane.

  Verify that the README lists each. If closing a pinned split's pane differs from the spec's "Pages of a pinned split", update the spec and D10 before 2.6.
- [ ] 1.2 Change `native/ClairHost.h` as D2 and D10 list:
  - `ClairTab.splitPartnerID`, `isLeadingPane` and `splitRatio`;
  - the split calls on `ClairBrowser`;
  - the split kind of `ClairPinnedItem`;
  - favorites as items.

  Document each as the header documents the rest. Verify that the header compiles in `ClairHostObjCxxTests.mm` in CI.
- [ ] 1.3 Update `FakeHost` and `FakeBrowser`: splits of two tabs, ratio, replace, swap, separate and close, pinned and favorited split items, and the one-row folding of D2. Verify with new cases in `FakeBrowserTests` in CI.

## 2. Engine

- [ ] 2.1 Audit Chromium's split code paths for the native window (design "Risks"):
  - `kSideBySide` checks in `TabStripModel`;
  - observers of `OnSplitTabChanged` in `chrome/browser/ui` that reach `BrowserView`;
  - what `IDC_CONTENT_CONTEXT_OPENLINKSPLITVIEW` and `NEW_SPLIT_VIEW` do in `browser_navigator.cc`.

  Turn on the feature or guard the paths as needed. Verify with an engine build (2.9) and the runtime test of 3.12 that making and closing a split doesn't crash, and record what was guarded in D1.
- [ ] 2.2 Add `engine/overlay/chrome/browser/clair/window/clair_splits.{h,mm}` (D1, D7, D12):
  - making a split from two tabs and from a new tab;
  - replacing, swapping, separating and closing a split;
  - the ratio;
  - keeping a split's tabs adjacent in `ClairSpaceTabs` and moving them as one, within a window, to another window and to another Space;
  - one row for the tab commands;
  - activating the remaining tab when a pane closes.

  Verify with the runtime tests in 3.12.
- [ ] 2.3 Focus and visibility (D4, D5): activate the partner on `OnWebContentsFocused`, and mark the partner visible in `ActiveTabChanged`. Verify with the runtime tests in 3.12:
  - both panes report `visible`, and both `hidden` after another tab is selected;
  - clicking in the other pane makes it the active tab.
- [ ] 2.4 Add `engine/patches/clair/split-on-option-click.patch` (D6) for Blink's `navigation_policy.cc` and `ui/base/window_open_disposition_utils.cc`, with a header comment and its `series` entry. Handle `NEW_SPLIT_VIEW` in `ClairSplits::OpenURL` (single page, split pane, Peek). Stop removing Open Link in Split View from the page's context menu. Verify:
  - the patch check applies the series;
  - the runtime tests in 3.12 cover Option+click on a single page, in each pane of a split (no new tab, Back returns), from a favorite (no Peek), inside a Peek, and from the context menu;
  - no download starts in any of these.
- [ ] 2.5 Add the split record to `ClairPinStore` (D10): split records with their place and ratio, pins that name their split and index, and splits in folders, still one level deep. Add pinning, unpinning, favoriting and separating a split, Remove Pin, Remove Favorite, Restore Last Closed Tab, and Move to Space. Verify with the runtime tests in 3.12 that pinned and favorited splits, their order, pages and ratio survive a relaunch, and that Separate leaves two pins in place (each read from `Local State` after quitting).
- [ ] 2.6 Bind pinned and favorited splits (D10): selecting one opens its unopened pages as a split with its ratio; closing one pane takes its pin out of the item, leaving the other pin in its place, and Restore Last Closed Tab brings the split back; a Today split with a pin-bound tab keeps the binding. Verify with the runtime tests in 3.12.
- [ ] 2.7 Peek's Open in Split View (D11): expand and split, and no button while the parent has a partner. Verify with the runtime tests in 3.12.
- [ ] 2.8 Bridge the D2 calls and snapshots, and the menu bar items of D9: Tabs › Split with Tab ›, and View › Add Split View (⌃⇧=), Close Split Pane (⌃⇧−) and Separate Tabs, with Add Split View showing "Cannot Add New Pane" while split. Verify with the runtime tests in 3.12.
- [ ] 2.9 Build the engine with `gh workflow run engine.yml -f ref=<branch>`. Verify that `chromium-engine-<key>` is published and CI's engine check passes.
- [ ] 2.10 Update `docs/native-window.md`:
  - a "Split view" section: `ClairSplits` over Chromium's split collections, focus and visibility, the Option+click patch, and splits across windows and Spaces;
  - "Pins and favorites": the split record.

  Verify that every file and decision it names exists.

## 3. ClairUI

- [ ] 3.1 Fold split tabs into one row in `TabListLogic` and the window model, and set `paneCount` from the active tab's partner (D2, D3). Verify with `ClairUI` unit tests in CI: rows for a Today split, a pinned split, a favorited split, and a Today split holding a pin-bound tab; and `PageHeaderPolicy` with the toolbar off while split.
- [ ] 3.2 Lay out the panes (D3): two `PageCardView`s with their own cards, the focus ring, the 10 pt gap, and the find field, loading indicator, Peek and toasts against the right area. Verify with unit tests in CI for the pane frames at a few widths and ratios, and by hand in 3.11.
- [ ] 3.3 Add `SplitDivider` (D3): grabber, resize cursor, live widths, the page minimum of about 210 pt (and the ratio held when the area is too narrow), the snap to equal panes within 20 pt of the centre, and `setSplitRatio` when the drag ends. Verify with unit tests in CI for the clamp, the narrow case, the snap and the ratio, and by hand in 3.11.
- [ ] 3.4 Add the pane headers and the split button (D9):
  - `PageHeaderContent.pane(leading:focused:)`, with × at the trailing slot;
  - the split button in the trailing slot of the toolbar, and before × in a pane header, with site controls, extensions and indicators one slot further left;
  - no button on a Peek's toolbar or while the toolbar is off and the page isn't split;
  - the other pane's split button, site controls, extensions and indicators shown while the pointer is over that pane, and a click on one focusing the pane first.

  Verify with unit tests in CI for each variant's controls and `ToolbarArrangement`'s slots, the narrow-window cases included.
- [ ] 3.5 Add the split button's two menus and Split with Tab › in the Today, pinned and favorite menus (D9), including Add Split View and New Tab making a new-tab-page pane with the command bar centred on it, and Esc leaving that page. Verify with unit tests in CI for each menu's items in order, the disabled Move Left and Move Right, the Today-only list in the sidebar's order with favicons and without tabs already in a split, the tab a New Tab split splits from each menu, Split with Tab disabled on a pinned tab or favorite already in a split, and the menu bar item disabled while split.
- [ ] 3.6 Add the link status texts of D13a: "Open <URL> in Split View" with Option, "Open <URL> in Peek" with Shift while the Peek preference is on, the URL alone in a Peek, updates as the keys change, and the capsule in the hovered link's pane. Verify with unit tests in CI for the text from each modifier, preference and Peek case, and by hand in 3.11.
- [ ] 3.7 Centre the command bar on the focused pane while split, clamped inside the window (D13b). Verify with unit tests in CI for its frame over each pane, a narrow pane, and a single page, and by hand in 3.11.
- [ ] 3.8 Add the split row (D2, D13): chips with favicon, title or custom name, the divider while not selected and pills while selected; × in Today, − and × in the pinned section; the click that shows the split; the row's menu with Separate Tabs and its omitted items; and the row dragged as one, into and out of folders too. Verify with unit tests in CI for the row's states, buttons and menu, and `PinsLogic.listDrop`'s gaps for a split row around open and closed folders.
- [ ] 3.9 Add the favorite split tile: the segments with icons, the divider line, and the white or light grey selected tile with the blended ring. Verify with unit tests in CI for the grid with a split tile, and by comparing screenshots with `arc-reference/screenshots/favorite-split*.jpg`.
- [ ] 3.10 Add dragging onto the page (D8): the portrait drag image, the half or pane drop zone and slide with 1.1's metrics, no zone for a split row or the tab already shown, and the drop calls. Verify with unit tests in CI for which zone a point picks, single and split, and the side passed to `splitTab:withTab:side:`, and by hand in 3.11.
- [ ] 3.11 Check the flow by hand against `arc-reference/` and `dia-reference/` with `tests/probe/`, using `build/probe/bin/drag` for drags. Verify that each of these matches the spec, and record anything that differs from Arc or Dia in the design:
  - a tab, pinned tab and favorite dragged onto each half of a single page, and onto each pane of a split;
  - Option+click in a single page, in each pane, from a pinned tab and inside a Peek;
  - the split button's place in the toolbar and each pane, both menus, and Move Left and Move Right;
  - Split with Tab from the menu bar and each tab menu, and Add Split View and New Tab, with a page chosen and with Esc;
  - closing a pane with ×, Cmd+W and ⌃⇧−, and Separate Tabs;
  - the divider and its limit: each page stops at about 210 pt, checked with DevTools' viewport width (no runtime test), and a release near the centre snapping to equal panes;
  - the command bar from Cmd+L, Cmd+T and a pane's host in each pane;
  - the link status with Option and Shift held, pressed and released over a link, in a split's panes and in a Peek;
  - the other pane's controls on hover;
  - the split row selected and not, its × and menu, and Ctrl+Tab over it;
  - a Peek from each pane, with only its parent pane washed out, and Open in Split View;
  - pinning, favoriting, a pinned split dragged into and out of a folder, Close and Keep Pinned, one pane of a pinned split closed, separating, unpinning;
  - the toolbar off while split;
  - Light and Dark Mode.
- [ ] 3.12 Add runtime tests to `tests/runtime/` (`SplitViewTests.swift`) for:
  - making a split from a tab menu, the menu bar and Option+click;
  - Option+click in a split (no new tab, Back returns), from a favorite, inside a Peek, and from the context menu, with no download;
  - both pages visible, and focus by clicking the other pane;
  - Move Right, Separate Tabs, and closing a pane with Cmd+W;
  - "Cannot Add New Pane";
  - the split row as one stop for Ctrl+Tab;
  - Move to Space and showing the split in another window;
  - closing the row and Restore Last Closed Tab;
  - a split and its ratio after a relaunch and Reopen Closed Window;
  - pinning, favoriting, separating and relaunching a pinned split, one in a folder included;
  - one pane of a pinned split closed, and restored with Restore Last Closed Tab;
  - Open in Split View from a Peek, and its absence on a Peek in a split.

  Verify that they pass in `quality.yml` on the branch.

## 4. Release notes and checks

- [ ] 4.1 Add a Changie fragment (Added): split view, two tabs side by side, made by dragging a tab onto the page, Option+click or the split button, shown as one row in the sidebar, and pinnable and favoritable as one item. Verify that it's in the PR.
- [ ] 4.2 Run `openspec validate --all --strict` and the merge gate, and start `quality.yml` on the branch with the last push. Verify that CI and the quality checks pass.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.
- Then delete the probe recordings in `build/probe/split/` and any others made for this change.
