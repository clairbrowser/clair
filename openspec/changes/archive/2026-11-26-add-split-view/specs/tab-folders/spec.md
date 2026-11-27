# Spec Delta

## MODIFIED Requirements

### Requirement: Folders hold pinned tabs
A Space's pinned section SHALL hold pinned tabs, pinned splits (`split-view`) and folders in the user's order. A folder SHALL have a name and hold pinned tabs and pinned splits only, in the user's order, and no folders. A folder SHALL belong to one Space. Favorites and Today tabs SHALL hold no folders, and incognito and guest windows SHALL show none.

#### Scenario: A folder among pinned tabs
- **WHEN** "Work" has the pinned tab "Mail", then the folder "Docs" holding the pinned tabs "Spec" and "Plan"
- **THEN** the pinned section lists "Mail", "Docs", and under "Docs" "Spec" and "Plan"

#### Scenario: Another Space
- **WHEN** the folder "Docs" is in "Work" and the window shows "Home"
- **THEN** the sidebar doesn't list "Docs"

#### Scenario: A split in a folder
- **WHEN** the folder "Docs" holds "Spec" and then a pinned split of "News" and "Plan"
- **THEN** under "Docs" the sidebar lists "Spec" and one split row holding a "News" chip and a "Plan" chip
