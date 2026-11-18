## MODIFIED Requirements

### Requirement: Grid of extensions
Under the heading "Extensions", the Site Control Center SHALL show every extension with an action as an icon tile, in rows of four. Pinned extensions SHALL come first, in their pinned order, followed by the others in alphabetical order of their names as `chrome://extensions` shows them. A tile's tooltip SHALL be the title the extension gives its action for the active tab, or its name when that title is empty, and the same text SHALL be its VoiceOver label.

#### Scenario: Order
- **WHEN** two of ten extensions are pinned and the Site Control Center opens
- **THEN** the two pinned extensions come first in their pinned order, followed by the other eight from A to Z

#### Scenario: Order ignores action titles
- **WHEN** an unpinned extension sets its action's title to text that sorts before every other extension's name, and the Site Control Center opens
- **THEN** its tile keeps its name's place among the unpinned extensions

#### Scenario: Tooltip
- **WHEN** the pointer rests on a tile
- **THEN** a tooltip shows the action's title, or the extension's name when the action has no title
