# Design

## Context

Unpin Tab moves a pinned tab to the top of the Today tabs, keeping its page. Remove Pin deletes the pinned tab and closes its page, as the × on an unselected pinned row does. The owner found the two items confusing side by side and chose to keep only Unpin Tab.

## Goals / Non-Goals

**Goals:**
- The behavior in `specs/`.

**Non-Goals:**
- Changing the ×, Unpin Tab, or Remove Favorite in a favorite's menu.

## Decisions

### D1. Remove the item and its menu command

`PinsLogic.pinnedMenu` no longer adds Remove Pin, and `MenuCommand.removePin`, which nothing else uses, goes. The row's × (`RowButton.removePin`) and `PinActions.removePin`, which it and Remove Favorite call, stay.

## Risks / Trade-offs

- **[A selected pinned tab can't be removed in one step]** → its row shows −, not ×. The user can select another tab first and click ×, or unpin the tab and close it. The owner accepted this.
