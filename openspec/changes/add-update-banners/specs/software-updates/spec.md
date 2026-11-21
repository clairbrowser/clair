# Spec Delta

## MODIFIED Requirements

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

## ADDED Requirements

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
