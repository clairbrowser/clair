# Spec Delta

## ADDED Requirements

### Requirement: Pinned tabs and favorites when a Space's profile changes
When a Space's profile changes, its pinned tabs SHALL stay in their order, with their pinned URLs and names, and those whose page was open SHALL reopen in the new profile. The Space's windows SHALL show the new profile's favorites. A Space whose only tabs are pinned tabs with no open page SHALL change at once, without the dialog.

#### Scenario: Pinned tabs and favorites
- **WHEN** a Space of "Personal" has two pinned tabs, one of them open, and the user sets its profile to "Work" and confirms
- **THEN** both stay pinned in the same order, the open one reloaded in "Work", and the sidebar shows the favorites of "Work" in place of those of "Personal"

#### Scenario: Only closed pinned tabs
- **WHEN** a Space's only tabs are two pinned tabs, neither open, and the user sets its profile to "Work"
- **THEN** the Space uses "Work" at once, with no prompt, and keeps both pinned tabs

## MODIFIED Requirements

### Requirement: Removing a profile
Remove SHALL be enabled only for a profile that no Space uses. It SHALL ask for confirmation in a dialog that says the profile's cookies, history, preferences and logins will be permanently removed, and SHALL enable "Delete" only once the user has typed the profile's name. Confirming SHALL delete the profile, its data and its favorites.

#### Scenario: Profile in use
- **WHEN** the user selects a profile that one Space uses
- **THEN** Remove is disabled

#### Scenario: The last profile
- **WHEN** there is one profile
- **THEN** Remove is disabled, since the remaining Space uses it

#### Scenario: Removing
- **WHEN** the user selects "Client", which no Space uses, clicks Remove, types "Client" and clicks Delete
- **THEN** "Client" leaves the list and every profile menu, and its data folder is deleted

#### Scenario: Wrong name
- **WHEN** the user types "client 2" in the dialog for "Client"
- **THEN** "Delete" stays disabled

#### Scenario: Favorites go with the profile
- **WHEN** "Client" had two favorites, and the user removes it, then creates a profile named "Client" and gives a Space to it
- **THEN** that Space shows no favorites
