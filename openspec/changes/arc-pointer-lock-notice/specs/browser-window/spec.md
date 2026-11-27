# Spec Delta

## ADDED Requirements

### Requirement: Hidden cursor notice
When a page locks the pointer outside page full screen, hiding the cursor, the popup in the card's top-trailing corner SHALL read "Your cursor is hidden. Press [esc] to show cursor.", as in Arc, with esc drawn as a key cap. It SHALL hide after a few seconds or when the lock ends. Esc SHALL end the lock and show the cursor. In page full screen, the full-screen notice SHALL show instead.

#### Scenario: Page locks the pointer
- **WHEN** a page in the card locks the pointer after a click
- **THEN** the popup in the card's top-trailing corner reads "Your cursor is hidden. Press [esc] to show cursor." with esc as a key cap, and hides after a few seconds

#### Scenario: Esc shows the cursor
- **WHEN** a page holds the pointer lock and the user presses Esc
- **THEN** the lock ends, the cursor shows, and the popup hides

#### Scenario: Pointer lock in page full screen
- **WHEN** a page in page full screen locks the pointer
- **THEN** the popup shows the full-screen notice, not the hidden-cursor one

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
