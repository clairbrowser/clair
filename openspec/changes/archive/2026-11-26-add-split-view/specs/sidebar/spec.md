# Spec Delta

## MODIFIED Requirements

### Requirement: Navigation controls
The sidebar's top row SHALL hold, after the window controls, a button that hides the sidebar, then back, forward and reload. Back and forward SHALL be dimmed and inert when the active tab can't go that way. Reload SHALL become stop while the active tab loads. When the sidebar is too narrow for that row, as in Arc, the row SHALL hold back, forward and a menu offering reload (or stop) and Hide Sidebar. While the toolbar or a split's pane headers show, the row SHALL hold only the window controls.

#### Scenario: Going back
- **WHEN** the user has followed a link in the active tab and clicks back
- **THEN** the tab returns to the previous page, and forward becomes available

#### Scenario: Loading
- **WHEN** the active tab starts loading a page
- **THEN** reload shows as stop until loading ends, and clicking it stops the load

#### Scenario: Narrow sidebar
- **WHEN** the toolbar is off and the user narrows the sidebar below 214 points
- **THEN** the top row shows back, forward and a "More" menu with Reload and Hide Sidebar

#### Scenario: Toolbar shown
- **WHEN** the toolbar is shown
- **THEN** the sidebar's top row shows only the window controls, and the hide-sidebar button, back, forward and reload are in the toolbar

#### Scenario: A split with the toolbar off
- **WHEN** the toolbar is off and the window shows a split
- **THEN** the sidebar's top row shows only the window controls, and the hide-sidebar button, back, forward and reload are in the pane headers

### Requirement: URL field
Below the top row, the sidebar SHALL show the active tab's host without a leading `www.`, or its full URL for pages without a host such as `chrome://` pages and files, with a search icon and "Search or Enter URL…" for a new tab page. Clicking the field SHALL open the command bar on the current URL, and its context menu SHALL offer Copy URL. While the pointer is over the field, its background SHALL darken. While the toolbar or a split's pane headers show, the field SHALL be their hosts instead.

#### Scenario: Web page
- **WHEN** the active tab shows `https://news.ycombinator.com/item?id=1`
- **THEN** the URL field reads `news.ycombinator.com`

#### Scenario: Host with www
- **WHEN** the active tab shows `https://www.apple.com/mac/`
- **THEN** the URL field reads `apple.com`

#### Scenario: Clicking the field
- **WHEN** the user clicks the URL field
- **THEN** the command bar opens with the tab's full URL selected

#### Scenario: Copying the URL
- **WHEN** the toolbar is off, the pointer is over the URL field and the user clicks its copy button
- **THEN** the tab's full URL is on the pasteboard, and Arc's "Copied Current URL" popup shows in the card's top-trailing corner

#### Scenario: Toolbar shown
- **WHEN** the toolbar is shown
- **THEN** the sidebar shows no URL field, and the toolbar shows the host

#### Scenario: A split with the toolbar off
- **WHEN** the toolbar is off and the window shows a split
- **THEN** the sidebar shows no URL field, and each pane's header shows its host

### Requirement: Today tab menu
A Today tab's context menu SHALL offer Copy Link, Rename…, Duplicate, Mute or Unmute, Split with Tab › (`split-view`), Pin Tab, Pin to Favorites, Move to Space (`spaces`), Close Tab and Close Tabs Below. Close Tabs Below SHALL close only the Today tabs below it.

#### Scenario: Today tab's menu
- **WHEN** there is one Space and the user right-clicks a Today tab's row
- **THEN** the menu offers Copy Link, Rename…, Duplicate, Mute, Split with Tab, Pin Tab, Pin to Favorites, Close Tab and Close Tabs Below

#### Scenario: Close Tabs Below leaves pinned tabs
- **WHEN** the user chooses Close Tabs Below on the first Today tab of a Space with pinned tabs
- **THEN** the Today tabs below it close, and the pinned tabs stay
