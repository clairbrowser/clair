# Spec Delta

## MODIFIED Requirements

### Requirement: Navigation controls
The sidebar's top row SHALL hold, after the window controls, a button that hides the sidebar, then back, forward and reload. Back and forward SHALL be dimmed and inert when the active tab can't go that way. Reload SHALL become stop while the active tab loads. When the sidebar is too narrow for that row, as in Arc, the row SHALL hold back, forward and a menu offering reload (or stop) and Hide Sidebar. While the toolbar shows, the row SHALL hold only the window controls.

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

### Requirement: Tooltips in Arc's wording
The sidebar's controls SHALL have Clair's own tooltips, never the system's, in Arc's wording and with their shortcuts: "Hide sidebar" ("Show sidebar" while hidden, "Lock sidebar" while the hidden sidebar is revealed), "Go back", "Go forward", "Reload this page" or "Stop loading this page", "Copy URL", "Site Control Center", "Close tab" and "More options"; also "Downloads", "New" on the footer's plus, and a pinned extension's action title, or its name when that's empty.

#### Scenario: Tooltip on back
- **WHEN** the pointer rests on the back button
- **THEN** a tooltip reads "Go back"

#### Scenario: Tooltip on a tab's close button
- **WHEN** the pointer rests on a tab's close button
- **THEN** a tooltip reads "Close tab" with the keys ⌘ and W

#### Scenario: Tooltip on the revealed sidebar's button
- **WHEN** the toolbar is off, the hidden sidebar is revealed and the pointer rests on its sidebar button
- **THEN** a tooltip reads "Lock sidebar"

#### Scenario: Tooltip on the toolbar's sidebar button
- **WHEN** the toolbar is shown, the sidebar is hidden, and the pointer rests on the toolbar's sidebar button
- **THEN** a tooltip reads "Show sidebar" with the keys ⌘ and S

#### Scenario: Tooltip on a pinned extension
- **WHEN** a pinned extension has set its action's title to "3 logins for this site" and the pointer rests on its tile
- **THEN** a tooltip reads "3 logins for this site"

### Requirement: URL field
Below the top row, the sidebar SHALL show the active tab's host without a leading `www.`, or its full URL for pages without a host such as `chrome://` pages and files, with a search icon and "Search or Enter URL…" for a new tab page. Clicking the field SHALL open the command bar on the current URL, and its context menu SHALL offer Copy URL. While the pointer is over the field, its background SHALL darken. While the toolbar shows, the field SHALL be its host instead.

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

### Requirement: URL field buttons
While the toolbar is off and the pointer is anywhere over the key window's sidebar, the URL field's trailing end SHALL show a copy button and the site-controls button, fading in and out. While the toolbar shows, its buttons SHALL always show (`page-toolbar`).

#### Scenario: Pointer over the tab list
- **WHEN** the toolbar is off and the pointer moves over the tab list of the key window
- **THEN** the URL field shows its copy and site-controls buttons

### Requirement: Extension actions
The sidebar SHALL show the actions of extensions the user has pinned as tiles with their icons and badges, in a row of their own below the URL field at every sidebar width, while the toolbar is off. Clicking an action SHALL run it as Chromium's toolbar would, opening its popup window beside the tile, as `extensions` defines. An action that's off for the active tab SHALL be dimmed and SHALL NOT run when clicked. The row SHALL show only while some extension is pinned.

#### Scenario: Pinned extension with a popup
- **WHEN** the user clicks a pinned extension's tile and its action has a popup
- **THEN** the popup window opens beside that tile and is interactive

#### Scenario: Pinned extension that's off for the tab
- **WHEN** a pinned extension's action is off for the active tab and the user clicks its tile
- **THEN** the tile stays dimmed and the action doesn't run, and right-clicking the tile still shows the extension's menu

#### Scenario: Badge text
- **WHEN** an extension sets its action's badge text to "3"
- **THEN** its tile in the sidebar shows a "3" badge

#### Scenario: Badge with the default colours
- **WHEN** an extension sets badge text without setting its colours
- **THEN** the badge shows black text on white in Light Mode, and white text on near-black in Dark Mode

#### Scenario: Badge colours set by the extension
- **WHEN** an extension sets its badge's background with `chrome.action.setBadgeBackgroundColor` and its text colour with `chrome.action.setBadgeTextColor`
- **THEN** the badge uses both colours, and without a text colour it uses black or white, whichever contrasts more with the background

#### Scenario: Extension without a pin
- **WHEN** the user opens the Site Control Center and chooses an unpinned extension
- **THEN** its action runs, and its popup window opens beside the site-controls button

#### Scenario: Nothing pinned
- **WHEN** extensions are installed and none of them is pinned
- **THEN** the sidebar shows no row for them

#### Scenario: Newly installed extension
- **WHEN** the user installs an extension with an action
- **THEN** its tile appears among the pinned actions, and the row shows if it was hidden

#### Scenario: Toolbar shown
- **WHEN** the toolbar is shown and an extension is pinned
- **THEN** the sidebar shows no row for it, and its tile is in the toolbar
