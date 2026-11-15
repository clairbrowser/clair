# tab-names Specification

## Purpose
Users can give a tab, pinned tab or favorite a name of their own, as in Arc, which the sidebar and the window show in place of the page's title for as long as the tab lasts.

## Requirements

### Requirement: Renaming a row in place
Double-clicking a Today or pinned tab's row, or choosing Rename… in its menu, SHALL turn its title into a field in place, in the same font, with no border, on the row's highlight. A double-click SHALL put the caret where it clicked; Rename… SHALL select the whole name. Return, or clicking elsewhere, SHALL keep the name, as in Arc, and Esc SHALL discard the edit.

#### Scenario: Rename…
- **WHEN** the user chooses Rename… on the tab "Example Domain", types "Fruit Co" and presses Return
- **THEN** the row reads "Fruit Co"

#### Scenario: Double-click
- **WHEN** the user double-clicks the title of a tab's row
- **THEN** the row's tab is active, its title is a field with the caret where the user clicked, and nothing is selected

#### Scenario: Esc
- **WHEN** the user types in the field and presses Esc
- **THEN** the row shows the name it had before

### Requirement: Renaming a favorite
Rename… in a favorite's menu SHALL open a dialog titled "Rename Tab…" with a field holding the favorite's name, selected, the placeholder "Keep it short and sweet!", and Cancel and Rename buttons. Return SHALL rename and Esc cancel.

#### Scenario: Renaming a favorite
- **WHEN** the user chooses Rename… on the favorite "Inbox (3) - Mail", types "Mail" and clicks Rename
- **THEN** the favorite is named "Mail"

### Requirement: Clearing a name
Keeping an empty name SHALL remove the custom name, so the row shows the page's title again. While the field is empty it SHALL show the page's title as its placeholder.

#### Scenario: Empty name
- **WHEN** the tab is named "Fruit Co", and the user deletes the whole name and presses Return
- **THEN** the row shows the page's title again

### Requirement: A name lasts as long as the tab
A custom name SHALL stay through navigation, to any site, through pinning and unpinning, Pin to Favorites, Move to Space and relaunches that restore the tab, until the user clears it. Duplicate SHALL give the new tab no custom name. The page's own title SHALL not change.

#### Scenario: Navigating
- **WHEN** the tab named "Fruit Co" follows a link to another site
- **THEN** its row still reads "Fruit Co"

#### Scenario: Unpinning
- **WHEN** the pinned tab named "Docs" is unpinned with Cmd+D
- **THEN** its Today row reads "Docs"

#### Scenario: Relaunch
- **WHEN** the user quits with a Today tab named "Fruit Co", and relaunches with tabs restored
- **THEN** the tab's row reads "Fruit Co"

### Requirement: Tooltips show the name
A renamed tab's row tooltip SHALL show only its custom name. Any other tab's tooltip SHALL show its page title with "Double-click to rename" on a second line. On a pinned tab navigated away from its pinned URL, hovering the icon SHALL show the name with "Back to Pinned URL".

#### Scenario: Renamed tab
- **WHEN** the pointer rests on the row of the tab named "Fruit Co" for 2 seconds
- **THEN** the tooltip reads "Fruit Co", without the page's title or the hint

#### Scenario: Tab without a name
- **WHEN** the pointer rests on the row of the tab "Example Domain" for 2 seconds
- **THEN** the tooltip reads "Example Domain" and, below it, "Double-click to rename"

### Requirement: The window's title is the tab's name
A window's title, which Mission Control, the Window menu and VoiceOver show, SHALL be its active tab's custom name, or else its page's title.

#### Scenario: Window menu
- **WHEN** the active tab is named "Fruit Co" and the user opens the Window menu
- **THEN** the window is listed as "Fruit Co"
