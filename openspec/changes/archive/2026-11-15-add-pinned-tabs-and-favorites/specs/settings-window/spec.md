# Spec Delta

## ADDED Requirements

### Requirement: Peek on links to other sites toggle
The Links page SHALL have, below the Peek toggle, a toggle labelled "Open a Peek window when clicking on links to other sites" with the note "(Note: This only affects Favorites and Pinned tabs)". It SHALL show and change the preference for links to other sites (`peek`), kept for the user across launches, on when no value is stored, and a change SHALL apply to open windows at once.

#### Scenario: Default
- **WHEN** Clair has no stored value for the preference and the user opens the Links page
- **THEN** the toggle is on, below the Shift-click toggle, with its note

#### Scenario: Turning it off
- **WHEN** the user turns the toggle off and clicks a link to another site in an open favorite
- **THEN** the favorite navigates to the link, and no Peek opens
