# Spec Delta

## MODIFIED Requirements

### Requirement: Space header
Above the tab list, the sidebar SHALL show the current Space's icon, if it has one, and its name. Right-clicking the header SHALL open a menu offering Change Space Icon…, Rename Space…, Set Profile (`profiles`), then between dividers New Folder (`tab-folders`), then Manage Spaces… and Delete Space. Hovering the header SHALL show a More button (…) at its trailing end, as in Arc, which opens the same menu. An incognito or guest window SHALL show no Space header.

#### Scenario: Header shows the Space
- **WHEN** a window shows the Space "Work", whose icon is 💼
- **THEN** the sidebar shows 💼 and "Work" above the "New Tab" row

#### Scenario: Header menu
- **WHEN** the user right-clicks the header
- **THEN** the menu lists Change Space Icon…, Rename Space…, Set Profile, New Folder, Manage Spaces… and Delete Space, in that order

#### Scenario: Incognito window
- **WHEN** the user opens an incognito window
- **THEN** its sidebar shows "Incognito" and no Space header or Space switcher

### Requirement: Deleting a Space
Delete Space SHALL be disabled for the only Space. Deleting a Space with no tabs, no pinned tabs and no folders SHALL happen at once. Otherwise Clair SHALL first ask for confirmation in a dialog, saying that its tabs will close; on confirmation its tabs SHALL close in every window and its pinned tabs and folders SHALL be removed. Each window that showed the Space SHALL then show the Space before it, or the one after when it was first.

#### Scenario: The only Space
- **WHEN** there is one Space and the user opens its header's menu
- **THEN** Delete Space is disabled

#### Scenario: Space with tabs
- **WHEN** the user deletes the second of three Spaces, which has two tabs, and confirms
- **THEN** the two tabs close, the Space leaves the switcher, and the window shows the first Space

#### Scenario: Cancelled
- **WHEN** the user cancels the confirmation
- **THEN** the Space and its tabs are untouched

#### Scenario: Space with pinned tabs only
- **WHEN** the user deletes a Space whose only tabs are two pinned tabs, none open, and confirms
- **THEN** the pinned tabs are removed with the Space, and the profile's favorites stay

#### Scenario: Space with an empty folder only
- **WHEN** the user deletes a Space whose only item is an empty folder
- **THEN** Clair asks for confirmation, and on confirmation the folder is removed with the Space

## ADDED Requirements

### Requirement: Tab commands and folders
The rows the tab commands act on SHALL include the tabs of open folders, in the sidebar's order, and SHALL leave out the tabs a closed folder hides. Ctrl+Shift+PageDown and Ctrl+Shift+PageUp SHALL move a folder's tab within its folder, stopping at its ends.

#### Scenario: A closed folder
- **WHEN** "Work" has the pinned tab P, then the closed folder "Docs" holding S, then the Today tab X, P is active, and the user presses Opt+Cmd+Down
- **THEN** X is active, and S stays closed

#### Scenario: An open folder
- **WHEN** "Docs" is open instead, and the user presses Cmd+2
- **THEN** S is active

#### Scenario: Moving a folder's tab
- **WHEN** S is the first of the two tabs in "Docs", S is active, and the user presses Ctrl+Shift+PageUp
- **THEN** nothing moves
