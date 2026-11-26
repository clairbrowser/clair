# Spec Delta

## MODIFIED Requirements

### Requirement: Pinned section
Between the Space header and the "New Tab" row, the sidebar SHALL list the Space's pinned tabs, and its pinned splits as split rows (`split-view`), in the user's order, with the icon and title each had when last open. A pinned tab whose page isn't open SHALL look like one whose page is open and isn't selected. A divider SHALL separate the pinned section from "New Tab" while the Space has Today tabs.

#### Scenario: Pinned and Today tabs
- **WHEN** a Space has the pinned tabs "Mail" and "Docs" and two Today tabs
- **THEN** the sidebar lists "Mail" and "Docs", then a divider, then "New Tab" and the two Today tabs

#### Scenario: A pinned tab not open
- **WHEN** "Mail" is pinned and its page isn't open
- **THEN** its row shows its icon and title, undimmed

#### Scenario: Another Space
- **WHEN** "Mail" is pinned in "Work" and the window shows "Home"
- **THEN** the sidebar doesn't list "Mail"

#### Scenario: A pinned split
- **WHEN** "Work" has the pinned tab "Mail" and then a pinned split of "News" and "Docs"
- **THEN** the pinned section lists "Mail" and then one row holding a "News" chip and a "Docs" chip

### Requirement: Pinned tab menu
A pinned tab's context menu SHALL offer Copy Link, Rename…, Mute or Unmute, Edit Pinned Page ›, Duplicate, Split with Tab › (`split-view`), Move to Space (with more than one Space), Pin to Favorites and Unpin Tab, and no Remove Pin. Copy Link SHALL copy the page's current URL, or the pinned URL while the page is closed. Duplicate SHALL open the same URL as a new Today tab at the top.

#### Scenario: Copy Link on a closed pinned tab
- **WHEN** the pinned tab "Mail" has no open page and the user chooses Copy Link
- **THEN** its pinned URL is copied

#### Scenario: Duplicate
- **WHEN** the user chooses Duplicate on the pinned tab "Docs"
- **THEN** a new Today tab at the top of the list shows the same URL, and "Docs" stays pinned

#### Scenario: The menu's last items
- **WHEN** the user right-clicks a pinned tab
- **THEN** the menu ends with Pin to Favorites and Unpin Tab

#### Scenario: Split with Tab
- **WHEN** the user right-clicks the pinned tab "Mail" and chooses Split with Tab › "News"
- **THEN** the window shows a split of "Mail" and "News", "News" focused
