## MODIFIED Requirements

### Requirement: Tab shortcuts treat a tab and its Peek as one
Ctrl+Tab and Ctrl+Shift+Tab (`tab-switcher`), Opt+Cmd+Down and Up, and Cmd+1 to Cmd+9 SHALL count a tab and its Peek as one stop. Selecting a tab that has a Peek SHALL show the Peek.

#### Scenario: Ctrl+Tab across a Peek
- **WHEN** the window showed "Docs", then "Mail" with its Peek open, and the user presses Ctrl+Tab
- **THEN** the switcher has one card for "Mail" and its Peek, and releasing Ctrl shows "Docs" while the Peek of "Mail" stays open

#### Scenario: Back to a Peek
- **WHEN** the user then presses Ctrl+Tab again
- **THEN** the window shows "Mail" with its Peek

#### Scenario: Next Tab across a Peek
- **WHEN** the first of three tabs has a Peek open and shows it, and the user presses Opt+Cmd+Down
- **THEN** the second tab becomes active, and the first tab's Peek stays open

#### Scenario: Cmd+number
- **WHEN** the second tab has a Peek and the user presses Cmd+2
- **THEN** the second tab shows with its Peek
