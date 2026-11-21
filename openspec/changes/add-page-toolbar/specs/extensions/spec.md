# Spec Delta

## MODIFIED Requirements

### Requirement: New extensions pinned to the sidebar
An extension the user has just installed through a confirmation SHALL be pinned, so its action shows as a button in the toolbar, or in the sidebar while the toolbar is off. Extensions installed without the user, such as by policy or sync, and updates to installed extensions SHALL keep their pinned state.

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

#### Scenario: Another extension from the toolbar
- **WHEN** the toolbar is shown and the user opens a second pinned extension's popup, whose tile is further from the trailing edge
- **THEN** its window's top-trailing corner is at the same place as the first's

#### Scenario: Moving a popup
- **WHEN** the user drags the popup window's title bar
- **THEN** the window moves and stays open, and the popup keeps working

#### Scenario: Page grows after it opens
- **WHEN** the popup page's content grows after the window has opened
- **THEN** the window grows to fit it, keeping its top-leading corner where it is, and stays on screen
