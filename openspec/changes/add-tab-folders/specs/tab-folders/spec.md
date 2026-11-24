# Spec Delta

## Purpose

Folders group the pinned tabs of a Space, as in Arc: a folder sits in the Space's pinned section among its pinned tabs, holds pinned tabs only, and opens and closes to show or hide them.

## ADDED Requirements

### Requirement: Folders hold pinned tabs
A Space's pinned section SHALL hold pinned tabs and folders in the user's order. A folder SHALL have a name and hold pinned tabs only, in the user's order, and no folders. A folder SHALL belong to one Space. Favorites and Today tabs SHALL hold no folders, and incognito and guest windows SHALL show none.

#### Scenario: A folder among pinned tabs
- **WHEN** "Work" has the pinned tab "Mail", then the folder "Docs" holding the pinned tabs "Spec" and "Plan"
- **THEN** the pinned section lists "Mail", "Docs", and under "Docs" "Spec" and "Plan"

#### Scenario: Another Space
- **WHEN** the folder "Docs" is in "Work" and the window shows "Home"
- **THEN** the sidebar doesn't list "Docs"

### Requirement: Creating a folder in place
New Folder in the footer's + menu, the Space header's menu and the sidebar's own menu SHALL add an open, empty folder named "Untitled" at the end of the Space's pinned section, and show its name in a field with the text selected and the placeholder "Folder Title". Return or the field losing focus SHALL keep the name; Esc or an empty name SHALL keep "Untitled".

#### Scenario: From the + menu
- **WHEN** "Work" has the pinned tabs "Mail" and "Docs", and the user chooses New Folder in the footer's + menu, types "Trip" and presses Return
- **THEN** the pinned section lists "Mail", "Docs" and the open, empty folder "Trip"

#### Scenario: Esc
- **WHEN** the user chooses New Folder in the Space header's menu and presses Esc
- **THEN** the folder "Untitled" stays, last in the pinned section

#### Scenario: Whatever is selected
- **WHEN** the first of three pinned tabs is selected and the user chooses New Folder
- **THEN** the folder is added after the third

### Requirement: New Folder dialog
Tabs › New Folder… SHALL open a dialog titled "New Folder…" with a field, focused, with the placeholder "What are you organizing?", and Cancel and Create. Create SHALL be disabled while the field is empty once trimmed. Create or Return SHALL add an open, empty folder with that name at the end of the Space's pinned section. The item SHALL be disabled in incognito and guest windows.

#### Scenario: Creating
- **WHEN** the user chooses Tabs › New Folder…, types "Inbox" and presses Return
- **THEN** the dialog closes, and the open folder "Inbox" is last in the pinned section

#### Scenario: Empty
- **WHEN** the dialog's field is empty
- **THEN** Create is disabled

#### Scenario: Cancelling
- **WHEN** the user presses Esc in the dialog
- **THEN** no folder is added

### Requirement: The folder row
A folder's row SHALL show a folder icon and its name, bold, as in Arc. Its tabs SHALL be listed under it while it's open, indented 16 pt. The icon SHALL be drawn open while the folder is open, closed while it's closed, and closed with "•••" while it's closed and any of its tabs is open.

#### Scenario: Open
- **WHEN** the folder "Docs" holds "Spec" and "Plan" and is open
- **THEN** its row shows the open icon, and "Spec" and "Plan" are listed under it, indented

#### Scenario: Closed with an open tab
- **WHEN** "Docs" is closed and the page of "Spec" is open
- **THEN** its icon shows "•••"

### Requirement: Opening and closing a folder
A click on a folder's row SHALL open it if it's closed and close it if it's open. A closed folder SHALL list none of its tabs, except the selected tab, which SHALL stay listed under it. Each folder SHALL remember whether it's open, in every window and across relaunches. A new folder SHALL be open.

#### Scenario: Closing
- **WHEN** the open folder "Docs" holds "Spec" and "Plan", and the user clicks its row
- **THEN** neither tab is listed

#### Scenario: The selected tab
- **WHEN** "Spec" is selected and the user closes "Docs"
- **THEN** "Spec" stays listed under "Docs", and "Plan" isn't

#### Scenario: After a relaunch
- **WHEN** the user closes "Docs", quits and relaunches
- **THEN** "Docs" is closed in every window

### Requirement: Folders in a collapsed pinned section
Collapsing the pinned section SHALL hide its folders with its pinned tabs, except the active row, even when it's in a folder. A Space with folders and no other pinned tabs SHALL show the header's chevron. Expanding the section SHALL show each folder open or closed as it was.

#### Scenario: Collapsing with folders
- **WHEN** a Space has the pinned tab "Mail" and the open folder "Docs" holding the active tab "Spec", and the user clicks the header's chevron
- **THEN** only "Spec" is listed above the divider, and expanding again shows "Mail", "Docs" open and "Spec"

#### Scenario: Folders only
- **WHEN** a Space's only pinned item is the empty folder "Ideas", and the pointer is over its header
- **THEN** the header shows the chevron

### Requirement: Close This Folder
While any tab of a folder is open, hovering the folder's row SHALL show a − button with the tooltip "Close This Folder". Clicking it SHALL close the pages of every tab in the folder, each with its leave-page confirmation, and keep the tabs in the folder. The window SHALL then show the next tab as `spaces` defines.

#### Scenario: Closing the folder's pages
- **WHEN** "Spec" and "Plan" in "Docs" are open, "Spec" is selected, and the user clicks −
- **THEN** both pages close, both tabs stay in "Docs", and the window shows the next tab

#### Scenario: No open tabs
- **WHEN** no tab in "Docs" is open and the pointer is over its row
- **THEN** the row shows no − button

### Requirement: Dragging tabs into a folder
A Today tab, pinned tab or favorite dropped on a folder's row SHALL become the folder's first tab, keeping its page and selection, whether the folder is open or closed. Dropped between an open folder's tabs, or just below its last tab, it SHALL go there in the folder. A Today tab or favorite SHALL become a pinned tab. While a drag is over a folder's row, the row SHALL show its hover pill.

#### Scenario: On the row
- **WHEN** the folder "Docs" holds "Spec", and the user drops a Today tab on its row
- **THEN** the tab is pinned, first in "Docs", before "Spec", with its page

#### Scenario: Below the last tab
- **WHEN** the open folder "Docs" holds "Spec" and "Plan", and the user drops a Today tab just below "Plan"
- **THEN** the tab is the third in "Docs"

#### Scenario: A favorite
- **WHEN** the user drops the favorite "Calendar" on "Docs"
- **THEN** "Calendar" leaves the grid and is the first tab in "Docs"

### Requirement: Dragging tabs out of a folder
A tab of a folder dragged elsewhere in the pinned section SHALL be a pinned tab there, outside the folder; dragged below the divider, it SHALL be unpinned there; dragged to favorites or the Space header, it SHALL follow `favorites` and `pinned-tabs`. It SHALL keep its page.

#### Scenario: Above the folder
- **WHEN** "Docs" holds "Spec", and the user drags "Spec" above "Docs"
- **THEN** "Spec" is a pinned tab just before "Docs", outside it

#### Scenario: Into Today
- **WHEN** the user drags "Spec" below the divider, above the first Today tab
- **THEN** "Spec" is the first Today tab, with its page

### Requirement: Reordering folders
A folder SHALL be draggable within its Space's pinned section, with its tabs. A folder dropped anywhere else, such as in another folder, below the divider, on the favorites or on the Space header, SHALL stay where it was.

#### Scenario: Moving a folder
- **WHEN** the pinned section lists "Mail" and then the folder "Docs", and the user drags "Docs" above "Mail"
- **THEN** it lists "Docs", with its tabs, then "Mail"

#### Scenario: Into Today
- **WHEN** the user drops "Docs" below the divider
- **THEN** "Docs" stays where it was

### Requirement: Folder menu
A folder's context menu SHALL offer Turn "<name>" into Space, then a divider, Rename…, then a divider, Duplicate and Move to Space ›, then a divider and Delete. Move to Space SHALL be absent with one Space. Rename… SHALL show the name in its field, selected, as when the folder was created.

#### Scenario: The menu
- **WHEN** there are two Spaces and the user right-clicks the folder "Docs"
- **THEN** the menu offers Turn "Docs" into Space, Rename…, Duplicate, Move to Space and Delete, in that order

#### Scenario: Renaming
- **WHEN** the user chooses Rename…, types "Specs" and presses Return
- **THEN** the folder's row reads "Specs"

### Requirement: Duplicating a folder
Duplicate SHALL add a folder with the same name directly after the folder, holding a copy of each of its tabs, in order, with their pinned URLs and names, none of them open. The copy SHALL be open.

#### Scenario: Duplicate
- **WHEN** the folder "Docs" holds "Spec", which is open, and the user chooses Duplicate
- **THEN** a second "Docs" follows the first, holding "Spec" not open, and the first "Spec" stays as it was

### Requirement: Moving a folder to another Space
Move to Space SHALL move the folder, with its tabs, to the end of the chosen Space's pinned section. Open tabs SHALL keep their pages within a profile; across profiles, `profiles` applies. Moving the folder holding the window's active tab SHALL switch the window to that Space; moving another SHALL show "Folder was moved to" and the Space's name.

#### Scenario: Moving a folder
- **WHEN** the window shows "Mail" in "Work", and the user moves the folder "Docs" to "Home"
- **THEN** "Work" no longer lists "Docs", "Home" lists it last in its pinned section, and a notice says "Folder was moved to Home"

### Requirement: Turning a folder into a Space
Turn "<name>" into Space SHALL add a Space named after the folder, without an icon, using the folder's Space's profile, after the last Space. The folder's tabs SHALL become its pinned tabs, in order, keeping their pages, and the folder SHALL be removed. The window SHALL then show the new Space. It SHALL ask for no confirmation.

#### Scenario: Turning a folder into a Space
- **WHEN** "Work" has the folder "Trip" holding "Flights", which is open, and "Hotels", and the user chooses Turn "Trip" into Space
- **THEN** a Space "Trip" is last in the switcher, the window shows it with the pinned tabs "Flights", with its page, and "Hotels", and "Work" no longer lists "Trip"

#### Scenario: An empty folder
- **WHEN** the user turns the empty folder "Ideas" into a Space
- **THEN** the window shows the new Space "Ideas", with no pinned tabs

### Requirement: Deleting a folder
Delete SHALL remove an empty folder at once. For a folder with tabs it SHALL first ask, in a dialog titled "Delete your "<name>" folder?", with the message "Deleting this folder will remove the tabs inside it.", Cancel and a destructive Delete Folder. On Delete Folder, the folder and its tabs SHALL be removed, and their open pages closed.

#### Scenario: An empty folder
- **WHEN** the user chooses Delete on the empty folder "Ideas"
- **THEN** "Ideas" is removed without a dialog

#### Scenario: A folder with tabs
- **WHEN** the user chooses Delete on "Docs", which holds "Spec", open, and "Plan", and chooses Delete Folder
- **THEN** "Docs", "Spec" and "Plan" leave the sidebar, and the page of "Spec" closes

#### Scenario: Cancelled
- **WHEN** the user chooses Cancel
- **THEN** "Docs" and its tabs are untouched

### Requirement: Restoring a deleted folder
Restore Last Closed Tab SHALL bring back the most recently deleted folder, when it's newer than any other closed tab, with its name, its tabs and whether it was open, at its place in its Space, or at the end of the pinned section when its place is gone. If tabs of the folder were open, it SHALL also reopen the page of the last one closed.

#### Scenario: Bringing it back
- **WHEN** the user deleted "Docs", the second item of the pinned section, holding "Spec" and "Plan", and chooses Restore Last Closed Tab
- **THEN** "Docs" is the second item again, holding "Spec" and "Plan"

#### Scenario: With an open tab
- **WHEN** "Spec" was open when the user deleted "Docs", and the user chooses Restore Last Closed Tab
- **THEN** "Docs" comes back holding "Spec" and "Plan", and the page of "Spec" is open again

### Requirement: Folders after a relaunch
Folders SHALL come back after every relaunch and after a crash, in their Spaces and order, with their names and their tabs in order, whichever windows come back.

#### Scenario: Relaunch
- **WHEN** the user quits with the folder "Docs" holding "Spec" and "Plan" in "Work", and relaunches
- **THEN** "Work" lists "Docs" in its place, holding "Spec" and "Plan"
