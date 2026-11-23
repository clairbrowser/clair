# Spec Delta

## ADDED Requirements

### Requirement: A drag over the favorites shows the tile
While a Today tab, pinned tab or favorite is dragged over the favorites grid or the "Drag to add Favorites" box, the drag SHALL show the tile it would become, as in Arc: the size of the slot it would take, with its icon. Leaving the grid or box SHALL bring back the drag's own image. A drop there SHALL be a move: the pointer SHALL show no "+".

#### Scenario: Over the grid
- **WHEN** a profile has one favorite and the user drags a Today tab over the grid
- **THEN** the favorite shrinks to half the row, the drag shows a half-row tile with the tab's icon, and the pointer shows no "+"

#### Scenario: Over the empty box
- **WHEN** a profile has no favorites, the box shows, and the user drags a Today tab over it
- **THEN** the box highlights, and the drag shows a tile as wide as the box

#### Scenario: Leaving the favorites
- **WHEN** the user drags a Today tab over the grid and then back over the Today tabs
- **THEN** the drag shows the tab's row again

#### Scenario: Dropping on the box
- **WHEN** a profile has no favorites and the user drops a pinned tab on the box
- **THEN** it becomes the profile's only favorite, and the box goes
