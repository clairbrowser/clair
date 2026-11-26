# Spec Delta

## MODIFIED Requirements

### Requirement: Peek layout
The Peek SHALL be a card with rounded corners centred over the page card, about 80% of the page card's width and its full height less about 2 points at the top and bottom. Behind it, the parent page SHALL shrink by about 9 points on each side and be washed out toward the window's background colour, in Light and Dark Mode. In a split, the Peek SHALL be centred over the whole page area, measured as one card, and only its parent's pane SHALL shrink and wash out behind it, as in Arc.

#### Scenario: Peek open
- **WHEN** a Peek is open in a window whose page card is 1723 by 1030 points
- **THEN** the Peek is about 1386 by 1026 points, centred on the card, over a smaller, washed-out parent page

#### Scenario: Resizing the window
- **WHEN** the user resizes the window with a Peek open
- **THEN** the Peek and the parent page keep their proportions to the card

#### Scenario: A Peek in a split
- **WHEN** the window shows a split and a Peek opens from the trailing pane
- **THEN** the Peek is centred on the page area, about 80% of its width, the trailing pane shrinks and washes out behind it, and the leading pane keeps its size and colour

### Requirement: Peek buttons
A column of round buttons SHALL sit outside the Peek's top-trailing corner, beside the card: Close (×), then Expand, then Open in Split View (`split-view`), as in Arc, which SHALL NOT show while the Peek's parent is in a split. Each SHALL highlight under the pointer and have a VoiceOver label naming its action, and Arc's tooltip: "Close" with ⌘W, "Expand" with ⌘O, and "Open in Split View".

#### Scenario: Buttons shown
- **WHEN** a Peek is open on a tab that isn't in a split
- **THEN** Close, Expand and Open in Split View show in a column beside its top-trailing corner, outside the card

#### Scenario: A Peek in a split
- **WHEN** a Peek is open on a tab in a split
- **THEN** only Close and Expand show

## ADDED Requirements

### Requirement: The link status names the Peek
While the Peek preference is on, Shift is held and the pointer rests on a link in a page, the link status (`browser-window`) SHALL read "Open <URL> in Peek", where Shift+click opens it in a Peek. Pressing or releasing Shift while the status shows SHALL update it at once. Inside a Peek, where Shift+click opens a new tab, it SHALL show the URL alone.

#### Scenario: Holding Shift over a link
- **WHEN** the pointer rests on a link to `https://example.com/` and the user holds Shift
- **THEN** the link status reads "Open https://example.com/ in Peek"

#### Scenario: Peek preference off
- **WHEN** the Peek preference is off and the user holds Shift over the link
- **THEN** the link status reads `https://example.com/`
