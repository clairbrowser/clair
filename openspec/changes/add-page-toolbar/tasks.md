# Tasks

This change touches only `ClairUI`, so the engine key doesn't change and no engine build is needed.
- **"CI"** is the merge gate in `ci.yml`: `ClairUI`'s build and unit tests, and `openspec validate --all --strict`.
- **"By hand"** means a test copy from `tests/probe/launch-clair.sh`, driven with the probe and compared with `arc-reference/` and `dia-reference/`, in Light and Dark Mode. Window drags can't be automated on this Mac (`arc-reference/README.md`), so ask the owner to check those.
- **D-numbers** are `design.md`'s decisions.

## 1. Arc reference

- [x] 1.1 Probe Arc with the toolbar on, using a public site, not `localhost`, and capture a Peek covering the toolbar, with the Peek's own toolbar. Verify: the screenshot is added to `arc-reference/` and listed in its README.
- [x] 1.2 With two extensions the owner pinned in Arc, capture the toolbar's extension tiles, their hover, both popups and two narrow windows. Verify: screenshots and measurements are in `arc-reference/`, and the specs and D4 and D6 follow them.

## 2. Preference and layout rule

- [ ] 2.1 Add `ToolbarPreference` (key `ClairShowsToolbar`, registered default on) and `PageHeaderPolicy` (D1, D8). Have each window observe the preference and expose `showsPageHeader` and `sidebarShowsControls` on `BrowserWindowModel`. Verify with new unit tests in CI: the default, a change reaching two models, and the policy for one pane and for two panes (both values).

## 3. Toolbar, card and sidebar

- [ ] 3.1 Add `ToolbarLayout` (D4). It keeps the host centred on the card. It places the site controls 21 pt from the trailing edge, with the pinned extensions and then the indicators to their left at a 36 pt pitch. When room runs out, it leaves out extensions (farthest from site controls first), then reload and the link icon, and only then truncates the host. Verify with unit tests in CI:
  - the trailing centres with two extensions and an indicator (21, 57, 93, 129 pt);
  - two extensions at Arc's 620 and 520 pt window widths: with Arc's slots the layout matches `toolbar-narrow-620.jpg` and `toolbar-narrow-520.jpg`, and with Clair's it gives what D4 records;
  - a long host in a narrow window;
  - ten pinned extensions.
- [ ] 3.2 Add `PageToolbar` and host it in `PageCardView` (D2, D4). It needs Arc's metrics, the 1 pt line over the page, reused controls with their identifiers plus `clair.toolbar`, and the host's hover background and link icon. The page, still view, infobars, DevTools and drag strip go below it, and it hides in page full screen. Verify in CI that it builds and the existing unit tests pass. By hand: the toolbar matches `arc-reference/screenshots/toolbar-on.jpg` and `toolbar-sidebar-hidden.jpg` within 1 pt, and the page's viewport starts below it.
- [x] 3.3 Strip the sidebar while `sidebarShowsControls` is false (D5): `TopRow` keeps only the window controls' room, there's no URL field, no extension row and no "More" menu, and the floating sidebar has no toggle. Verify by hand: the sidebar matches `toolbar-on.jpg` with the window controls at their place, the floating sidebar matches `dia-reference/screenshots/toolbar-sidebar-revealed.jpg`, and with the toolbar off the sidebar is unchanged from `main`.
- [ ] 3.4 Give the toolbar's background window dragging, `TitleBarArea`'s double-click and activation events, independent of `WindowDragPreference` (D4). Verify by hand, with the owner doing the drags: blank toolbar space moves the window with the preference on and off, a double-click zooms it, a press on reload that wobbles still reloads, and the page-top strip works 20 pt below the toolbar's line but not 70 pt below it.
- [x] 3.5 Lay out find and the notice popup from `PageCardView.contentTop` (D7), and keep the toolbar inside `cardScaler`, so a Peek covers it (D3). Verify by hand: Cmd+F and Shift+Cmd+C show below the toolbar, a Peek covers the shrunk, washed toolbar, and a click on the washed toolbar closes the Peek.
- [ ] 3.6 Give the Peek its own `PageToolbar` with `.peek` content (`clair.peekToolbar`) at the top of its card, with its page below it, only while the toolbar preference is on (D3, D4). Verify with a unit test in CI that `.peek` content leaves out the toggle, extensions, indicators and site controls. By hand: a Peek matches `arc-reference/screenshots/toolbar-peek.jpg`, its back acts on the Peek's page only, and with the toolbar off the Peek has no toolbar.
- [x] 3.7 Update the runtime suite for the new default layout. `NativeWindowStructureTests/testBrowserWindowLayout` checks the toolbar layout, and `WindowContentTests` the card's frames with the toolbar. A Harness helper writes `ClairShowsToolbar` before launch, as `ClairRestoreWindows` does, for a toolbar-off variant. Verify by running that test locally, which is allowed on this Mac, and they pass.
- [x] 3.8 Describe the toolbar, `PageHeaderPolicy` and where its files live in `docs/native-window.md`. Verify that the doc names files that exist.

## 4. Popups and prompts

- [ ] 4.1 Report the toolbar's control frames through `AnchorFramesKey` in a separate table, convert them to window coordinates, and give `AnchorResolver` `toolbarShown` with `.bottom` anchors (D6). Verify with `AnchorResolver` unit tests in CI: toolbar shown with the sidebar shown, hidden and revealed; page full screen falls back; and toolbar off keeps today's results.
- [ ] 4.2 Add the toolbar placement to `ExtensionPopupWindow`: top-trailing corner at the card's top edge, 40 pt in from its trailing edge, kept on screen, with the tile closing it while the popup leaves it uncovered (D6). Verify with a unit test of the placement maths in CI, including a window near the screen's edge. By hand: both pinned extensions' popups open at the same place as in `toolbar-extension-popup.jpg` and `toolbar-extension-popup-2.jpg`, and a click beside the popup closes it. (A popup covers the tiles below its top-trailing corner, as in Arc, so a click there reaches the popup.)
- [ ] 4.3 Verify by hand, with the toolbar on and the sidebar shown, hidden and revealed:
  - a location permission prompt opens below the toolbar's site controls, and Allow grants it;
  - the Site Control Center hangs below its button;
  - the back button's history menu opens below it;
  - in window full screen the prompt still attaches to the toolbar.

## 5. Turning it on and off

- [ ] 5.1 Add View › Hide Toolbar / Show Toolbar (⇧⌘D) from `ClairUI`, after Hide Sidebar, with a `validateMenuItem` title (D8). Give the toolbar, on its host and blank areas, a context menu with Copy URL and "Hide Toolbar", leaving its buttons' own menus alone. Give the sidebar URL field's menu, which shows only with the toolbar off, "Show as Toolbar". Verify with a `MainMenuTitles` unit test in CI: the item is added once, after Hide Sidebar, with ⇧⌘D, and its title follows the preference. By hand: right-clicking the toolbar's blank space shows the menu, and right-clicking back shows the history menu.
- [ ] 5.2 Add `LayoutThumbnail` and `LocationBarPicker`, and the "Location bar" row after Default browser on General (D9). Verify with unit tests in CI: the row's choices default to Toolbar and choosing writes the preference. SwiftUI doesn't build its accessibility tree in the unit-test process, so 5.3's runtime test checks the row's group and selected state. By hand: the thumbnails are sharp at Settings' size and at 3× that size, in Light and Dark Mode and with a non-blue accent colour.
- [x] 5.3 Add runtime tests in `NativeWindowTests`:
  - ⇧⌘D hides the toolbar in two open windows, the sidebar's `clair.urlField` appears, and no bookmark UI opens;
  - ⇧⌘D again brings the toolbar back;
  - choosing Sidebar in Settings › General does the same, and the row is a group labelled "Location bar" with Toolbar selected at first.

  Verify by running them locally, and they pass.
- [x] 5.4 Add a Changie fragment (`changie new`) for the toolbar, its default and the Settings row. Verify that the fragment exists under `.changes/unreleased/`.

## 6. Integration

- [ ] 6.1 Push the branch, then start CI and `gh workflow run quality.yml --ref <branch>` together on the last push. Verify that CI and the quality checks pass on the branch.
- [ ] 6.2 Check the whole feature by hand against `arc-reference/` and `dia-reference/`:
  - toolbar on and off;
  - sidebar shown, hidden and revealed;
  - a narrow window;
  - incognito;
  - a Peek;
  - DevTools docked;
  - page and window full screen;
  - Light and Dark Mode.

  Verify that every difference found is either fixed or recorded in `design.md`.

## Workflow follow-up

- After the implementation PR merges, a docs-only PR ticks any tasks its last checks verified, syncs the delta specs and archives the change, as `CLAUDE.md` describes.
