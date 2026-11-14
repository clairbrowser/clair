# Spec Delta

## Purpose

Pinned tabs keep the sites a user returns to in each Space, as in Arc: a pinned tab is a saved item with a pinned URL that stays in the sidebar whether or not its page is open, and comes back after every relaunch.

## ADDED Requirements

### Requirement: A pinned tab is a saved item
A pinned tab SHALL keep its pinned URL, its page title, its icon and any custom name whether or not its page is open. Its page SHALL open in a tab when the user selects it, and close without the pin going away. A pinned tab SHALL belong to one Space.

#### Scenario: Selecting a pinned tab whose page isn't open
- **WHEN** the pinned tab "Mail" has no open page and the user clicks its row
- **THEN** its pinned URL loads in a tab, and the row is highlighted

#### Scenario: Selecting a pinned tab whose page is open
- **WHEN** the pinned tab "Mail" has its page open and the user clicks its row
- **THEN** that page shows as it was, without reloading

### Requirement: Pinned section
Between the Space header and the "New Tab" row, the sidebar SHALL list the Space's pinned tabs in the user's order, with the icon and title each had when last open. A pinned tab whose page isn't open SHALL look like one whose page is open and isn't selected. A divider SHALL separate the pinned section from "New Tab" while the Space has Today tabs.

#### Scenario: Pinned and Today tabs
- **WHEN** a Space has the pinned tabs "Mail" and "Docs" and two Today tabs
- **THEN** the sidebar lists "Mail" and "Docs", then a divider, then "New Tab" and the two Today tabs

#### Scenario: A pinned tab not open
- **WHEN** "Mail" is pinned and its page isn't open
- **THEN** its row shows its icon and title, undimmed

#### Scenario: Another Space
- **WHEN** "Mail" is pinned in "Work" and the window shows "Home"
- **THEN** the sidebar doesn't list "Mail"

### Requirement: Pinning and unpinning
Tabs › Pin Tab (Cmd+D) and Pin Tab in a Today tab's menu SHALL pin the tab at the bottom of the pinned section, keeping its page and its selection. On a pinned tab, the item SHALL read Unpin Tab and SHALL move the tab to the top of the Today tabs, keeping its page, or opening it if closed, and its custom name. The pinned URL SHALL be the page's URL when it was pinned.

#### Scenario: Pinning the active tab
- **WHEN** the active tab shows `https://example.com/inbox` and the user presses Cmd+D
- **THEN** it becomes the last pinned tab, stays active with its page, and its pinned URL is `https://example.com/inbox`

#### Scenario: Unpinning
- **WHEN** the active tab is pinned and the user presses Cmd+D
- **THEN** it becomes the first Today tab, active, with its page and name

#### Scenario: The menu item's title
- **WHEN** the active tab is pinned and the user opens the Tabs menu
- **THEN** the item reads "Unpin Tab"

### Requirement: Reordering and dragging pinned tabs
Pinned tabs SHALL be reorderable by dragging. Dragging a Today tab into the pinned section SHALL pin it where it's dropped, and dragging a pinned tab below the divider SHALL unpin it where it's dropped. Favorites follow `favorites`.

#### Scenario: Dragging a Today tab into the pinned section
- **WHEN** a Space has the pinned tabs "Mail" and "Docs" and the user drags a Today tab between them
- **THEN** it is pinned second, between "Mail" and "Docs"

#### Scenario: Dragging a pinned tab out
- **WHEN** the user drags the pinned tab "Docs" below the second Today tab
- **THEN** "Docs" is no longer pinned and is the third Today tab, with its page

### Requirement: Closing a pinned tab keeps it pinned
On the selected pinned tab, hovering its row SHALL show a − button with the tooltip "Close and Keep Pinned" and Cmd+W. The button, Cmd+W and Tabs › Close and Keep Pinned SHALL close its page and keep the row where it is. The window SHALL then show the next tab as `spaces` defines.

#### Scenario: Close and Keep Pinned
- **WHEN** the user selects the pinned tab "Mail" from the Today tab "News", and presses Cmd+W
- **THEN** "Mail" keeps its row, its page is closed, and "News" is active

#### Scenario: Selecting it again
- **WHEN** the user then clicks "Mail"
- **THEN** its pinned URL loads again

### Requirement: Removing a pin
On a pinned tab that isn't selected, hovering its row SHALL show an × button with the tooltip "Remove Pin", which removes the pinned tab and closes its page if open. Remove Pin in the row's menu SHALL do the same for any pinned tab. Restore Last Closed Tab SHALL bring a removed pinned tab back pinned, at its place.

#### Scenario: × on a pinned tab
- **WHEN** the user clicks × on the pinned tab "Docs", which isn't selected
- **THEN** "Docs" leaves the pinned section and its page closes

#### Scenario: Bringing it back
- **WHEN** the user removed "Docs", second of three pinned tabs, and chooses Restore Last Closed Tab
- **THEN** "Docs" is pinned second again, with its pinned URL

### Requirement: Navigated away from the pinned URL
While a pinned tab's page is at another URL than its pinned URL, its row SHALL show its icon, a grey "/" and the current page's title, or its custom name. Hovering the icon SHALL turn it into a button and show "Back to Pinned URL" under the title. Clicking it, or Tabs › Back to Pinned URL, SHALL load the pinned URL as a new navigation.

#### Scenario: Following a link
- **WHEN** the pinned tab "Docs" at `https://docs.example.com/` follows a link to `https://docs.example.com/guide` titled "Guide"
- **THEN** its row reads "/ Guide" after its icon

#### Scenario: Back to Pinned URL
- **WHEN** the user then clicks the row's icon
- **THEN** the tab loads `https://docs.example.com/`, the row shows its plain title again, and Back returns to "Guide"

#### Scenario: At the pinned URL
- **WHEN** the pinned tab is at its pinned URL
- **THEN** Tabs › Back to Pinned URL is disabled

### Requirement: Editing the pinned URL
A pinned tab's menu SHALL offer Edit Pinned Page › with "Replace Pinned URL with Current", which makes the page's current URL the pinned URL, and "Edit…", which opens a dialog titled "Edit Pinned URL" with the URL selected in a field, Cancel and Save. Save SHALL be disabled while the field holds no valid URL.

#### Scenario: Replacing with the current URL
- **WHEN** the pinned tab "Docs" shows `https://docs.example.com/guide` and the user chooses Replace Pinned URL with Current
- **THEN** its pinned URL is `https://docs.example.com/guide`, and its row no longer shows "/"

#### Scenario: Editing
- **WHEN** the user chooses Edit…, types `https://docs.example.com/api` and clicks Save
- **THEN** that is the pinned URL, and Back to Pinned URL loads it

#### Scenario: Not a URL
- **WHEN** the field holds "not a url"
- **THEN** Save is disabled

### Requirement: Pinned tab menu
A pinned tab's context menu SHALL offer Copy Link, Rename…, Mute or Unmute, Edit Pinned Page ›, Duplicate, Move to Space (with more than one Space), Pin to Favorites, Unpin Tab and Remove Pin. Copy Link SHALL copy the page's current URL, or the pinned URL while the page is closed. Duplicate SHALL open the same URL as a new Today tab at the top.

#### Scenario: Copy Link on a closed pinned tab
- **WHEN** the pinned tab "Mail" has no open page and the user chooses Copy Link
- **THEN** its pinned URL is copied

#### Scenario: Duplicate
- **WHEN** the user chooses Duplicate on the pinned tab "Docs"
- **THEN** a new Today tab at the top of the list shows the same URL, and "Docs" stays pinned

### Requirement: Collapsing the pinned section
Hovering the Space header SHALL show a chevron at its leading edge. Clicking it, or View › Collapse Pinned Tabs, SHALL hide the pinned rows except the active one, and turn the chevron to point sideways, shown without hover. Clicking it again or View › Expand Pinned Tabs SHALL show them. Each Space SHALL remember the choice across windows and launches.

#### Scenario: Collapsing
- **WHEN** a Space has four pinned tabs, the second active, and the user clicks the chevron
- **THEN** only the second pinned tab is listed above the divider, and the chevron points sideways

#### Scenario: After a relaunch
- **WHEN** the user collapsed the pinned section of "Work", quits and relaunches
- **THEN** "Work"'s pinned section is still collapsed

### Requirement: Pinned tabs after a relaunch
Pinned tabs SHALL come back after every relaunch, in their Spaces and order, with their pinned URLs and names, whatever Chromium's "On startup" setting and Clair's restore-windows setting say. A pinned tab whose page was open SHALL come back open only when Today tabs are restored.

#### Scenario: Starting on a new tab page
- **WHEN** "On startup" is "Open the New Tab page", and the user quits with three pinned tabs in "Work" and relaunches
- **THEN** "Work" lists the three pinned tabs, none of them open

#### Scenario: Continuing where the user left off
- **WHEN** "On startup" is "Continue where you left off", and the user quits with the pinned tab "Mail" open at another URL than its pinned URL, and relaunches
- **THEN** "Mail" is open at that URL, and its row shows "/"

#### Scenario: After a crash
- **WHEN** Clair crashes after the user pinned a tab and is launched again
- **THEN** the tab is still pinned

### Requirement: Clear Today
While the pointer is over the sidebar and the Space has Today tabs, the divider SHALL show "↓ Clear" at its trailing end, with the tooltip "Clear Today tabs" and Shift+Cmd+K. It and Tabs › Clear Today (Shift+Cmd+K) SHALL close every Today tab of the Space, each with its leave-page confirmation, and leave pinned tabs and favorites as they are.

#### Scenario: Clearing
- **WHEN** "Work" has two pinned tabs and three Today tabs, and the user clicks Clear
- **THEN** the three Today tabs close, and the two pinned tabs stay

#### Scenario: Restoring
- **WHEN** the user then chooses Restore Last Closed Tab
- **THEN** the last Today tab closed comes back

#### Scenario: No Today tabs
- **WHEN** the Space has no Today tabs
- **THEN** there is no divider and no Clear button, and Tabs › Clear Today is disabled

### Requirement: No pins in private windows
Incognito and guest windows SHALL show no pinned section or favorites, and SHALL disable Pin Tab, Pin to Favorites, Back to Pinned URL, Close and Keep Pinned and Collapse Pinned Tabs. Their tabs' menus SHALL offer neither pin item.

#### Scenario: Incognito
- **WHEN** the user opens an incognito window and presses Cmd+D
- **THEN** nothing is pinned, and the sidebar has no pinned section or favorites
