# Design

## Context

- **Chromium's Bookmarks menu.** `main_menu_builder.mm` (`BuildBookmarksMenu`) builds it with tag `IDC_BOOKMARKS_MENU` and these fixed items:
  - Open Bookmarks Manager (`IDC_SHOW_BOOKMARK_MANAGER`, ⌥⌘B);
  - a separator tagged `IDC_BOOKMARK_THIS_TAB`;
  - Bookmark This Tab… (`IDC_BOOKMARK_THIS_TAB`, ⌘D);
  - Bookmark All Tabs… (`IDC_BOOKMARK_ALL_TABS`, ⇧⌘D);
  - a second separator tagged `IDC_BOOKMARK_THIS_TAB`.

  `BookmarkMenuBridge` fills in the rest from the profile's `BookmarkMergedSurfaceService`. It rebuilds lazily when the menu opens after a change. A rebuild first deletes every separator, every submenu and every `openBookmarkMenuItem:` item, and leaves the other fixed items where they are. `BuildRootMenu` then appends:
  - a separator, then the Managed folder as a submenu and the Bookmarks Bar's children **inline**;
  - another separator, then Other Bookmarks and Mobile Bookmarks as submenus.

  `AddSubmenu` CHECKs that a permanent folder isn't empty, so each one is added only while `HasContent`. Choosing a bookmark goes through `BookmarkMenuCocoaController`, which takes the disposition from the event (⌘ means a new tab) and opens the bookmark in the last active browser.
- **What Clair does today** (`replace-browser-window` D10):
  - `InstallNativeWindowMenus` (`clair_window_hooks.mm`), run once at start-up, hides the `IDC_BOOKMARKS_MENU` item.
  - `ClairIsRemovedCommand` (`clair_native_window.mm`) lists `IDC_BOOKMARK_THIS_TAB`, `IDC_BOOKMARK_ALL_TABS`, `IDC_SHOW_BOOKMARK_BAR` and `IDC_SHOW_BOOKMARK_SIDE_PANEL`. The same hook hides their items and clears their keys, and `ClairWindowCommandHandler` disables them.
  - `ClairWindowCommandHandler -validateUserInterfaceItem:window:` already adjusts some items per command, such as Close Tab's shortcut.
  - `PinsMenu` puts Pin Tab on ⌘D, and `add-page-toolbar` plans to put View › Hide Toolbar on ⇧⌘D.
- **⇧⌘B** is bound only through View › Always Show Bookmarks Bar (`IDC_SHOW_BOOKMARK_BAR`), whose item Clair hides and clears. `global_keyboard_shortcuts_mac.mm` doesn't bind it, so it's free.
- **`chrome::BookmarkCurrentTab`**, which runs `IDC_BOOKMARK_THIS_TAB`, works like this:
  - It adds the bookmark with `AddIfNotBookmarked`, into `GetParentForNewNodes`: the most recently modified user folder, or the Bookmarks Bar.
  - It adds nothing when the page is already bookmarked.
  - While the window is active, it then calls `BrowserWindow::ShowBookmarkBubble(url, already_bookmarked)`.

  `ClairBrowserWindow::ShowBookmarkBubble` only logs that the bubble is unavailable.
- **Clair's dialogs** (`ClairDialog.swift`, the `dialogs` spec). A `ClairDialogPage` has:
  - an optional 62 pt icon above the title, a title, an optional message and a content view;
  - buttons, plus one `leadingButton` that neither key chooses;
  - an optional `width`, and `escapePressesDefault` for a dialog with no cancelling button.

  `ClairDialogPresenter` queues one dialog per window over the dimmed window. The Rename and Link Rules dialogs put their fields in `content`.
- **Autocomplete.** `ClairChromiumAutocomplete` builds its `AutocompleteController` with `DefaultOmniboxProviders() & ~kBookmark`, and `KindOf` maps every match that isn't a search, a typed URL or an open tab to `ClairSuggestionKindHistory`. `SuggestionRow` (`OverlayViews.swift`) draws a symbol per kind (`magnifyingglass`, `globe`, `clock`, `square.on.square`) when a suggestion has no `icon`. Since #164, `clair_autocomplete.mm` fetches history, typed-URL and most-visited rows' favicons from the profile's favicon database and republishes the rows when they arrive.
- **Dia** (`dia-reference/README.md`) uses one popover for adding and editing. Only its title changes. It adds the bookmark before showing the popover, Esc keeps the edits, and New Folder… creates the folder in Bookmarks Bar from an inline field. Clair departs from Dia on folders: it has one list, Other Bookmarks, called "Bookmarks" (D6).

## Goals / Non-Goals

**Goals:**
- Reuse Chromium's Bookmarks menu, `BookmarkMenuBridge` and `IDC_BOOKMARK_THIS_TAB`, changing only their order, titles, keys and one layout detail.
- One bookmark dialog in `ClairUI`, built on `ClairDialog`, opened the same way from the menu and ⇧⌘B.
- Keep changes to Chromium's own files to one small patch.

**Non-Goals:**
- A bookmarks bar, star, Chromium's bubble or editor, or Bookmark All Tabs.
- Hiding the Bookmarks Bar folder in `chrome://bookmarks`. It would take a behaviour patch to Chromium's WebUI (the folder tree and `router.ts`'s default folder), which upstream reworks often. Kept empty (D6), the folder is harmless there.
- A native bookmark manager: `chrome://bookmarks` stays the manager.
- Dia's Recent Bookmarks section.
- Bookmarks in the sidebar, or any link between bookmarks and pins or Favorites.
- A text label or a badge for bookmarks in command bar rows. The bookmark icon in place of the favicon is their only mark (D8).
- Editing a bookmark's URL in the dialog (Dia doesn't, and Manage Bookmarks can).

## Decisions

### D1. Show Chromium's menu and fix it up once at start-up

`InstallNativeWindowMenus` stops hiding `IDC_BOOKMARKS_MENU`, and `ClairIsRemovedCommand` drops `IDC_BOOKMARK_THIS_TAB`. The other three bookmark commands stay removed. In the Bookmarks submenu, the hook then:

1. removes Chromium's two separators tagged `IDC_BOOKMARK_THIS_TAB`, which the bridge would delete at its first rebuild anyway, so the menu looks the same before and after;
2. moves the `IDC_BOOKMARK_THIS_TAB` item to index 0, ahead of the manager item. The bridge leaves fixed items in place, so the order survives rebuilds;
3. gives it ⇧⌘B. The removed-command loop has already cleared ⌘D from it, and ⇧⌘B from Always Show Bookmarks Bar.

`MainMenuTitles` in `ClairUI` retitles `IDC_SHOW_BOOKMARK_MANAGER` to "Manage Bookmarks" by tag, as it does Open Location Bar.

The manager opens on Other Bookmarks, since the Bookmarks Bar it would otherwise select first is always empty (D6). `ExecuteCommand` in `clair_native_window.mm` runs `IDC_SHOW_BOOKMARK_MANAGER` as `clair::ShowBookmarkManager`, which calls Chromium's `ShowBookmarkManagerForNode` with Other Bookmarks' ID, opening `chrome://bookmarks/?id=<id>`. Like Chromium's command, it uses `GetBrowserForOpeningWebUi` and switches to an open manager tab, which then shows Other Bookmarks. Typing `chrome://bookmarks` still selects the Bookmarks Bar: changing the page's default would mean patching its TypeScript.

*Alternative:* build a Bookmarks menu in `ClairUI` from the folder snapshots of D3. Rejected: it would duplicate `BookmarkMenuBridge` (lazy submenus, favicons, live updates, dispositions, managed folders) for no visible difference.

### D2. "Bookmark This Page…" or "Edit Bookmark…" from menu validation

`ClairWindowCommandHandler -validateUserInterfaceItem:window:` titles the `IDC_BOOKMARK_THIS_TAB` item every time AppKit validates it, which is whenever the menu opens or a key equivalent is matched:
- "Edit Bookmark…" when `bookmarks::IsBookmarkedByUser` is true for the page Chromium would bookmark for the active tab (`chrome::GetURLAndTitleToBookmark`, its visible URL), as `BookmarkCurrentTab` checks it;
- "Bookmark This Page…" otherwise.

The command stays `IDC_BOOKMARK_THIS_TAB`, so ⇧⌘B does what the title says: `BookmarkCurrentTab` adds nothing to a bookmarked page, and reports `already_bookmarked` true.

The title lives in the engine, not in `MainMenuTitles`, because only the engine knows the bookmark state at validation time, without a round trip through snapshots.

### D3. The contract: bookmark and folder snapshots, and three browser calls

`ClairHost.h` gains:
- `typedef int64_t ClairBookmarkID` and `ClairBookmarkFolderID`, Chromium's node IDs, and `ClairBookmarkFolderIDNone` (-1).
- **`@protocol ClairBookmark`**, a snapshot with:
  - `bookmarkID`, `title`, `url`, `folderID`;
  - `isNew`: true when ⇧⌘B added it, which picks the dialog's title;
- **`@protocol ClairBookmarkFolder`**, with `folderID`, `title` and `depth` (0 for Other Bookmarks itself, which the popup calls "Bookmarks").
- **`ClairBrowser`**:
  - `bookmarkFolders`: the user-editable folders in the popup's order. That's Other Bookmarks, then its folders depth-first. The Bookmarks Bar is left out, since D6 keeps it empty. Managed and Mobile Bookmarks are left out too: managed bookmarks can't be edited, and ungoogled-chromium has no sync to fill Mobile.
  - `-updateBookmark:title:folder:`: renames the bookmark and moves it to the end of the folder, one of `bookmarkFolders`; a bookmark already there keeps its place, and an unknown folder leaves it where it is. An empty title becomes the page's title: the window's active tab's when it shows the bookmark's URL, which it does while the dialog is up, or else the URL formatted for people. An ID that no longer exists, because the bookmark was removed meanwhile, does nothing.
  - `-removeBookmark:(ClairBookmarkID)`: the dialog's Remove.
  - `-addBookmarkFolder:(NSString *)title`: adds the folder at the end of Other Bookmarks and returns its ID, or `ClairBookmarkFolderIDNone` for a title that's empty once trimmed.
- **`-[ClairWindow showBookmarkDialog:(id<ClairBookmark>)]`**, for the ⇧⌘B path.
- **`-[ClairWindow showBookmarksBarNotice]`**, for the Bookmarks Bar notice (D6). `ClairUI` owns the text.

All of it is additive. `ClairUI` and the engine ship together in one app, so there's no version skew to handle.

### D4. One way in: ⇧⌘B and the menu item

⇧⌘B and the menu item run `IDC_BOOKMARK_THIS_TAB`. The native window's `ExecuteCommand` (`clair_native_window.mm`) handles it before Chromium does, as it already handles `IDC_NEW_TAB`, through `clair::BookmarkActivePage` (`clair_bookmarks.mm`, beside the bridge's other bookmark calls). For the page Chromium would bookmark (`chrome::GetURLAndTitleToBookmark`), it adds a bookmark under the page's title at the end of Other Bookmarks, with `isNew` true, unless the user has bookmarked the page already, in which case it takes the URL's most recently added bookmark (`GetMostRecentlyAddedUserNodeForURL`). An incognito page's favicon is saved first, as `BookmarkCurrentTab` does. It then calls `showBookmarkDialog:` with that snapshot. Chromium's `BookmarkCurrentTab` would add to `GetParentForNewNodes`, the most recently modified folder, which can be the Bookmarks Bar. `ClairBrowserWindow::ShowBookmarkBubble` keeps logging, since nothing calls it any more.

`BrowserWindowController.showBookmarkDialog(_:)` presents the bookmark dialog (D5) through the window's `ClairDialogPresenter`, so it queues behind any other dialog on that window.

*Alternative:* Chromium's `BookmarkBubbleView`, attached to the site controls (the previous plan). Rejected: it needed a hook in Chromium's bubble code, and a fix for its folder editor crashing without an anchor view. A dialog centred on the window needs none of them, and it's Clair's own look.

*Alternative:* add the bookmark only on Done, so Cancel leaves nothing. Rejected: Dia adds first and offers Remove, and the owner asked for Dia's behaviour.

### D5. The bookmark dialog: Dia's controls in Clair's card

`BookmarkDialog.swift` builds its `ClairDialogPage`, as `LinkRulesDialog.swift` builds the Link Rules dialog's:
- **Title:** "Bookmark Added" (`isNew`) or "Edit Bookmark". These are Dia's words in the Title Case of Clair's other dialogs.
- **No icon.** Dia shows the favicon at the title row's trailing end (`dia-reference/screenshots/edit.jpg`). Clair leaves it out: it would be the only thing `ClairDialog` lacks, and the dialog's title and Name already say which page it is. `ClairDialogPage.icon`, the 62 pt icon above the title, stays unused.
- **Content:** two rows, each a label in a 68 pt column, in secondary grey, then a control filling the rest of the content width, 36 pt tall, with 12 pt between the rows (Dia's measurements):
  - Name: a `TextField`, focused with its text selected when the dialog opens;
  - Folder: a popup button. It lists `bookmarkFolders` indented 16 pt per `depth`, the first titled "Bookmarks", with a checkmark on the current folder. New Folder… comes after the folders, then a divider and Manage Bookmarks.
- **New Folder…** swaps the popup for a `TextField` with the placeholder "New folder name…" and a × button. Return calls `addBookmarkFolder:`, reloads the folders, selects the new one and puts focus back in Name. × swaps the popup back. While the field shows, Return goes to it, not to Done.
- **Buttons:** Done is the default (Return, ↵ capsule), Remove is the `leadingButton`, and `escapePressesDefault` is true, so Esc saves as in Dia.
- **Answers:** Done and Esc call `updateBookmark:title:folder:`. Remove calls `removeBookmark:`. Manage Bookmarks saves, closes, then performs the main menu's Manage Bookmarks item, found by tag as `MainMenuTitles` finds it. That runs `IDC_SHOW_BOOKMARK_MANAGER`, so the dialog switches to an open `chrome://bookmarks` tab just as ⌥⌘B does, with no new contract call.

The card keeps `ClairDialogView`'s width and insets, so it matches Clair's other dialogs. Dia's own 380 pt popover and 16 pt padding aren't used.

### D6. One list: Other Bookmarks, called "Bookmarks"

Clair's interface shows one bookmark list. Chromium's model always has a Bookmarks Bar and an Other Bookmarks folder, both permanent, and Clair uses Other Bookmarks:
- the menu lists its contents directly (D7);
- the dialog's folder popup starts with it, titled "Bookmarks" (D5);
- new bookmarks and new folders are added to it (D4, D3).

**Keeping the Bookmarks Bar empty.** `overlay/chrome/browser/clair/clair_bookmark_bar_drain.{h,mm}` is a `BaseBookmarkModelObserver`, one for each original profile that isn't a guest profile, kept as the profile's user data. `ClairBrowserWindow` starts it beside `ApplyPasswordAndAutofillOverrides`, for every window, incognito ones included (`ClairBookmarkBarDrain::WindowOpened`). It drains the bar when:
- the model loads;
- `BookmarkNodeAdded` or `BookmarkNodeMoved` puts a node directly in the bar;
- `ExtensiveBookmarkChangesEnded` runs, which is when an import finishes. While `IsDoingExtensiveChanges()` is true, it waits.

Draining posts a task, so it never moves nodes inside an observer callback. It moves the bar's children to the top of Other Bookmarks, in their order, with `BookmarkModel::Move`, so they keep the place they had in Chromium's menu, before Other Bookmarks. A folder moves whole. A managed (policy) node is never in the bar, and the account-storage bar, which only sync fills, is drained the same way if it exists.

**The notice.** It shows once for the whole app, so its flag is a local-state pref, `clair.bookmarks_bar_notice_shown`, false by default, registered in `clair::RegisterLocalStatePrefs` (`clair_window_hooks.mm`) with Clair's other local-state prefs. That hook is already called from `browser_prefs.cc`, so no Chromium file changes for it. When a drain moves at least one node and the pref is false, it calls `showBookmarksBarNotice` on the profile's most recently active normal window and sets the pref. When the profile has no normal native window, as when an extension fills the bar of a profile whose windows have closed, the drain waits, and `WindowOpened` shows the notice in the next normal window that opens for the profile, setting the pref then. No `BrowserList` observer is needed, since every native window passes through `WindowOpened`. Incognito and guest windows never show it: the drain only runs for original profiles.

`ClairUI` shows it through the window's `ClairDialogPresenter`: a `ClairDialogPage`, built in its own `BookmarksBarNotice.swift`, titled "Heads Up", with the message "Clair doesn't have a bookmarks bar, so bookmarks saved or imported there are moved to the Bookmarks menu.", one default OK button, and `escapePressesDefault` true. It queues behind any other dialog on that window.

*Alternative:* show it on every drain. Rejected: after the first, the user knows, and an extension that writes to the bar would show it again and again.

*Alternative:* once per profile, in a profile pref. Rejected: what the notice explains is the same in every profile, and registering a profile pref would need another hook in `browser_prefs.cc`.

*Alternative:* show the bar's contents and Other Bookmarks' together, moving nothing. Rejected: the dialog would still have to show two roots, and an extension's or import's bookmarks would sit apart from the user's.

*Alternative:* leave the bar alone. Rejected: Chrome imports and most other browsers' bookmarks land there, and they would vanish from the menu.

### D7. The menu's bookmarks: `bookmarks-menu-root.patch`

Chromium's `BuildRootMenu` lists the Bookmarks Bar's children directly in the menu, and Other Bookmarks as a submenu. Clair wants the reverse with no bar. `AddSubmenu` and the bridge's node map are private, so a patch to `bookmark_menu_bridge.mm` is needed. It lists Other Bookmarks' children where the bar's were, with the same `AddNodeToMenu`, and no longer adds Other Bookmarks as a submenu. The Managed folder's submenu stays before them and Mobile Bookmarks' after, each only while it has content, under one separator.

The patch is about ten lines and keeps Chromium's structure. Like `copy-url-shortcut.patch`, it changes Chromium's behaviour directly, because a hook would need to reach the bridge's private members. Its header explains why.

*Alternative:* move the bar's items into a submenu after each rebuild from the hook. Rejected: the bridge keeps `bookmark_nodes_` pointing at the items it made, and its incremental updates and `ClearBookmarkMenu` assume they're in `menu_root_` or in its submenus.

### D8. The command bar: turn the bookmark provider back on

`clair_autocomplete.mm` uses `DefaultOmniboxProviders()` unmasked. `AutocompleteResult` already removes duplicates by destination URL. In incognito, `BookmarkModelFactory` hands the provider the original profile's bookmarks, as Chromium's omnibox does.

**Titles first.** Chromium's controller sets `swap_contents_and_description` on every match with a description that isn't a search, and the omnibox then shows the description, the page's title, first. `clair_autocomplete.mm` didn't, so history rows read as their URLs; it now honours the flag, so a bookmark row reads as its title, as the `command-bar` spec says of every row.

**A bookmark kind and icon.** `ClairHost.h` adds `ClairSuggestionKindBookmark = 4`. `KindOf` returns it for any match that isn't a search or an open tab and whose `destination_url` passes `bookmarks::IsBookmarkedByUser`, so a `BOOKMARK_TITLE` match and a history match for a bookmarked page look the same. For those rows, `clair_autocomplete.mm` skips the favicon lookup that #164 added for history rows, and sends `icon` as nil. `SuggestionRow` then draws the kind's SF Symbol, `bookmark`: the same shape as the bookmark button in Dia's URL bar (`dia-reference/screenshots/edit.jpg`). The empty-query list's most visited sites follow the same rule. VoiceOver reads "Bookmark" at the end of the row, after "Switch to Tab"'s place, since the icon has no text.

Bookmark rows, which are the ones most likely to have no entry in Chromium's favicon database, never wait on it or show a late icon. Open-tab rows keep their icon (the tab's favicon in the empty-query list, `square.on.square` otherwise), because "Switch to Tab" is about the tab. Searches keep the magnifying glass.

*Alternative:* the favicon with a small bookmark badge. Rejected: the owner chose the plain bookmark icon, and a badge would still need the favicon store.

The `command-bar` delta modifies #164's "Row icons" requirement to add the bookmark icon, so the spec has one rule for row icons.

### D9. Tests seed bookmarks through the profile's `Bookmarks` file

The runtime harness already launches with `--user-data-dir`. A helper writes `Default/Bookmarks` before launch. It holds two bookmarks in the Bookmarks Bar, to check that they're drained and that the notice shows, and in Other Bookmarks a bookmark and a "Reading" folder with one bookmark, pointing at the suite's page server, at paths the test never visits. Chromium's decoder doesn't check a checksum, so the file can leave it out.

## Risks / Trade-offs

- **[A Chromium update re-binds ⇧⌘B or ⌘D, or rebuilds the fixed items]** → The runtime tests press ⇧⌘B and ⌘D. The hook finds items by tag, not by index.
- **[Moving bookmarks surprises an extension]** → An extension that creates a bookmark in the Bookmarks Bar gets `onMoved` right after `onCreated`, and its later calls by ID still work. This is the cost of one list.
- **[A drain loop]** → Moving out of the bar never adds to it, and the drain only reacts to nodes whose new parent is the bar.
- **[The notice covers the first window at launch]** → It shows once for the whole app and closes with Return or Esc. The runtime tests that seed the Bookmarks Bar dismiss it first.
- **[A large import]** → One task moves the bar's children once the import's extensive changes end, not node by node.
- **[The bookmark is removed while the dialog is open, by an extension or Manage Bookmarks in another window]** → `updateBookmark:` and `removeBookmark:` ignore an unknown ID, so Done closes and nothing happens.
- **[Esc saves rather than cancels]** → That's Dia's behaviour, which the owner chose. Remove undoes an add.
- **[The menu patch conflicts on an engine update]** → It's small and in one function. The patch check catches the conflict on the bump PR.
- **[Bookmark matches outrank history]** → Chromium's own relevance scoring decides, as in the omnibox.
- **[Bookmarks from a 0.1.x profile appear suddenly]** → That's intended. Nothing migrates.

## Migration Plan

On the first launch after the update, D6 moves the Bookmarks Bar's contents to Other Bookmarks, and every bookmark shows in the menu and the command bar. Rolling back hides them from the interface again. Bookmarks stay where D6 moved them, and nothing is lost.
