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
- **Tab menus.** `PinsLogic.todayMenu`, `pinnedMenu` and `favoriteMenu` return `[MenuItem?]` (title, command, enabled). `TabRow.menuItems` and the pinned and favorite views map them to `RowClickCatcher.Item`s, which have no shortcut.
- **Autocomplete.** `ClairChromiumAutocomplete` builds its `AutocompleteController` with `DefaultOmniboxProviders() & ~kBookmark`, and `KindOf` maps every match that isn't a search, a typed URL or an open tab to `ClairSuggestionKindHistory`.
- **Dia** (`dia-reference/README.md`) uses one popover for adding and editing. Only its title changes. It adds the bookmark before showing the popover, Esc keeps the edits, and New Folder… creates the folder in Bookmarks Bar from an inline field.

## Goals / Non-Goals

**Goals:**
- Reuse Chromium's Bookmarks menu, `BookmarkMenuBridge` and `IDC_BOOKMARK_THIS_TAB`, changing only their order, titles, keys and one layout detail.
- One bookmark dialog in `ClairUI`, built on `ClairDialog`, opened the same way from the menu, ⇧⌘B and tab menus.
- Keep changes to Chromium's own files to one small patch.

**Non-Goals:**
- A bookmarks bar, star, Chromium's bubble or editor, or Bookmark All Tabs.
- A native bookmark manager: `chrome://bookmarks` stays the manager.
- Dia's Recent Bookmarks section and its tab menus' Move Bookmark ›.
- Bookmarks in the sidebar, or any link between bookmarks and pins or Favorites.
- A bookmark-specific icon or label in command bar rows.
- Editing a bookmark's URL in the dialog (Dia doesn't, and Manage Bookmarks can).

## Decisions

### D1. Show Chromium's menu and fix it up once at start-up

`InstallNativeWindowMenus` stops hiding `IDC_BOOKMARKS_MENU`, and `ClairIsRemovedCommand` drops `IDC_BOOKMARK_THIS_TAB`. The other three bookmark commands stay removed. In the Bookmarks submenu, the hook then:

1. removes Chromium's two separators tagged `IDC_BOOKMARK_THIS_TAB`, which the bridge would delete at its first rebuild anyway, so the menu looks the same before and after;
2. moves the `IDC_BOOKMARK_THIS_TAB` item to index 0, ahead of the manager item. The bridge leaves fixed items in place, so the order survives rebuilds;
3. gives it ⇧⌘B. The removed-command loop has already cleared ⌘D from it, and ⇧⌘B from Always Show Bookmarks Bar.

`MainMenuTitles` in `ClairUI` retitles `IDC_SHOW_BOOKMARK_MANAGER` to "Manage Bookmarks" by tag, as it does Open Location Bar.

*Alternative:* build a Bookmarks menu in `ClairUI` from the folder snapshots of D3. Rejected: it would duplicate `BookmarkMenuBridge` (lazy submenus, favicons, live updates, dispositions, managed folders) for no visible difference.

### D2. "Bookmark This Page…" or "Edit Bookmark…" from menu validation

`ClairWindowCommandHandler -validateUserInterfaceItem:window:` titles the `IDC_BOOKMARK_THIS_TAB` item every time AppKit validates it, which is whenever the menu opens or a key equivalent is matched:
- "Edit Bookmark…" when `bookmarks::IsBookmarkedByUser` is true for the active tab's last committed URL;
- "Bookmark This Page…" otherwise.

The command stays `IDC_BOOKMARK_THIS_TAB`, so ⇧⌘B does what the title says: `BookmarkCurrentTab` adds nothing to a bookmarked page, and reports `already_bookmarked` true.

The title lives in the engine, not in `MainMenuTitles`, because only the engine knows the bookmark state at validation time, without a round trip through snapshots.

### D3. The contract: bookmark and folder snapshots, and seven browser calls

`ClairHost.h` gains:
- `typedef int64_t ClairBookmarkID` and `ClairBookmarkFolderID`, Chromium's node IDs.
- **`@protocol ClairBookmark`**, a snapshot with:
  - `bookmarkID`, `title`, `url`, `folderID`;
  - `isNew`: true when this action added it, which picks the dialog's title;
  - `favicon`: the tab's favicon, or nil.
- **`@protocol ClairBookmarkFolder`**, with `folderID`, `title` and `depth` (0 for Bookmarks Bar and Other Bookmarks).
- **`ClairBrowser`**:
  - `canEditBookmarks`: false for guest profiles, and when `bookmarks::prefs::kEditBookmarksEnabled` is off.
  - `bookmarkFolders`: the user-editable folders in the popup's order. That's Bookmarks Bar, then its folders depth-first, then Other Bookmarks and its folders. Managed and Mobile Bookmarks are left out: managed bookmarks can't be edited, and ungoogled-chromium has no sync to fill Mobile.
  - `-bookmarkTab:(ClairTabID)`: returns the tab's `ClairBookmark`. It adds the bookmark with `AddIfNotBookmarked` first, so `isNew` is true, unless the page is already bookmarked. It returns nil for a tab without a page that can be bookmarked.
  - `-updateBookmark:title:folder:`: renames and moves the bookmark. An empty title becomes the page's title. An ID that no longer exists, because the bookmark was removed meanwhile, does nothing.
  - `-removeBookmark:(ClairBookmarkID)`: the dialog's Remove.
  - `-removeBookmarkForTab:(ClairTabID)`: `bookmarks::RemoveAllBookmarks` for the tab's URL, for the tab menu's Remove Bookmark.
  - `-bookmarkPin:(ClairPinID)` and `-removeBookmarkForPin:(ClairPinID)`: the same for a pinned tab or favorite. While the pin's tab is open, they act on that tab's page, as `bookmarkTab:` does, even when it has moved away from the pinned URL, as Copy Link does. While it's closed, they act on the pinned URL. A new bookmark is titled with the pin's `name`, or its `title` when it has none, and `favicon` is the pin's `icon`. The bookmark goes into the pin's profile.
  - `-addBookmarkFolder:(NSString *)title`: adds the folder at the end of Bookmarks Bar, as Dia does, and returns its ID.
- **`ClairTab.isBookmarked`**: whether the profile has a user bookmark for the tab's last committed URL. The browser bridge observes the profile's `BookmarkModel` (`BaseBookmarkModelObserver`) and re-snapshots tabs whose URL a change touches, coalesced as other snapshot changes are.
- **`ClairPin.isBookmarked`**: whether the pinned URL has a user bookmark. Pins whose URL a change touches are re-snapshotted the same way. A pin row reads its open tab's `isBookmarked`, or this one while it's closed.
- **`-[ClairWindow showBookmarkDialog:(id<ClairBookmark>)]`**, for the ⇧⌘B path.

All of it is additive. `ClairUI` and the engine ship together in one app, so there's no version skew to handle.

### D4. Two ways in, one dialog

- **⇧⌘B and the menu item** run `IDC_BOOKMARK_THIS_TAB`. Chromium adds the bookmark, or doesn't, and calls `ClairBrowserWindow::ShowBookmarkBubble(url, already_bookmarked)`. That builds a `ClairBookmark` for `GetMostRecentlyAddedUserNodeForURL(url)` with `isNew = !already_bookmarked`, and calls `showBookmarkDialog:`.
- **Add to Bookmarks…** in a tab menu calls `bookmarkTab:` for a Today tab, or `bookmarkPin:` for a pinned tab or favorite, and shows the dialog with the result. The tab isn't activated, and Chromium's command isn't involved, because it acts only on the active tab.

`BrowserWindowController.showBookmarkDialog(_:)` presents a `BookmarkDialog` through the window's `ClairDialogPresenter`, so it queues behind any other dialog on that window.

*Alternative:* Chromium's `BookmarkBubbleView`, attached to the site controls (the previous plan). Rejected: it needed a hook in Chromium's bubble code, a fix for its folder editor crashing without an anchor view, and row anchors for tab menus. A dialog centred on the window needs none of them, and it's Clair's own look.

*Alternative:* add the bookmark only on Done, so Cancel leaves nothing. Rejected: Dia adds first and offers Remove, and the owner asked for Dia's behaviour. It also keeps ⇧⌘B on Chromium's command.

### D5. `BookmarkDialog`: Dia's controls in Clair's card

`BookmarkDialog.swift` builds a `ClairDialogPage`:
- **Title:** "Bookmark Added" (`isNew`) or "Edit Bookmark". These are Dia's words in the Title Case of Clair's other dialogs.
- **Icon:** a new `ClairDialogPage.titleAccessory: NSImage?` draws the favicon at 16 pt at the title row's trailing end, where Dia has it (`dia-reference/screenshots/edit.jpg`). The 62 pt `icon` stays unused here. With no favicon, it shows a globe, as Dia does.
- **Content:** two rows, each a label in a 68 pt column, in secondary grey, then a control filling the rest of the content width, 36 pt tall, with 12 pt between the rows (Dia's measurements):
  - Name: a `TextField`, focused with its text selected when the dialog opens;
  - Folder: a popup button. It lists `bookmarkFolders` indented 16 pt per `depth`, with a checkmark on the current folder. New Folder… comes after Bookmarks Bar's folders, then Other Bookmarks' group, a divider and Manage Bookmarks.
- **New Folder…** swaps the popup for a `TextField` with the placeholder "New folder name…" and a × button. Return calls `addBookmarkFolder:`, reloads the folders, selects the new one and puts focus back in Name. × swaps the popup back. While the field shows, Return goes to it, not to Done.
- **Buttons:** Done is the default (Return, ↵ capsule), Remove is the `leadingButton`, and `escapePressesDefault` is true, so Esc saves as in Dia.
- **Answers:** Done and Esc call `updateBookmark:title:folder:`. Remove calls `removeBookmark:`. Manage Bookmarks saves, closes, then performs the main menu's Manage Bookmarks item, found by tag as `MainMenuTitles` finds it. That runs `IDC_SHOW_BOOKMARK_MANAGER`, so the dialog switches to an open `chrome://bookmarks` tab just as ⌥⌘B does, with no new contract call.

The card keeps `ClairDialogView`'s width and insets, so it matches Clair's other dialogs. Dia's own 380 pt popover and 16 pt padding aren't used.

### D6. Tab menus

`PinsLogic`'s three menus take `bookmark: BookmarkItem?`:
- `nil` hides the item (when `canEditBookmarks` is false);
- otherwise the item is `.add` or `.remove`, from the row's open tab's `isBookmarked`, or a closed pin's `isBookmarked`.

The item goes right after the last pin item: after Pin to Favorites in `todayMenu` (or where those items would be when `canPin` is false), after Remove Pin in `pinnedMenu`, and after Remove Favorite in `favoriteMenu`.

`MenuItem` gains an optional `shortcut`, set to ⇧⌘B only on Add to Bookmarks…, and `RowClickCatcher.Item.action` carries it to the `NSMenuItem`'s key equivalent. It only shows the key: a context menu's key equivalents don't fire once it closes, and the main menu's item handles ⇧⌘B.

### D7. Bookmarks Bar as a submenu: `bookmarks-menu-folders.patch`

The owner wants the Bookmarks Bar as a submenu beside Other Bookmarks, but Chromium lists its children inline. `BuildRootMenu` is the only place this can change, and `AddSubmenu` is private, so a patch to `bookmark_menu_bridge.mm` is needed. It replaces the inline loop with `AddSubmenu(menu_root_, bookmark_bar_folder, folder_image_, recurse)` while the folder `HasContent`. It also merges the two separators into one, added before the first folder that has content. The order stays Managed, Bookmarks Bar, Other Bookmarks, Mobile Bookmarks.

The patch is about ten lines and keeps Chromium's structure. Like `copy-url-shortcut.patch`, it changes Chromium's behaviour directly, because a hook would need to reach the bridge's private members. Its header explains why.

*Alternative:* move the bar's items into a submenu after each rebuild from the hook. Rejected: the bridge keeps `bookmark_nodes_` pointing at the items it made, and its incremental updates and `ClearBookmarkMenu` assume they're in `menu_root_` or in its submenus.

### D8. The command bar: turn the bookmark provider back on

`clair_autocomplete.mm` uses `DefaultOmniboxProviders()` unmasked. Chromium's `BOOKMARK_TITLE` matches fall to `ClairSuggestionKindHistory` in `KindOf`, so they look like history rows and get their favicon as history rows do. `AutocompleteResult` already removes duplicates by destination URL. `ClairSuggestionKind` doesn't change. In incognito, `BookmarkModelFactory` hands the provider the original profile's bookmarks, as Chromium's omnibox does.

### D9. Tests seed bookmarks through the profile's `Bookmarks` file

The runtime harness already launches with `--user-data-dir`. A helper writes `Default/Bookmarks` before launch. It holds one bookmark in the Bookmarks Bar, one in a "Reading" folder there, and one in Other Bookmarks, pointing at the suite's page server, at paths the test never visits. Chromium's decoder doesn't check a checksum, so the file can leave it out.

## Risks / Trade-offs

- **[A Chromium update re-binds ⇧⌘B or ⌘D, or rebuilds the fixed items]** → The runtime tests press ⇧⌘B and ⌘D. The hook finds items by tag, not by index.
- **[`BookmarkCurrentTab` calls `ShowBookmarkBubble` only while the window is active]** → ⇧⌘B and the menu act on the key window, so it always is. Tab menus don't go through it.
- **[The bookmark is removed while the dialog is open, by an extension or Manage Bookmarks in another window]** → `updateBookmark:` and `removeBookmark:` ignore an unknown ID, so Done closes and nothing happens.
- **[Esc saves rather than cancels]** → That's Dia's behaviour, which the owner chose. Remove undoes an add.
- **[`isBookmarked` costs a lookup per tab snapshot]** → `IsBookmarkedByUser` is a hash lookup in the model's URL index. Snapshots are already coalesced.
- **[The patch conflicts on an engine update]** → It's small and in one function. The patch check catches the conflict on the bump PR.
- **[Bookmark matches outrank history]** → Chromium's own relevance scoring decides, as in the omnibox.
- **[Bookmarks from a 0.1.x profile appear suddenly]** → That's intended. Nothing migrates.

## Migration Plan

None. Bookmarks already in the profile appear in the menu, the tab menus and the command bar on the first launch after the update. Rolling back hides them again, and the data is unchanged.
