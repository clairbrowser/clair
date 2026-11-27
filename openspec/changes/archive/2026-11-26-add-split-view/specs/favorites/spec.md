# Spec Delta

## MODIFIED Requirements

### Requirement: Favorites grid
Favorites SHALL show as tiles of equal size between the URL field and the Space header, each with the page's icon centred, in rows of at most four. A favorited split SHALL take one tile (`split-view`). The grid SHALL take as few rows as that allows, and as few columns as those rows allow. Tiles SHALL be 47 points tall and share the sidebar's width, less 8 points at the edges and between tiles.

#### Scenario: One favorite
- **WHEN** a profile has one favorite
- **THEN** one tile fills the row

#### Scenario: Five favorites
- **WHEN** a profile has five favorites
- **THEN** they show in two rows of three columns, the second row holding two tiles at its leading edge

#### Scenario: Eight favorites
- **WHEN** a profile has eight favorites and the sidebar is at its default width
- **THEN** they show in two rows of four square tiles

#### Scenario: A favorited split
- **WHEN** a profile's favorites are a split of two pages and one other favorite
- **THEN** the grid shows two tiles, each half the row

### Requirement: Favorite menu
A favorite's context menu SHALL offer Copy Link, Rename…, Mute or Unmute, Edit Pinned Page › (`pinned-tabs`), Duplicate, Split with Tab › (`split-view`), Close Tab while its page is shown, and Remove Favorite. Hovering a tile SHALL show no button.

#### Scenario: The shown favorite's menu
- **WHEN** the window shows "Mail" and the user right-clicks its tile
- **THEN** the menu offers Copy Link, Rename…, Mute, Edit Pinned Page, Duplicate, Split with Tab, Close Tab and Remove Favorite

### Requirement: Leaving a favorite's site
From a favorite, a URL the user enters in the command bar or URL field that is on another site (another scheme or host, as for Peeks in `peek`) SHALL open in a new Today tab at the top, leaving the favorite's page as it was. A URL on the same site SHALL load in the favorite. A favorite's page in a split (`split-view`) SHALL load either in its pane. A favorite's page navigated away from its pinned URL SHALL keep Back to Pinned URL in the Tabs menu (`pinned-tabs`).

#### Scenario: Another site from the URL field
- **WHEN** the window shows the favorite "Mail" at `https://mail.example.com/` and the user enters `https://news.example.org/` in the URL field
- **THEN** a new Today tab at the top shows `https://news.example.org/`, and "Mail" keeps its page

#### Scenario: The same site
- **WHEN** the user enters `https://mail.example.com/settings` there instead
- **THEN** "Mail" loads it

#### Scenario: Another site in a favorited split's pane
- **WHEN** the window shows a favorited split of "Mail" and "Calendar", with "Mail" focused, and the user enters `https://news.example.org/` in the command bar
- **THEN** "Mail"'s pane loads `https://news.example.org/`, and no Today tab opens
