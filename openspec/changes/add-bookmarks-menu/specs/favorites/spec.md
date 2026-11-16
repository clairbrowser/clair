# Spec Delta

## MODIFIED Requirements

### Requirement: Favorite menu
A favorite's context menu SHALL offer Copy Link, Rename…, Mute or Unmute, Edit Pinned Page › (`pinned-tabs`), Duplicate, Close Tab while its page is shown, Remove Favorite, and Add to Bookmarks… or Remove Bookmark (`bookmarks`). Hovering a tile SHALL show no button.

#### Scenario: The shown favorite's menu
- **WHEN** the window shows "Mail", whose page isn't bookmarked, and the user right-clicks its tile
- **THEN** the menu offers Copy Link, Rename…, Mute, Edit Pinned Page, Duplicate, Close Tab, Remove Favorite and Add to Bookmarks…
