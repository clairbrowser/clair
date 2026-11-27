# Tasks

Groups 1 and 2 change the engine key, so build the engine first and push docs afterwards, as `CLAUDE.md` describes. "CI" is the merge gate in `ci.yml`. D-numbers are `design.md`'s decisions. `arc-reference/README.md` holds Arc's behavior and measurements. `quality.yml` runs on the branch before merging (`gh workflow run quality.yml --ref <branch>`), since the change alters menus and views the runtime suite drives.

Suggested order:
1. Group 1.
2. Then groups 2 and 3 in parallel, with group 3 working against `FakeHost` while the engine builds.
3. Then groups 4 to 6.

## 1. Contract and fakes

- [ ] 1.1 Add to `ClairBrowser` in `native/ClairHost.h`, documented as the header documents the rest:
  - `-requestPreviewOfTab:size:completion:` (D4);
  - `-showTab:`, which shows a tab of any of the window's Spaces, switching Space, and swapping windows for another profile's Space as `-[ClairHost showSpace:]` does.

  Verify that the header compiles in `ClairHostObjCxxTests.mm` in CI.
- [ ] 1.2 Update `FakeBrowser` and `FakeHost`:
  - previews per tab (set by tests, nil by default);
  - `showTab` across Spaces, which posts `shownSpaceDidChange` before `activeTabDidChange`.

  Verify with new cases in `FakeBrowserTests` in CI.

## 2. Engine

- [ ] 2.1 Delete Chromium's Tab menu in `clair_window_hooks.mm`'s main-menu setup (D5), before any window becomes main. Verify in the engine build (2.5) that Clair starts with no Tab menu, and that switching windows and profiles doesn't crash: `AppController`'s `TabMenuBridge` and `onVerticalTabStripModeChanged` get nil.
- [ ] 2.2 Remove the engine's handling of Tab-menu-only commands (D5a):
  - in `ExecuteTabCommand`: `IDC_CYCLE_TO_NEXT_TAB`, `IDC_CYCLE_TO_PREV_TAB`, `IDC_WINDOW_CLOSE_TABS_TO_RIGHT` and `IDC_WINDOW_CLOSE_OTHER_TABS`;
  - in `ClairPeeks::ExecuteCommand`: `IDC_DUPLICATE_TAB` and `IDC_MOVE_TAB_TO_NEW_WINDOW`;
  - the same four commands in the native window's modal-dialog validation list;
  - `IDC_TAB_SEARCH`, `IDC_WINDOW_GROUP_TAB`, `IDC_GROUP_TARGET_TAB` and `IDC_NEW_SPLIT_TAB` from `ClairIsRemovedCommand`.

  Before each, grep the Chromium tree (`/Volumes/My Shared Files/clair/build/src`) for other senders of the command, and keep any case that has one, noting why in D5a. Verify that the engine compiles (2.5), and that Opt+Cmd+Down and Up, Cmd+1…9 and Close Tabs Below still work in the runtime suite (5.2).
- [ ] 2.3 Add `ClairTabPreview` (`engine/overlay/chrome/browser/clair/window/`), as D4 describes:
  - on each active-tab change, `CopyPage` copies the outgoing row's page (each pane of a split), scales it to 2× the card width and cuts it to 3:2 from the top;
  - the copy is kept as `WebContents` user data and replaced on each hide;
  - `-requestPreviewOfTab:size:completion:` returns it, or copies the shown tab live, or nil.

  Verify in the hand check (6.1) that a background tab's card shows its page as left, and the shown tab's card its live page.
- [ ] 2.4 Implement `-showTab:` in `clair_browser_bridge.mm`:
  - a tab of the shown Space activates as `-activateTab:` does, taking it from another window;
  - a tab of another Space of the same profile shows that Space with the tab active;
  - a tab of another profile's Space goes through the profile swap of `ShowSpace`, and the incoming window activates the tab.

  Verify with the runtime test of 5.3.
- [ ] 2.5 Push the branch and build the engine (`gh workflow run engine.yml -f ref=<branch>`). Verify that `chromium-engine-<key>` is published.

## 3. ClairUI

- [ ] 3.1 Add `RecentTabs` (D1): the front-on-show rule, splits and Peeks as their row, the still's placeholder left out, pruning on tab and pin changes, at most 16 entries. The incoming window takes the list on a profile swap. Verify with unit tests in CI for each scenario of `tab-switcher` "Recent tabs".
- [ ] 3.2 Add `SwitcherState` (D2, D3): open forward or back, step and wrap, commit, cancel, no-op with fewer than two entries, at most five cards, and the 100 ms delay before the panel shows (at once on a second Tab, never on a commit before it). Verify with unit tests in CI, with an injected clock, for the scenarios of "Opening the switcher", "Moving the selection", "Choosing a tab", "Cancelling the switcher" and "A quick Ctrl+Tab shows no panel".
- [ ] 3.3 Add `TabSwitcher`:
  - the local key and mouse monitors of D2, acting only in a normal browser window with no dialog or sheet;
  - commit through `showTab`;
  - cancel on resign-key and when the shown tab closes.

  Verify with unit tests in CI that feed it synthetic `NSEvent`s: Ctrl+Tab is swallowed, other keys pass while it's closed, and releasing Ctrl commits.
- [ ] 3.4 Add the switcher panel (D3): the child `NSPanel`, the cards with previews (a split's composed in pane order), favicons and titles or custom names, the accent highlight, centring kept on screen, no animation, and the identifiers of D7. Verify with a unit test of the layout maths (panel size for one to five cards, the clamp to the screen's visible frame) in CI, and by the hand check (6.1).
- [ ] 3.5 Add `TabsMenu` (D5), before the Window menu: Pin Tab, the new Pin to Favorites, New Folder…, Next and Previous Tab through `commandDispatch:`, Split with Tab › (moved from `SplitMenu`), Move to Space ›, and Clear Unpinned Tabs, with the enabled rules of `tabs-menu`. Verify with unit tests in CI for the items, their order, titles, shortcuts and enabled states, including incognito and a favorite.
- [ ] 3.6 Remove ClairUI's customizations of Chromium's Tab menu (D5a):
  - `PinsMenu` keeps only View › Collapse Pinned Tabs, without `tabMenuTag` or the hiding of Chromium's pin items;
  - `MainMenuCommand.backToPinnedURL` and `.closeKeepingPin` go;
  - `SplitMenu` keeps only its View items;
  - `SplitTests` and `FoldersTests` drop their fake Tab menus.

  Verify with `grep -rn "tabMenuTag\|35013\|35051" native/` finding nothing, and the unit tests passing in CI.
- [ ] 3.7 Rebuild `PinsLogic`'s menus as groups (D6): the Today, pinned and favorite menus, Close Tab on an open pinned tab (as Close and Keep Pinned), and the split chip's Separate Tabs in Split with Tab's place. Add Back to Pinned URL to Edit Pinned Page ›. Verify with unit tests in CI for each menu scenario in the `sidebar`, `pinned-tabs`, `favorites` and `split-view` deltas, including incognito and one Space.
- [ ] 3.8 Rename the sidebar Clear button's tooltip to "Clear unpinned tabs" (`PinsViews`). Verify with `grep -rn '"[^"]*Today[^"]*"' native/ClairUI` finding no user-facing string.

## 4. Probe tooling

- [ ] 4.1 Add `tests/probe/tools/keys.swift` (D8): steps `ctrldown`, `ctrlup`, `shiftdown`, `shiftup`, `tab`, `esc`, `sleep:<s>` and `shot:<png>:<x,y,w,h>`. Build it in `tools/build.sh`, and document it in the README beside `drag` and `mouse`. Verify by running `build/probe/bin/keys ctrldown tab sleep:0.5 shot:… ctrlup` against Arc and seeing the switcher in the shot.

## 5. Runtime suite

- [ ] 5.1 Move the runtime suite to the Tabs menu: `PinsTests.tabMenu` reads "Tabs", Clear Today becomes Clear Unpinned Tabs, and Back to Pinned URL is tested through the row's icon and Edit Pinned Page ›. `FoldersTests` and `SplitViewTests` follow. Add a check that the menu bar has no "Tab" menu. Verify by the suite passing in `quality.yml` on the branch.
- [ ] 5.2 Add `TabSwitcherTests`, using `perform(withKeyModifiers: .control)` to hold Ctrl:
  - a quick Ctrl+Tab returns to the previous tab, and `clair.tabSwitcher` never appears;
  - while held, `clair.tabSwitcher` shows the recent tabs' cards, the second selected;
  - Esc keeps the tab;
  - Opt+Cmd+Down still steps through the rows.

  Verify by the suite passing in `quality.yml`.
- [ ] 5.3 Add a cross-Space case: a tab shown in another Space comes back with Ctrl+Tab, and the window switches Space. Verify by the suite passing in `quality.yml`.
- [ ] 5.4 Add context menu checks: a Today tab's menu items and dividers in order, and a pinned tab's Close Tab keeping its row. Verify by the suite passing in `quality.yml`.

## 6. Hand check, docs and release notes

- [ ] 6.1 Hand check with `tests/probe/launch-clair.sh` and the `keys` tool, against `arc-reference/`, with the same tabs:
  - the panel's size and position;
  - card and highlight sizes;
  - previews of background and shown tabs, and of a split;
  - stepping, wrapping and Esc;
  - a quick tap: no panel in a 60 fps recording;
  - no animation in a 60 fps recording.

  Record the numbers in `arc-reference/README.md` under "Clair", and fix any difference larger than 2 pt.
- [ ] 6.2 Update the docs:
  - `docs/native-window.md`'s "Rows and commands" (Ctrl+Tab leaves the row commands; the switcher and its previews get a short section);
  - `docs/building.md`'s "Updating the engine" gains a note to grep Chromium for new `IDC_TAB_MENU` users (design "Risks").

  Verify by reading both pages.
- [ ] 6.3 Add a Changie fragment (`changie new`) for the switcher, the Tabs menu and the tab menus. Verify that `.changes/unreleased/` holds it.
- [ ] 6.4 Run CI and `quality.yml` on the last push together, with every note in that push. Verify that both pass.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks the last checks verified, syncs the delta specs and archives the change.
- Delete the temporary probe screenshots in the scratchpad and `build/probe/` once the change is archived. `arc-reference/screenshots/` stays with the change.
