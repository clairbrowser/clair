# Spec Delta

## MODIFIED Requirements

### Requirement: Chromium bubbles placed in the native window
Chromium bubbles that remain, including permission prompts and page info, SHALL open attached to their control in the sidebar while it is shown, or to the card's top-leading corner while it is hidden or the window is in full screen. While the toolbar shows, they SHALL attach below their control in it instead, unless a page is in full screen. They SHALL work as they do in Chromium. Extension popups and the install and remove confirmations are not bubbles (`extensions`).

#### Scenario: Permission prompt with the sidebar shown
- **WHEN** the toolbar is off and a page asks for the user's location while the sidebar is shown
- **THEN** Chromium's permission prompt opens attached to the site controls in the sidebar, and choosing Allow grants the permission to the page

#### Scenario: Permission prompt with the sidebar hidden
- **WHEN** the toolbar is off and a page asks for the user's location while the sidebar is hidden
- **THEN** the prompt opens at the card's top-leading corner, fully on screen, and choosing Block denies the permission

#### Scenario: Extension popup with the sidebar hidden
- **WHEN** the toolbar is off and an extension opens its popup while the sidebar is hidden
- **THEN** the popup window opens at the card's top-leading corner, fully on screen

#### Scenario: Permission prompt with the toolbar shown
- **WHEN** the toolbar is shown and a page asks for the user's location, with the sidebar shown or hidden
- **THEN** Chromium's permission prompt opens below the toolbar's site-controls button, and choosing Allow grants the permission to the page

#### Scenario: Toolbar in window full screen
- **WHEN** the toolbar is shown, the window is in macOS full screen, and a page asks for the user's location
- **THEN** the prompt opens below the toolbar's site-controls button

### Requirement: Full screen
The native window SHALL support macOS full screen. When a page asks for full screen, as a video does, the page SHALL fill the screen alone, without the sidebar or card insets, and Esc SHALL end it. The notice saying so SHALL use the same popup as Copy URL, with Esc drawn as a key.

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

### Requirement: Top row laid out from the window controls
The sidebar's top-row buttons SHALL be vertically centred on the window controls, and the first of them SHALL start after the zoom button, wherever the system draws the window controls and whatever their size and spacing. The sidebar SHALL NOT narrow so far that the compact top row reaches the zoom button. While the toolbar shows, the top row SHALL hold no buttons, only the window controls.

#### Scenario: Default top row on macOS 27
- **WHEN** a native window opens with the sidebar shown and the toolbar off on macOS 27
- **THEN** the top-row buttons are centred 24 points below the sidebar's top, on the window controls' centre line, and the hide-sidebar button starts 7 points after the zoom button, at 81 points

#### Scenario: Window controls drawn elsewhere
- **WHEN** the toolbar is off and the system draws the window controls a few points higher or lower, or wider apart, than on macOS 27
- **THEN** the top-row buttons move to stay centred on them, and the hide-sidebar button still starts after the zoom button

#### Scenario: Narrowest sidebar
- **WHEN** the toolbar is off and the user drags the sidebar's edge as far left as it goes
- **THEN** the compact top row's back button starts after the zoom button

#### Scenario: Toolbar shown
- **WHEN** a native window opens with the sidebar and the toolbar shown
- **THEN** the sidebar's top row shows the window controls at their place and no buttons
