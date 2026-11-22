# Focus for this run

Edit this file before each review run. It holds what is specific to the moment; the section briefs hold what is always worth checking.

## Where Clair stands

- Clair has not been released. Nobody has data to migrate, so stored formats and the `ClairHost.h` contract may change freely. Do not recommend migrations or compatibility shims.
- Profiles landed recently. Each Space uses one Chromium profile and several Spaces can share one. A window switches between Spaces of different profiles in place, by holding one hidden Chromium browser window for each extra profile.
- Pinned tabs and favourites landed recently. A pin is a saved item in Local State (`clair.pins`) that stays whether or not a page is open: a pinned tab belongs to a Space, a favourite to a profile and shows in every Space of it. A link to another site clicked in a pinned tab opens in a peek, through a navigation throttle. Session restore now always runs. The decisions are in the archived change `add-pinned-tabs-and-favorites`.
- Link rules have just landed, and no review has seen them (archived change `add-link-rules`, `clair/link-rules.patch`). A rule matches a link's URL (contains, exact, or starts with) and opens it in a new tab of a chosen Space, possibly in another profile. Only links handed over by macOS are routed: from other apps, `open` and Handoff. Links clicked inside Clair, the command bar, extensions and session restore never are. The rules are read and replaced as a whole through `ClairHost.h`, and deleting a Space or profile removes its rules. Check how a routed link crosses a profile boundary: what travels with it (referrer, opener, session) and whether a crafted URL can match a rule it shouldn't.
- Arc stops working on 2026-12-22, which is why the remaining features are being built quickly.

## Two features come next

Both are proposed and not built: `openspec/changes/add-page-toolbar/` and `openspec/changes/add-bookmarks-menu/`. Answer these in the "Forward look" part of your report where they touch your section. The aim is to learn, before the features are built, what the current code makes easy and what it makes hard.

**Page toolbar.** A 32 pt toolbar inside the top of the page card, on by default, holding the sidebar toggle, back, forward, reload, the host, pinned extensions, permission indicators and site controls. It reverses change 1's sidebar-only decision, and will become split view's pane header.

- Where does the sidebar's navigation, URL and extension UI live today, and how cleanly could one source of state drive both the sidebar and a toolbar, switched at runtime for every open window?
- Chromium anchors bubbles, the Site Control Center, extension popups, find and infobars to something today. What would it take to anchor them to toolbar controls that move, and what breaks if the page view moves down 32 pt (page-top window dragging, `page-cannot-move-window`)?
- Is there one place where "which header is shown" could be decided, so split view can reuse it?

**Bookmarks menu.** A Bookmarks menu (Bookmark This Page… ⇧⌘B, Manage Bookmarks, then Other Bookmarks and its folders), a Clair bookmark dialog, bookmark suggestions in the command bar, and a Bookmarks Bar that Clair keeps empty by moving its contents to Other Bookmarks in every profile.

- Where would menu items and a dialog that read and write Chromium's `BookmarkModel` per profile go, and what does `ClairHost.h` need to carry?
- Moving bookmarks out of the Bookmarks Bar whenever anything lands there (import, `chrome://bookmarks`, an extension): where can that be observed safely, and what could fight it (sync is off, but extensions and policies remain)?
- What does re-adding `BookmarkProvider` to `ClairChromiumAutocomplete` change for the command bar's ranking and for what a page or extension can learn?

## The freeze list

For anything in your section that becomes expensive to change after the first release (stored data formats, key material, identifiers, entitlements, on-disk layout), say whether it is in a state worth keeping.
