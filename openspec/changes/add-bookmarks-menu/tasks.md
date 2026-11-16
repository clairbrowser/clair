# Tasks

Groups 1 and 2 change the engine key, so build the engine first and push docs afterwards, as `CLAUDE.md` describes.

- **"CI"** is the merge gate in `ci.yml`.
- **"By hand"** means a test copy from `tests/probe/launch-clair.sh`, driven with the probe and compared with `dia-reference/`, whose README indexes the screenshots and Dia's measurements. Don't re-probe Dia for what they already show.
- `quality.yml` runs on the branch before merging (`gh workflow run quality.yml --ref <branch>`), because the change alters the menu bar, which the runtime suite drives.
- **D-numbers** are `design.md`'s decisions.

Suggested order: 1, then 2 and 3 in parallel. Group 3 can start against `FakeHost` once 1 is done, while the engine builds. Group 4 is last.

Read `design.md` in full before starting. Verify every Chromium call it names against the engine workspace's source before using it, and update the design if one differs.

## 1. Contract and fakes

- [ ] 1.1 Add D3 to `native/ClairHost.h`, documented as the header documents the rest:
  - `ClairBookmarkID` and `ClairBookmarkFolderID`;
  - `ClairBookmark` and `ClairBookmarkFolder`;
  - `ClairSuggestionKindBookmark`;
  - `ClairBrowser`'s `bookmarkFolders` and three calls;
  - `-[ClairWindow showBookmarkDialog:]`.

  Verify that the header compiles in `ClairHostObjCxxTests.mm` in CI.
- [ ] 1.2 Give `FakeHost` a seedable bookmark store that behaves as D3 describes: updating with an empty title, removing by ID, an unknown ID doing nothing, folders in the popup's order with Other Bookmarks first, and new folders added to Other Bookmarks. Verify with new cases in `FakeBrowserTests` in CI.

## 2. Engine

- [ ] 2.1 In `InstallNativeWindowMenus`, stop hiding `IDC_BOOKMARKS_MENU`. Remove `IDC_BOOKMARK_THIS_TAB` from `ClairIsRemovedCommand`, and keep the other three bookmark commands. In the Bookmarks submenu, remove the two separators tagged `IDC_BOOKMARK_THIS_TAB`, move that item to index 0, and give it ⇧⌘B (D1). Update the D10 comments in both files. Verify with the runtime tests in 3.3.
- [ ] 2.2 Title `IDC_BOOKMARK_THIS_TAB` "Bookmark This Page…" or "Edit Bookmark…" in `ClairWindowCommandHandler -validateUserInterfaceItem:window:` (D2). Verify with the runtime tests in 3.3 and 3.4.
- [ ] 2.3 Implement D3 in the browser bridge:
  - the bookmark and folder snapshots;
  - `bookmarkFolders`;
  - the three calls.

  Verify with the runtime tests in 3.4.
- [ ] 2.4 Handle `IDC_BOOKMARK_THIS_TAB` in the native window's `ExecuteCommand`, adding the active tab's page to Other Bookmarks unless it's bookmarked, and calling `showBookmarkDialog:` (D4). Verify with the runtime tests in 3.4.
- [ ] 2.5 Add `patches/clair/bookmarks-menu-root.patch`, listed in `patches/series`, to `BookmarkMenuBridge::BuildRootMenu` (D7). It lists Other Bookmarks' contents directly in the menu, with no Bookmarks Bar or Other Bookmarks submenu, keeping the Managed and Mobile submenus while they have content, under one separator. Its header says why it isn't a hook. Verify that the patch check applies it, and with the runtime test in 3.3.
- [ ] 2.6 Add `overlay/chrome/browser/clair/clair_bookmark_bar_drain.{h,mm}` and start it for each original profile (D6), with its sources in the `BUILD.gn` hunk. Verify with the runtime tests in 3.3: the seeded Bookmarks Bar is drained at launch, and a bookmark created in the bar by a new test extension with the `bookmarks` permission, in `tests/runtime/extensions/`, moves to Other Bookmarks.
- [ ] 2.7 Use `DefaultOmniboxProviders()` unmasked in `clair_autocomplete.mm`, and update its header comment. Return `ClairSuggestionKindBookmark` from `KindOf` for bookmarked matches that aren't searches or open tabs, and skip the favicon lookup for them (D8). Verify with the runtime test in 3.5.
- [ ] 2.8 Build the engine with `gh workflow run engine.yml -f ref=<branch>`. Verify that `chromium-engine-<key>` is published and CI's engine check passes.
- [ ] 2.9 Update `docs/native-window.md`: describe the Bookmarks menu, the dialog and how it opens (D1 to D7), change the command bar row's "no bookmarks", and add rows for the bridge calls, the dialog, the Bookmarks Bar drain and the patch in "Where each piece lives". Verify that every file it names exists.

## 3. ClairUI and runtime tests

- [ ] 3.1 Add `BookmarkDialog.swift` and `BrowserWindowController.showBookmarkDialog(_:)` (D4, D5): the title, the Name and Folder rows, the indented folder popup with its checkmark, New Folder…'s field and ×, Manage Bookmarks, Remove, and Done on Return and Esc. Verify:
  - with `BookmarkDialog` cases in CI against `FakeHost`, one for each scenario of `bookmarks`' requirements from "Bookmark dialog" to "New folder in the bookmark dialog";
  - by hand against `dia-reference/screenshots/edit.jpg`, `folder-popup.jpg` and `new-folder.jpg`, in Light and Dark Mode: the controls' order, alignment and sizes match the README's measurements within a few points, and the card is Clair's.
- [ ] 3.2 Retitle `IDC_SHOW_BOOKMARK_MANAGER` to "Manage Bookmarks" in `MainMenuTitles.apply` (D1). Verify with a `MainMenuTitles` unit test in CI that the item is retitled by tag and other items keep their titles.
- [ ] 3.3 Add a Harness helper that writes `Default/Bookmarks` before launch (D9), and `tests/runtime/ClairRuntimeTests/BookmarksTests.swift`, with tests for the menu:
  - with the seeded bookmarks, the menu lists Bookmark This Page… (⇧⌘B), Manage Bookmarks (⌥⌘B), a divider, then the two drained Bookmarks Bar bookmarks, Other Bookmarks' bookmark and the "Reading" submenu, with no Bookmarks Bar or Other Bookmarks submenu;
  - with no bookmarks, the menu has only the two items;
  - choosing a bookmark loads it in the active tab;
  - ⌥⌘B opens `chrome://bookmarks`;
  - there's no Bookmark All Tabs item and no View › Always Show Bookmarks Bar.

  Verify by running the tests locally, which is allowed on this Mac, and they pass.
- [ ] 3.4 Add tests for the dialog through ⇧⌘B:
  - ⇧⌘B on a served page opens the dialog titled "Bookmark Added" with the page's title selected in Name;
  - the menu's first item then reads Edit Bookmark…;
  - typing a name and pressing Esc renames the bookmark;
  - choosing the "Reading" folder and Done moves it;
  - the folder popup starts with "Bookmarks" and lists no Bookmarks Bar;
  - New Folder… with a name and Return creates it in the Bookmarks menu;
  - ⇧⌘B again opens "Edit Bookmark" and adds nothing;
  - Remove deletes it;
  - ⌘D still pins the tab and adds no bookmark.

  Verify by running them locally, and they pass.
- [ ] 3.5 Give `SuggestionRow` the `bookmark` symbol for `.bookmark` (D8). Verify with a unit test in CI that each kind maps to its symbol. Then add runtime tests for suggestions:
  - a seeded, never-visited bookmark with a unique title is listed when its title is typed, shows the bookmark icon, and choosing it opens the page;
  - a visited, bookmarked page with a favicon (`tests/runtime/pages/favicon.html`) is listed once, with the bookmark icon;
  - with that page open in a tab, its "Switch to Tab" row doesn't show the bookmark icon.

  Verify by running them locally, and they pass.

## 4. Release notes and integration

- [ ] 4.1 Add a Changie fragment (`changie new`): one bookmark list, with Bookmarks Bar bookmarks moved into it; the Bookmarks menu, Bookmark This Page… and Edit Bookmark… on ⇧⌘B with the bookmark dialog, Manage Bookmarks on ⌥⌘B, and bookmarks in the command bar. Verify that it's in the PR.
- [ ] 4.2 Check by hand, in Light and Dark Mode:
  - the dialog on a narrow window, and on a second window while the first shows one;
  - bookmark favicons in the menu, and the bookmark icon in command bar rows, aligned and sized as the other kinds' symbols;
  - ⇧⌘B in an incognito window bookmarks into the regular profile;
  - ⇧⌘D still reaches the toolbar toggle if `add-page-toolbar` has landed.

  Verify that each check passes, and note anything that differs in the PR.
- [ ] 4.3 Run the merge gate, and start `quality.yml` on the branch with the last push. Verify that CI and the quality checks pass.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.
- After archiving, delete the temporary probe output in `build/probe/dia-bookmarks/`. Keep `dia-reference/`, which moves into the archive with the change.
