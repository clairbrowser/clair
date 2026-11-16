# Spec Delta

## MODIFIED Requirements

### Requirement: Pinned tab menu
A pinned tab's context menu SHALL offer Copy Link, Rename…, Mute or Unmute, Edit Pinned Page ›, Duplicate, Move to Space (with more than one Space), Pin to Favorites, Unpin Tab, Remove Pin, and Add to Bookmarks… or Remove Bookmark (`bookmarks`). Copy Link SHALL copy the page's current URL, or the pinned URL while the page is closed. Duplicate SHALL open the same URL as a new Today tab at the top.

#### Scenario: Copy Link on a closed pinned tab
- **WHEN** the pinned tab "Mail" has no open page and the user chooses Copy Link
- **THEN** its pinned URL is copied

#### Scenario: Duplicate
- **WHEN** the user chooses Duplicate on the pinned tab "Docs"
- **THEN** a new Today tab at the top of the list shows the same URL, and "Docs" stays pinned

#### Scenario: Bookmark item after the pin items
- **WHEN** the user right-clicks the open pinned tab "Docs", whose page is bookmarked
- **THEN** Remove Bookmark follows Remove Pin
