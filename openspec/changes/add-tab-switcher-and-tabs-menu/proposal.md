# Proposal

## Why

In Clair, Ctrl+Tab still steps through the sidebar's rows in order, as Chromium's Next Tab does. In Arc it goes back to the tab used last, with a switcher showing the five most recent tabs while Ctrl is held. People coming from Arc expect Ctrl+Tab to return to the previous tab. The menu bar's Tab menu is also still Chromium's: it is called "Tab", mixes Chromium items that mean nothing in Clair (Move Tab to New Window, Search Tabs, Close Tabs to the Right…) with Clair's own items, and its tab context menus have grown one item at a time with no sections. The owner gave the target layouts for both.

## What Changes

- **Ctrl+Tab switcher, as in Arc** (probed on 2026-11-26, `arc-reference/`):
  - Pressing Ctrl+Tab shows a panel over the window with the window's five most recently used tabs, the shown tab first. Each tab is a card with a preview of its page, its favicon and its title. The second card is selected.
  - While Ctrl is held, each Tab selects the next card and each Shift+Tab the previous one, wrapping at the ends. Ctrl+Shift+Tab opens the panel with the last card selected.
  - Releasing Ctrl shows the selected tab, clicking a card shows that card's tab, and Esc closes the panel without switching. A quick Ctrl+Tab returns to the previous tab without showing the panel: as in Arc, it appears only once Ctrl has been held for about 100 ms, or at once on a second Tab.
  - Recents span the window's Spaces, as in Arc, and include favorites and pinned tabs while their page is open. Choosing a tab of another Space switches the window to that Space. A split is one card showing both pages, labelled with both favicons. A tab leaves the list when its page closes.
  - The panel appears, moves its selection and closes with no animation, as in Arc.
  - Opt+Cmd+Down and Up (Next Tab and Previous Tab) and Cmd+1 to 9 still step through the sidebar's rows.
- **Clair's Tabs menu replaces Chromium's Tab menu,** which is deleted. It lists, in sections:
  - Pin Tab (⌘D), Pin to Favorites and New Folder…
  - Next Tab (⌥⌘↓) and Previous Tab (⌥⌘↑)
  - Split with Tab › and Move to Space ›
  - Clear Unpinned Tabs (⇧⌘K)

  Chromium's items leave the menu bar. Clair's Back to Pinned URL and Close and Keep Pinned leave it too: they stay on the row's icon, the − button and Cmd+W.
- **Tab context menus in sections.** A Today tab's menu becomes:
  - Pin Tab and Pin to Favorites
  - Copy Link and Duplicate
  - Split with Tab › and Move to Space ›
  - Rename… and Mute or Unmute
  - Close Tab and Close Tabs Below

  Pinned tabs and favorites get the same sections and order with their own items: Unpin Tab and Remove Favorite in place of the pin items, and Edit Pinned Page › kept. The split row's menu keeps Separate Tabs in place of Split with Tab ›.
- **BREAKING (`ClairHost.h`):** the browser gains page previews for tabs and a call that shows a tab in any of the window's Spaces.

**Out of scope:**
- Arc's other menu bar menus, and View, File and Edit, which keep their items.
- A setting to turn the switcher off or make Ctrl+Tab step through the sidebar.

## Capabilities

### New Capabilities

- `tab-switcher`: Ctrl+Tab's switcher: the recents list and what it holds, the panel, its cards and previews, the keys, and choosing a tab.
- `tabs-menu`: the menu bar's Tabs menu: its items, their order, shortcuts and when each is enabled, and Chromium's Tab menu leaving the menu bar.

### Modified Capabilities

- `sidebar`: "Today tab menu" takes the new sections and order.
- `pinned-tabs`:
  - "Pinned tab menu" takes the new sections.
  - "Closing a pinned tab keeps it pinned" and "Navigated away from the pinned URL" lose their Tabs menu items.
  - "Clear Today" is renamed Clear Unpinned Tabs in the Tabs menu, and the sidebar's Clear button's tooltip reads "Clear unpinned tabs".
  - "Editing the pinned URL" adds Back to Pinned URL to Edit Pinned Page ›, so a favorite navigated away still has it.
  - "No pins in private windows" drops the removed items.
- `favorites`:
  - "Favorite menu" takes the new sections.
  - "Leaving a favorite's site" points to Edit Pinned Page › Back to Pinned URL instead of the Tabs menu.
- `spaces`: "Tab commands follow the Space" no longer covers Ctrl+Tab, which follows `tab-switcher`.
- `peek`: "Tab shortcuts treat a tab and its Peek as one" covers the switcher, and names Next and Previous Tab's current shortcuts.
- `split-view`:
  - "Tab commands treat a split as one row" covers the switcher.
  - "The split row's menu" places Separate Tabs in its section.

## Impact

- **`native/ClairHost.h`** changes, so the engine key changes and the engine is rebuilt.
- **Engine:** the engine copies a tab's page as it stops being shown, as it copies the still, and keeps one preview per tab. A new browser call shows a tab in another of the window's Spaces. Chromium's Tab menu is deleted at start-up, and Clair's handling of commands only it sent goes: Select Next/Previous Tab, Close Tabs to the Right, Close Other Tabs, Duplicate Tab and Move Tab to New Window for Peeks, and the hiding of its Search Tabs, Group and Split items.
- **ClairUI:** a recents list per window, the switcher panel, a key monitor for Ctrl+Tab, `TabsMenu` in place of every customization of Chromium's Tab menu (`PinsMenu` hiding Chromium's pin items and adding Clair's, `SplitMenu` adding Split with Tab), and the context menus in `PinsLogic`.
- **Tests:** ClairUI unit tests for recents, the switcher's keys and the menus. The runtime suite's checks of the Tab menu and the context menus change with them.
