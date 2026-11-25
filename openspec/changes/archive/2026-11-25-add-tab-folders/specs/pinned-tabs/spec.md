# Spec Delta

## MODIFIED Requirements

### Requirement: Reordering and dragging pinned tabs
Pinned tabs SHALL be reorderable by dragging. Dragging a Today tab into the pinned section SHALL pin it where it's dropped, also while the Space has no pinned tabs, by dropping it above the divider. Dragging a pinned tab below the divider SHALL unpin it where it's dropped. Dragging into, within and out of folders follows `tab-folders`. Favorites follow `favorites`.

#### Scenario: Dragging a Today tab into the pinned section
- **WHEN** a Space has the pinned tabs "Mail" and "Docs" and the user drags a Today tab between them
- **THEN** it is pinned second, between "Mail" and "Docs"

#### Scenario: Dragging into an empty pinned section
- **WHEN** a Space has no pinned tabs and the user drags its third Today tab above the divider
- **THEN** it becomes the Space's only pinned tab, above the divider

#### Scenario: Dragging a pinned tab out
- **WHEN** the user drags the pinned tab "Docs" below the second Today tab
- **THEN** "Docs" is no longer pinned and is the third Today tab, with its page

#### Scenario: Dragging a pinned tab to the top of Today
- **WHEN** a Space has Today tabs and the user drags the pinned tab "Docs" between "New Tab" and the first Today tab
- **THEN** "Docs" is no longer pinned and is the first Today tab

#### Scenario: Dragging a pinned tab next to a folder
- **WHEN** the pinned section lists "Mail" and then the closed folder "Work", and the user drags "Mail" just below "Work"
- **THEN** "Mail" follows "Work", outside it

### Requirement: Removing a pin
On a pinned tab that isn't selected, hovering its row SHALL show an × button with the tooltip "Remove Pin", which removes the pinned tab and closes its page if open. Restore Last Closed Tab SHALL bring a removed pinned tab back pinned, at its place, in its folder if it was in one that still exists, and otherwise at the end of the pinned section.

#### Scenario: × on a pinned tab
- **WHEN** the user clicks × on the pinned tab "Docs", which isn't selected
- **THEN** "Docs" leaves the pinned section and its page closes

#### Scenario: Bringing it back
- **WHEN** the user removed "Docs", second of three pinned tabs, and chooses Restore Last Closed Tab
- **THEN** "Docs" is pinned second again, with its pinned URL

#### Scenario: Bringing it back into its folder
- **WHEN** the user removed "Spec", first in the folder "Work", and chooses Restore Last Closed Tab
- **THEN** "Spec" is first in "Work" again

### Requirement: Pinned tabs after a relaunch
Pinned tabs SHALL come back after every relaunch, in their Spaces, folders and order, with their pinned URLs and names, whichever windows come back. A pinned tab whose page was open when Clair quit SHALL come back open at the URL it showed (`browser-window`); one whose page wasn't SHALL come back not open.

#### Scenario: Relaunch
- **WHEN** the user quits with three pinned tabs in "Work", one of them open, and relaunches
- **THEN** "Work" lists the three pinned tabs in order, the one that was open open again, and the other two not open

#### Scenario: In a folder
- **WHEN** the user quits with the pinned tab "Spec" open in the folder "Docs", and relaunches
- **THEN** "Spec" is in "Docs", open

#### Scenario: Navigated away
- **WHEN** the user quits with the pinned tab "Mail" open at another URL than its pinned URL, and relaunches
- **THEN** "Mail" is open at that URL, and its row shows "/"

#### Scenario: After a crash
- **WHEN** Clair crashes after the user pinned a tab and is launched again
- **THEN** the tab is still pinned
