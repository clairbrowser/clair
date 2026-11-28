# Proposal

## Why

People switching to Clair come from Arc, Dia or Safari with months of Spaces, pinned tabs, favorites, history and extensions, and Clair can't bring any of it over. Chromium's own importer, which Clair still ships, reads only Safari's bookmarks and Firefox on macOS, knows nothing of Spaces, pinned tabs or favorites, and puts what it imports in a Bookmarks Bar Clair doesn't have.

## What Changes

- **Import from Another Browser…:** a new item in the Clair menu opens Clair's own import dialog on the frontmost window. It replaces Chromium's "Import Bookmarks and Settings…".
- **Sources:** Arc, Dia, Safari and Chrome, shown only when present on the Mac.
  - **Arc** brings favorites, pinned tabs with their folders, Today tabs, splits, Spaces with their emoji icons, bookmarks, history and extensions, read from Arc's own files.
  - **Dia** brings the same, its "profiles" becoming Spaces. Its sidebar is encrypted, so the import reads the "Dia Safe Storage" key from the keychain, after the user allows it, only to read Dia's data on this Mac.
  - **Safari** brings bookmarks and history from the .zip Safari's File › Export Browsing Data to File… makes. Clair asks for no Full Disk Access.
  - **Chrome** brings, per Chrome profile, a Space with its last session's pinned and open tabs, bookmarks, history and extensions.
  - A bookmarks bar (Chrome's, or Safari's Favorites) comes over as a bookmarks folder, keeping its folders, never as Clair favorites.
- **Two steps:** the first picks the browser; the second lists what will come over and, for each of the source's profiles, which Clair profile receives it, an existing one or a new one. Dia's second step says the data stays on the Mac; Safari's explains the export and takes the .zip. A summary with counts and anything skipped ends the import.
- **Splits** come over as Clair splits with their widths. Splits of three or more panes come over as separate tabs in pane order, since Clair's splits hold two.
- **Repeat imports** skip what the destination already has, and merge into a Space of the same name.
- **Chromium's importer is turned off:** `chrome://settings/importData`, its row in Settings and its menu item are gone. Manage Bookmarks keeps importing a bookmarks HTML file.
- **Reuse:** the import is built apart from its dialog, so a later onboarding dialog can offer it, and so more Chromium-based browsers (Brave, Edge, Vivaldi) can be added as sources without engine changes.
- `arc-reference/clair-menus.md`'s decision to leave out "Import from Another Browser" is reversed.

## Capabilities

### New Capabilities

- `browser-import`: importing another browser's data into Clair: the menu item, the dialog's steps, what each source brings and from where, choosing destination profiles, how Spaces, pins, splits, bookmarks, history and extensions land, repeat imports, the summary, and the privacy of a Dia import.

### Modified Capabilities

- `dialogs`: adds a stepped dialog layout, with Cancel at the bottom leading corner and Back beside the default button.
- `bookmarks`: the Bookmarks Bar import scenario now covers a bookmarks file imported in Manage Bookmarks, since Chromium's importer is gone.
- `app-identity`: the keychain requirement allows reading another browser's storage key during an import the user started, never creating or changing it.
- `chromium-engine`: `browser-import` joins Clair's own capabilities, Settings loses its import row, and hooks may turn Chromium's importer off.

## Impact

- `native/ClairUI/Import/` (new): the sources (a Chromium-family reader with Arc's and Dia's sidebar readers, Safari's export reader), the import plan, the coordinator and the dialog, with unit tests and fixtures.
- `native/ClairHost.h`: **BREAKING** for the contract only: an import entry point that applies a plan and reports progress. The engine key changes, so it needs an engine build.
- `engine/overlay/chrome/browser/clair/`: a `clair_importer` that writes Spaces, pins, splits, favorites and Today tabs through Clair's stores, bookmarks and history through Chromium's services, and installs extensions from the Chrome Web Store.
- `engine/patches/clair/`: a patch that turns off Chromium's importer and its settings page and row; the menu item is hidden by ClairUI.
- `tests/runtime/`: import tests against fixture copies of Arc, Dia, Safari and Chrome data.
- `CREDITS.md` and `licenses/`: Cra (MIT), whose work showed how Dia's sidebar is encrypted.
- A Changie fragment (user-facing).
