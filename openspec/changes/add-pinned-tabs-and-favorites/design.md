# Design

"`add-spaces` D*n*", "`share-tabs` D*n*", "`add-peek` D*n*" and "`add-profiles` D*n*" below are decisions in those changes' archived `design.md`.

## Context

See proposal.md, "Why". What shapes the approach:

- **Clair's tab list is live tabs only.**
  - `ClairSpaceTabs`, one per profile, keeps an ordered list of tab handles per Space across the profile's browsers (`add-spaces` D2).
  - Session restore and Reopen Closed Tab put each tab back through two session tags, `clair_space` and `clair_order`, plus `clair_window` (`add-spaces` D6, `add-profiles` D6). `patches/clair/space-session.patch` hooks the rebuild, `browser_live_tab_context.cc` and `CreateRestoredTab`.
  - Spaces live in Local State (`ClairSpaceStore`, `clair.spaces`).
- **The rest of the earlier changes stay in place:**
  - The shown-Space invariant (`add-spaces` D3) and the came-from rule for the next tab (`add-spaces` D4).
  - Tab commands over the rows (D5).
  - Takes and stills across windows (`share-tabs` D1, D2).
  - Reopening tabs in another profile (`add-profiles` D9).
- **Peeks open through hooks.**
  - Shift+click opens a Peek through `clair::MaybeOpenPeek` in `browser_web_contents_delegate.cc`, which reads `ClairWindow.opensPeekOnShiftClick` for each link.
  - A plain link click that navigates in place never reaches those delegate calls.
  - `ClairPeeks::Expand` turns a Peek into a tab directly below its parent.
- **"On startup" decides whether tabs come back at all.**
  - Chromium's session restore brings back windows and their tabs together, and runs only when the profile's `session.restore_on_startup` says "continue where you left off".
  - `add-spaces` D11 made that the default through `clair::RegisterProfilePrefOverrides`, except in headless mode, but left the setting changeable in `chrome://settings`, and extensions can override startup pages.
  - Which windows come back is Clair's own `ClairRestoreWindows` toggle, applied after Chromium's restore (`add-profiles` D6).
  - Arc has no setting to start without tabs. Clair has no users yet, so nothing needs migrating.
- **Cmd+D and the window title:**
  - Cmd+D is `IDC_BOOKMARK_THIS_TAB`, which `ClairIsRemovedCommand` hides with its key equivalent.
  - `ClairBrowserWindow::UpdateTitleBar` sets the `NSWindow` title from Chromium's title for the current tab.
- **Arc's behaviour, measurements and storage keys were recorded on 2026-11-14,** in light and dark (Arc's own dark Space theme), with `tests/probe/`. What design needs is summarised under "Arc reference" below. The screenshots are not in git: the probe writes to `build/probe/`.

## Goals / Non-Goals

**Goals:**
- Pins outlive their tabs and the session, as data Clair owns, with no Chromium concept of pinning.
- One model for pinned tabs and favorites, which differ only in where they're kept and shown.
- Leave room for folders in the store's format.
- Hooks only in Chromium files: the throttle registration, the restore command, the session tags and the title.

**Non-Goals:**
- Chromium's `TabStripModel` pinning, `chrome.tabs`' `pinned` field, and bookmarks.
- Changing icons, Live Folders, split view.
- Sync.

## Arc reference

Observed in Arc 1.17x on 2026-11-14, sidebar 228 pt. All sizes are in points.

**Geometry**

| Element | Measurement |
|---|---|
| Rows | 40 tall on a 41 pitch; favicon 18×18 at x=17; title from x=43; hover button 26×26 at x=189 |
| Second line ("Back to Pinned URL", "Double-click to rename") | 16 tall, at the title's y+17 |
| Space header to first pinned row | 3 |
| Divider | a 17-tall row with a 0.5 hairline from x=18 to 210, shortened while "↓ Clear" shows |
| Clear | a 12×9 arrow plus text, at the trailing end of the divider |
| Navigated pinned tab | the favicon becomes a 38×38 button at x=7; the title moves to x=45 after a grey "/" |
| Rename field | x=41, 19 tall: 170 wide from Rename…, 144 from a double-click because the × stays |
| Favorites grid | below the URL field; 8 inset and 8 gaps; tiles 47 tall; height 63, 118 or 173 for 1, 2 or 3 rows |
| Favorites columns | rows = ceil(n/4), columns = ceil(n/rows): tiles 212, 102, 65.3 or 47 wide (47 is square) |
| Empty favorites box | dashed accent border on a light accent tint, 105.5 tall: a star in an accent circle, "Drag to add Favorites" in bold, "Favorites keep your most used sites and apps close", and a dismiss × at the top-trailing corner. The owner reports that Arc never shows it again once it's dismissed or a favorite has been added |

**Colours, against Arc's default Space theme (RGB)**

| Surface | Light | Dark |
|---|---|---|
| Sidebar background | 232 229 248 | 41 41 61 |
| Active pill | 245 244 246 | about 88 86 101 |
| Hover pill | 221 218 236 | 62 62 80 |
| Hovered × or − | 207 203 219 | 78 78 95 |
| Favorite tile, idle | 216 216 238 | 63 62 82 |
| Favorite tile, hover | 206 205 227 | 73 72 92 |
| Favorite tile, selected | 245 245 249, with a 2 pt ring in the favicon's main colour | about 149 149 157, with the same ring |
| Divider hairline | 198 195 210 | 79 73 90 |

Clair's sidebar has its own material, not Arc's themes, so D11 maps these as contrasts against the sidebar, not as fixed colours.

**Behaviours**

- **Pinning:** Cmd+D pins at the bottom of the pinned list with about a 100 ms slide, and unpins to the top of Today.
- **Hover button:** − ("Close and Keep Pinned ⌘W") on the selected pinned tab; × ("Archive this tab", which removes the pin) on any other. Cmd+Shift+T brought a removed pin back in place.
- **Closed pinned tabs** look exactly like open ones, with the favicon from the last load.
- **Collapse:** the chevron turns from ˅ to ›, the rows clip away in about 130 ms, and the active pinned tab stays visible.
- **Rename:**
  - The field is in place, borderless, on the row's pill. Double-click puts the caret where it clicked; Rename… selects all.
  - Return keeps, Esc cancels, and an empty name restores the title. The placeholder is the page title.
  - The name survives navigation and unpinning.
  - The tooltip shows the name alone; an unrenamed tab's shows the title plus "Double-click to rename".
  - The window title is the name.
  - Favorites rename in a 450×222 sheet: "Rename Tab…", placeholder "Keep it short and sweet!", Cancel ESC and Rename ↩.
- **Edit Pinned URL sheet:** a large favicon, "Edit Pinned URL", "This is what opens first when you click this tab or its favicon.", a URL field with its text selected and the placeholder "Enter a URL…", and Cancel and Save.
- **Storage:** the custom name is the item's top-level `title`; `savedURL` and `savedTitle` stay at the pinned page while the tab is navigated away; favorites live in one `topApps` container per profile; order is `childrenIds`.

## Decisions

### D1. Pins live in Local State, beside the Spaces

A new `ClairPinStore` (`overlay/chrome/browser/clair/clair_pin_store.{h,mm}`) keeps every pin in one Local State pref, registered through `clair::RegisterLocalStatePrefs` like `clair.spaces`:

```
clair.pins  { "version": 1,
              "spaces":   { "<space uuid>":  ["<pin uuid>", …] },   // pinned tabs, in order
              "profiles": { "<profile dir>": ["<pin uuid>", …] },   // favorites, in order
              "items":    { "<pin uuid>": { "url":   "https://…",   // the pinned URL
                                            "title": "…",           // the page title at the pinned URL
                                            "name":  "…",           // custom name, absent if none
                                            "parent": "" } } }      // reserved for folders; always "" now
```

- **Icons go in files,** `<user data dir>/Clair Pin Icons/<pin uuid>.png`, at most 64 × 64 px. The engine writes one on a background sequence when a bound tab (D2) at its pinned URL gets a new favicon, and deletes it with the pin. Snapshots load it lazily and cache it.
- **Why Local State:** it's where the Spaces are, for the reasons `add-spaces` D1 gives. A pinned tab refers to a Space and a favorite to a profile directory, both of which Local State already holds. Deleting a Space or profile drops its entry in the same store (D9).
- **Why not Chromium's favicon database:** it belongs to a profile's history, which "Clearing history" empties, and favorites must keep their icons.
- **Alternative: pins as Chromium tabs, discarded when closed.** Rejected because a pin would vanish with a failed or skipped session restore, such as headless mode or a guest session, and every pin would cost a tab.
- **Alternative: per-profile prefs.** Rejected because pinned tabs belong to Spaces, which are app-wide.

### D2. A live tab binds to its pin

- **Binding:** a tab showing a pin's page carries the pin's UUID as `WebContents` user data, and in a third session tag, `clair_pin`, written and read where `clair_space` is (`add-spaces` D6).
- **One tab per pin.** Opening a pin that already has a tab selects that tab: it takes it into this window if another window shows it (`share-tabs` D1), or shows the window's still of it.
- **The pin's lifetime is the store's.** A bound tab closing for any reason (Cmd+W, the − button, `window.close()`, an extension, its window closing) unbinds the pin and leaves it in place. Only Remove Pin, Remove Favorite, unpinning, deleting the Space and removing the profile change the store.
- **Lists:**
  - `ClairSpaceTabs` keeps a bound pinned tab out of the Space's Today list and lists it with its pin, in the pin's order.
  - A bound favorite's tab is in no Space: `ClairSpaceTabs` holds it in a per-profile favorites list.
  - `add-spaces` D3's invariant becomes: a browser's active tab belongs to its shown Space, or is a favorite's tab of its profile.
- **Title and icon:** the pin's `title` and icon follow the bound tab only while it is at its pinned URL. A tab is at its pinned URL when its last committed entry's URL, or the entry's original request URL (so a redirect counts), equals the pinned URL, ignoring the fragment.
- **Names:** a pinned tab's or favorite's custom name is the record's `name`. A Today tab's is a fourth session tag, `clair_name`. Pinning moves the name into the record; unpinning or dragging out moves it back to the tag.

### D3. Restoring pins

- **At launch:** the store is read before any window opens, so every pin is listed even before session restore finishes. Session restore always runs (D12). A restored tab whose `clair_pin` names a pin with no tab binds to it. A tab whose pin is gone, or already bound, joins the Today list of its `clair_space`, keeping its name. Every other pin starts unbound.
- **New tab pages:** a restored bound tab at the new tab page is dropped with the others (`add-profiles` D6), leaving its pin unbound.
- **Removed pins:** `ClairPinStore` keeps the last 25 removed records in memory, each with its container, its index and the time it was removed.
  - A hook at the start of `IDC_RESTORE_TAB`, in `browser_command_controller.cc`, compares the newest removal with the newest `TabRestoreService` entry.
  - When the removal is newer, it puts the record back at its index and stops. A pin that had no tab comes back that way, with nothing to reopen.
  - Otherwise Chromium restores the entry. If the restored tab carries the `clair_pin` of a removed record, the record goes back first, and the tab binds to it.
  - The memory goes with the session, as Chromium's own recently-closed list does for windows that never saved.
- **Alternative: a synthetic `TabRestoreService` entry for a pin with no tab.** Rejected, because the service builds entries from live tabs only, and faking one needs more patching.

### D4. Opening, closing and the next tab

- **Opening:** `openPin:inBrowser:` selects the bound tab, or creates a tab in the window's browser at the pinned URL, binds it and activates it. For a pinned tab the new tab joins the Space shown; for a favorite, the favorites list.
- **Closing:** − and Cmd+W close the bound tab through Chromium's close flow, so leave-page prompts apply. The next tab is chosen by `add-spaces` D4, over rows of open tabs, pinned rows first and then Today. Unbound pins are skipped. A favorite counts as a came-from tab but not as a row.
- **Tab commands:** `add-spaces` D5's rows become every pin of the Space, bound or not, then the Today tabs. Cmd+N or Ctrl+Tab landing on an unbound pin opens it. Favorites are never rows. Ctrl+Shift+PageUp/Down reorders within the row's own section.
- **Clear Today** closes the Space's Today tabs in every window through the close flow, as Close Tabs Below does, and leaves every bound pin alone.

### D5. Pinning, unpinning and moving

- **Contract calls** (D10):
  - `pinTab:atIndex:` and `favoriteTab:atIndex:` create a record from the tab, with its current URL, title, icon and `clair_name`, and bind the tab to it.
  - `unpinTab:atIndex:` deletes the record and returns the tab, opening it at the pinned URL if unbound, to the Today list at the index, with its name in `clair_name`.
  - `movePin:toSpace:atIndex:` and `movePin:toFavoritesAtIndex:` move a record between containers, carrying its bound tab between the Space and favorites lists.
  - Indices are positions in the destination section, so drags and Cmd+D go through the same calls.
- **Move to Space** of a pinned tab moves the record to the bottom of the destination's pinned section, then moves the bound tab, if any, with `add-spaces` D7. Across profiles, `add-profiles` D9 reopens the tab, keeping its `clair_pin`.
- **A Space's profile changing** (`add-profiles` D9) keeps its pinned records. Bound tabs reopen in the new profile with their `clair_pin`. Bound favorites of the old profile are untouched, since they belong to the profile, not the Space.

### D6. Back to Pinned URL and editing it

- **Back to Pinned URL** loads the pinned URL in the bound tab as a new browser-initiated navigation with `PAGE_TRANSITION_AUTO_BOOKMARK`, so it adds a history entry and Back returns.
- **Replace Pinned URL with Current** copies the tab's last committed URL and title, and its icon, into the record.
- **Edit…** sets the URL. The dialog's Save is enabled when `url_formatter::FixupURL` of the field gives a valid http(s), file or chrome URL; the fixed-up URL is what's saved.
- **Snapshots:** `ClairPin.isAtPinnedURL` (D2's rule) drives the row's "/" and the Tabs menu item's enabled state.

### D7. Peeks for links to other sites

A new `ClairPinnedLinkThrottle` (`overlay/chrome/browser/clair/window/clair_pinned_link_throttle.{h,mm}`) is added to every navigation by a one-line hook in `chrome_content_browser_client_navigation_throttles.cc`. In `WillStartRequest` it cancels the navigation and opens a Peek of its tab with the URL, through `ClairPeeks::OpenURL`, when all of these hold:

- the navigation is in the primary main frame, renderer-initiated, with a user gesture, and not same-document, a reload or a history navigation;
- its page transition's core type is `PAGE_TRANSITION_LINK`;
- its tab is bound to a pin (D2);
- the tab's native window reports `opensPeekForOtherSites` (D10);
- the destination's scheme differs from the current page's, or `net::registry_controlled_domains::SameDomainOrHost` with private registries is false for the two.

A link opening a new tab or window never reaches it as a navigation of this tab, so Cmd-click and Shift+click keep their behaviour.

- **Why a throttle:** a plain link click that stays in the tab goes straight to the renderer's navigation and never reaches `OpenURLFromTab`, where `MaybeOpenPeek` sits.
- **Why "site" and not host:** an app that spans subdomains (mail and docs of one service) should stay in its pin, and Chromium's site is the standard boundary for that. Whether Arc compares sites or hosts is checked in task 3.10; if Arc uses hosts, the spec and this decision change before merging.

**Leaving a favorite's site:** when the command bar or URL field opens a URL in the current tab and that tab is a favorite's, the engine opens it as a new foreground Today tab instead if it is on another site, by the same test.

**Expanding a Peek** of a pinned tab or favorite puts the new tab at the top of Today, not below its parent: `ClairPeeks::Expand` asks `ClairSpaceTabs` for the insertion point, which is the top for a bound parent.

### D8. The window title and names

- **Window title:** `ClairBrowserWindow::UpdateTitleBar` uses the active tab's custom name (record or `clair_name`) when it has one. Setting a name calls it for each window showing the tab.
- **Page and Chromium titles:** the `WebContents` title is never changed, so pages, history and extensions see the page's title.
- **Duplicate** copies neither `clair_pin` nor `clair_name`.

### D9. Space and profile removal

- **Deleting a Space** drops its `spaces` entry, its records and their icons. The bound tabs close with the Space's other tabs (`add-spaces` D7's delete flow). The confirmation counts open tabs and pinned tabs as tabs that will go.
- **Removing a profile** (`add-profiles`) drops its `profiles` entry and its records and icons.
- **Removed records aren't kept for Restore Last Closed Tab** in either case: the user confirmed.

### D10. The contract (`native/ClairHost.h`)

- **A new snapshot, `ClairPin`:** `pinID`, `isFavorite`, `spaceID` (pinned tabs) or `profileID` (favorites), `url`, `title`, `name` (nullable), `icon` (nullable), `tabID` (`ClairTabIDNone` when unbound) and `isAtPinnedURL`.
- **`ClairTab` gains** `pinID` (nullable) and `name` (nullable): the custom name, from the record for a bound tab.
- **The host gains:**
  - `pinsInSpace:` and `favoritesOfProfile:`;
  - the D5 calls;
  - `openPin:inBrowser:`, `removePin:`, `returnToPinnedURL:`, `replacePinnedURLWithCurrent:` and `setPinnedURL:forPin:`;
  - `setName:forTab:` and `setName:forPin:`, where nil or empty clears the name;
  - `clearTodayInSpace:`.
- **Lists:** `tabsInSpace:` keeps returning the Space's tabs, now Today tabs only, Peeks following parents. Bound tabs reach `ClairUI` through their pins' snapshots, which carry `tabID`, and through `spaceTabDidChange:` for their state.
- **`ClairSpacesObserver` gains** `pinsDidChangeInSpace:` and `favoritesDidChangeForProfile:`, coalesced per run-loop turn like the rest.
- **`ClairWindow` gains** `opensPeekForOtherSites`, read for each link as `opensPeekOnShiftClick` is, backed by the user default `ClairPeekForOtherSites`, registered as true.

This is a breaking change to the contract, so the engine key changes.

### D11. `ClairUI`

- **`SpacesModel`** caches pins per Space and favorites per profile next to tabs, and notifies listeners. `BrowserWindowModel` copies the window's Space's pinned rows and its profile's favorites, as it does tabs.
- **`SidebarView`'s `TabList`** becomes the sections, in order: favorites grid, Space header, pinned section, divider, New Tab, Today.
  - Rows stay `TabRow`, which gains a pinned style: the − or × button by selection, the "/" with the navigated title, and the favicon button with the "Back to Pinned URL" line on hover.
  - The divider is a new view with Clear, shown on sidebar hover while Today has tabs.
- **`FavoritesGrid`:** a pure layout function in `FavoritesLayout.swift` gives rows, columns and tile frames for a count and width, unit-tested with Arc's table. Tiles carry the hover and selected states, the selected ring's colour (the favicon's most saturated dominant colour, computed once per icon), and the Peek badge from `PeekBadge`. The empty box shows with a dismiss ×.
- **Colours:** tiles, hover pills and the selected tile are expressed against `SidebarFill`, as the existing pills are. Light uses black overlays; dark uses white ones, at the contrasts Arc's colours give against its background (idle tile about 7%, hover about 11%, selected near-white). Tune them by hand against Arc with the probe in both appearances.
- **Rename:** the in-place field reuses `SpaceHeaderView`'s editing pattern: one field, a commit on Return, cancel on Esc, and a cancel when focus leaves. A double-click on a row sets the caret from the click; Rename… selects all. The favorite dialog and Edit Pinned URL are `ClairDialog`s with Arc's wording.
- **Drag and drop:** one drag source for rows and tiles carries the tab or pin ID. Drop targets compute the section and index, show the insertion (tiles making room in the grid, the gap in lists) and call D5.
- **Persistent preferences:** the collapse state is the user default `ClairCollapsedPinnedSpaces` (Space IDs). This per-Space rule is unverified: Arc saves the state per window (`spacesWithCollapsedPinnedSections` in `StorableWindows.json`). Task 3.10 checks whether a collapse shows in Arc's other windows and survives a relaunch, and the spec and this key follow what Arc does. The empty-favorites box is `ClairFavoritesHintDone` (profile IDs): a profile joins it when its box is dismissed or it gets its first favorite, and never leaves it. Per profile, so a new profile shows the box once; task 3.10 checks whether Arc shows it for a new profile, and if it doesn't, the key becomes one app-wide flag.
- **Settings › Links** gains the second toggle, bound to `ClairPeekForOtherSites`.
- **Menus:**
  - The tab, pinned and favorite context menus as the specs list.
  - Main menu items inserted by `InstallNativeWindowMenus` into Chromium's Tab menu: Pin Tab (Cmd+D), Back to Pinned URL, Close and Keep Pinned and Clear Today (Shift+Cmd+K). View › Collapse Pinned Tabs is inserted after Hide Sidebar.
  - Each item uses `ClairSidebarMenuTarget`'s pattern: Clair tags, actions sent to the key `ClairWindow`, which validates titles and enabled states.
  - Cmd+D leaves `ClairIsRemovedCommand`'s hidden bookmark item and moves to Pin Tab.

### D12. Session restore always runs

Clair restores tabs at every launch, as Arc does:

- **The hook:** `SessionStartupPref::GetStartupPref(const PrefService*)`, in `session_startup_pref.cc`, ends with a call to `clair::ApplyStartupPref`, which sets the type to `LAST`, except in headless mode. Guest sessions never reach it, as Chromium already returns `DEFAULT` for them first.
- **What it covers:** a value the user stored, startup pages an extension sets through `chrome_settings_overrides`, and anything else that writes `session.restore_on_startup`. All of them read through that call.
- **Settings:** the `page_visibility.ts` hunk of `native-window-hook.patch` sets `onStartup: false`, so `chrome://settings` has no "On startup" section.
- **The old default** in `clair::RegisterProfilePrefOverrides` goes, since the hook replaces it.
- **Windows are unchanged:** which windows come back stays `ClairRestoreWindows` (`add-profiles` D6).
- **Why a hook and not only the default and a hidden section:** an extension's startup pages and a policy would still turn restore off, with no visible setting left to explain it.
- **Alternative: `--restore-last-session`.** Rejected, for `add-spaces` D11's reason: it would break the headless commands.

## Risks / Trade-offs

- **[A redirecting pin looks navigated away]** A pinned URL that redirects (to a sign-in, or to `/u/0/`) would show "/" at once. → D2 counts the entry's original request URL. Task 3.10 checks Arc on a redirecting pin and a single-page app that rewrites its path; if Arc ignores path changes within the site, `isAtPinnedURL` follows it.
- **[Peek on every link out of an app]** Sign-in and payment flows hop sites with real link clicks. → Only renderer-initiated link clicks with a gesture peek; redirects, form posts and scripts without a gesture don't. The toggle turns it off.
- **[Local State grows with pins]** A few hundred bytes per record, written through Chromium's pref writer with its batching. → Icons are files, not prefs.
- **[Icon files outlive a crash mid-delete]** → At start-up, `ClairPinStore` deletes icon files whose pin isn't in the store.
- **[`ClairSpaceTabs` gets a third kind of list]** Space lists, bound pinned tabs and favorites. → The came-from rule, takes and stills are written against tab handles, not lists. The runtime suite covers closes across sections and windows (task 3.12).
- **[Extensions don't see pins]** `chrome.tabs` reports `pinned: false`, and an extension pinning a tab through Chromium does nothing visible. → Accepted; recorded in the proposal's out of scope.
- **[An older Clair after a downgrade]** It ignores `clair.pins` and the new tags, so bound tabs come back as ordinary tabs and pins are invisible but kept. → Acceptable for a pre-1.0 app; the store is versioned.

## Migration Plan

- **Nothing to migrate.** An existing profile starts with no pins and no favorites, and its tabs come back as Today tabs.
- **Rollback** is the downgrade case above.
