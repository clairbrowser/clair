# Spec Delta

## MODIFIED Requirements

### Requirement: Removing a pin
On a pinned tab that isn't selected, hovering its row SHALL show an × button with the tooltip "Remove Pin", which removes the pinned tab and closes its page if open. Restore Last Closed Tab SHALL bring a removed pinned tab back pinned, at its place.

#### Scenario: × on a pinned tab
- **WHEN** the user clicks × on the pinned tab "Docs", which isn't selected
- **THEN** "Docs" leaves the pinned section and its page closes

#### Scenario: Bringing it back
- **WHEN** the user removed "Docs", second of three pinned tabs, and chooses Restore Last Closed Tab
- **THEN** "Docs" is pinned second again, with its pinned URL

### Requirement: Pinned tab menu
A pinned tab's context menu SHALL offer Copy Link, Rename…, Mute or Unmute, Edit Pinned Page ›, Duplicate, Move to Space (with more than one Space), Pin to Favorites and Unpin Tab, and no Remove Pin. Copy Link SHALL copy the page's current URL, or the pinned URL while the page is closed. Duplicate SHALL open the same URL as a new Today tab at the top.

#### Scenario: Copy Link on a closed pinned tab
- **WHEN** the pinned tab "Mail" has no open page and the user chooses Copy Link
- **THEN** its pinned URL is copied

#### Scenario: Duplicate
- **WHEN** the user chooses Duplicate on the pinned tab "Docs"
- **THEN** a new Today tab at the top of the list shows the same URL, and "Docs" stays pinned

#### Scenario: The menu's last items
- **WHEN** the user right-clicks a pinned tab
- **THEN** the menu ends with Pin to Favorites and Unpin Tab
