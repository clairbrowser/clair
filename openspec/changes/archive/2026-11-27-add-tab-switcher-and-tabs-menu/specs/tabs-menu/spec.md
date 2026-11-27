## Purpose

The menu bar's Tabs menu holds Clair's commands for the shown tab and the Space's tabs, in place of Chromium's Tab menu, with the items and shortcuts the owner chose after Arc's.

## ADDED Requirements

### Requirement: Tabs menu items
The menu bar SHALL have a Tabs menu just before the Window menu, offering, with a divider between each group:
- Pin Tab (⌘D), Pin to Favorites and New Folder…
- Next Tab (⌥⌘↓) and Previous Tab (⌥⌘↑)
- Split with Tab › and Move to Space ›
- Clear Unpinned Tabs (⇧⌘K)

It SHALL offer nothing else.

#### Scenario: The items
- **WHEN** the user opens the Tabs menu
- **THEN** it offers Pin Tab, Pin to Favorites, New Folder…, a divider, Next Tab, Previous Tab, a divider, Split with Tab, Move to Space, a divider and Clear Unpinned Tabs

### Requirement: Chromium's Tab menu is gone
The menu bar SHALL have no Chromium Tab menu, and none of its items, such as Move Tab to New Window, Search Tabs or Close Tabs to the Right, SHALL appear elsewhere in it. Their shortcuts SHALL do nothing unless Clair gives them another meaning.

#### Scenario: The menu bar
- **WHEN** the user looks at the menu bar of a browser window
- **THEN** it has a Tabs menu and no Tab menu

### Requirement: Acting on the shown tab
The Tabs menu's items SHALL act on the main browser window and its shown tab, as `pinned-tabs`, `favorites`, `tab-folders`, `split-view` and `spaces` define for the same commands. Without a browser window, every item SHALL be disabled.

#### Scenario: Pin Tab
- **WHEN** the window shows the Today tab "Mail" and the user chooses Tabs › Pin Tab
- **THEN** "Mail" becomes the last pinned tab, as Cmd+D does

#### Scenario: No window
- **WHEN** no browser window is open and the user opens the Tabs menu
- **THEN** every item is disabled

### Requirement: Pin items
Pin Tab SHALL read Unpin Tab on a pinned tab, and SHALL be disabled on a favorite. Pin to Favorites SHALL make the shown Today or pinned tab the last favorite, as Pin to Favorites in its menu does, and SHALL be disabled on a favorite. Both, and New Folder…, SHALL be disabled in incognito and guest windows.

#### Scenario: On a pinned tab
- **WHEN** the window shows a pinned tab and the user opens the Tabs menu
- **THEN** the first item reads Unpin Tab, and Pin to Favorites is enabled

#### Scenario: On a favorite
- **WHEN** the window shows a favorite
- **THEN** Pin Tab and Pin to Favorites are disabled

### Requirement: Move to Space submenu
Tabs › Move to Space › SHALL list every Space but the shown one, in the switcher's order, each with its icon, and move the shown tab there as a tab's Move to Space does (`spaces`). It SHALL be disabled with one Space, on a favorite, and in incognito and guest windows.

#### Scenario: Moving the shown tab
- **WHEN** the window shows "Docs" in "Home", and the user chooses Tabs › Move to Space › "Research"
- **THEN** the window shows "Research" with "Docs" first in its list and active

#### Scenario: One Space
- **WHEN** there is one Space
- **THEN** Tabs › Move to Space is disabled

### Requirement: Clear Unpinned Tabs
Tabs › Clear Unpinned Tabs (⇧⌘K) SHALL close the shown Space's Today tabs as the sidebar's Clear does (`pinned-tabs`), and SHALL be disabled while the Space has none.

#### Scenario: Clearing
- **WHEN** "Work" has two pinned tabs and three Today tabs, and the user presses Shift+Cmd+K
- **THEN** the three Today tabs close, and the two pinned tabs stay
