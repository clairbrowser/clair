# settings-window Specification

## Purpose
Clair's native Settings window, in the style of Arc's: how Settings… opens it, its pages and their rows, and the hand-off to `chrome://settings` for Chromium's own settings.

## Requirements

### Requirement: Settings… opens the Settings window
The application menu SHALL contain exactly one Settings item, titled "Settings…" with the shortcut Cmd+,. Choosing it SHALL open Clair's native Settings window without opening a browser tab or window. There SHALL be at most one Settings window: choosing Settings… while it's open SHALL bring that window to the front.

#### Scenario: Opening Settings from the menu
- **WHEN** the user chooses Clair › Settings…
- **THEN** the native Settings window opens, and no tab showing `chrome://settings` opens

#### Scenario: One Settings item
- **WHEN** the user opens the Clair menu
- **THEN** it has exactly one item titled "Settings…", with the shortcut Cmd+,, and no item titled "Preferences…"

#### Scenario: Opening Settings with the shortcut
- **WHEN** a browser window is key and the user presses Cmd+,
- **THEN** the native Settings window opens

#### Scenario: Opening Settings again
- **WHEN** the Settings window is open behind a browser window and the user chooses Settings… again
- **THEN** the same Settings window comes to the front, and no second one opens

#### Scenario: No browser window open
- **WHEN** no browser window is open and the user chooses Settings…
- **THEN** the Settings window opens, and no browser window opens

### Requirement: Default browser row
The General page SHALL say whether Clair is the default web browser. When it isn't, the row SHALL offer "Make Default", which asks macOS to make Clair the default browser, leaving the confirmation to macOS. When it is, the row SHALL say so and offer no button. The row SHALL reflect a change made elsewhere, such as in System Settings, whenever the Settings window comes to the front.

#### Scenario: Clair isn't the default browser
- **WHEN** another browser is the default and the user opens the General page
- **THEN** the row says Clair isn't the default browser and offers "Make Default"

#### Scenario: Making Clair the default
- **WHEN** the user chooses "Make Default" and confirms macOS's prompt
- **THEN** Clair becomes the default web browser, and the row says Clair is the default browser, with no button

#### Scenario: Changed in System Settings
- **WHEN** the Settings window is open on General, the user changes the default browser in System Settings, and then brings the Settings window to the front
- **THEN** the row shows the new state

### Requirement: Window dragging toggle
The Advanced page SHALL have a toggle labelled "Allow window dragging from the top of webpages" that shows and changes the window dragging preference of `browser-window`. It SHALL be on when no value is stored, and a change SHALL apply to open browser windows at once, without relaunching Clair.

#### Scenario: Default
- **WHEN** Clair has no stored value for the preference and the user opens the Advanced page
- **THEN** the toggle is on

#### Scenario: Turning it off
- **WHEN** the user turns the toggle off and then drags from empty space at the top of an open browser window's page
- **THEN** the drag reaches the page and the window doesn't move

#### Scenario: Turning it back on
- **WHEN** the user turns the toggle on again and drags from empty space at the top of the page
- **THEN** the window moves with the pointer

### Requirement: More Settings opens Chromium's settings
The Advanced page SHALL have a "More Settings…" button that opens `chrome://settings` in a new foreground tab of the most recently active browser window, or in a new browser window if none is open, and closes the Settings window. `chrome://settings` SHALL stay reachable by URL as well.

#### Scenario: More Settings with a browser window open
- **WHEN** a browser window is open and the user chooses "More Settings…" on the Advanced page
- **THEN** the Settings window closes, and that window comes to the front with a new tab showing `chrome://settings`

#### Scenario: More Settings with no browser window open
- **WHEN** no browser window is open and the user chooses "More Settings…"
- **THEN** the Settings window closes, and a new browser window opens showing `chrome://settings`

### Requirement: Peek toggle
The Links page SHALL have a toggle labelled "Open a Peek window when clicking on links with Shift held" that shows and changes the Peek preference, kept for the user across launches. It SHALL be on when no value is stored. A change SHALL apply to open windows at once. While it's off, Shift+clicking a link SHALL open a new window, as in Chromium.

#### Scenario: Default
- **WHEN** Clair has no stored value for the preference and the user opens the Links page
- **THEN** the toggle is on

#### Scenario: Turning it off
- **WHEN** the user turns the toggle off and Shift+clicks a link in an open window
- **THEN** the link opens in a new window, and no Peek opens

#### Scenario: Turning it back on
- **WHEN** the user turns the toggle on again and Shift+clicks a link
- **THEN** the link opens in a Peek

### Requirement: Warn before quitting toggle
The Advanced page SHALL have a toggle labelled "Warn before quitting" that shows and changes Chromium's warn-before-quitting setting. It SHALL be on when the user never changed it, as in Chromium, and a change SHALL apply at once. While it is on, Cmd+Q and Clair › Quit Clair SHALL ask in a quit dialog laid out as Dia's, and Chromium's "Hold ⌘Q to Quit" panel SHALL NOT show. No other quit SHALL ask. The menu bar SHALL NOT have Chromium's own "Warn Before Quitting" item, which the toggle replaces.

#### Scenario: On
- **WHEN** the toggle is on and the user presses Cmd+Q
- **THEN** Clair shows the quit dialog on the window and keeps running until the user answers

#### Scenario: The quit dialog
- **WHEN** the quit dialog shows
- **THEN** it is on the key browser window, or the most recently active one, with the title "Are you sure you want to quit Clair?", the message "You may lose unsaved work in your tabs.", "Always quit" at the bottom leading corner, and Cancel and a destructive Quit at the trailing corner, as in `native-quit-confirmation`'s `dia-reference/`

#### Scenario: Cancel
- **WHEN** the quit dialog shows and the user presses Esc or clicks Cancel
- **THEN** the dialog closes and Clair keeps running

#### Scenario: Quit
- **WHEN** the quit dialog shows and the user presses Return or clicks Quit
- **THEN** Clair quits

#### Scenario: Always quit
- **WHEN** the quit dialog shows and the user clicks "Always quit"
- **THEN** Clair quits, and after the next launch the toggle is off and Cmd+Q quits at once

#### Scenario: The Quit menu item
- **WHEN** the toggle is on and the user chooses Clair › Quit Clair
- **THEN** Clair shows the quit dialog

#### Scenario: Other quits
- **WHEN** the toggle is on and the user quits from the Dock, logs out, or Clair relaunches for an update, or no browser window is open
- **THEN** Clair quits without the dialog

#### Scenario: A download in progress
- **WHEN** the toggle is on, a download is in progress and the user presses Cmd+Q
- **THEN** only Chromium's warning about the download shows

#### Scenario: Off
- **WHEN** the user turns the toggle off and presses Cmd+Q
- **THEN** Clair quits at once

#### Scenario: Menu bar
- **WHEN** the user opens the Clair menu
- **THEN** it has no "Warn Before Quitting" item

### Requirement: Restore windows toggle
The Advanced page SHALL have a toggle labelled "When opening Clair, restore windows from previous session", as Arc's has, that shows and changes whether Clair reopens the previous session's windows at launch (`browser-window`, "Windows restored at launch"). It SHALL be off when no value is stored, and a change SHALL apply from the next launch.

#### Scenario: Default
- **WHEN** Clair has no stored value for the preference and the user opens the Advanced page
- **THEN** the toggle is off

#### Scenario: Turning it on
- **WHEN** the user turns the toggle on, quits with two windows open and relaunches
- **THEN** both windows reopen

### Requirement: Pages of the Settings window
The Settings window SHALL show a toolbar of pages, General, Profiles, Links and Advanced in that order, with each page's rows grouped in rounded cards. Choosing a toolbar item SHALL show that page in place of the current one, and the window's title SHALL be the shown page's name. The window SHALL open on General each time it opens; it SHALL NOT remember the page last shown.

#### Scenario: Opening
- **WHEN** the user opens Settings
- **THEN** the window shows the General page, titled "General", with toolbar items General, Profiles, Links and Advanced

#### Scenario: Switching pages
- **WHEN** the Settings window shows General and the user chooses Advanced in the toolbar
- **THEN** the window shows the Advanced page in place of General, and its title becomes "Advanced"

#### Scenario: Opening again
- **WHEN** the user leaves the Settings window on Advanced, closes it and opens Settings again
- **THEN** the window shows the General page

#### Scenario: Profiles page
- **WHEN** the user chooses Profiles in the toolbar
- **THEN** the window shows the Profiles page, wider than the other pages, and its title becomes "Profiles"

### Requirement: Peek on links to other sites toggle
The Links page SHALL have, below the Peek toggle, a toggle labelled "Open a Peek window when clicking on links to other sites" with the note "Note: This only affects Favorites and Pinned tabs" in italics, as Arc's. It SHALL show and change the preference for links to other sites (`peek`), kept for the user across launches, on when no value is stored, and a change SHALL apply to open windows at once.

#### Scenario: Default
- **WHEN** Clair has no stored value for the preference and the user opens the Links page
- **THEN** the toggle is on, below the Shift-click toggle, with its note in italics

#### Scenario: Turning it off
- **WHEN** the user turns the toggle off and clicks a link to another site in an open favorite
- **THEN** the favorite navigates to the link, and no Peek opens

### Requirement: Link Rules button
The Links page SHALL end with a card of its own below the Peek toggles, separated from them by a divider, laid out as Arc's Air Traffic Control row: one row labelled "Choose where links open inside Clair", without a full stop, with a "Link Rules…" button at its trailing edge, and no info button. The button SHALL open the Link Rules dialog on the Settings window (`link-rules`).

#### Scenario: The row
- **WHEN** the user opens the Links page
- **THEN** below the Peek toggles' card and a divider, a separate card shows "Choose where links open inside Clair" and a "Link Rules…" button, with no info button

#### Scenario: Opening the dialog
- **WHEN** the user chooses "Link Rules…"
- **THEN** the Link Rules dialog opens on the Settings window, which dims behind it

### Requirement: Links page icon
The Links page's toolbar item SHALL show the `interface.window.on.rectangle` symbol, a window over a window as Arc's Links icon.

#### Scenario: The toolbar
- **WHEN** the user opens the Settings window
- **THEN** the Links item shows a window over a window

### Requirement: Peek explanation
The Links page SHALL start with Arc's explanation of Peek, in plain text above the Peek toggles' card: "Peek is a way to preview a link without opening a new tab. It's perfect for quickly looking at a link from an email or news article."

#### Scenario: Opening the Links page
- **WHEN** the user opens the Links page
- **THEN** the explanation shows above the Peek toggles

### Requirement: Location bar picker
The General page SHALL have, below the default browser row, a row labelled "Location bar" that shows and changes the toolbar preference (`page-toolbar`). It SHALL offer two choices side by side, "Toolbar" and "Sidebar", each a drawing of the top-left corner of a Clair window in that layout above its name. The chosen one SHALL have an accent-coloured ring and a bold name. A change SHALL apply to open windows at once.

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
- **THEN** the "Toolbar" drawing shows the window controls in their colours and, across the top of the page, the sidebar toggle, back, forward and reload symbols, and the "Sidebar" drawing shows those symbols and the URL field in the sidebar above its tabs, both in the current appearance and accent colour

#### Scenario: VoiceOver and keyboard
- **WHEN** VoiceOver reads the row
- **THEN** it reads the two choices as a group labelled "Location bar", says which one is chosen, and lets the user choose the other with the keyboard
