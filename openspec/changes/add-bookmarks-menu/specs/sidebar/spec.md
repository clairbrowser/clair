# Spec Delta

## MODIFIED Requirements

### Requirement: Today tab menu
A Today tab's context menu SHALL offer Copy Link, Rename…, Duplicate, Mute or Unmute, Pin Tab, Pin to Favorites, Add to Bookmarks… or Remove Bookmark (`bookmarks`), Move to Space (`spaces`), Close Tab and Close Tabs Below. Close Tabs Below SHALL close only the Today tabs below it.

#### Scenario: Today tab's menu
- **WHEN** there is one Space and the user right-clicks a Today tab's row whose page isn't bookmarked
- **THEN** the menu offers Copy Link, Rename…, Duplicate, Mute, Pin Tab, Pin to Favorites, Add to Bookmarks…, Close Tab and Close Tabs Below

#### Scenario: Close Tabs Below leaves pinned tabs
- **WHEN** the user chooses Close Tabs Below on the first Today tab of a Space with pinned tabs
- **THEN** the Today tabs below it close, and the pinned tabs stay
