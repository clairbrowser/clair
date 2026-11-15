# Spec Delta

## ADDED Requirements

### Requirement: Link Rules button
The Links page SHALL have, in a card below the Peek toggles, a row labelled "Link rules" with the note "Choose which Space opens links from other apps." and a "Link Rules…" button that opens the Link Rules dialog on the Settings window (`link-rules`).

#### Scenario: The row
- **WHEN** the user opens the Links page
- **THEN** below the Peek toggles, a card shows "Link rules", its note and a "Link Rules…" button

#### Scenario: Opening the dialog
- **WHEN** the user chooses "Link Rules…"
- **THEN** the Link Rules dialog opens on the Settings window, which dims behind it
