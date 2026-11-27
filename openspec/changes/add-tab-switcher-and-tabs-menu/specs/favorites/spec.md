## MODIFIED Requirements

### Requirement: Favorite menu
A favorite's context menu SHALL offer, with a divider between each group: Remove Favorite; Copy Link and Duplicate; Split with Tab › (`split-view`); Rename…, Mute or Unmute, and Edit Pinned Page › (`pinned-tabs`); Close Tab while its page is shown. Hovering a tile SHALL show no button.

#### Scenario: The shown favorite's menu
- **WHEN** the window shows "Mail" and the user right-clicks its tile
- **THEN** the menu offers Remove Favorite, a divider, Copy Link, Duplicate, a divider, Split with Tab, a divider, Rename…, Mute, Edit Pinned Page, a divider and Close Tab

#### Scenario: A favorite that isn't shown
- **WHEN** the window shows another tab and the user right-clicks the tile of "Mail"
- **THEN** the menu ends with Edit Pinned Page, with no Close Tab

### Requirement: Leaving a favorite's site
From a favorite, a URL the user enters in the command bar or URL field that is on another site (another scheme or host, as for Peeks in `peek`) SHALL open in a new Today tab at the top, leaving the favorite's page as it was. A URL on the same site SHALL load in the favorite. A favorite's page in a split (`split-view`) SHALL load either in its pane. A favorite's page navigated away from its pinned URL SHALL offer Edit Pinned Page › Back to Pinned URL in its menu (`pinned-tabs`).

#### Scenario: Another site from the URL field
- **WHEN** the window shows the favorite "Mail" at `https://mail.example.com/` and the user enters `https://news.example.org/` in the URL field
- **THEN** a new Today tab at the top shows `https://news.example.org/`, and "Mail" keeps its page

#### Scenario: The same site
- **WHEN** the user enters `https://mail.example.com/settings` there instead
- **THEN** "Mail" loads it

#### Scenario: Another site in a favorited split's pane
- **WHEN** the window shows a favorited split of "Mail" and "Calendar", with "Mail" focused, and the user enters `https://news.example.org/` in the command bar
- **THEN** "Mail"'s pane loads `https://news.example.org/`, and no Today tab opens
