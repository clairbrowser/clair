# Proposal

## Why

`replace-browser-window` removed bookmarks from the interface because Arc has none. People coming from other browsers still have bookmarks, and the ones they imported, or saved in Clair 0.1.x, are still in the profile. Today they can only reach them by typing `chrome://bookmarks`. A Bookmarks menu and a bookmark dialog let them open, add, edit and remove bookmarks without bringing back the bookmarks bar, the star or the omnibox.

Today the command bar doesn't suggest bookmarks either. `ClairChromiumAutocomplete` removes Chromium's `BookmarkProvider` (`clair_autocomplete.mm`). A bookmark only affects the results through history: the history providers rank a visited bookmarked page higher and never drop it. A bookmark the user hasn't visited never shows up. Once bookmarks have a menu, the command bar should find them too.

## What Changes

- **The Bookmarks menu comes back**, after History, where Chromium puts it. It holds, in order:
  - **Bookmark This Page…**, ⇧⌘B, which reads **Edit Bookmark…** while the active tab's page is bookmarked;
  - **Manage Bookmarks**, ⌥⌘B, which opens `chrome://bookmarks`;
  - a divider;
  - the bookmarks and folders of Chromium's Other Bookmarks, directly in the menu, with favicons, each folder as a submenu.

  Choosing a bookmark opens it in the active tab, and ⌘-choosing it opens it in a new tab, as Chromium's menu does.
- **One bookmark list, "Bookmarks".** Clair uses only Chromium's Other Bookmarks folder and calls it "Bookmarks". The Bookmarks Bar has no place in Clair's interface, so Clair keeps it empty. Whatever is there at launch, or lands there later from an import, Manage Bookmarks or an extension, moves to Other Bookmarks. `chrome://bookmarks` still shows the empty Bookmarks Bar: hiding it would mean patching Chromium's page for little gain.

  The first time Clair moves anything out of a Bookmarks Bar, in any profile, a dialog explains why. It shows only once for the whole app:
  - **Title:** "Heads Up";
  - **Message:** "Clair doesn't have a bookmarks bar, so bookmarks saved or imported there are moved to the Bookmarks menu.";
  - **Button:** OK.
- **A bookmark dialog**, one of Clair's own dialogs, with Dia's controls (`dia-reference/`). It's the same dialog for adding and editing:
  - **Title:** "Bookmark Added" or "Edit Bookmark". Dia's small favicon at the end of the title row is left out, so the dialog needs nothing new from `ClairDialog`.
  - **Name:** a field holding the bookmark's name, focused with its text selected.
  - **Folder:** a popup listing "Bookmarks" with its folders indented beneath it, plus New Folder… and Manage Bookmarks. New Folder… turns the popup into a "New folder name…" field.
  - **Buttons:** Remove at the bottom leading corner, and Done ↵ at the bottom trailing corner.

  As in Dia, adding a bookmark saves it before the dialog opens. Remove deletes it, and Done, Return or Esc keep the edits. Bookmark This Page… and Edit Bookmark… open it for the active tab.
- **The command bar suggests bookmarks.** Chromium's bookmark source joins the command bar's suggestions, so a bookmark the user has never visited shows up by its title or URL. Chromium already lists a page once, even when it's both visited and bookmarked.
- **Bookmarked rows show a bookmark icon** instead of the page's favicon, whether the row came from bookmarks or from history. Bookmark rows therefore never need Chromium's favicon store, which has nothing for a bookmark that was imported and never visited. Searches keep their icon, and "Switch to Tab" rows keep theirs.
- **Shortcuts that stay:** ⌘D pins or unpins the tab (`pinned-tabs`), and ⇧⌘D stays free for `add-page-toolbar`'s toolbar toggle. Chromium's ⇧⌘B (Always Show Bookmarks Bar) becomes Bookmark This Page….
- **What stays out:** the bookmarks bar and the Bookmarks Bar folder, View › Always Show Bookmarks Bar, the bookmark star, Chromium's bookmark bubble, Bookmark All Tabs, the bookmarks side panel, and Dia's Recent Bookmarks section.

## Capabilities

### New Capabilities

- `bookmarks`: the bookmarks the interface offers: the Bookmarks menu and its items, the bookmark dialog, opening bookmarks from the menu, and the bookmarks UI Clair leaves out.

### Modified Capabilities

- `browser-window`: "No bookmarks in the interface" is removed. What it still ruled out (the bar, the star, Cmd+D as a bookmark key) moves to `bookmarks`.
- `command-bar`: "Suggestions from Chromium's autocomplete" now includes bookmarks, and "Row icons" shows a bookmark icon for bookmarked pages.

## Impact

- **Engine** (the engine key changes):
  - `clair_window_hooks.mm`: the Bookmarks menu is shown, and its first item is moved to the top and given ⇧⌘B.
  - `clair_native_window.mm`: `ClairIsRemovedCommand` no longer removes `IDC_BOOKMARK_THIS_TAB`. The window's menu validation titles it Bookmark This Page… or Edit Bookmark…, and the window runs it itself, adding to Other Bookmarks and asking `ClairUI` for the bookmark dialog.
  - A new `clair_bookmark_bar_drain.{h,mm}` keeps each profile's Bookmarks Bar empty, moving what lands there to Other Bookmarks.
  - The browser bridge lists the profile's bookmark folders, edits and removes bookmarks, and adds folders.
  - `clair_autocomplete.mm`: stops removing `kBookmark` from the providers, and marks bookmarked rows with the new kind instead of fetching their favicon.
  - A new `patches/clair/bookmarks-menu-root.patch` makes Chromium's `BookmarkMenuBridge` list Other Bookmarks' contents directly in the menu, where it lists the Bookmarks Bar's, with no Bookmarks Bar or Other Bookmarks submenu. No other Chromium file changes.
- **`ClairHost.h`:** additive:
  - a bookmark snapshot (`ClairBookmark`) and a folder snapshot (`ClairBookmarkFolder`);
  - `ClairSuggestionKindBookmark`;
  - `ClairBrowser.bookmarkFolders`, `-updateBookmark:…`, `-removeBookmark:` and `-addBookmarkFolder:`;
  - `-[ClairWindow showBookmarkDialog:]` and `-[ClairWindow showBookmarksBarNotice]`.
- **`ClairUI`:**
  - a `BookmarkDialog` built on `ClairDialog` as it is, and the Bookmarks Bar notice;
  - Manage Bookmarks' title in `MainMenuTitles`.
- **Runtime suite:** new tests cover the menu and its titles, ⇧⌘B and the dialog, and bookmark suggestions, using a seeded `Bookmarks` file in the test profile. The PR runs `quality.yml` on its branch.
- **Users:** bookmarks already in the profile appear in the menu right away. Bookmarks in the Bookmarks Bar move to Other Bookmarks on the first launch, and the Heads Up dialog says so. They stay there if Clair is rolled back, but nothing is lost.
- **Docs:** `docs/native-window.md` (the menu, the dialog and the bridge calls), and a Changie fragment.
