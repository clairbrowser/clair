# Spec Delta

## ADDED Requirements

### Requirement: Location bar picker
The General page SHALL have, below the default browser row, a row labelled "Location bar" that shows and changes the toolbar preference (`page-toolbar`). It SHALL offer two choices side by side, "Toolbar" and "Sidebar", each a drawing of a Clair window in that layout above its name. The chosen one SHALL have an accent-coloured ring and a bold name. A change SHALL apply to open windows at once.

#### Scenario: Default
- **WHEN** Clair has no stored value for the toolbar preference and the user opens the General page
- **THEN** the "Location bar" row shows "Toolbar" chosen, with an accent ring around its drawing

#### Scenario: Choosing Sidebar
- **WHEN** the user clicks the "Sidebar" drawing
- **THEN** "Sidebar" becomes the chosen one, and every open window moves its browser controls into the sidebar

#### Scenario: Changed from the menu bar
- **WHEN** the Settings window shows General and the user presses ⇧⌘D in a browser window
- **THEN** the row's choice changes to match

#### Scenario: Drawings
- **WHEN** the row shows
- **THEN** the "Toolbar" drawing shows a window with a sidebar and a bar across the top of the page, and the "Sidebar" drawing shows the bar's controls in the sidebar above its tabs, both in the current appearance and accent colour

#### Scenario: VoiceOver and keyboard
- **WHEN** VoiceOver reads the row
- **THEN** it reads the two choices as a group labelled "Location bar", says which one is chosen, and lets the user choose the other with the keyboard
