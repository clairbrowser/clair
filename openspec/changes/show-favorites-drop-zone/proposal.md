# Proposal

## Why

Once a profile's "Drag to add Favorites" box is dismissed, or after its last favorite is removed, nothing marks where favorites go, so a tab can't be dragged there to make one. Arc shows the box again during the drag: as soon as the pointer goes above the Space header, a box with the same words, without the ×, opens where the favorites would be, and stays until the drag ends. The owner asked for the same in Clair.

## What Changes

- **A drop zone during a drag.** While a profile has no favorites and the box doesn't show, a Today tab, pinned tab or favorite dragged above the Space header opens a box where the favorites would be, with the star, "Drag to add Favorites" and the message, and no ×. It stays until the drag ends, wherever that is.
- **Its own look, as in Arc** (`arc-reference/`): a fainter dashed border and a faint white fill. With the drag over it, the border turns solid, the fill lighter, and its contents fade to half.
- **The drag over it shows a square tile**, 47 pt, with the item's icon, as Arc's does. A drop makes the profile's first favorite.
- **The area above the box takes drops too.** Between the window's top and the Space header (the top row, the URL field and the extensions), a drop makes the profile's first favorite.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `favorites`: a new requirement adds the drop zone, and "A drag over the favorites shows the tile" covers it.

## Impact

- **`ClairUI`:**
  - `FavoritesDropArea.swift`: a new `FavoritesDropTrigger`, the AppKit view that opens the zone and takes drops above it.
  - `PinsViews.swift`: `FavoritesHintBox` gets the drop zone's style.
  - `SidebarView.swift`: the trigger above the header, and the zone in the favorites' place.
- **Runtime suite:** the zone shows only during a drag, which the suite doesn't do, and nothing it drives moves while no drag runs. The quality checks still run on the branch, since the change is in the sidebar around views it drives.
- **`ClairHost.h`, the engine and packaging:** no change.
