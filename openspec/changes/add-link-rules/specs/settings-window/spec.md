# Spec Delta

## ADDED Requirements

### Requirement: Link Rules button
The Links page SHALL end with a card of its own below the Peek toggles, separated from them by a divider, laid out as Arc's Air Traffic Control row: one row labelled "Choose where links open inside Clair", without a full stop, with a "Link Rules…" button at its trailing edge, and no info button. The button SHALL open the Link Rules dialog on the Settings window (`link-rules`).

#### Scenario: The row
- **WHEN** the user opens the Links page
- **THEN** below the Peek toggles' card and a divider, a separate card shows "Choose where links open inside Clair" and a "Link Rules…" button, with no info button

#### Scenario: Opening the dialog
- **WHEN** the user chooses "Link Rules…"
- **THEN** the Link Rules dialog opens on the Settings window, which dims behind it

### Requirement: Links page icon
The Links page's toolbar item SHALL show the `interface.window.on.rectangle` symbol, a window over a window as Arc's Links icon.

#### Scenario: The toolbar
- **WHEN** the user opens the Settings window
- **THEN** the Links item shows a window over a window

## MODIFIED Requirements

### Requirement: Peek on links to other sites toggle
The Links page SHALL have, below the Peek toggle, a toggle labelled "Open a Peek window when clicking on links to other sites" with the note "Note: This only affects Favorites and Pinned tabs" in italics, as Arc's. It SHALL show and change the preference for links to other sites (`peek`), kept for the user across launches, on when no value is stored, and a change SHALL apply to open windows at once.

#### Scenario: Default
- **WHEN** Clair has no stored value for the preference and the user opens the Links page
- **THEN** the toggle is on, below the Shift-click toggle, with its note in italics

#### Scenario: Turning it off
- **WHEN** the user turns the toggle off and clicks a link to another site in an open favorite
- **THEN** the favorite navigates to the link, and no Peek opens
