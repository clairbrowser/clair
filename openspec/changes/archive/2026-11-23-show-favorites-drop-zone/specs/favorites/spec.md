# Spec Delta

## ADDED Requirements

### Requirement: A drop zone while dragging
While a profile has no favorites and the "Drag to add Favorites" box doesn't show, a Today tab, pinned tab or favorite dragged above the Space header SHALL open a drop zone in the grid's place, as in Arc: the box's star and words, with no ×, a fainter dashed border and a faint white fill. It SHALL stay until the drag ends, wherever it ends. A drop on it, or anywhere above the Space header, SHALL make the item the profile's first favorite.

#### Scenario: Dragging above the header
- **WHEN** a profile has no favorites, its box was dismissed, and the user drags a Today tab above the Space header
- **THEN** the drop zone opens where the grid would be, and the Space moves down to make room

#### Scenario: Dragging below the header
- **WHEN** the user drags the tab among the Today and pinned tabs only
- **THEN** no zone opens

#### Scenario: The zone stays during the drag
- **WHEN** the zone is open and the user drags the tab back down and drops it among the Today tabs
- **THEN** the zone stays until the drop, then goes, and the tab moves there

#### Scenario: Dropping on the zone
- **WHEN** the zone is open and the user drops the tab on it
- **THEN** it becomes the profile's only favorite, and the zone goes

## MODIFIED Requirements

### Requirement: A drag over the favorites shows the tile
While a Today tab, pinned tab or favorite is dragged over the favorites grid, the "Drag to add Favorites" box or the drop zone, the drag SHALL show the tile it would become, as in Arc: the size of the slot it would take, or a square tile over the drop zone, with its icon. Leaving the grid, box or zone SHALL bring back the drag's own image. A drop there, or above the Space header while the zone can open, SHALL be a move: the pointer SHALL show no "+".

#### Scenario: Over the grid
- **WHEN** a profile has one favorite and the user drags a Today tab over the grid
- **THEN** the favorite shrinks to half the row, the drag shows a half-row tile with the tab's icon, and the pointer shows no "+"

#### Scenario: Over the empty box
- **WHEN** a profile has no favorites, the box shows, and the user drags a Today tab over it
- **THEN** the box highlights, and the drag shows a tile as wide as the box

#### Scenario: Over the drop zone
- **WHEN** the drop zone is open and the user drags a Today tab over it
- **THEN** its border turns solid, its contents fade, and the drag shows a square tile with the tab's icon

#### Scenario: Leaving the favorites
- **WHEN** the user drags a Today tab over the grid and then back over the Today tabs
- **THEN** the drag shows the tab's row again

#### Scenario: Dropping on the box
- **WHEN** a profile has no favorites and the user drops a pinned tab on the box
- **THEN** it becomes the profile's only favorite, and the box goes
