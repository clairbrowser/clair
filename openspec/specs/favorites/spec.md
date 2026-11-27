# favorites Specification

## Purpose
Favorites keep a profile's most used sites as tiles at the top of the sidebar, as in Arc, the same in every Space of that profile. A favorite is a saved item like a pinned tab, and stays whether or not its page is open.

## Requirements

### Requirement: Favorites belong to a profile
Each profile SHALL have its own favorites, in the user's order. A window SHALL show the favorites of the profile its Space uses, the same in every Space of that profile. A favorite SHALL keep its pinned URL, page title, icon and custom name whether or not its page is open, as a pinned tab does (`pinned-tabs`).

#### Scenario: Two Spaces of one profile
- **WHEN** "Home" and "Travel" use the profile "Personal", which has the favorites "Mail" and "Calendar", and the user switches from "Home" to "Travel"
- **THEN** the sidebar shows "Mail" and "Calendar" in both, unchanged

#### Scenario: A Space of another profile
- **WHEN** the user switches to "Work", which uses the profile "Work" with the favorite "Tracker"
- **THEN** the sidebar shows "Tracker" and not "Mail" or "Calendar"

#### Scenario: A favorite's open page across Spaces
- **WHEN** the user opens "Mail" in "Home" and then clicks it in "Travel"
- **THEN** the same page shows, without reloading

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

### Requirement: Favorite tile states
A tile SHALL be tinted against the sidebar, darker under the pointer in Light Mode and lighter in Dark Mode. The tile of the favorite whose page the window shows SHALL turn white in Light Mode, or light grey in Dark Mode, with a 2-point ring in its icon's main colour. No other row SHALL be highlighted while it's shown.

#### Scenario: Selecting a favorite
- **WHEN** the user clicks the tile of a favorite whose page isn't open
- **THEN** its pinned URL loads, its tile shows as selected, and no tab row is highlighted

#### Scenario: Dark Mode
- **WHEN** the system is in Dark Mode and a favorite is selected
- **THEN** its tile is light grey with the ring

### Requirement: Adding favorites
Pin to Favorites in a Today or pinned tab's menu SHALL make the tab the last favorite of its profile, keeping its page, its selection and its name; the tab leaves its list. Dragging a Today or pinned tab onto the grid SHALL add it where it's dropped, the tiles making room as it moves over them.

#### Scenario: Pin to Favorites
- **WHEN** the user chooses Pin to Favorites on the active Today tab "Mail"
- **THEN** "Mail" becomes the last favorite, still showing its page, and leaves the Today tabs

#### Scenario: Dragging onto the grid
- **WHEN** a profile has two favorites and the user drags a Today tab between them
- **THEN** it becomes the second of three favorites

### Requirement: A drag over the favorites shows the tile
While a Today tab, pinned tab or favorite is dragged over the favorites grid, the "Drag to add Favorites" box or the drop zone, the drag SHALL show the tile it would become, as in Arc: the size of the slot it would take, or a square tile over the drop zone, with its icon. Leaving the grid, box or zone SHALL bring back the drag's own image. A drop there, or above the Space header while the zone can open, SHALL be a move: the pointer SHALL show no "+".

#### Scenario: Over the grid
- **WHEN** a profile has one favorite and the user drags a Today tab over the grid
- **THEN** the favorite shrinks to half the row, the drag shows a half-row tile with the tab's icon, and the pointer shows no "+"

#### Scenario: Over the empty box
- **WHEN** a profile has no favorites, the box shows, and the user drags a Today tab over it
- **THEN** the box highlights, and the drag shows a tile as wide as the box

#### Scenario: Over the drop zone
- **WHEN** the drop zone is open and the user drags a Today tab over it
- **THEN** its border turns solid, its contents fade, and the drag shows a square tile with the tab's icon

#### Scenario: Leaving the favorites
- **WHEN** the user drags a Today tab over the grid and then back over the Today tabs
- **THEN** the drag shows the tab's row again

#### Scenario: Dropping on the box
- **WHEN** a profile has no favorites and the user drops a pinned tab on the box
- **THEN** it becomes the profile's only favorite, and the box goes

### Requirement: Reordering and removing favorites
Favorites SHALL be reorderable by dragging within the grid. Dragging a favorite into the pinned section or below the divider SHALL make it a pinned or Today tab there, keeping its page. Remove Favorite in its menu SHALL remove it and close its page, and Restore Last Closed Tab SHALL bring it back at its place.

#### Scenario: Reordering
- **WHEN** the user drags the third favorite before the first
- **THEN** it becomes the first

#### Scenario: Dragging out of the grid
- **WHEN** the user drags the open favorite "Mail" below the divider
- **THEN** "Mail" is a Today tab there, with its page, and leaves the grid

#### Scenario: Removing
- **WHEN** the user chooses Remove Favorite on "Calendar"
- **THEN** its tile goes, and its page closes

### Requirement: Closing a favorite's page
While the window shows a favorite's page, Cmd+W and Close Tab in its menu SHALL close the page and keep the favorite, and the window SHALL show the tab it came from, as `spaces` defines.

#### Scenario: Cmd+W on a favorite
- **WHEN** the user selects the favorite "Mail" from the Today tab "News" and presses Cmd+W
- **THEN** "Mail" keeps its tile, its page is closed, and "News" is active

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

### Requirement: Favorite tiles show their Peek
While a favorite's page has a Peek open, its tile SHALL show the Peek page's favicon as a small badge at its top-trailing corner.

#### Scenario: Peek from a favorite
- **WHEN** a link to another site opens in a Peek from the favorite "Mail"
- **THEN** "Mail"'s tile shows the Peek page's favicon as a badge

### Requirement: No favorites yet
While a profile has no favorites, the grid's place SHALL show a dashed box with a star, "Drag to add Favorites", "Favorites keep your most used sites and apps close" and an × that hides it. Once the user has dismissed it or added a favorite to the profile, it SHALL never show again for that profile, even after the last favorite is removed.

#### Scenario: A new profile
- **WHEN** the user opens a Space of a profile that has never had a favorite and whose box was never dismissed
- **THEN** the dashed box shows where the grid would be

#### Scenario: Dismissing
- **WHEN** the user clicks the box's ×
- **THEN** the box goes and stays gone after a relaunch

#### Scenario: Removing the last favorite
- **WHEN** the user adds a favorite to a profile and then removes it
- **THEN** the box doesn't show again

### Requirement: A drop zone while dragging
While a profile has no favorites and the "Drag to add Favorites" box doesn't show, a Today tab, pinned tab or favorite dragged above the Space header SHALL open a drop zone in the grid's place, as in Arc: the box's star and words, with no ×, a fainter dashed border and a faint white fill. It SHALL stay until the drag ends, wherever it ends. A drop on it, or anywhere above the Space header, SHALL make the item the profile's first favorite.

#### Scenario: Dragging above the header
- **WHEN** a profile has no favorites, its box was dismissed, and the user drags a Today tab above the Space header
- **THEN** the drop zone opens where the grid would be, and the Space moves down to make room

#### Scenario: Dragging below the header
- **WHEN** the user drags the tab among the Today and pinned tabs only
- **THEN** no zone opens

#### Scenario: The zone stays during the drag
- **WHEN** the zone is open and the user drags the tab back down and drops it among the Today tabs
- **THEN** the zone stays until the drop, then goes, and the tab moves there

#### Scenario: Dropping on the zone
- **WHEN** the zone is open and the user drops the tab on it
- **THEN** it becomes the profile's only favorite, and the zone goes
