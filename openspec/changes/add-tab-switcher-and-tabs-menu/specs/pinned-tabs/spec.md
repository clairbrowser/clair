## MODIFIED Requirements

### Requirement: Pinned tab menu
A pinned tab's context menu SHALL offer, with a divider between each group: Unpin Tab and Pin to Favorites; Copy Link and Duplicate; Split with Tab › (`split-view`) and Move to Space (with more than one Space); Rename…, Mute or Unmute, and Edit Pinned Page ›; Close Tab while its page is open. It SHALL offer no Remove Pin. Copy Link SHALL copy the page's current URL, or the pinned URL while the page is closed. Duplicate SHALL open the same URL as a new Today tab at the top.

#### Scenario: Copy Link on a closed pinned tab
- **WHEN** the pinned tab "Mail" has no open page and the user chooses Copy Link
- **THEN** its pinned URL is copied

#### Scenario: Duplicate
- **WHEN** the user chooses Duplicate on the pinned tab "Docs"
- **THEN** a new Today tab at the top of the list shows the same URL, and "Docs" stays pinned

#### Scenario: The menu's items
- **WHEN** there is one Space and the user right-clicks the pinned tab "Mail", whose page is open
- **THEN** the menu offers Unpin Tab, Pin to Favorites, a divider, Copy Link, Duplicate, a divider, Split with Tab, a divider, Rename…, Mute, Edit Pinned Page, a divider and Close Tab

#### Scenario: The menu's last items
- **WHEN** the user right-clicks a pinned tab whose page is open
- **THEN** the menu ends with Close Tab, after a divider

#### Scenario: A closed pinned tab
- **WHEN** the user right-clicks a pinned tab whose page isn't open
- **THEN** the menu has no Close Tab and no divider before where it would be, and Mute is disabled

#### Scenario: Split with Tab
- **WHEN** the user right-clicks the pinned tab "Mail" and chooses Split with Tab › "News"
- **THEN** the window shows a split of "Mail" and "News", "News" focused

### Requirement: Closing a pinned tab keeps it pinned
On the selected pinned tab, hovering its row SHALL show a − button with the tooltip "Close and Keep Pinned" and Cmd+W. The button, Cmd+W and Close Tab in its menu SHALL close its page and keep the row where it is. The window SHALL then show the next tab as `spaces` defines.

#### Scenario: Close and Keep Pinned
- **WHEN** the user selects the pinned tab "Mail" from the Today tab "News", and presses Cmd+W
- **THEN** "Mail" keeps its row, its page is closed, and "News" is active

#### Scenario: Selecting it again
- **WHEN** the user then clicks "Mail"
- **THEN** its pinned URL loads again

#### Scenario: From its menu
- **WHEN** the user right-clicks the open pinned tab "Docs", which isn't shown, and chooses Close Tab
- **THEN** its page closes, its row stays, and the window keeps its tab

### Requirement: Navigated away from the pinned URL
While a pinned tab's page is at another URL than its pinned URL, its row SHALL show its icon, a grey "/" and the current page's title, or its custom name. Hovering the icon SHALL turn it into a button and show "Back to Pinned URL" under the title. Clicking it SHALL load the pinned URL as a new navigation. As in Arc, another query or fragment, or a redirect from the pinned URL, is still at it.

#### Scenario: Following a link
- **WHEN** the pinned tab "Docs" at `https://docs.example.com/` follows a link to `https://docs.example.com/guide` titled "Guide"
- **THEN** its row reads "/ Guide" after its icon

#### Scenario: Back to Pinned URL
- **WHEN** the user then clicks the row's icon
- **THEN** the tab loads `https://docs.example.com/`, the row shows its plain title again, and Back returns to "Guide"

#### Scenario: Another query
- **WHEN** the pinned tab at `https://docs.example.com/search?q=a` follows a link to `https://docs.example.com/search?q=b`
- **THEN** its row shows its plain title, with no "/"

#### Scenario: At the pinned URL
- **WHEN** the pinned tab is at its pinned URL and the user hovers its icon
- **THEN** the icon isn't a button and no "Back to Pinned URL" shows

### Requirement: Clear Today
While the pointer is over the sidebar and the Space has Today tabs, the divider SHALL show "↓ Clear" at its trailing end, with the tooltip "Clear Today tabs" and Shift+Cmd+K. It and Tabs › Clear Unpinned Tabs (Shift+Cmd+K, `tabs-menu`) SHALL close every Today tab of the Space, each with its leave-page confirmation, and leave pinned tabs and favorites as they are.

#### Scenario: Clearing
- **WHEN** "Work" has two pinned tabs and three Today tabs, and the user clicks Clear
- **THEN** the three Today tabs close, and the two pinned tabs stay

#### Scenario: Restoring
- **WHEN** the user then chooses Restore Last Closed Tab
- **THEN** the last Today tab closed comes back

#### Scenario: No Today tabs
- **WHEN** the Space has no Today tabs
- **THEN** there is no divider and no Clear button, and Tabs › Clear Unpinned Tabs is disabled

### Requirement: No pins in private windows
Incognito and guest windows SHALL show no pinned section or favorites, and SHALL disable Pin Tab, Pin to Favorites, New Folder… and Collapse Pinned Tabs. Their tabs' menus SHALL offer neither pin item.

#### Scenario: Incognito
- **WHEN** the user opens an incognito window and presses Cmd+D
- **THEN** nothing is pinned, and the sidebar has no pinned section or favorites

### Requirement: Editing the pinned URL
A pinned tab's menu SHALL offer Edit Pinned Page › with "Back to Pinned URL", enabled while the page is at another URL than its pinned URL and loading the pinned URL as the row's icon does, "Replace Pinned URL with Current", which makes the page's current URL the pinned URL, and "Edit…", which opens a dialog titled "Edit Pinned URL" with the URL selected in a field, Cancel and Save. Save SHALL be disabled while the field holds no valid URL.

#### Scenario: Replacing with the current URL
- **WHEN** the pinned tab "Docs" shows `https://docs.example.com/guide` and the user chooses Replace Pinned URL with Current
- **THEN** its pinned URL is `https://docs.example.com/guide`, and its row no longer shows "/"

#### Scenario: Editing
- **WHEN** the user chooses Edit…, types `https://docs.example.com/api` and clicks Save
- **THEN** that is the pinned URL, and Back to Pinned URL loads it

#### Scenario: Not a URL
- **WHEN** the field holds "not a url"
- **THEN** Save is disabled

#### Scenario: Back to Pinned URL from the menu
- **WHEN** the favorite "Docs" at `https://docs.example.com/` follows a link to `https://docs.example.com/guide`, and the user chooses Edit Pinned Page › Back to Pinned URL on its tile
- **THEN** it loads `https://docs.example.com/`

#### Scenario: At the pinned URL
- **WHEN** the pinned tab is at its pinned URL
- **THEN** Edit Pinned Page › Back to Pinned URL is disabled
