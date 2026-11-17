## MODIFIED Requirements

### Requirement: Remove confirmation as a native sheet
When an extension is removed through a path that asks for confirmation, such as the store's "Remove from Clair" button, Clair SHALL ask in a Clair dialog (`dialogs`) on the window. The dialog SHALL have the title "Remove “<name>” from Clair?", the extension's icon, a "Remove Extension" button (default, Return) that isn't marked destructive, as Arc's isn't, "Cancel" (Esc), and no "report abuse" option. When another extension asked for the removal, the dialog SHALL also say "“<requester>” wants to remove this extension." under the title.

#### Scenario: Removing from the store
- **WHEN** the user clicks "Remove from Clair" on an installed extension's store page and clicks "Remove Extension"
- **THEN** the extension is removed, its button leaves the sidebar, and the store page shows it as not installed

#### Scenario: Keeping the extension
- **WHEN** the remove sheet is shown and the user presses Esc
- **THEN** the extension stays installed

#### Scenario: Another extension asks to remove one
- **WHEN** an extension calls `chrome.management.uninstall` for a different extension and the dialog shows
- **THEN** the dialog says "“<requester>” wants to remove this extension." with the requesting extension's name, keeps its title, icon and buttons, and Esc keeps the extension installed

#### Scenario: The user removes an extension
- **WHEN** the dialog shows for a removal the user started, or for an extension removing itself
- **THEN** the dialog has no line naming a requester
