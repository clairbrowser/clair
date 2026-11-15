# Tasks

Groups 1 and 2 change the engine key, so build the engine first and push docs afterwards, as `CLAUDE.md` describes. "CI" is the merge gate in `ci.yml`. "By hand" means the owner launches a test build of the branch; behaviour compared with Arc is checked there with `tests/probe/`. `quality.yml` runs on the branch before merging (`gh workflow run quality.yml --ref <branch>`), since the change alters views the runtime suite drives. D-numbers are `design.md`'s decisions; its "Arc reference" section has Arc's wording, measurements and colours.

Suggested order: 1, then 2 and 3 in parallel. Group 3 can start in `ClairUI` against `FakeHost` and `FakeBrowser` as soon as 1 is done, while the engine builds. Group 4 is last.

Read `design.md` in full before starting. Verify every Chromium call it names against the engine workspace's source before using it, and update the design if one differs.

## 1. Contract and fakes

- [ ] 1.1 Change `native/ClairHost.h` as D10 lists:
  - add the `ClairPin` snapshot and `ClairTab.pinID` and `ClairTab.name`;
  - add `pinsInSpace:`, `favoritesOfProfile:`, the D5 calls, `removePin:`, `returnToPinnedURL:`, `replacePinnedURLWithCurrent:`, `setPinnedURL:forPin:`, `setName:forTab:`, `setName:forPin:` and `clearTodayInSpace:` to the host, and `openPin:` and `unpin:toIndex:` to `ClairBrowser`;
  - add the observer's two calls and `ClairWindow.opensPeekForOtherSites`;
  - narrow `tabsInSpace:` to Today tabs.

  Document each as the header documents the rest. Verify that the header compiles in `ClairHostObjCxxTests.mm` in CI.
- [ ] 1.2 Update `FakeHost` and `FakeBrowser` to pins:
  - pin records per Space and per profile, binding and unbinding tabs, and the D5 moves with names carried between record and tab;
  - Back to Pinned URL and the URL edits;
  - D4's next-tab rule over pinned and Today rows, skipping unbound pins and counting a favorite as came-from;
  - Clear Today.

  Verify with new cases in `FakeBrowserTests` and `SharedTabsTests` in CI.

## 2. Engine

- [ ] 2.1 Add `overlay/chrome/browser/clair/clair_pin_store.{h,mm}` (D1): the `clair.pins` Local State pref and its registration; create, move, rename, edit and remove records; icon files written on a background sequence and deleted with their pin; orphaned icon files removed at start-up; the in-memory list of the last 25 removed records (D3); observers. Add the sources to the `BUILD.gn` hunk. Verify with the runtime tests in 3.12: pins and favorites survive a relaunch, with their pages open or not as they were, and a crash.
- [ ] 2.2 Bind tabs to pins in `clair_space_tabs.{h,mm}` (D2): the pin's user data; bound pinned tabs listed with their pins, outside the Today list; bound favorites in a per-profile list; the shown-Space invariant extended to favorites; title and icon following the bound tab only at its pinned URL (the entry's URL or original request URL, without the fragment); names in the record or in `clair_name`. Verify with the runtime tests in 3.12: a pinned tab's title stays at the pinned page's while it's navigated away, and a favorite opened in one Space shows the same page in another.
- [ ] 2.3 Add `clair_pin` and `clair_name` to `clair_space_session.{h,mm}`, which `space-session.patch`'s three call sites already carry whole, and restore bindings (D3): a restored tab binds to its unbound pin, and otherwise joins its Space's Today list with its name; new tab pages are dropped unbound. Verify with the runtime tests in 3.12 for a relaunch with restoring windows off and on.
- [ ] 2.4 Always restore tabs (D12): add `clair::ApplyStartupPref` and its call at the end of `SessionStartupPref::GetStartupPref(const PrefService*)` in a new `patches/clair/always-restore.patch` listed in `patches/series`; set `onStartup: false` in `native-window-hook.patch`'s `page_visibility.ts` hunk; remove the `kRestoreOnStartup` default from `RegisterProfilePrefOverrides` and update its comment in `clair_window_hooks.h`. Verify that the patch check applies the patches, that the engine's headless smoke test still finishes, and with the runtime tests in 3.12: `chrome://settings` has no "On startup" section, and tabs come back after `session.restore_on_startup` is set to 5 (the New Tab page) through `chrome.settingsPrivate`.
- [ ] 2.5 Implement opening, closing, tab commands and Clear Today (D4): `openPin:inBrowser:` with takes and stills; closes that unbind and keep the record; the next-tab rule over the new rows; Cmd+1 to 9, Ctrl+Tab and Next/Previous Tab over pinned then Today rows, opening an unbound pin; Ctrl+Shift+PageUp/Down within a section; Clear Today through the close flow. Verify with the runtime tests in 3.12.
- [ ] 2.6 Implement pinning, unpinning and moves (D5), including Move to Space of a pinned tab within and across profiles, and keeping pins when a Space's profile changes. Verify with the runtime tests in 3.12.
- [ ] 2.7 Handle `IDC_RESTORE_TAB` for removed pins in the native window's `ExecuteTabCommand` and menu validation (D3). Verify with the runtime tests in 3.12: × on an unbound pinned tab and on an open one, then Restore Last Closed Tab, puts each back pinned in place.
- [ ] 2.8 Implement Back to Pinned URL, Replace Pinned URL with Current and `setPinnedURL:forPin:` (D6), and `isAtPinnedURL`. Verify with the runtime tests in 3.12: Back to Pinned URL adds a history entry that Back undoes.
- [ ] 2.9 Add `overlay/chrome/browser/clair/window/clair_pinned_link_throttle.{h,mm}` and its hook in `chrome_content_browser_client_navigation_throttles.cc`, in a new `patches/clair/pinned-link-peek.patch` listed in `patches/series` (D7). Open command-bar URLs from a favorite to another site in a new Today tab. Expand a bound tab's Peek at the top of Today. Verify that the patch check applies it, and with the runtime tests in 3.12: a cross-site link click from a favorite and from a pinned tab opens a Peek; a same-site link, a Today tab's link, a Cmd-click, a scripted navigation without a gesture and the toggle off don't.
- [ ] 2.10 Use the custom name in `ClairBrowserWindow::UpdateTitleBar` and update the title when a name changes (D8). Remove the pins and icons of a deleted Space or removed profile, and count pinned tabs in the Space deletion's confirmation (D9). Verify with the runtime tests in 3.12: the window's title is the name, and a deleted Space's pins are gone after a relaunch.
- [ ] 2.11 Finish the bridge (D10, D11): the new host and browser calls and snapshots, the observer's calls, `opensPeekForOtherSites`. `ClairUI`'s `PinsMenu` inserts Pin Tab (Cmd+D), Back to Pinned URL, Close and Keep Pinned, Clear Today (Shift+Cmd+K) and View › Collapse Pinned Tabs, and hides Chromium's own Pin Tab; Cmd+D is free since the bookmark item's key equivalent is cleared. Verify with the runtime tests in 3.12: the menu items, their shortcuts and their enabled states.
- [ ] 2.12 Build the engine with `gh workflow run engine.yml -f ref=<branch>`. Verify that `chromium-engine-<key>` is published and CI's engine check passes.
- [ ] 2.13 Update `docs/native-window.md` with a "Pins and favorites" section (the store, binding, the session tags, restore and removed pins, the throttle, the title) and its table of files, and correct the "Spaces" section's tab lists, next-tab rule and "Sessions" entry, which still describes the `session.restore_on_startup` default (D12). Verify that every file and decision it names exists.

## 3. ClairUI

- [ ] 3.1 Carry pins and favorites in `SpacesModel` and `BrowserWindowModel` (D11), and partition rows in `TabListLogic`: pinned rows, then Today rows, with favorites apart. Verify with `ClairUI` unit tests in CI for the sections, Cmd+number counting and the came-from rule's inputs.
- [ ] 3.2 Add `FavoritesLayout.swift` and `FavoritesGrid` (D11): the layout function, tiles with idle, hover and selected states, the ring's colour from the icon, the Peek badge, and the empty box, recorded as done in `ClairFavoritesHintDone` once dismissed or once the profile gets a favorite. Verify with unit tests in CI for the layout of 1 to 9 favorites at the default width against `design.md`'s Arc table, and that the box never returns after either.
- [ ] 3.3 Add the pinned section: rows with − or × by selection and their tooltips, the "/" and favicon button with "Back to Pinned URL" when navigated away, the header's chevron and the collapse (keeping the active row) stored in `ClairCollapsedPinnedSpaces`, and the divider with Clear. Verify with unit tests in CI for the button choice, the navigated title, the collapsed rows and when the divider and Clear show.
- [ ] 3.4 Add the menus (D11): the Today, pinned and favorite context menus as the specs list them, in order; the main menu items' actions and validation on the key `ClairWindow`. Verify with unit tests in CI for each menu's items and each item's enabled state, including incognito.
- [ ] 3.5 Add renaming (D11): the in-place field for Today and pinned rows (caret on double-click, select-all from Rename…, Return, Esc, focus loss, the title placeholder, an empty name clearing); the "Rename Tab…" dialog for favorites; the tooltips of `tab-names`. Verify with unit tests in CI for commit, cancel and clear, and for the tooltip text with and without a name.
- [ ] 3.6 Add the Edit Pinned URL dialog (D6, D11) with Arc's wording, Save enabled only for a valid URL. Verify with unit tests in CI for Save's state and the saved URL.
- [ ] 3.7 Add drag and drop between Today, the pinned section and favorites, and reordering within each, with the grid making room (D11). Verify with unit tests in CI for the drop index each section computes, and by hand with `build/probe/bin/drag` in 3.10.
- [ ] 3.8 Add the Links toggle "Open a Peek window when clicking on links to other sites" with its note, bound to `ClairPeekForOtherSites`, on when unset. Verify with unit tests in CI for the default and a write.
- [ ] 3.9 Tune the colours and sizes against Arc in Light and Dark Mode (D11, "Arc reference"): rows, divider, tiles, hover and selected states, the rename field. Verify by comparing screenshots of Clair's test copy and Arc side by side with `tests/probe/` in both appearances.
- [ ] 3.10 Check the flow by hand against Arc with `tests/probe/` in both appearances:
  - pinning with Cmd+D and by drag, unpinning, and the collapse;
  - − and ×, and Restore Last Closed Tab after ×;
  - Back to Pinned URL and Edit Pinned URL;
  - renaming in place and the favorite's dialog;
  - a favorite's Peek and its badge;
  - Clear.

  Also check:
  - **Peeks:** whether Arc peeks a link between subdomains of one site (D7);
  - **Back to Pinned URL:** how Arc shows a pinned tab whose URL redirects, or whose page rewrites its path (Risks);
  - **Rename:** whether clicking elsewhere keeps or discards an edit in progress;
  - **Collapse:** whether a collapsed pinned section shows collapsed in Arc's other windows, and after a relaunch with restoring windows off and on;
  - **Empty favorites:** whether Arc shows the "Drag to add Favorites" box for a newly created profile.

  Update the specs and design where Arc differs. Verify by the owner accepting the comparison.
- [ ] 3.11 Update the `ClairUI` docs that describe the sidebar's sections and rows (`docs/native-window.md`'s sidebar part, if 2.12 doesn't cover it). Verify that the views they name exist.
- [ ] 3.12 Add runtime tests to `tests/runtime/` (`PinsTests.swift`), using the local pages server with a page that links within its site and to another (`localhost` and `127.0.0.1`):
  - **Pinning:** Cmd+D pins at the bottom and unpins to the top of Today, with the page kept; Pin to Favorites; the menu items' titles and enabled states.
  - **Closing:**
    - − and Cmd+W keep the pin and select the came-from tab;
    - × removes the pin, and Restore Last Closed Tab brings it back, for a pin with and without a page;
    - Clear Today closes Today tabs only, and Restore Last Closed Tab brings the last one back.
  - **Rows and commands:** Cmd+number over pinned and Today rows opening an unbound pin; the next tab after a close passing over unbound pins.
  - **Back to Pinned URL:** a link to another query leaves the row plain; after a same-site link it loads the pinned URL, and Back returns; Replace with Current; Edit Pinned URL.
  - **Peek:**
    - a cross-site link from a favorite and from a pinned tab opens a Peek, and so does a link to a subdomain;
    - a same-site link, a Today tab's link, a Cmd-click and the toggle off don't;
    - expanding a pinned tab's Peek puts the tab at the top of Today.
  - **Favorites:** the same favorite tab across two Spaces of a profile; another profile's Space shows its own; a URL to another site entered from a favorite opens a Today tab.
  - **Names:**
    - Rename… then Return names the row and the window;
    - Esc cancels, and an empty name restores the title;
    - the name survives navigation, unpinning and a relaunch with tabs restored.
  - **Relaunch:**
    - pins and favorites come back, those that were open open again and the others not, and an open pinned tab comes back navigated away if it was;
    - tabs come back after `session.restore_on_startup` is set to the New Tab page, and `chrome://settings` has no "On startup" section; this replaces `SpacesTests.testOnStartupSettingStillApplies`;
    - a deleted Space's pins and a removed profile's favorites are gone.
  - **Incognito:** no pinned section or favorites, and Cmd+D does nothing.

  Verify with a `quality.yml` run on the branch.

## 4. Release notes and integration

- [ ] 4.1 Add Changie fragments (`changie new`): Added for pinned tabs, for favorites, for renaming tabs, and for Peeks on links to other sites with its setting; Changed for Cmd+D pinning tabs, and for tabs always coming back at launch with no "On startup" section in `chrome://settings`. Verify that they're in the PR.
- [ ] 4.2 Run `openspec validate --all --strict` and the merge gate, and start `quality.yml` on the branch with the last push. Verify that CI and the quality checks pass.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.
- After archiving, delete `build/probe/shots/arc-pins/` and the related recordings in `build/probe/rec/`.
