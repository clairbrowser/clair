# software-updates Specification

## Purpose

Defines how an installed copy of Clair finds, verifies, downloads and installs newer Clair releases. Users stay on current engine security fixes without reinstalling by hand.

## Requirements

### Requirement: Update feed location
Clair SHALL check for updates against the appcast at `https://github.com/clairbrowser/clair/raw/main/.sparkle/appcast.xml`, and against no other update source.

#### Scenario: Update check request
- **WHEN** Clair checks for updates
- **THEN** it fetches the appcast from `https://github.com/clairbrowser/clair/raw/main/.sparkle/appcast.xml` and makes no request to Google's or Chromium's update services

### Requirement: Automatic background updates
Clair SHALL check for updates automatically at least once every 24 hours while running, without asking permission first. When an update is found, Clair SHALL download it in the background without showing any window. Clair SHALL provide no settings UI for update behavior.

#### Scenario: Fresh install checks automatically
- **WHEN** a newly installed Clair has been running for 24 hours
- **THEN** it has checked the appcast at least once without the user asking it to

#### Scenario: Update found in the background
- **WHEN** an automatic check finds a newer compatible release
- **THEN** Clair downloads it without showing a dialog or interrupting browsing

### Requirement: Downloaded update installs on quit
A downloaded update SHALL be installed the next time the user quits Clair. The user's next launch then runs the new version, with no other action needed.

#### Scenario: Quit with an update ready
- **WHEN** an update has finished downloading and the user quits Clair
- **THEN** the update is installed, and the next launch of Clair runs the new version

### Requirement: Downloaded update installs while the user is idle
While a downloaded update is waiting, Clair SHALL install it and relaunch on its own once the Mac has received no keyboard, mouse or trackpad input for 30 minutes. It SHALL NOT do so while a download is in progress, an incognito window is open, or a tab is playing audio or using the camera, microphone or screen; it SHALL try again at the next idle period. If Clair was not the active app, the relaunched Clair SHALL stay in the background.

#### Scenario: User away with an update ready
- **WHEN** an update is waiting and the Mac has had no input for 30 minutes
- **THEN** Clair installs the update, relaunches with its windows and tabs restored, and runs the new version

#### Scenario: Something would be interrupted
- **WHEN** an update is waiting and the Mac has had no input for 30 minutes, but a download is in progress, an incognito window is open, or a tab is playing audio or using the camera, microphone or screen
- **THEN** Clair does not install the update, and installs it at a later idle period once none of these holds

#### Scenario: Clair in the background
- **WHEN** Clair installs an update while idle and another app was active
- **THEN** the relaunched Clair does not become the active app

### Requirement: Update ready indicator in the application menu
The Clair application menu SHALL contain one update item. While a downloaded update is waiting to be installed, that item SHALL read "Update Available…" and carry a "1 update" badge, in place of "Check for Updates…". Choosing it SHALL show an alert with the new version and "Restart and Update" and "Later". Clair SHALL add no other update item to the menu. Status SHALL NOT appear on the About settings page.

#### Scenario: Update ready
- **WHEN** an update has finished downloading
- **THEN** the Clair menu's update item reads "Update Available…" with a "1 update" badge, and the menu has no "Check for Updates…" item

#### Scenario: Choosing Update Available
- **WHEN** the user chooses "Update Available…"
- **THEN** an alert shows the new version with "Restart and Update" and "Later", and "Restart and Update" installs the update and relaunches Clair

#### Scenario: No update waiting
- **WHEN** no downloaded update is waiting
- **THEN** the Clair menu's update item reads "Check for Updates…" with no badge

### Requirement: Manual update check
While no downloaded update is waiting, the Clair application menu's update item SHALL read "Check for Updates…". It SHALL check the appcast immediately and report the result in a small alert. When a newer release is available, the alert SHALL show its version and offer "Restart and Update" and "Later".

#### Scenario: Already up to date
- **WHEN** a user chooses "Check for Updates…" while running the newest compatible release in the appcast
- **THEN** an alert says Clair is up to date and shows the running version

#### Scenario: Update available after a manual check
- **WHEN** a user chooses "Check for Updates…" and the appcast lists a newer compatible release
- **THEN** Clair downloads it, and an alert shows the new version with "Restart and Update" and "Later"

#### Scenario: Choosing Later
- **WHEN** the user chooses "Later" in that alert
- **THEN** the update stays downloaded, the Clair menu's update item reads "Update Available…", and the update installs on quit or while the user is idle

#### Scenario: Check fails
- **WHEN** a user chooses "Check for Updates…" and the appcast cannot be reached
- **THEN** an alert says the check failed, and nothing changes

### Requirement: Update signature verification
Clair SHALL install an update only if the new app carries a valid code signature and either of these holds:
- its EdDSA signature verifies against the Sparkle public key embedded in the running app
- the new app is signed by the same Apple team as the running app, and its EdDSA signature verifies against the new app's own public key, as when the EdDSA key is rotated

An update that meets neither MUST be rejected and left uninstalled.

#### Scenario: Tampered update is rejected
- **WHEN** a downloaded update's file does not match its EdDSA signature in the appcast
- **THEN** Clair refuses to install it, the Clair menu doesn't show "Update Available…" for it, and Clair keeps running the current version unchanged

#### Scenario: Valid update is installed
- **WHEN** a downloaded update's EdDSA signature verifies against the running app's key and its app has a valid code signature
- **THEN** Clair installs it

#### Scenario: Team and key both changed
- **WHEN** a downloaded update's app is signed by a different Apple team, and its EdDSA signature verifies only against a new key in that app
- **THEN** Clair refuses to install it, as Sparkle allows changing the team or the EdDSA key in one update, not both

### Requirement: Only newer, compatible releases are offered
Clair SHALL offer only releases whose build number is higher than the running build, and whose minimum macOS version is no higher than the running macOS version.

#### Scenario: Older or equal build is not offered
- **WHEN** the newest appcast item's build number is equal to or lower than the running build
- **THEN** Clair downloads nothing, and a manual check reports that Clair is up to date

#### Scenario: Release needs a newer macOS
- **WHEN** the newest appcast item declares a minimum macOS version higher than the running macOS
- **THEN** Clair does not offer that release

### Requirement: Delta updates with full-update fallback
When the appcast provides a delta for the running build, Clair SHALL download the delta instead of the full release. If no delta matches, or applying it fails, Clair SHALL use the full release.

#### Scenario: Delta available
- **WHEN** the newest release includes a delta for the running build number
- **THEN** Clair downloads only the delta and installs the new release from it

#### Scenario: Delta fails to apply
- **WHEN** applying a downloaded delta fails, for example because the installed app was modified
- **THEN** Clair downloads the full release and installs that instead

### Requirement: Relaunch preserves the browsing session
When Clair relaunches to install an update, through "Restart and Update" or while the user is idle, it SHALL restore every window and tab that was open before the relaunch, whatever the user's startup setting. After "Restart and Update", in the update alert or the sidebar banner, it SHALL warn first if quitting would cancel an active download, and SHALL NOT ask about incognito windows, which close and are not restored, as in Arc.

#### Scenario: Restart and update
- **WHEN** a user chooses "Restart and Update" while three windows with open tabs exist
- **THEN** Clair quits, installs the update, and relaunches with the same three windows and their tabs restored

#### Scenario: Restore setting off
- **WHEN** "When opening Clair, restore windows from previous session" is off and a user chooses "Restart and Update" while two windows with open tabs exist
- **THEN** Clair relaunches with both windows and their tabs restored, not one window

#### Scenario: Active download on relaunch
- **WHEN** a user chooses "Restart and Update" while a download is in progress
- **THEN** Clair warns that relaunching will cancel the download, and lets the user postpone the update

#### Scenario: Incognito window on relaunch
- **WHEN** a user chooses "Restart and Update", in the update alert or the sidebar banner, while an incognito window is open
- **THEN** Clair relaunches without asking, the incognito window is not restored, and the other windows and tabs are

### Requirement: Waiting update banner in the sidebar
While a downloaded update is waiting to be installed, every window's sidebar SHALL show a pill reading "New Clair Version Available" at its bottom, directly above the footer and across the sidebar's width. It SHALL show in incognito and guest windows too. It SHALL NOT show while no downloaded update is waiting.

#### Scenario: Update downloaded in the background
- **WHEN** an automatic check finishes downloading an update while two windows are open
- **THEN** both windows' sidebars show "New Clair Version Available" above the footer, and the Clair menu's update item reads "Update Available…"

#### Scenario: No update waiting
- **WHEN** no downloaded update is waiting
- **THEN** no window's sidebar shows the pill, and the footer sits directly below the tab list

#### Scenario: Rejected update
- **WHEN** a downloaded update fails signature verification
- **THEN** no window's sidebar shows the pill

#### Scenario: Window opened later
- **WHEN** an update is waiting and the user opens a new window
- **THEN** the new window's sidebar shows the pill too

### Requirement: The banner opens on hover
While the pointer is over the waiting-update pill, it SHALL grow upward into a card over the tab list, holding the title "New Clair Version Available" and a "Restart and Update" button. When the pointer leaves the card, it SHALL collapse back into the pill. The card SHALL have no update settings. Opening it SHALL NOT move the tab list.

#### Scenario: Hovering the pill
- **WHEN** the pointer moves onto the pill
- **THEN** the pill grows upward into a card with the title and a "Restart and Update" button, and the tabs behind it stay where they were

#### Scenario: Pointer leaves
- **WHEN** the card is open and the pointer moves off it
- **THEN** the card collapses back into the pill

### Requirement: Restart and Update from the banner
Choosing the banner's "Restart and Update" SHALL install the waiting update and relaunch Clair without the new version's alert, since the click is the confirmation. From there it SHALL behave exactly as the update alert's "Restart and Update": no question about incognito windows, a warning only before cancelling an active download, and declining that warning SHALL leave the update waiting.

#### Scenario: Nothing to lose
- **WHEN** the user clicks the banner's "Restart and Update" with no active download
- **THEN** Clair relaunches into the new version with its windows and tabs restored, and shows no alert first

#### Scenario: Incognito window open
- **WHEN** the user clicks the banner's "Restart and Update" while an incognito window is open
- **THEN** Clair relaunches without asking, the incognito window is not restored, and the other windows and tabs are

#### Scenario: Active download
- **WHEN** the user clicks the banner's "Restart and Update" while a download is in progress
- **THEN** Clair warns that relaunching will cancel the download, and if the user postpones, Clair keeps running and the pill stays

### Requirement: Update Complete card after an update
On the first launch of a version newer than the one Clair last ran, every window's sidebar SHALL show an open "Update Complete!" card at its bottom, above the footer, with a close button and a "See What's New" row. It SHALL NOT show on Clair's first launch ever, on a launch of the same version, or on a launch of an older version. A waiting update's pill SHALL replace it.

#### Scenario: First launch after updating
- **WHEN** Clair relaunches after installing an update from 0.1.2 to 0.1.3
- **THEN** each window's sidebar shows "Update Complete!" with a close button and "See What's New", without the pointer over it

#### Scenario: First launch ever
- **WHEN** Clair launches with no record of a previous version
- **THEN** no window shows the card

#### Scenario: Ordinary relaunch
- **WHEN** Clair quits and launches again on the same version, whether or not the card was closed
- **THEN** no window shows the card

#### Scenario: Another update arrives
- **WHEN** the card shows and an automatic check downloads a newer update
- **THEN** the card goes, and the pill shows "New Clair Version Available" in its place

### Requirement: Closing the Update Complete card
The card's close button SHALL close the card in every window. Choosing "See What's New" SHALL open the running version's release page, `https://github.com/clairbrowser/clair/releases/tag/v<version>`, in a new foreground tab of that window, and close the card in every window. The card SHALL show only during the first launch of the new version: once Clair quits, it SHALL NOT show again for that version, whether or not it was closed.

#### Scenario: Close button
- **WHEN** the user clicks the card's close button while two windows are open
- **THEN** the card goes in both windows, and it doesn't come back when Clair relaunches

#### Scenario: See What's New
- **WHEN** the user chooses "See What's New" after updating to 0.1.3
- **THEN** a new active tab opens `https://github.com/clairbrowser/clair/releases/tag/v0.1.3` in that window, and the card goes in every window

#### Scenario: Not closed before quitting
- **WHEN** the card shows and the user quits Clair without closing it, then launches it again
- **THEN** no window shows the card
