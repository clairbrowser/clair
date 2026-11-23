# Proposal

## Why

A pinned tab's context menu offers both Unpin Tab and Remove Pin, which read alike, and the owner asked to keep only Unpin Tab. Removing a pinned tab stays one click away, on the × that shows when the pointer is over a pinned tab that isn't selected.

## What Changes

- **The pinned tab menu loses Remove Pin.** It ends with Pin to Favorites and Unpin Tab.
- **The × stays.** Over a pinned tab that isn't selected, the × with the tooltip "Remove Pin" still removes it and closes its page, and Restore Last Closed Tab still brings it back.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `pinned-tabs`: "Removing a pin" drops the menu item, and "Pinned tab menu" no longer lists it.

## Impact

- **`ClairUI`:** `PinsLogic.pinnedMenu` and its `removePin` menu command, the menu's dispatch in `PinsViews.swift`, and the menu test in `PinsTests`.
- **Runtime suite:** it doesn't use the item. The quality checks run on the branch anyway, since the pinned rows are views it drives.
- **`ClairHost.h`, the engine and packaging:** no change.
