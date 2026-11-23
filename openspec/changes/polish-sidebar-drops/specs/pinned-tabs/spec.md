# Spec Delta

## MODIFIED Requirements

### Requirement: Reordering and dragging pinned tabs
Pinned tabs SHALL be reorderable by dragging. Dragging a Today tab into the pinned section SHALL pin it where it's dropped, also while the Space has no pinned tabs, by dropping it above the divider. Dragging a pinned tab below the divider SHALL unpin it where it's dropped. Favorites follow `favorites`.

#### Scenario: Dragging a Today tab into the pinned section
- **WHEN** a Space has the pinned tabs "Mail" and "Docs" and the user drags a Today tab between them
- **THEN** it is pinned second, between "Mail" and "Docs"

#### Scenario: Dragging into an empty pinned section
- **WHEN** a Space has no pinned tabs and the user drags its third Today tab above the divider
- **THEN** it becomes the Space's only pinned tab, above the divider

#### Scenario: Dragging a pinned tab out
- **WHEN** the user drags the pinned tab "Docs" below the second Today tab
- **THEN** "Docs" is no longer pinned and is the third Today tab, with its page

#### Scenario: Dragging a pinned tab to the top of Today
- **WHEN** a Space has Today tabs and the user drags the pinned tab "Docs" between "New Tab" and the first Today tab
- **THEN** "Docs" is no longer pinned and is the first Today tab

## ADDED Requirements

### Requirement: Dropping on the Space header
Dropping a Today tab, a pinned tab or a favorite on the header of the Space the window shows SHALL pin it last in that Space, keeping its page, as Pin Tab does, whether the pinned section is empty, expanded or collapsed. While a drag is over the header, the header SHALL show its hover pill. The drop SHALL be a move: the pointer SHALL show no "+". Incognito and guest windows SHALL take no drop there.

#### Scenario: Pinning on the header
- **WHEN** a Space has the pinned tab "Mail" and the user drops a Today tab on its header
- **THEN** the tab is pinned second, after "Mail"

#### Scenario: The header highlights
- **WHEN** the user drags a Today tab over the Space header
- **THEN** the header shows its pill, and the pointer shows no "+"

#### Scenario: A collapsed section
- **WHEN** a Space's pinned section is collapsed and the user drops a Today tab on its header
- **THEN** the tab is pinned last, hidden with the other pinned tabs unless it's selected

#### Scenario: A favorite on the header
- **WHEN** the user drops the favorite "Calendar" on the Space header
- **THEN** "Calendar" leaves the grid and is the Space's last pinned tab, with its page
