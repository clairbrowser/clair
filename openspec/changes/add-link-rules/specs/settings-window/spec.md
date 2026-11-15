# Spec Delta

## ADDED Requirements

### Requirement: Link Rules button
The Links page SHALL end with a card of its own below the Peek toggles, laid out as Arc's Air Traffic Control row: one row labelled "Choose where links open inside Clair." with a "Link Rules…" button at its trailing edge, and no info button. The button SHALL open the Link Rules dialog on the Settings window (`link-rules`).

#### Scenario: The row
- **WHEN** the user opens the Links page
- **THEN** below the Peek toggles' card, a separate card shows "Choose where links open inside Clair." and a "Link Rules…" button, with no info button

#### Scenario: Opening the dialog
- **WHEN** the user chooses "Link Rules…"
- **THEN** the Link Rules dialog opens on the Settings window, which dims behind it
