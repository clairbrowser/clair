# Spec Delta

## MODIFIED Requirements

### Requirement: Sidebar footer
The sidebar SHALL end in a footer, as in Arc, however short the tab list is: the downloads button leading, the Space switcher in the middle and a plus button trailing. The switcher SHALL show one item per Space, the current one darker, and SHALL be absent with one Space and in incognito and guest windows. The plus button SHALL open the plus menu. While the tab list scrolls, a thin line SHALL separate it from the footer.

#### Scenario: Plus menu
- **WHEN** the user clicks the footer's plus button
- **THEN** a menu shows New Space…, New Folder and New Tab with ⌘T, and choosing New Tab opens the command bar for a new tab

#### Scenario: Line above the footer
- **WHEN** the window has more tabs than the list can show
- **THEN** a line shows between the list and the footer, and it goes once tabs are closed until the rest fit

#### Scenario: Switcher with two Spaces
- **WHEN** there are two Spaces and the window shows the first
- **THEN** the footer shows two items between the downloads button and the plus, the first darker

#### Scenario: One Space
- **WHEN** there is one Space
- **THEN** the footer shows no switcher

## ADDED Requirements

### Requirement: Plus menu
The footer's plus menu SHALL offer New Space…, New Folder (`tab-folders`), a divider and New Tab (⌘T), which opens the command bar as Cmd+T does, as in Arc but without its Easel, Boost and Split items. Incognito and guest windows SHALL offer New Tab only.

#### Scenario: The items
- **WHEN** the user clicks the footer's plus button
- **THEN** the menu shows New Space…, New Folder, a divider and New Tab with ⌘T

#### Scenario: Incognito
- **WHEN** the user clicks the plus button of an incognito window
- **THEN** the menu shows New Tab only

### Requirement: The sidebar's own menu
Right-clicking the sidebar between the Space header and the footer where there is no row or control, or right-clicking the "New Tab" row, SHALL open the Space header's menu (`spaces`) at the pointer, as in Arc. The "New Tab" row SHALL show its hover pill while the menu is open. Incognito and guest windows SHALL open no menu there.

#### Scenario: Below the tabs
- **WHEN** the user right-clicks the empty sidebar below the last Today tab
- **THEN** the Space header's menu opens, offering New Folder

#### Scenario: The "New Tab" row
- **WHEN** the user right-clicks the "New Tab" row
- **THEN** the Space header's menu opens, and the row shows its hover pill

#### Scenario: Incognito
- **WHEN** the user right-clicks the empty sidebar of an incognito window
- **THEN** no menu opens
