# Spec Delta

## MODIFIED Requirements

### Requirement: Bookmarks Bar emptied into Bookmarks
Clair SHALL keep Chromium's Bookmarks Bar folder empty. Whatever is in it at launch, and whatever lands in it later (from a bookmarks file imported in Manage Bookmarks, Manage Bookmarks itself or an extension), SHALL move to Other Bookmarks, so it shows in the Bookmarks menu. Folders SHALL move whole. Manage Bookmarks MAY still show the empty Bookmarks Bar folder.

#### Scenario: Bookmarks Bar at launch
- **WHEN** a profile's Bookmarks Bar holds "A" then "B", Other Bookmarks holds "C", and Clair launches
- **THEN** Other Bookmarks holds "A", "B" and "C", the Bookmarks Bar is empty, and the menu lists all three

#### Scenario: Added later
- **WHEN** an extension creates a bookmark in the Bookmarks Bar
- **THEN** it moves to Other Bookmarks, and the Bookmarks menu lists it

#### Scenario: Import
- **WHEN** the user imports a bookmarks HTML file in Manage Bookmarks and Chromium puts its bookmarks in the Bookmarks Bar, loose or in a folder
- **THEN** they move to Other Bookmarks

### Requirement: Manage Bookmarks
Manage Bookmarks, from the menu or ⌥⌘B, SHALL open `chrome://bookmarks` on Other Bookmarks in a tab of the frontmost window, or switch to that page if the window already has it open, showing Other Bookmarks. Moving, sorting, and importing and exporting a bookmarks HTML file SHALL happen there. Importing from another browser SHALL happen in Clair's import dialog (`browser-import`).

#### Scenario: Shortcut
- **WHEN** the user presses ⌥⌘B
- **THEN** `chrome://bookmarks` opens with Other Bookmarks selected, listing the bookmarks the Bookmarks menu lists, rather than the empty Bookmarks Bar

#### Scenario: Importing a file
- **WHEN** the user chooses Import bookmarks in Manage Bookmarks' menu and picks a bookmarks HTML file
- **THEN** its bookmarks are added, and show in the Bookmarks menu
