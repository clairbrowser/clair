# Design

## Context

See proposal.md for why and `specs/browser-import/spec.md` for the behavior.

**Chromium's importer** (`chrome/browser/importer`, `chrome/utility/importer`) reads, on macOS, Safari's `~/Library/Safari/Bookmarks.plist` (bookmarks only, behind Full Disk Access) and Firefox. It has no Chromium-to-Chromium importer, knows nothing of Spaces, pins or favorites, and `ProfileWriter::AddBookmarks` writes into the Bookmarks Bar, which Clair empties with a "Heads Up" dialog (`bookmarks`). It's reached from the Clair menu's "Import Bookmarks and Settings…" (`IDC_IMPORT_SETTINGS`, built in `main_menu_builder.mm`) and from `chrome://settings`.

**What the sources keep**, read on this Mac on 2026-11-27 (Arc 1.170, Dia 1.58.2, Safari 26; Chrome isn't installed here):

- **Arc**, `~/Library/Application Support/Arc/`:
  - `StorableSidebar.json`: `sidebar.containers[1]` holds `items`, `spaces` and `topAppsContainerIDs`, each a flat array alternating an ID and its object. A Space has `title`, `customInfo.iconType.emoji_v2`, `profile` (`{"default": true}` or `{"custom": {"_0": {"directoryBasename": "Profile 6"}}}`) and `containerIDs` alternating `"pinned"`/`"unpinned"` with an item container's ID. An item has `parentID`, ordered `childrenIds`, a `title` (the custom name) and `data` with one key: `tab` (`savedURL`, `savedTitle`), `list` (a folder), `splitView` (`layoutOrientation` `horizontal`/`vertical`, `itemWidthFactors` alternating a pane's ID and its share for every pane but the last) or `itemContainer`. Favorites are the `topApps` container of each profile.
  - `User Data/`: a Chromium user data folder. `Local State`'s `profile.info_cache` names the profiles ("Your Arc", "Work"). Each profile has `History`, `Favicons`, `Preferences`, `Secure Preferences`, and `Bookmarks` only once someone has used `arc://bookmarks`.
- **Dia**, `~/Library/Application Support/Dia/User Data/`: a Chromium user data folder whose `Local State` names one entry per Chromium profile ("Profile 2 (sharing data with 3)"). Each profile's `tabs.db` is SQLCipher 4 (raw 32-byte key, 4096-byte pages ending in a 16-byte IV and a 64-byte HMAC, page 1 starting with the 16-byte KDF salt) and keeps recent commits in `tabs.db-wal`. Decrypted:
  - `spaces` (`id`, `title`, `theme`): Dia's "profiles", several sharing one Chromium profile.
  - `nodes` (`id`, `kind`, `entity_id`, `parent_id`, `order`, `deleted_at`, `space_id`): per Space a `favorites`, a `pinned_container` (both created lazily) and one `window` per window. A `tab` holds one `content_pane`, or two or more for a split (`tabs.split_view_widths`, a JSON array); a `group` (`tab_groups.title`) is a folder.
  - `content_panes.custom_title`, `web_contents.url`/`title`.
  - Deleting a window marks only its node deleted; its children stay, orphaned.
  - Dia's own export (Settings › Advanced › Tabs › Export Data) is Markdown without titles, names, splits, or a pinned/Today distinction, and with folders whose end can't be told, so it isn't used.
- **Safari**: its own files need Full Disk Access. File › Export Browsing Data to File… writes a .zip with `Bookmarks.html` (Netscape format, the Favorites bar as a folder, the Reading List as one), `History.json` (`history[]` with `url`, `title`, `visit_count`, last visit time) and, if chosen, passwords and cards, which Clair ignores.
- **Chrome**, `~/Library/Application Support/Google/Chrome/`: a Chromium user data folder, as Arc's `User Data/`, with `Local State`'s profile names and each profile's `Bookmarks` (and `AccountBookmarks` when signed in), `History`, `Favicons`, `Preferences` and `Secure Preferences`. Each profile's `Sessions/Session_<time>` files are Chromium's own session commands (SNSS), whose windows hold tabs with their navigations, `pinned`, `group` and `split_id`, and split visual data with a `split_ratio`. None of what Clair imports is encrypted, so no keychain item is read.

**Prior art:** Cra (MIT, `VictorKildahl/cra`, `Sources/Cra/Services/Import/`) imports from these and other browsers. Its `DiaSidebar.swift` documents Dia's key derivation, which a spike on this Mac confirmed against Dia 1.58.2. Cra flattens splits, copies extensions' folders and loads them unpacked, and decrypts Dia's database to a temporary file; Clair does none of those (D5, D8). Dia's own importer (`dia-reference/`) takes Safari's .zip and primes the user for a keychain prompt.

**Clair today:** Spaces (`ClairSpaceStore`), pins, folders, pinned splits and favorites (`ClairPinStore`) live in Local State; Today tabs are Chromium tabs tagged with their Space (`clair_space_session`). `ClairHost.h` already creates Spaces and profiles; nothing writes pins, history or extensions in bulk.

## Goals / Non-Goals

**Goals:**
- One import pipeline that the import dialog and a later onboarding dialog share.
- Sources added as data, not code paths: another Chromium-based browser (Brave, Edge, Vivaldi) needs a descriptor, an icon and a fixture.
- Parsing, the part that breaks when a source changes, in `ClairUI`, where unit tests run in CI in minutes without an engine build.

**Non-Goals:**
- Passwords, cookies, sign-ins, autofill and payment methods: Clair has no password manager, and cookies would need each source's encryption key.
- Arc's archive, Easels, Notes, Boosts, Little Arc, Space colours and themes; Dia's chats and skills.
- Firefox, Zen and other non-Chromium browsers besides Safari.
- Safari's pinned and open tabs, tab groups and extensions: they need Full Disk Access, and Safari's extensions aren't Chrome extensions.
- Chrome's tab groups as groups: Clair's Today tabs hold no folders (`tab-folders`).
- Turning a bookmarks bar into favorites: favorites hold no folders, so the bar's structure would be lost.
- Undoing an import.

## Decisions

### D1. Sources read in `ClairUI`, the engine writes

```
ClairUI/Import/                                    unit-tested with fixtures
  ImportSource ── ChromiumFamilySource(descriptor) ─┬─ ArcSidebarReader
             │                                      └─ DiaSidebarReader
             └── SafariExportSource
        │ makePlan()
        v
  ImportPlan (Codable) ──> ImportCoordinator ──> ImportFlow (steps, state)
                                │                    │
                                │                    └─ ImportDialog (views); later onboarding
                                v ClairHost.h: -applyImportPlan:progress:completion:
engine/overlay/chrome/browser/clair/clair_importer.{h,mm}
  profiles, Spaces, pins, favorites, Today tabs, bookmarks, history, favicons, extensions
```

Each source's file formats are read in Swift. The engine receives a neutral plan and writes it through Clair's stores and Chromium's services, which only it can reach.

**Alternatives:** Chromium's importer framework with new `user_data_importer` types (patches to Chromium's enums and utility process for each source, and its parsing tests need an engine build); everything in `ClairUI` through many new contract methods (bookmarks, history and extensions have no `ClairHost.h` surface, and bulk writes over Objective-C objects would be slow and wide).

### D2. Sources

`ImportSource` gives an ID, a display name, the app icon (from the bundle ID through `NSWorkspace`, falling back to a bundled image), whether it's present, the items it brings (the second step's list), what it needs first (nothing, an export file with its steps, or a keychain item with its notice), and `makePlan(destinations:)`.

`ChromiumFamilySource` takes a descriptor: name, bundle ID, user data folder, and an optional sidebar reader with its keychain service. It reads `Local State`'s profiles and, per profile, bookmarks, history, favicons and extensions (D7). Arc's and Dia's descriptors add their sidebar readers (D4, D5); Chrome's adds its session (D13). Brave, Edge or Vivaldi would be descriptors like Chrome's, session included.

`SafariExportSource` (D6) takes the file the user chooses.

Chrome's descriptor: bundle ID `com.google.Chrome`, user data folder `~/Library/Application Support/Google/Chrome`, no keychain item.

Presence: Arc when `StorableSidebar.json` exists, Dia when its `Local State` lists a profile with a `tabs.db`, Chrome when its `Local State` lists a profile, Safari always.

### D3. The plan crosses the contract as JSON

`ImportPlan` is `Codable` and goes to the engine as UTF-8 JSON with `"version": 1`:

```
{ "version": 1, "source": "arc", "sourceName": "Arc",
  "folder": "<the import's private folder>" | null,
  "profiles": [ {
      "sourceKey": "Profile 6", "sourceName": "Work",
      "destination": { "profile": "<Clair profile ID>" } | { "newProfile": "Work" },
      "spaces": [ { "name": "Space 3", "icon": "😀" | null,
                    "pinned": [<item>], "today": [<item>] } ],
      "favorites": [<item>],
      "bookmarks": <folder tree> | null,
      "history": { "chromiumDB": "<temp path>" } | { "safariJSON": "<temp path>" } | null,
      "favicons": { "chromiumDB": "<temp path>" } | null,
      "session": { "chromiumSessions": "<temp folder>", "space": "Person 1" } | null,
      "extensions": [ { "id", "name", "enabled", "pinned", "manifest" } ],
      "skipped": [ { "reason", "name" } ] } ] }

<item> = { "tab": { "url", "title", "name"? } }
       | { "split": { "panes": [<tab>, <tab>], "ratio": 0.5 } }
       | { "folder": { "name", "children": [<item>] } }
```

`folder` names the private folder (D10), which the engine removes when the import ends; `manifest` is the installed version's manifest as JSON text (D8 step 8); `skipped` lists what the reader left out, which the summary lists before the engine's own skips. Bookmarks travel in the plan (small); history and favicons travel as paths to private copies (D7), since they can hold hundreds of thousands of rows. Splits of three or more panes become tabs in the plan, stacked splits plain splits, and nested folders top-level folders named with their path (`Parent / Child`, after their parent; a folder holding only folders dropped), in one shared pass over every reader's tree, so the engine sees only what Clair can show (`browser-import`, "Splits from an import"). A split's `ratio` is the leading pane's share: Arc's first `itemWidthFactors` share, Dia's first `split_view_widths` entry normalised to the sum.

The contract gains one method on `ClairHost`, with progress (a fraction and a phase name) and a completion carrying the summary as JSON (counts per item kind, and skips with a reason code and the item's name or URL). The fake host in `ClairUITests` records the plan, which is where most unit tests assert.

**Alternatives:** Objective-C protocol objects per item (many new protocols for one call, and every source change would touch the contract); a file path to the plan (one more temporary file).

### D4. Arc's sidebar reader

Parses `StorableSidebar.json` with `JSONSerialization`, pairing the alternating arrays. For each Space: its profile's folder (`default` is `Default`), name and emoji; its pinned and unpinned containers walked through `childrenIds`, so items in no container are ignored. `tab` items give `savedURL`, `savedTitle` and `title` as the custom name; `list` gives a folder; `splitView` gives a split of its children in order. Favorites: each `topAppsContainerIDs` entry's container, keyed by the profile it names. Items whose `data` is another kind (Easels, notes) are skipped and reported.

No keychain item is needed.

### D5. Dia's sidebar reader

**Key:** the "Dia Safe Storage" password, read with `SecItemCopyMatching` only once the user clicks Import, so macOS's prompt names Clair. The root key is PBKDF2-HMAC-SHA1 of it, salt `saltysalt`, 1003 rounds, 16 bytes, as Chromium's. Each database's key is HKDF-SHA256 of the root key with salt `HMAC-SHA256(k, label)` and info `label`, where `label` is `profile/<profile folder>/tabs` and `k` is the 32-byte constant Cra found in Dia's binary, credited in the source and `CREDITS.md`.

**Decryption in memory:** read `tabs.db` and `tabs.db-wal`, fold in the WAL's committed frames of its current salt, decrypt each page with AES-256-CBC (CommonCrypto), and check that page 1 now has SQLite's header. The plaintext is opened with `sqlite3_deserialize` from the system SQLite, so no decrypted copy ever touches the disk. The key and plaintext are zeroed after use.

**Walk:** from each Space's live root nodes (`favorites`, `pinned_container`, every `window`) down by `parent_id` in `order`, skipping `deleted_at` rows, so orphans of deleted windows never come over. A `tab` with one pane is a tab, with two a split, with more its panes as tabs; a `group` is a folder.

**Mapping:** each Dia Chromium profile is a plan profile whose Spaces are the `spaces` rows; its row label joins their names. Favorites of every Space go to the profile's favorites, de-duplicated by URL. Dia's Space colours are dropped.

A wrong key, a denied prompt or an unexpected schema yields no sidebar, and the summary says so; the rest of the profile still imports (`browser-import`, "Dia's privacy note").

**Alternatives:** Dia's Markdown export (lossy, see Context); decrypting to a temporary file as Cra does (plaintext on disk); SQLCipher as a dependency (a package the owner would rather not add, for one read).

### D6. Safari's export

The chosen .zip unpacks with `/usr/bin/ditto -x -k` into the import's private folder (D10); a folder is read in place. `Bookmarks.html` parses as Netscape bookmarks: the contents of the "Favorites" folder (Safari's Favorites bar) come first, then the file's other top-level items, and the "Reading List" is dropped. `History.json` goes to the engine by path. A file with neither is refused with the spec's error. Its one plan profile is "Safari".

### D7. Chromium-family profile data

- **Bookmarks:** `Bookmarks` (and `AccountBookmarks` when present) parse as Chromium's JSON in Swift into one list: the bar's children, then the other bookmarks' and the mobile bookmarks' children, as Clair's own bar drain orders them (`clair_bookmark_bar_drain`).
- **History and favicons:** the source has quit before Import (D14), so its databases are at rest. Each is still copied with its `-wal` and `-journal` into the import's private folder, so nothing reads or locks the source's own files, and the engine opens the copy with `sql::Database`. It opens it read-write, not read-only: the copy is private and thrown away, and SQLite can roll back a hot journal or fold in a log only with write access. The engine runs SQLite's `quick_check` on each copy first, as `ClairUI` does on Dia's decrypted database; a copy that fails it is skipped and reported in the summary, never read in part.
- **Extensions:** the union of `extensions.settings` in `Preferences` and `Secure Preferences`. Kept: `location` 1 (internal) with `from_webstore` true, whose manifest isn't a theme or an app; turned on unless `disable_reasons` holds a reason other than Chrome's unsupported-manifest-version one; pinned when in `extensions.pinned_extensions`. Others are listed as skipped in the plan.

### D8. The engine writes the plan

`clair_importer` runs one plan at a time, on the UI thread for the stores and on a blocking task runner for reading the copies:

1. **Profiles:** each `newProfile` is created as `ClairHost`'s Create Profile is, with " 2", " 3" added until the name is free.
2. **Spaces:** a Space named like one in the destination profile receives the import; others are created after the existing ones.
3. **Pins, folders, pinned splits and favorites:** through `ClairPinStore`, at the end of their section, folders closed. Each pin's icon comes from the source's favicons for its URL.
4. **Today tabs:** created in the Space's window group like session restore's background tabs, with their navigation entry set and their page not loaded until selected, below the existing Today tabs; splits through the split code with their ratio.
5. **Bookmarks:** through `BookmarkModel`, appended to Other Bookmarks as they are, never into the Bookmarks Bar, so the Heads Up dialog doesn't show. A folder named like one at the same place merges into it.
6. **History:** read from the copy's `urls` table (or Safari's JSON) in batches, written with `ProfileWriter::AddHistoryPage` (`HistoryService::AddPagesWithDetails`), which keeps title, visit count and typed count and adds one visit at the last visit time.
7. **Favicons:** for the imported URLs, from the copy's `favicons` and `icon_mapping`, with `ProfileWriter::AddFavicons`.
8. **Extensions:** `WebstoreInstaller`, as Clair's restored store uses it, downloads each ID from the Chrome Web Store, with an `InstallApproval::CreateWithNoInstallPrompt` built from the manifest of the version the user installed in the source and a loose manifest check, and no post-install UI: no prompt shows, and the install fails, reported as one the store couldn't provide, if the store's version asks for more permissions than that one. Once installed, its enabled state and pin are set. The summary waits for them, each install counting in the progress. `WebstoreStandaloneInstaller` isn't used: its first step fetches the item's snippet with Google's API key, which ungoogled-chromium builds don't have.

**Repeat imports:** an item is skipped when its URL is already in the same favorites, Space section or folder, and a bookmark when its URL is in the same folder, after same-named folders merge. A history page is skipped when the destination's history already has a visit to its URL at or after the source's last visit, looked up in its visits (not the page's `last_visit`, which `AddPagesWithDetails` doesn't update for an existing page) on the history thread before each batch is written; otherwise `AddPagesWithDetails` adds the source's last visit as a visit to the existing page, so a newer visit is never lost and a repeated one never doubled. Clair stores nothing about past imports: repeat imports rely on these comparisons alone.

### D9. The flow and the dialog

`ImportFlow` is an observable state machine (choose source → items, destinations and the source's requirement → importing → summary) that knows nothing of the window. `ImportDialog` presents it in a `ClairDialog` with the new stepped layout (`dialogs`, "Stepped dialogs"): Cancel at the leading corner, Back and the default button at the trailing one, the card's width fixed across steps. The onboarding dialog will host the same flow and step views in its own frame. The Clair menu item is added by `ClairUI` where Chromium's "Import Bookmarks and Settings…" stood, after Clear Browsing Data…, and shows the dialog on the frontmost window through the existing dialog queue. With no window open, it sends Chromium's New Window command and shows the dialog on the window that opens. (The Clair menu has no Set as Default Browser item, which the proposal's placement assumed; Settings › General has the default browser setting.)

Step 1's cards are a two-column grid of rounded, bordered cards with the app icon at 40 points, the name in the system font and a trailing radio, the selected card's border in the accent colour. Clair's own type and spacing are used throughout; Dia's serif title, full-width black button and painted artwork are not.

### D10. Privacy

Each import gets a private folder in the user's temporary directory, mode 0700, for the copies and the unpacked .zip; it's removed when the import ends, and any left by a crash are removed at the next launch. Dia's plaintext never touches the disk (D5). Before Import, Clair reads only what finding sources and labelling their profiles needs (`Local State`, Arc's `StorableSidebar.json` existing, Dia's `tabs.db` existing) and the Safari file the user chooses, to check it; everything else, and the keychain, waits for Import. Clair writes nothing to a source, and makes no network request but the Chrome Web Store downloads.

### D11. Hiding Chromium's import menu item

A patch, `clair/hide-import-menu-item.patch`, removes the Clair menu's `IDC_IMPORT_SETTINGS` item in `main_menu_builder.mm` (a `.remove_if`), so "Import from Another Browser…" is the menu's only import item. Chromium's importer itself stays, reachable from `chrome://settings`. A patch is the clean way here: Chromium builds the item whether or not a window is open.

**Alternative:** adding `IDC_IMPORT_SETTINGS` to `ClairIsRemovedCommand` hides it only while a native window is key.

### D13. Chrome's tabs come from Chromium's own session reader

Chrome's session format is Chromium's, so the engine reads it with Chromium's code rather than a Swift parser: the plan names a private copy of the profile's `Sessions` folder (D7, D10), and `clair_importer` reads its newest session with `sessions::CommandStorageBackend` (no encryptor) and turns the commands into windows with `sessions::RestoreSessionFromCommands`. In window order, each window's `pinned` tabs go to the end of the profile's Space's pinned section, pinned at their current navigation's URL with its title, and the others become Today tabs (D8 step 4). The two tabs sharing a `split_id` become a Clair split with the split's `split_ratio`, pinned or Today as Chrome had them; Chrome's splits hold two tabs, as Clair's do. `group` is ignored, so a group's tabs stay in place. The Space is named after the Chrome profile.

**Alternatives:** parsing SNSS in Swift, as Cra does (a second reader of a format Chromium already reads, which would drift as Chrome adds commands); reading Chrome's `Current Session`/`Last Session` legacy names (Chrome writes `Sessions/` now).

### D14. The source quits before Import

Copying a database while its browser writes it can tear the copy, and Chromium holds `History` locked while running. So while the source app runs (`NSRunningApplication` for the descriptor's bundle ID), `ImportFlow` replaces Import with "Quit <browser>", which sends the app `terminate()`, the polite quit its own Quit command makes, and watches `NSWorkspace.didTerminateApplicationNotification`; a launch notification turns the button back. The app's own confirmations, such as Arc's or Chrome's warning about closing windows, still apply.

**Alternatives:** reading a running source (torn or locked copies, D7); forcing it to quit (lost state in the source); asking the user to quit it themselves with no button (one more trip out of the dialog).

### D12. Testing

- `ClairUITests`: fixtures for Chrome (a `Local State`, `Bookmarks` with bar, other and nested folders, `Preferences`/`Secure Preferences` with a store, an unpacked and a disabled extension, and a `Sessions` folder that the plan passes by path), Arc (a trimmed `StorableSidebar.json` and `Local State` with nested folders, a renamed pin, splits of two, three and stacked panes, two profiles), Dia (a `tabs.db` encrypted by the test with a known secret, with an orphan, a WAL frame and a split) and Safari (a .zip whose Favorites hold a bookmark and a folder, with a Reading List and `History.json`), asserting the plans; and the flow's steps and defaults against the fake host.
- `tests/runtime/`: an `ImportTests` class that imports each fixture into a fresh profile through the dialog, then checks the sidebar, Bookmarks menu, history and summary over the DevTools protocol and XCUITest. A `CLAIR_TEST_IMPORT_ROOT` environment variable points the sources at the fixtures, and `CLAIR_TEST_DIA_SECRET` replaces the keychain read; both are honoured only with the test switches the suite already uses. Extension installs are checked with one small store extension.

## Risks / Trade-offs

- [Dia changes its database or key scheme, as it did in 1.55] → The reader validates the schema and reports Dia's sidebar as unreadable, importing everything else; a fixture test pins the format, and fixing it is a `ClairUI` change without an engine build.
- [Arc's JSON changes] → Arc is in maintenance, so it's unlikely; unknown item kinds are skipped and reported.
- [The keychain prompt reads "Clair wants to use your confidential information stored in 'Dia Safe Storage'", which can alarm] → The second step explains it before Import (spec wording), as Dia's own importer does.
- [Installing extensions without a prompt grants their permissions silently] → Only Chrome Web Store extensions the user already installed in the source, into the profile the user chose; the summary lists them.
- [A source the user reopens during the import could write while Clair copies] → The copies are checked with `quick_check` and skipped with a note when torn (D7).
- [Large histories take time] → Batched writes with progress; the dialog shows the phase.
- [Chrome stops writing clear session files] → Chrome's `EncryptSessionStorage` feature now writes both `Sessions` and `Sessions_Encrypted` and reads the clear one; a later stage writes only the encrypted one, whose key is "Chrome Safe Storage". Then Chrome's tabs couldn't be read without that keychain item, and the summary would say Chrome's tabs couldn't be read; bookmarks, history and extensions still import.
- [History older than 90 days] → `AddPagesWithDetails` drops visits history would expire; the import counts only the pages it writes.
- [Imported Today tabs could be many] → They're created unloaded.

## Migration Plan

None: nothing existing is converted, and Chromium's importer stays in Settings.

## Open Questions

- ~~Which `history::VisitSource` Arc's and Dia's visits use.~~ Decided: History, its page and the command bar's providers treat every source alike but `SOURCE_ACTOR` (only `GetUniqueDomainsVisited`'s locally-visited list counts `SOURCE_BROWSED` alone), so Safari's visits are `SOURCE_SAFARI_IMPORTED` and Arc's, Dia's and Chrome's `SOURCE_OS_MIGRATION_IMPORTED`, the generic source Chromium's own `StablePortabilityDataImporter` uses for another browser's history.
- Whether a Safari export with several Safari profiles holds one profile per file, and so whether a .zip ever needs more than one row.
