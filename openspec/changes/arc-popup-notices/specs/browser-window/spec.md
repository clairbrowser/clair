# Spec Delta

## ADDED Requirements

### Requirement: Notice popup
Every notice in the popup at the card's top-trailing corner, Copy URL's and those below, SHALL show for the same time, about 5 seconds, and then hide by itself. A new notice SHALL replace the one showing and show for the full time. A notice SHALL hide sooner only when what it describes ends, such as the full screen or the pointer lock it explains.

#### Scenario: One time for every notice
- **WHEN** the popup shows the full-screen notice, and later the zoom level
- **THEN** each stays for about 5 seconds

#### Scenario: A newer notice
- **WHEN** a notice has shown for 3 seconds and another one comes
- **THEN** the new one replaces it and stays for about 5 seconds

#### Scenario: Ending early
- **WHEN** the user leaves page full screen while its notice shows
- **THEN** the notice hides at once

### Requirement: Hidden cursor notice
When a page locks the pointer outside page full screen, hiding the cursor, the popup in the card's top-trailing corner SHALL read "Your cursor is hidden. Press [esc] to show cursor.", as in Arc, with esc drawn as a key cap. Esc SHALL end the lock and show the cursor. In page full screen, the full-screen notice SHALL show instead.

#### Scenario: Page locks the pointer
- **WHEN** a page in the card locks the pointer after a click
- **THEN** the popup in the card's top-trailing corner reads "Your cursor is hidden. Press [esc] to show cursor." with esc as a key cap

#### Scenario: Esc shows the cursor
- **WHEN** a page holds the pointer lock and the user presses Esc
- **THEN** the lock ends, the cursor shows, and the popup hides

#### Scenario: Pointer lock in page full screen
- **WHEN** a page in page full screen locks the pointer
- **THEN** the popup shows the full-screen notice, not the hidden-cursor one

### Requirement: Window full-screen notice
Whenever the window enters macOS full screen other than for a page, by View › Enter Full Screen, the green button, its shortcut or an extension, the popup SHALL read "To exit full screen, press and hold [esc]", as Arc shows a notice however full screen was entered. Holding Esc for about 1.5 s SHALL leave full screen wherever the keyboard focus is. A quick Esc SHALL do what it does outside full screen.

#### Scenario: Entering from the menu
- **WHEN** the user chooses View › Enter Full Screen
- **THEN** the popup reads "To exit full screen, press and hold [esc]" with esc as a key cap

#### Scenario: Entering from the green button
- **WHEN** the user clicks the window's green button
- **THEN** the same notice shows

#### Scenario: Holding Esc
- **WHEN** the window is in full screen and the user holds Esc for about 1.5 s, with the focus on the page or in the sidebar
- **THEN** the window leaves full screen

#### Scenario: A quick Esc
- **WHEN** the window is in full screen with the command bar open and the user presses Esc briefly
- **THEN** the command bar closes and the window stays in full screen

### Requirement: No download notice
A download that starts while the window or a page is in full screen, or while a page holds the pointer lock, SHALL NOT show a notice in the popup. A notice already showing SHALL stay as it was, and a notice the same change of mode brings SHALL show without mention of the download.

#### Scenario: Download in page full screen
- **WHEN** a page in page full screen starts a download
- **THEN** the popup shows no "Download started" notice, and the window stays in full screen

#### Scenario: Entering full screen with a download
- **WHEN** a page enters full screen while a download it started a moment ago is in progress
- **THEN** the popup reads "To exit full screen, press [esc]", with no mention of the download

### Requirement: Zoom notice
When the user changes a page's zoom, by View's zoom commands, their shortcuts or a pinch, the popup SHALL show the new level alone, such as "110%", as in Arc. Each further change SHALL show its level in the same popup. No toast SHALL show for the zoom.

#### Scenario: Zooming in
- **WHEN** a page is at 100% and the user presses Cmd+=
- **THEN** the popup in the card's top-trailing corner reads "110%", and no toast shows at the bottom of the card

#### Scenario: Zooming again
- **WHEN** the zoom popup shows "110%" and the user presses Cmd+= again
- **THEN** the same popup reads "125%"

## MODIFIED Requirements

### Requirement: Full screen
The native window SHALL support macOS full screen. When a page asks for full screen, as a video does, the page SHALL fill the screen alone, without the sidebar or card insets, and Esc SHALL end it. The notice saying so SHALL use the same popup as Copy URL, with the key drawn as a key cap labelled "esc", as in every notice the popup shows.

#### Scenario: Window full screen
- **WHEN** the user chooses View > Enter Full Screen
- **THEN** the window enters macOS full screen and keeps its sidebar state

#### Scenario: Top row in full screen
- **WHEN** the window is in macOS full screen with the sidebar shown and the toolbar off
- **THEN** the top row stays where it is in a window, and the hide-sidebar button moves to the sidebar's leading edge in place of the window controls

#### Scenario: Toolbar in full screen
- **WHEN** the window is in macOS full screen with the toolbar shown
- **THEN** the toolbar stays at the top of the card, with the sidebar toggle at its leading end

#### Scenario: Page full screen
- **WHEN** a page's video enters full screen
- **THEN** the video fills the screen with no sidebar, toolbar, card margin or rounded corners, and pressing Esc returns the window to its previous state

#### Scenario: Full-screen notice
- **WHEN** a page enters full screen
- **THEN** the popup in the card's top-trailing corner reads "To exit full screen, press [esc]", with esc as a key cap
