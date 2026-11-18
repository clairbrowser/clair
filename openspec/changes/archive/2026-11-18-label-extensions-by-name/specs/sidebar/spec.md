## MODIFIED Requirements

### Requirement: Tooltips in Arc's wording
The sidebar's controls SHALL have Clair's own tooltips, never the system's, in Arc's wording and with their shortcuts: "Hide sidebar" ("Lock sidebar" while the hidden sidebar is revealed), "Go back", "Go forward", "Reload this page" or "Stop loading this page", "Copy URL", "Site Control Center", "Close tab" and "More options"; also "Downloads", "New" on the footer's plus, and on a pinned extension's tile the title the extension gives its action for the active tab, or its name when that title is empty.

#### Scenario: Tooltip on back
- **WHEN** the pointer rests on the back button
- **THEN** a tooltip reads "Go back"

#### Scenario: Tooltip on a tab's close button
- **WHEN** the pointer rests on a tab's close button
- **THEN** a tooltip reads "Close tab" with the keys ⌘ and W

#### Scenario: Tooltip on the revealed sidebar's button
- **WHEN** the hidden sidebar is revealed and the pointer rests on its sidebar button
- **THEN** a tooltip reads "Lock sidebar"

#### Scenario: Tooltip on a pinned extension
- **WHEN** a pinned extension has set its action's title to "3 logins for this site" and the pointer rests on its tile
- **THEN** a tooltip reads "3 logins for this site"
