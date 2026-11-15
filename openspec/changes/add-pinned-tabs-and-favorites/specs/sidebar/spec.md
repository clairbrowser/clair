# Spec Delta

## ADDED Requirements

### Requirement: Sections of the sidebar
Below the URL field, the sidebar SHALL show, in this order: the favorites of the Space's profile (`favorites`), the Space header, the Space's pinned tabs (`pinned-tabs`), the divider, the "New Tab" row and the Space's Today tabs. Rows SHALL show a tab's custom name in place of its title (`tab-names`). The pinned tabs, the divider, "New Tab" and the Today tabs SHALL scroll together; the favorites stay above them, also while the window slides to another Space of the same profile.

#### Scenario: Order of the sections
- **WHEN** a Space's profile has two favorites, and the Space has one pinned tab and one Today tab
- **THEN** the sidebar shows the two favorite tiles, the Space header, the pinned tab, the divider, "New Tab" and the Today tab, in that order

#### Scenario: A renamed tab
- **WHEN** a Today tab is named "Fruit Co"
- **THEN** its row reads "Fruit Co"

### Requirement: Today tab menu
A Today tab's context menu SHALL offer Copy Link, Rename…, Duplicate, Mute or Unmute, Pin Tab, Pin to Favorites, Move to Space (`spaces`), Close Tab and Close Tabs Below. Close Tabs Below SHALL close only the Today tabs below it.

#### Scenario: Today tab's menu
- **WHEN** there is one Space and the user right-clicks a Today tab's row
- **THEN** the menu offers Copy Link, Rename…, Duplicate, Mute, Pin Tab, Pin to Favorites, Close Tab and Close Tabs Below

#### Scenario: Close Tabs Below leaves pinned tabs
- **WHEN** the user chooses Close Tabs Below on the first Today tab of a Space with pinned tabs
- **THEN** the Today tabs below it close, and the pinned tabs stay

## MODIFIED Requirements

### Requirement: Tab list
Below the pinned section, the sidebar SHALL show a "New Tab" row and then every Today tab of the Space the window shows, from every window, in the Space's tab order, with its favicon and title. The active tab SHALL be highlighted, more lightly while the window isn't key. A tab that plays sound or is muted SHALL show a speaker between its favicon and title, as in Arc, that mutes or unmutes it, with the tooltip "Mute this tab" or "Unmute this tab". It SHALL scroll when it doesn't fit.

#### Scenario: Selecting a tab
- **WHEN** the user clicks a tab row
- **THEN** that tab becomes active and its row is highlighted

#### Scenario: Muting a tab
- **WHEN** a tab plays sound and the user clicks its speaker
- **THEN** the tab is muted and its speaker shows as muted

#### Scenario: Many tabs
- **WHEN** the window has more tabs than the sidebar can show
- **THEN** the tab list scrolls, and the top row, URL field and footer stay in place

#### Scenario: Another Space's tabs
- **WHEN** "Home" has two tabs and "Work" has three, and the window shows "Work"
- **THEN** the list shows the three tabs of "Work" and none of "Home"

#### Scenario: A tab opened in another window
- **WHEN** two windows show "Home" and a tab is opened in the first
- **THEN** the second window's list shows it too

### Requirement: Closing, reordering and tab menu
Hovering a Today tab's row SHALL show a close button, as large as Arc's, which highlights under the pointer. Clicking it, or middle-clicking the row, SHALL close the tab. Tabs SHALL be reorderable by dragging, and draggable between Today, the pinned section and favorites. A row's context menu SHALL offer the items of its kind (Today tab menu, `pinned-tabs`, `favorites`), and opening it SHALL draw no selection ring around the row.

#### Scenario: Reordering
- **WHEN** the user drags the third tab above the first
- **THEN** it becomes the first tab, and Cmd+1 selects it

#### Scenario: Close Tabs Below
- **WHEN** the user chooses Close Tabs Below on the second of five tabs
- **THEN** the third to fifth tabs close, each with its usual leave-page confirmation

### Requirement: Tab titles and clicks in tooltips
Resting the pointer on a tab row for about 2 seconds SHALL show a tooltip as `tab-names` defines: the tab's custom name, or else its full title with "Double-click to rename". A click on a control, including the right click that opens a context menu, SHALL put its tooltip away until the pointer leaves the control.

#### Scenario: Full title of a tab
- **WHEN** the pointer rests on the row of a tab without a custom name for 2 seconds
- **THEN** a tooltip shows the tab's full title, and "Double-click to rename" below it

#### Scenario: Context menu on a tab
- **WHEN** the user right-clicks a tab row and leaves its context menu open
- **THEN** no tooltip shows the tab's title

### Requirement: An expanded Peek goes below its tab
A Peek expanded into a tab SHALL be inserted directly below its parent tab, the one exception to new tabs going to the top of the list. A Peek of a pinned tab or favorite SHALL be expanded into a Today tab at the top of the list.

#### Scenario: Expanded Peek
- **WHEN** the user expands a Peek open on the third tab of five
- **THEN** the new tab is fourth in the list, directly below the third, and active

#### Scenario: Expanded Peek of a pinned tab
- **WHEN** the user expands a Peek open on a pinned tab
- **THEN** the new tab is the first Today tab, active, and the pinned tab keeps its page
