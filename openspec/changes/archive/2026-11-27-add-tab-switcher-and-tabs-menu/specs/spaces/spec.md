## MODIFIED Requirements

### Requirement: Tab commands follow the Space
Tabs › Next Tab (Opt+Cmd+Down), Previous Tab (Opt+Cmd+Up), Cmd+1 to Cmd+9 and Close Tabs Below SHALL act on the rows the sidebar lists, pinned tabs first and then Today tabs, in its order, whichever window holds them, and never on a tab of another Space or on favorites. Selecting a pinned tab whose page isn't open SHALL open it. Ctrl+Shift+PageDown and Ctrl+Shift+PageUp SHALL move the active row one row down or up within its section, stopping at its ends. Ctrl+Tab follows `tab-switcher`.

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

