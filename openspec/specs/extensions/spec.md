# extensions Specification

## Purpose
Defines how Clair installs, updates, confirms, pins and shows Chrome extensions, following Arc: installs from the Chrome Web Store, automatic updates, native confirmations, and popups in a small window.

## Requirements

### Requirement: Installing from the Chrome Web Store
Clair SHALL let users install extensions from `https://chromewebstore.google.com`. The store's install button SHALL be enabled, and installing SHALL download the extension from Google and install it after the user confirms.

#### Scenario: Installing a store extension
- **WHEN** the user opens an extension's page in the Chrome Web Store, clicks its install button and confirms
- **THEN** the extension is downloaded from Google, installed and enabled, and the store page shows it as installed

#### Scenario: The store's download stays out of Downloads
- **WHEN** an extension is installed from the store
- **THEN** its package doesn't appear in the sidebar's downloads list

### Requirement: Other installation paths kept
Clair SHALL keep the installation paths it had before, including CRX files with the "Always prompt for install" flag (`--extension-mime-request-handling=always-prompt-for-install`). Installed extensions SHALL run with full Chrome extension API support, except for APIs that show UI the native window doesn't host, such as side panels, as `browser-window` defines.

#### Scenario: Installing an extension from a CRX file
- **WHEN** a user enables "Always prompt for install" for extension MIME handling in `chrome://flags`, and then opens a link to an extension's CRX file
- **THEN** Clair asks to confirm the install, and after installation the extension runs and its action is listed in the Site Control Center

### Requirement: Store wording names Clair
On the Chrome Web Store's pages, the install button SHALL read "Add to Clair" and, for an installed extension, "Remove from Clair", and the store's prompts to switch to Chrome SHALL be removed. The rest of the store's text SHALL be left as the store wrote it.

#### Scenario: Extension not installed
- **WHEN** the user opens the store page of an extension that isn't installed
- **THEN** its button reads "Add to Clair", and no banner or popup asks the user to switch to Chrome

#### Scenario: Extension installed
- **WHEN** the user opens the store page of an installed extension
- **THEN** its button reads "Remove from Clair"

### Requirement: Extensions update automatically
Clair SHALL check for updates to installed extensions whose update URL is the Chrome Web Store's, or that set their own, and SHALL install the updates, as Chrome does. Store extensions SHALL be checked with Google's extension update service, and other extensions with their own update server. A profile with no such extensions SHALL make no update requests.

#### Scenario: A newer version is published
- **WHEN** a store extension is installed and the store publishes a newer version
- **THEN** Clair installs the newer version at its next update check without the user doing anything

#### Scenario: No store extensions
- **WHEN** a profile has no extensions with an update URL
- **THEN** Clair makes no extension update requests to Google

#### Scenario: Extension with its own update server
- **WHEN** an installed extension's update URL names a server other than the store's
- **THEN** Clair checks it with that server only, and the check doesn't reach Google

### Requirement: Install confirmation as a native sheet
Before an extension is installed, Clair SHALL ask in a Clair dialog (`dialogs`) on the window. The dialog SHALL show the extension's icon, the title "Add “<name>” to Clair?", the heading "It can:" followed by the extension's permissions as a list, and the buttons "Add Extension" (default, Return) and "Cancel" (Esc). The window SHALL stay blocked until the user answers.

#### Scenario: Confirming an install
- **WHEN** the user clicks "Add to Clair" on a store page
- **THEN** a sheet asks "Add “<name>” to Clair?" with the extension's permissions under "It can:", and pressing Return installs the extension

#### Scenario: Cancelling an install
- **WHEN** the install sheet is shown and the user presses Esc or clicks "Cancel"
- **THEN** the sheet closes, the extension isn't installed, and the store page shows it as not installed

#### Scenario: Extension without permissions
- **WHEN** the extension being installed asks for no permissions
- **THEN** the sheet shows the title and buttons without the "It can:" list

#### Scenario: Many permissions
- **WHEN** the extension being installed asks for more permissions than fit
- **THEN** the list scrolls inside the dialog, and the buttons stay visible

### Requirement: Other install prompts as native sheets
Chromium's other install prompts, such as re-enabling an extension whose update asks for new permissions or an extension asking for optional permissions, SHALL use the same kind of sheet. Each SHALL show Chromium's own title, permissions and button labels for that prompt, and answering it SHALL have the effect Chromium's prompt has.

#### Scenario: Optional permission request
- **WHEN** an extension calls `chrome.permissions.request` for a permission it doesn't have
- **THEN** a sheet shows Chromium's request text and the permission, and accepting grants it while cancelling leaves it denied

### Requirement: Remove confirmation as a native sheet
When an extension is removed through a path that asks for confirmation, Clair SHALL ask in a Clair dialog (`dialogs`) on the window, titled "Remove “<name>” from Clair?", with the extension's icon, a "Remove Extension" button (default, Return) not marked destructive, as in Arc, "Cancel" (Esc), and no "report abuse" option. When another extension asked for the removal, the dialog SHALL also say "“<requester>” wants to remove this extension." under the title.

#### Scenario: Removing from the store
- **WHEN** the user clicks "Remove from Clair" on an installed extension's store page and clicks "Remove Extension"
- **THEN** the extension is removed, its button leaves the sidebar, and the store page shows it as not installed

#### Scenario: Keeping the extension
- **WHEN** the remove sheet is shown and the user presses Esc
- **THEN** the extension stays installed

#### Scenario: Another extension asks to remove one
- **WHEN** an extension calls `chrome.management.uninstall` for a different extension and the dialog shows
- **THEN** the dialog says "“<requester>” wants to remove this extension." with the requesting extension's name, keeps its title, icon and buttons, and Esc keeps the extension installed

#### Scenario: The user removes an extension
- **WHEN** the dialog shows for a removal the user started, or for an extension removing itself
- **THEN** the dialog has no line naming a requester

### Requirement: No post-install box
After an extension is installed, Clair SHALL NOT show Chromium's "has been added" box or any other dialog about the install.

#### Scenario: Installed from the store
- **WHEN** the user confirms an install from the store
- **THEN** no box, bubble or dialog appears after the extension is installed, and the window stays usable

### Requirement: New extensions pinned to the sidebar
An extension the user has just installed through a confirmation SHALL be pinned, so its action shows as a button in the toolbar, or in the sidebar while the toolbar is off, unless the user has turned off pinning new extensions on `chrome://extensions`. Chromium pins it, once; Clair doesn't pin it again. Extensions installed without the user, such as by policy or sync, and updates to installed extensions SHALL keep their pinned state.

#### Scenario: Installing an extension with an action
- **WHEN** the user installs an extension that has a toolbar action
- **THEN** its button appears among the pinned extensions, in the toolbar or the sidebar, after those already pinned

#### Scenario: Update keeps an unpinned extension unpinned
- **WHEN** the user has unpinned an extension and it updates
- **THEN** it stays unpinned

### Requirement: Extension popups in a window
An extension's popup SHALL open in a small titled window whose only enabled control is the close button. The window SHALL be movable by its title bar. It SHALL first open beside the control that opened it, following `sidebar`, or over the toolbar at a fixed place by the card's top-trailing corner while the toolbar shows (`page-toolbar`), as in Arc. Its page SHALL show whole, at the size the extension asks for, within Chromium's limits of 25×25 to 800×600 points.

#### Scenario: Opening a popup
- **WHEN** the toolbar is off and the user clicks a pinned extension's button whose action has a popup
- **THEN** a window with a close button opens beside the button, showing the whole popup page with no part clipped

#### Scenario: Opening a popup from the toolbar
- **WHEN** the toolbar is shown and the user clicks a pinned extension's tile whose action has a popup
- **THEN** a window with a close button opens over the toolbar, its top-trailing corner at the card's top edge and 40 points in from the card's trailing edge, showing the whole popup page

#### Scenario: A popup from the trailing pane
- **WHEN** the window shows a split and the user clicks a pinned extension's tile in the trailing pane's header
- **THEN** the popup's window opens at the trailing pane's top-trailing corner, not the leading pane's

#### Scenario: Another extension from the toolbar
- **WHEN** the toolbar is shown and the user opens a second pinned extension's popup, whose tile is further from the trailing edge
- **THEN** its window's top-trailing corner is at the same place as the first's

#### Scenario: Moving a popup
- **WHEN** the user drags the popup window's title bar
- **THEN** the window moves and stays open, and the popup keeps working

#### Scenario: Page grows after it opens
- **WHEN** the popup page's content grows after the window has opened
- **THEN** the window grows to fit it, keeping its top-leading corner where it is, and stays on screen

#### Scenario: Page resizes over the toolbar
- **WHEN** the toolbar is shown and the popup page's content changes size after the window has opened
- **THEN** the window fits it, keeping its top-trailing corner where it is, as in Arc, and stays on screen

### Requirement: Closing an extension popup
The popup window SHALL close when the user clicks its close button, presses Esc, clicks anywhere outside it, or clicks the button that opened it, when the page or Chromium closes it, and when the browser window it belongs to closes, whether or not its page has finished loading. Clicking the opening button SHALL only close the popup, not open it again.

#### Scenario: Clicking outside
- **WHEN** a popup window is open and the user clicks the page in the browser window
- **THEN** the popup closes and the click reaches the page

#### Scenario: Esc
- **WHEN** a popup window is key and the user presses Esc
- **THEN** the popup closes

#### Scenario: Close button
- **WHEN** the user clicks the popup window's close button
- **THEN** the popup closes, and Chromium treats it as closed by the user

#### Scenario: The window closes while the popup loads
- **WHEN** a popup's browser window closes before the popup's page has finished loading, as when the page closes that window itself
- **THEN** the popup closes with the window, the `chrome.action.openPopup()` call that opened it fails, and the browser keeps running

### Requirement: Opening a popup from the extension API
An extension SHALL be able to open its own popup with `chrome.action.openPopup()` in an active Clair window. The popup SHALL open as if its button had been clicked: beside its pinned tile, or beside the site-controls button when it isn't pinned.

#### Scenario: openPopup from a background script
- **WHEN** an extension with a popup calls `chrome.action.openPopup()` while a Clair window is active
- **THEN** the call succeeds and the extension's popup window opens beside its tile

#### Scenario: openPopup for an unpinned extension
- **WHEN** an unpinned extension with a popup calls `chrome.action.openPopup()` while a Clair window is active
- **THEN** the call succeeds and the extension's popup window opens beside the site-controls button

### Requirement: Extension context menu
Right-clicking or Control-clicking a pinned extension's tile, or a tile in the Site Control Center's grid, SHALL show a native menu built from Chromium's extension menu. It SHALL offer the items Chromium offers for that extension, including its name (which opens its home page), its own `chrome.contextMenus` action items, site access where it applies, Options, Pin or Unpin, Remove and Manage. It SHALL NOT offer a side panel item or Inspect Popup.

#### Scenario: Right-clicking a pinned button
- **WHEN** the user right-clicks a pinned extension's tile
- **THEN** a native menu with that extension's items opens, and the extension's popup doesn't open

#### Scenario: Pinning from a list row
- **WHEN** the user right-clicks an unpinned extension's tile in the Site Control Center and chooses Pin
- **THEN** its tile appears among the sidebar's pinned actions

#### Scenario: Right-clicking a tile in the Site Control Center
- **WHEN** the user right-clicks a tile in the Site Control Center's grid
- **THEN** a native menu with that extension's items opens, and the extension's popup doesn't open

#### Scenario: Removing from the menu
- **WHEN** the user chooses the menu's Remove item
- **THEN** the remove sheet asks for confirmation, as `Remove confirmation as a native sheet` defines

#### Scenario: Unpinning from the menu
- **WHEN** the user chooses Unpin in a pinned extension's menu
- **THEN** its tile leaves the sidebar's pinned actions

### Requirement: No uninstall pages
When an extension is removed, Clair SHALL NOT open the page the extension set with `chrome.runtime.setUninstallURL`. The API call SHALL still succeed.

#### Scenario: Removing an extension with an uninstall page
- **WHEN** the user removes an extension that has set an uninstall URL
- **THEN** the extension is removed and no new tab opens

### Requirement: Extensions menu
The menu bar SHALL have an Extensions menu just left of Window. It SHALL list every extension with an action in the frontmost browser window's profile, with its icon, by its name as `chrome://extensions` shows it, in alphabetical order of those names, followed by a separator, "Add Extension…" and "Manage Extensions…". The title an extension gives its action SHALL NOT change the menu.

#### Scenario: Listing extensions
- **WHEN** three extensions are installed and the user opens the Extensions menu
- **THEN** it lists the three with their icons from A to Z, then a separator, "Add Extension…" and "Manage Extensions…"

#### Scenario: An extension titles its action
- **WHEN** an extension sets its action's title to text other than its name, such as "Manage Extensions…", and the user opens the Extensions menu
- **THEN** the menu lists that extension by its name, in its name's place in the order

#### Scenario: Managing extensions
- **WHEN** the user chooses "Manage Extensions…"
- **THEN** `chrome://extensions` opens in a new tab

#### Scenario: Adding an extension
- **WHEN** the user chooses "Add Extension…"
- **THEN** the Chrome Web Store opens in a new tab

### Requirement: Running an extension from the Extensions menu
Choosing an extension in the Extensions menu SHALL run its action as Chromium's toolbar would, with its popup opening beside the site-controls button. An extension whose action is off for the active tab SHALL be listed but unavailable.

#### Scenario: Choosing an extension
- **WHEN** the user chooses an extension with a popup from the Extensions menu
- **THEN** its popup window opens beside the site-controls button

#### Scenario: Extension off for the tab
- **WHEN** an extension's action is off for the active tab and the user opens the Extensions menu
- **THEN** the extension is listed but can't be chosen

### Requirement: What a store update check sends
A store update check SHALL send only each extension's ID, version, install source and the hash of its cached store package, Clair's Chromium version, channel and language, the platform and architecture, and random per-request IDs. It SHALL NOT send the macOS version, hardware details, install dates or IDs, cohorts, enabled state or activity data, and Clair SHALL send no report after an install or update.

#### Scenario: Reading a store update check
- **WHEN** a profile with a store extension checks for updates and the request is captured
- **THEN** its body names the extension's ID, version and install source, the Chromium version, channel, language, `mac` and `arm64`, and none of the fields this requirement rules out

#### Scenario: Update as a patch
- **WHEN** a store extension that Clair last downloaded through an update check gets a newer version
- **THEN** the check names the hash of the package Clair already has, and Clair installs the update from a patch to it when the store offers one, or from the full package when it doesn't

#### Scenario: After an update installs
- **WHEN** a store update check finds a newer version and Clair installs it
- **THEN** Clair sends no further request to Google about the install

### Requirement: Store-flagged extensions turned off
When a store update check reports that an installed extension is malware, Clair SHALL unload it, and the user SHALL only be able to remove it. When it reports a policy violation or a potentially unwanted extension, Clair SHALL turn the extension off, with Chromium's reason shown in `chrome://extensions`, and the user MAY turn it back on. When a later check clears the flag, Clair SHALL restore the extension as Chrome does.

#### Scenario: Malware
- **WHEN** an installed store extension is reported as malware at an update check
- **THEN** it stops running, its button leaves the sidebar and the Extensions menu, and `chrome://extensions` lists it as malware with no way to turn it on

#### Scenario: Policy violation
- **WHEN** an installed store extension is reported as violating the store's policy
- **THEN** it's turned off, `chrome://extensions` gives that reason, and the user can turn it back on there

#### Scenario: Turned back on by the user
- **WHEN** the user has turned a policy-violation extension back on and the next check reports the same flag
- **THEN** the extension stays on

#### Scenario: Flag cleared
- **WHEN** a check no longer reports the malware flag for an extension Clair unloaded for it
- **THEN** the extension is loaded again, as it was before

### Requirement: Notice for malware extensions
When Clair unloads an extension for malware, it SHALL tell the user in a Clair dialog (`dialogs`) on the frontmost browser window, saying the extension contains malware and was turned off for the user's safety, with a single OK button. One dialog SHALL name every extension unloaded for malware that the user hasn't yet been told about. Policy-violation and potentially unwanted extensions SHALL be turned off without a dialog, as in Chrome.

#### Scenario: One extension found
- **WHEN** an installed extension is unloaded for malware while a browser window is open
- **THEN** a dialog on that window says "“X” contains malware and was turned off for your safety.", naming the extension, and OK closes it

#### Scenario: Told once
- **WHEN** the user has closed the dialog for an extension and Clair is relaunched
- **THEN** no dialog about that extension appears again

#### Scenario: No window open
- **WHEN** an extension is unloaded for malware while no browser window is open
- **THEN** the dialog appears on the next browser window that opens
