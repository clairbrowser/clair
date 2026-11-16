# Spec Delta

## Purpose

Defines how Clair's interface offers the profile's bookmarks: the Bookmarks menu, the bookmark dialog for adding, editing and removing a page's bookmark, the bookmark item in tabs' menus, opening bookmarks from the menu, and the bookmarks UI Clair leaves out.

## ADDED Requirements

### Requirement: Bookmarks menu
The menu bar SHALL have a Bookmarks menu after History. It SHALL hold, in order, Bookmark This Page… (⇧⌘B), Manage Bookmarks (⌥⌘B), a divider, then a Bookmarks Bar submenu and an Other Bookmarks submenu with their folders and bookmarks. A folder's submenu SHALL appear only while it holds bookmarks, and the divider only while one does.

#### Scenario: Profile with bookmarks
- **WHEN** the profile has a bookmark in the Bookmarks Bar folder and one in Other Bookmarks, and the user opens the Bookmarks menu
- **THEN** it lists Bookmark This Page…, Manage Bookmarks, a divider, Bookmarks Bar and Other Bookmarks, and each submenu lists its bookmark by title with its favicon

#### Scenario: Profile without bookmarks
- **WHEN** the profile has no bookmarks and the user opens the Bookmarks menu
- **THEN** it lists only Bookmark This Page… and Manage Bookmarks, with no divider

#### Scenario: Bookmarks change
- **WHEN** a bookmark is added, renamed or removed in Manage Bookmarks or by an extension
- **THEN** the Bookmarks menu shows the change the next time it opens

### Requirement: Opening a bookmark from the menu
Choosing a bookmark in the Bookmarks menu SHALL open it in the active tab of the frontmost window. ⌘-choosing it SHALL open it in a new tab.

#### Scenario: Choosing a bookmark
- **WHEN** the user chooses a bookmark for `https://example.com/` in the Bookmarks menu
- **THEN** the active tab loads `https://example.com/`

#### Scenario: New tab
- **WHEN** the user ⌘-chooses the same bookmark
- **THEN** a new tab opens on `https://example.com/`, and the previous tab keeps its page

### Requirement: Manage Bookmarks
Manage Bookmarks, from the menu or ⌥⌘B, SHALL open `chrome://bookmarks` in a tab of the frontmost window, or switch to that page if the window already has it open. Moving, sorting and importing bookmarks SHALL happen there.

#### Scenario: Shortcut
- **WHEN** the user presses ⌥⌘B
- **THEN** `chrome://bookmarks` opens and lists the profile's bookmarks

### Requirement: Bookmark This Page
Bookmark This Page…, from the menu or ⇧⌘B, SHALL bookmark the active tab's page under its title, in the folder Chromium uses for new bookmarks (the Bookmarks Bar folder unless the user last changed another folder), then open the bookmark dialog titled "Bookmark Added". It SHALL be disabled when the active tab's page can't be bookmarked.

#### Scenario: New bookmark
- **WHEN** the active tab shows `https://example.com/`, which isn't bookmarked, and the user presses ⇧⌘B
- **THEN** a bookmark for `https://example.com/` with the page's title is added, the bookmark dialog opens titled "Bookmark Added", and the Bookmarks menu lists the bookmark

### Requirement: Edit Bookmark
While the active tab's page is bookmarked, the Bookmarks menu's first item SHALL read Edit Bookmark…, keeping ⇧⌘B. It and ⇧⌘B SHALL open the bookmark dialog for the page's most recently added bookmark, titled "Edit Bookmark", and SHALL add nothing.

#### Scenario: Title follows the page
- **WHEN** the active tab's page is bookmarked and the user opens the Bookmarks menu
- **THEN** its first item reads Edit Bookmark…, and after switching to a tab whose page isn't bookmarked it reads Bookmark This Page…

#### Scenario: Editing
- **WHEN** the user presses ⇧⌘B on a bookmarked page
- **THEN** the bookmark dialog opens titled "Edit Bookmark", and no second bookmark is added

### Requirement: Bookmark dialog
The bookmark dialog SHALL be one of Clair's dialogs (`dialogs`), with Dia's controls in Dia's layout: the title with the page's favicon at its trailing end, a Name field, a Folder popup, Remove at the bottom leading corner and Done at the bottom trailing corner. It SHALL be the same dialog for adding and editing, apart from its title. It SHALL open with the Name field focused and its text selected.

#### Scenario: Layout
- **WHEN** the bookmark dialog opens
- **THEN** it shows the title and favicon, then "Name" beside its field, "Folder" beside its popup, Remove at the leading edge and Done ↵ at the trailing edge, as in `dia-reference/screenshots/edit.jpg`

#### Scenario: Name selected
- **WHEN** the dialog opens and the user types "Reading"
- **THEN** the field holds only "Reading"

### Requirement: Saving and removing in the bookmark dialog
Done, Return and Esc SHALL close the bookmark dialog and save its name and folder. A name left empty SHALL save as the page's title. Remove SHALL delete the bookmark and close the dialog.

#### Scenario: Renaming
- **WHEN** the dialog is open after ⇧⌘B, the user types "Reading" and presses Return
- **THEN** the dialog closes, and the bookmark is named "Reading" in the Bookmarks menu

#### Scenario: Esc keeps the edits
- **WHEN** the user types "Reading" and presses Esc
- **THEN** the dialog closes, and the bookmark is named "Reading"

#### Scenario: Removing
- **WHEN** the user clicks Remove
- **THEN** the dialog closes, the bookmark is gone, and the menu's first item reads Bookmark This Page…

### Requirement: Choosing a folder in the bookmark dialog
The Folder popup SHALL list Bookmarks Bar, then its folders indented one step per level, then New Folder…, then Other Bookmarks and its folders, a divider and Manage Bookmarks. The bookmark's folder SHALL have a checkmark. Manage Bookmarks SHALL save, close the dialog and open `chrome://bookmarks`, as ⌥⌘B does.

#### Scenario: Folders
- **WHEN** the profile has a folder "Reading" in Bookmarks Bar and the user opens the Folder popup of a bookmark in Other Bookmarks
- **THEN** it lists Bookmarks Bar, "Reading" indented under it, New Folder…, Other Bookmarks with a checkmark, a divider and Manage Bookmarks

#### Scenario: Manage Bookmarks from the popup
- **WHEN** the user types "Reading" in Name and chooses Manage Bookmarks in the Folder popup
- **THEN** the dialog closes, the bookmark is named "Reading", and `chrome://bookmarks` shows

### Requirement: New folder in the bookmark dialog
New Folder… SHALL turn the Folder popup into a field with the placeholder "New folder name…" and a × button. Return there SHALL create the folder at the end of Bookmarks Bar and select it, keeping the dialog open with focus back in Name. × SHALL bring the popup back unchanged.

#### Scenario: New folder
- **WHEN** the user chooses New Folder…, types "Recipes" and presses Return, then clicks Done
- **THEN** a folder "Recipes" exists in Bookmarks Bar, and the bookmark is in it

#### Scenario: Cancelling a new folder
- **WHEN** the user chooses New Folder… and clicks ×
- **THEN** the popup shows the previous folder again, and no folder is created

### Requirement: Bookmark item in tab menus
A tab's context menu SHALL offer Add to Bookmarks…, showing ⇧⌘B, while the tab's page isn't bookmarked, and Remove Bookmark, with no shortcut, while it is. Add to Bookmarks… SHALL bookmark that tab's page and open the bookmark dialog for it, without activating the tab. Remove Bookmark SHALL remove every bookmark of the page.

#### Scenario: Adding from a background tab
- **WHEN** the user right-clicks a Today tab that isn't active, whose page isn't bookmarked, and chooses Add to Bookmarks…
- **THEN** the page is bookmarked, the bookmark dialog opens titled "Bookmark Added" with that page's title in Name, and the active tab doesn't change

#### Scenario: Removing from the menu
- **WHEN** the user right-clicks a tab whose page is bookmarked
- **THEN** the menu offers Remove Bookmark with no shortcut, and choosing it removes the bookmark with no dialog

#### Scenario: Closed pinned tab
- **WHEN** the user right-clicks a pinned tab that has no open page
- **THEN** Add to Bookmarks… is shown and disabled

#### Scenario: Guest window
- **WHEN** the user right-clicks a tab in a guest window
- **THEN** the menu has neither Add to Bookmarks… nor Remove Bookmark

### Requirement: Bookmarks UI Clair leaves out
Clair SHALL NOT show a bookmarks bar, bookmark star, Chromium's bookmark bubble or the bookmarks side panel, and SHALL NOT offer Bookmark All Tabs or View › Always Show Bookmarks Bar. ⌘D SHALL pin or unpin the tab (`pinned-tabs`), as in Arc, and SHALL NOT create a bookmark. Bookmarks already in the profile SHALL be kept.

#### Scenario: Menu bar
- **WHEN** the user looks through the menu bar
- **THEN** there is no Bookmark All Tabs item, and the View menu has no "Always Show Bookmarks Bar" item

#### Scenario: Pin shortcut
- **WHEN** the user presses ⌘D on a Today tab
- **THEN** the tab is pinned, and no bookmark is created
