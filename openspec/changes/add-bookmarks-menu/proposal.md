# Proposal

## Why

`replace-browser-window` removed bookmarks from the interface because Arc has none. People coming from other browsers still have bookmarks, and the ones they imported, or saved in Clair 0.1.x, are still in the profile. Today they can only reach them by typing `chrome://bookmarks`. A Bookmarks menu, a bookmark item in tabs' menus and a bookmark dialog let them open, add, edit and remove bookmarks without bringing back the bookmarks bar, the star or the omnibox.

Today the command bar doesn't suggest bookmarks either. `ClairChromiumAutocomplete` removes Chromium's `BookmarkProvider` (`clair_autocomplete.mm`). A bookmark only affects the results through history: the history providers rank a visited bookmarked page higher and never drop it. A bookmark the user hasn't visited never shows up. Once bookmarks have a menu, the command bar should find them too.

## What Changes

- **The Bookmarks menu comes back**, after History, where Chromium puts it. It holds, in order:
  - **Bookmark This Page…**, ⇧⌘B, which reads **Edit Bookmark…** while the active tab's page is bookmarked;
  - **Manage Bookmarks**, ⌥⌘B, which opens `chrome://bookmarks`;
  - a divider;
  - a **Bookmarks Bar** submenu and an **Other Bookmarks** submenu, listing their folders and bookmarks with favicons. Each submenu appears only when its folder holds bookmarks. Chromium's Managed and Mobile folders appear after them, under the same rule.

  Choosing a bookmark opens it in the active tab, and ⌘-choosing it opens it in a new tab, as Chromium's menu does.
- **A bookmark dialog**, one of Clair's own dialogs, with Dia's controls (`dia-reference/`). It's the same dialog for adding and editing:
  - **Title:** "Bookmark Added" or "Edit Bookmark", with the page's favicon at the trailing end of the title row.
  - **Name:** a field holding the bookmark's name, focused with its text selected.
  - **Folder:** a popup listing Bookmarks Bar and Other Bookmarks with their folders indented beneath them, plus New Folder… and Manage Bookmarks. New Folder… turns the popup into a "New folder name…" field.
  - **Buttons:** Remove at the bottom leading corner, and Done ↵ at the bottom trailing corner.

  As in Dia, adding a bookmark saves it before the dialog opens. Remove deletes it, and Done, Return or Esc keep the edits. Bookmark This Page… and Edit Bookmark… open it for the active tab.
- **Tabs' context menus** get a bookmark item right after their last pin action. A Today tab's comes after Pin to Favorites, a pinned tab's after Remove Pin, and a favorite's after Remove Favorite. Incognito Today tabs have no pin items, so theirs takes the same place.
  - **Add to Bookmarks…**, with ⇧⌘B shown, while the tab's page isn't bookmarked. It adds the bookmark and opens the dialog for that tab, without switching tabs.
  - **Remove Bookmark**, with no shortcut, while it is. It removes the page's bookmarks at once.

  A pinned tab or favorite acts on the page it shows. While it has no open page, it acts on its pinned URL under its name, as Copy Link does. Guest windows, and profiles whose policy forbids editing bookmarks, don't show the item.
- **The command bar suggests bookmarks.** Chromium's bookmark source joins the command bar's suggestions, so a bookmark the user has never visited shows up by its title or URL. Chromium already lists a page once, even when it's both visited and bookmarked.
- **Bookmarked rows show a bookmark icon** instead of the page's favicon, whether the row came from bookmarks or from history. Bookmark rows therefore never need Chromium's favicon store, which has nothing for a bookmark that was imported and never visited. Searches keep their icon, and "Switch to Tab" rows keep theirs.
- **Shortcuts that stay:** ⌘D pins or unpins the tab (`pinned-tabs`), and ⇧⌘D stays free for `add-page-toolbar`'s toolbar toggle. Chromium's ⇧⌘B (Always Show Bookmarks Bar) becomes Bookmark This Page….
- **What stays out:** the bookmarks bar, View › Always Show Bookmarks Bar, the bookmark star, Chromium's bookmark bubble, Bookmark All Tabs, the bookmarks side panel, and Dia's Recent Bookmarks section.

## Capabilities

### New Capabilities

- `bookmarks`: the bookmarks the interface offers: the Bookmarks menu and its items, the bookmark dialog, the bookmark item in tabs' menus, opening bookmarks from the menu, and the bookmarks UI Clair leaves out.

### Modified Capabilities

- `browser-window`: "No bookmarks in the interface" is removed. What it still ruled out (the bar, the star, Cmd+D as a bookmark key) moves to `bookmarks`.
- `command-bar`: "Suggestions from Chromium's autocomplete" now includes bookmarks.
- `sidebar`: "Today tab menu" gains Add to Bookmarks… or Remove Bookmark.
- `pinned-tabs`: "Pinned tab menu" gains the same item.
- `favorites`: "Favorite menu" gains the same item.

## Impact

- **Engine** (the engine key changes):
  - `clair_window_hooks.mm`: the Bookmarks menu is shown, and its first item is moved to the top and given ⇧⌘B.
  - `clair_native_window.mm`: `ClairIsRemovedCommand` no longer removes `IDC_BOOKMARK_THIS_TAB`, and the window's menu validation titles it Bookmark This Page… or Edit Bookmark….
  - `clair_browser_window.mm`: `ShowBookmarkBubble` asks `ClairUI` for the bookmark dialog instead of logging that it's unavailable.
  - The browser bridge reports whether each tab's page is bookmarked, lists the profile's bookmark folders, and adds, edits and removes bookmarks and folders.
  - `clair_autocomplete.mm`: stops removing `kBookmark` from the providers, and marks bookmarked rows with the new kind instead of fetching their favicon.
  - A new `patches/clair/bookmarks-menu-folders.patch` makes Chromium's `BookmarkMenuBridge` list the Bookmarks Bar as a submenu, as it does Other Bookmarks. No other Chromium file changes.
- **`ClairHost.h`:** additive:
  - a bookmark snapshot (`ClairBookmark`) and a folder snapshot (`ClairBookmarkFolder`);
  - `ClairTab.isBookmarked` and `ClairPin.isBookmarked`;
  - `ClairSuggestionKindBookmark`;
  - `ClairBrowser.canEditBookmarks`, `bookmarkFolders`, `-bookmarkTab:`, `-bookmarkPin:`, `-updateBookmark:…`, `-removeBookmark:`, `-removeBookmarkForTab:`, `-removeBookmarkForPin:` and `-addBookmarkFolder:`;
  - `-[ClairWindow showBookmarkDialog:]`.
- **`ClairUI`:**
  - a `BookmarkDialog` built on `ClairDialog`, which gains a small trailing title icon;
  - the three tab menus in `PinsLogic` and their views, with a shortcut shown on a context-menu item;
  - Manage Bookmarks' title in `MainMenuTitles`.
- **Runtime suite:** new tests cover the menu and its titles, ⇧⌘B and the dialog, the tab menus' items, and bookmark suggestions, using a seeded `Bookmarks` file in the test profile. The PR runs `quality.yml` on its branch.
- **Users:** bookmarks already in the profile appear in the menu right away. Nothing migrates.
- **Docs:** `docs/native-window.md` (the menu, the dialog and the bridge calls), and a Changie fragment.
