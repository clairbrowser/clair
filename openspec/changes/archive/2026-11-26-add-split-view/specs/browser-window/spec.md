# Spec Delta

## ADDED Requirements

### Requirement: Both pages of a split are visible
When the active tab is in a split, the page area SHALL show both tabs' pages in their panes (`split-view`), each resized with its pane, and both SHALL be reported to the page as visible. Selecting a tab outside the split SHALL report both as hidden.

#### Scenario: A split
- **WHEN** the window shows a split
- **THEN** both panes' pages report `document.visibilityState` as `visible`

#### Scenario: Leaving the split
- **WHEN** the user selects a tab outside the split
- **THEN** both of the split's pages report `document.visibilityState` as `hidden`
