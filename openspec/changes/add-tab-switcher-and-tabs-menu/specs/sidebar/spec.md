## MODIFIED Requirements

### Requirement: Today tab menu
A Today tab's context menu SHALL offer, with a divider between each group: Pin Tab and Pin to Favorites; Copy Link and Duplicate; Split with Tab › (`split-view`) and Move to Space › (`spaces`); Rename… and Mute or Unmute; Close Tab and Close Tabs Below. A group whose items are all left out SHALL be left out with its divider. Close Tabs Below SHALL close only the Today tabs below it.

#### Scenario: Today tab's menu
- **WHEN** there is one Space and the user right-clicks a Today tab's row
- **THEN** the menu offers Pin Tab, Pin to Favorites, a divider, Copy Link, Duplicate, a divider, Split with Tab, a divider, Rename…, Mute, a divider, Close Tab and Close Tabs Below

#### Scenario: With another Space
- **WHEN** there are two Spaces and the user right-clicks a Today tab's row
- **THEN** Move to Space follows Split with Tab in its group

#### Scenario: Incognito
- **WHEN** the user right-clicks a tab's row in an incognito window
- **THEN** the menu starts with Copy Link and Duplicate, with no pin items and no divider before them

#### Scenario: Close Tabs Below leaves pinned tabs
- **WHEN** the user chooses Close Tabs Below on the first Today tab of a Space with pinned tabs
- **THEN** the Today tabs below it close, and the pinned tabs stay
