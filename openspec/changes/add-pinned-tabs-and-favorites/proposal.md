# Proposal

## Why

In Arc, people keep the sites they live in as favorites and pinned tabs, and give tabs their own names. Clair's sidebar lists only live tabs, so every tab is temporary and ends with the session. "Pinned tabs, and favorites stored per profile", "reset pinned tab to its URL" and Peek for links to other sites from them are on the MVP list in `ship-plain-ungoogled-build`'s roadmap. Arc stops working on 2026-12-22.

This builds on `add-spaces`, `share-tabs-across-windows`, `add-peek` and `add-profiles`, all merged, as built.

## What Changes

- **A pin is a saved item.** A pinned tab or favorite keeps its pinned URL, page title, icon and any custom name in a store Clair owns, whether or not a page is loaded. A live tab attaches to it while open. Pins come back after every relaunch.
- **Tabs always come back at launch, as in Arc.** Today tabs, and the pages of pinned tabs and favorites that were open, return until the user closes them. Chromium's "On startup" section leaves `chrome://settings`, and a startup choice from a stored preference or an extension is ignored. Which windows come back stays Clair's "restore windows" toggle. Today, "On startup" can still be set to open a new tab page instead.
- **Favorites, per profile.** A grid of tiles above the Space header, laid out as Arc's: up to four tiles across, as few rows as possible, square tiles once a row is full. The favorites stay put when the user switches to another Space of the same profile. A selected favorite's tile turns white with a ring in its icon's colour.
- **Pinned tabs, per Space.** A pinned section between the Space header and a divider, above "New Tab" and the Today tabs. The header's chevron collapses the section, and the active pinned tab stays visible while it's collapsed.
- **Pinning and unpinning.** Cmd+D (Tabs › Pin/Unpin Tab) pins a Today tab at the bottom of the pinned section, and unpins a pinned tab to the top of Today. "Pin to Favorites" in a tab's menu adds a favorite. Dragging moves tabs between Today, the pinned section and favorites, and reorders within each.
- **Closing a pinned tab.** On the selected pinned tab, the row's − button, Cmd+W and Tabs › Close and Keep Pinned unload the page and keep the pin. On any other pinned tab, the × button removes the pin and closes its page. Reopen Closed Tab brings a removed pin back where it was. Clair has no archive: history is the record.
- **Back to the pinned URL.** A pinned tab or favorite navigated away from its pinned URL shows "favicon / current title". Hovering the favicon turns it into a "Back to Pinned URL" button, which loads the pinned URL as a new navigation. The row's menu gains "Edit Pinned Page ›" with "Replace Pinned URL with Current" and "Edit…". The Tabs menu gains Back to Pinned URL.
- **Clear Today.** Hovering the sidebar shows "↓ Clear" on the divider ("Clear Today tabs ⇧⌘K"), which closes every Today tab of the Space. So does Tabs › Clear Today (Shift+Cmd+K).
- **Renaming tabs.**
  - Double-click a Today or pinned tab, or choose Rename…, to edit its title in place. Return keeps the name, Esc cancels, and an empty name brings back the page title. Favorites rename in a "Rename Tab…" dialog.
  - The name stays through navigation, unpinning and relaunches.
  - A renamed tab's tooltip shows only its name; any other tab's tooltip adds "Double-click to rename". The name is also the window's title.
- **Peek for links to other sites.** Following a link to another site from a pinned tab or favorite opens a Peek, as in Arc. Settings › Links gains the toggle "Open a Peek window when clicking on links to other sites", with the note "(Note: This only affects Favorites and Pinned tabs)", on by default.
- **Tab commands over every row.** Next Tab, Previous Tab, Ctrl+Tab and Close Tabs Below cover pinned and Today rows in order. Cmd+1 to Cmd+9 count them too, but not favorites.
- **Incognito and guest windows** show no favorites and no pinned section.
- **BREAKING (`ClairHost.h`):** the host gains pins, favorites, their observer and their calls. A tab gains its pin and its custom name.

**Out of scope:**
- Folders, which come in a later change. The store leaves room for them.
- Arc's Change Icon…, Customize Page… and Live Folders.
- Chromium's own pinned tabs: Clair doesn't use them, so `chrome.tabs` reports no tab as pinned.
- Syncing pins.

## Capabilities

### New Capabilities

- `pinned-tabs`: the saved item behind a pinned tab or favorite and how a live tab attaches to it. Also the pinned section, pinning and unpinning, closing and removing a pin, Back to Pinned URL and editing the pinned URL, and pins after a relaunch.
- `favorites`: the per-profile favorites grid, its layout and states, adding, removing and reordering favorites, and what a favorite does when selected or navigated.
- `tab-names`: renaming a tab, pinned tab or favorite, how long a name lasts, and where it shows (the row, tooltip and window title).

### Modified Capabilities

- `sidebar`:
  - "Sections of the sidebar" and "Today tab menu" are added.
  - "Tab list" lists Today tabs below the pinned section.
  - "Closing, reordering and tab menu" gains dragging between sections.
  - "Tab titles and clicks in tooltips" follows `tab-names`.
  - "An expanded Peek goes below its tab" puts a pinned tab's or favorite's expanded Peek at the top of Today.
- `spaces`:
  - "The next tab among pinned tabs and favorites" is added.
  - "Tabs belong to a Space" excepts favorites' tabs.
  - "Deleting a Space" removes its pinned tabs.
  - "Moving a tab to another Space" moves pinned tabs into the pinned section.
  - "Tab commands follow the Space" covers pinned rows.
- `profiles`: "Pinned tabs and favorites when a Space's profile changes" is added, and "Removing a profile" removes its favorites.
- `peek`: "Links to other sites from pinned tabs and favorites" is added.
- `settings-window`: "Peek on links to other sites toggle" is added.
- `chromium-engine`: "Browser behavior as in ungoogled-chromium outside Clair's interface" lists "On startup" among the absent settings sections.
- `browser-window`:
  - "No bookmarks in the interface" gives Cmd+D to Pin/Unpin Tab.
  - "Tabs restored at launch" is replaced by "Tabs always restored at launch", which always restores tabs, open pins included, and hides "On startup".
  - The window's title is in `tab-names`.

## Impact

- **`native/ClairHost.h`** changes, so the engine key changes and the engine is rebuilt.
- **Overlay:** a new pin store in Local State next to the Space store, holding each item's URL, title, name, cached icon and order. A session tag ties a live tab to its pin, and another keeps a Today tab's name. The tab lists, the next-tab choice, the Tabs menu, Peek's link handling, Space and profile deletion, and session restore all change. A hook makes session restore run at every launch.
- **`ClairUI`:** the favorites grid, the pinned section and its collapse, the divider and Clear, pinned rows and their states, inline rename and the rename dialog, Edit Pinned URL, drag and drop between sections, the new menu items, and the Links toggle. The window title changes too.
- **Runtime suite:** new coverage for pins, favorites and renaming. Views the suite drives change, so the quality checks run on the branch before merging.
- **Arc references:** captured on 2026-11-14 in light and dark for this change. The measurements and behaviours go into `design.md`; the screenshots stay out of git.
