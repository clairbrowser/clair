# Spec Delta

## ADDED Requirements

### Requirement: The next tab among pinned tabs and favorites
For the tab chosen after a close, a favorite the user came from SHALL count as the tab it was selected from, and pinned tabs whose page isn't open SHALL be passed over as rows. Closing the Space's only open tab, pinned or not, SHALL leave the window on a new tab page in the Space.

#### Scenario: A closed pinned tab above
- **WHEN** the rows are the pinned tab M, whose page isn't open, then the Today tabs T and U, U wasn't selected from another tab, and the user closes T
- **THEN** U is active, and M stays closed

#### Scenario: Back to a favorite
- **WHEN** the user selects the Today tab T from the open favorite "Mail", then closes T
- **THEN** "Mail" shows

#### Scenario: The Space's only open tab is a pinned tab
- **WHEN** the pinned tab "Mail" is the Space's only open tab, the Space has no Today tabs, and the user chooses Close and Keep Pinned
- **THEN** the window stays on the Space, on a new tab page with the command bar, and "Mail" keeps its row

## MODIFIED Requirements

### Requirement: Tabs belong to a Space
Every tab outside incognito and guest windows SHALL belong to exactly one Space, except a favorite's tab, which belongs to its profile (`favorites`). A new tab SHALL join the Space its window shows, whether it comes from Cmd+T, a link, an extension or another app.

#### Scenario: New tab
- **WHEN** a window shows "Work" and the user opens a tab with Cmd+T
- **THEN** the tab is listed in "Work" and in no other Space

#### Scenario: Link opened in a new tab
- **WHEN** the user Cmd-clicks a link in a tab of "Work"
- **THEN** the new tab is listed in "Work"

#### Scenario: A favorite's tab
- **WHEN** the user opens the favorite "Mail" in "Work" and switches to "Home", which uses the same profile
- **THEN** "Mail" is in neither Space's list, and its tile shows in both

### Requirement: Deleting a Space
Delete Space SHALL be disabled for the only Space. Deleting a Space with no tabs and no pinned tabs SHALL happen at once. Otherwise Clair SHALL first ask for confirmation in a dialog, saying that its tabs will close; on confirmation its tabs SHALL close in every window and its pinned tabs SHALL be removed. Each window that showed the Space SHALL then show the Space before it, or the one after when it was first.

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

### Requirement: Moving a tab to another Space
With more than one Space, a tab row's context menu SHALL offer "Move to Space" with every other Space, which puts a Today tab at the top of that Space's list and a pinned tab at the end of its pinned section. Moving the active tab SHALL switch the window to that Space, showing the tab; moving another tab SHALL leave the window as it is and show "Tab was moved to" and the Space's name, in the popup Copy URL uses. Within a profile the tab SHALL keep its page; across profiles, `profiles` applies.

#### Scenario: Moving the active tab
- **WHEN** a window shows "Home" on a tab, and the user moves that tab to "Research"
- **THEN** the window shows "Research" with the tab first in its list and active, and "Home" no longer lists it

#### Scenario: Moving a tab
- **WHEN** a window shows "Home" on the tab "Docs", and the user moves the tab "Maps", which has a half-filled form, to "Research", which uses the same profile
- **THEN** the window keeps showing "Docs" in "Home", "Maps" is first in "Research" with the form as it was, and a notice says "Tab was moved to Research"

#### Scenario: One Space
- **WHEN** there is one Space
- **THEN** the tab's menu has no "Move to Space"

#### Scenario: Moving a pinned tab
- **WHEN** "Research" has two pinned tabs, and the user moves the pinned tab "Mail" from "Home" to "Research"
- **THEN** "Mail" is the third pinned tab of "Research", with its pinned URL and name, and "Home" no longer lists it

### Requirement: Tab commands follow the Space
Tabs › Next Tab (Opt+Cmd+Down), Previous Tab (Opt+Cmd+Up), Ctrl+Tab, Cmd+1 to Cmd+9 and Close Tabs Below SHALL act on the rows the sidebar lists, pinned tabs first and then Today tabs, in its order, whichever window holds them, and never on a tab of another Space or on favorites. Selecting a pinned tab whose page isn't open SHALL open it. Ctrl+Shift+PageDown and Ctrl+Shift+PageUp SHALL move the active row one row down or up within its section, stopping at its ends.

#### Scenario: Moving a row with the keyboard
- **WHEN** a window shows "Work", whose rows are X, Y and Z, Z is active, and the user presses Ctrl+Shift+PageUp
- **THEN** the rows are X, Z and Y, and Z is still active

#### Scenario: Cmd+number
- **WHEN** a window shows "Work", whose rows are X, Y and Z, and the user presses Cmd+2
- **THEN** Y is active

#### Scenario: Next tab at the Space's end
- **WHEN** the last row of the Space is active and the user presses Opt+Cmd+Down
- **THEN** the first row of the same Space is active

#### Scenario: Cmd+number on a tab from another window
- **WHEN** a window shows "Work", whose rows are X, Y and Z, Y was opened in another window, and the user presses Cmd+2
- **THEN** this window shows Y

#### Scenario: Cmd+number with pinned tabs and favorites
- **WHEN** the profile has three favorites, "Work" has the pinned tabs P and Q, Q isn't open, and the Today tabs X and Y, and the user presses Cmd+2
- **THEN** Q opens at its pinned URL and is active

#### Scenario: Moving a row stops at its section
- **WHEN** the first Today tab is active and the user presses Ctrl+Shift+PageUp
- **THEN** nothing moves, and the tab stays unpinned
