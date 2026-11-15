# Spec Delta

## Purpose

Defines the toolbar that Clair shows above the page, on by default, in place of the browser controls in the sidebar: its preference and how it's changed, what it holds and where, how it moves the window, and where popups attach to its controls. It follows Arc's "Show as Toolbar" layout.

## ADDED Requirements

### Requirement: Toolbar preference
A preference, kept for the user across launches, SHALL choose between showing the toolbar above the page and keeping the browser controls in the sidebar, for every native window, incognito and guest windows included. It SHALL be on when no value is stored. A change SHALL apply to every open window at once, without relaunching Clair.

#### Scenario: Default
- **WHEN** Clair starts with no stored value for the preference and opens a window
- **THEN** the window shows the toolbar above the page

#### Scenario: Turned off with windows open
- **WHEN** two windows are open and the user turns the toolbar off in one of them
- **THEN** both windows show the browser controls in the sidebar instead, and a window opened afterwards does too

#### Scenario: Kept across launches
- **WHEN** the user turns the toolbar off, quits and relaunches Clair
- **THEN** the windows open without the toolbar

### Requirement: Toolbar placement
The toolbar SHALL sit inside the card, across its top, 32 points tall, with a 1-point line of about 5% black below it, as in Arc. The page SHALL fill the rest of the card below it. The card's own frame SHALL be the same with the toolbar shown or not. The toolbar's background SHALL be a fixed light grey, Arc's on most pages, not a colour taken from the page. It SHALL show in window full screen and hide while a page is in full screen.

#### Scenario: Toolbar shown
- **WHEN** a window shows the toolbar with the sidebar shown
- **THEN** the card is inset 10 points from the window's top, trailing and bottom edges as without the toolbar, the toolbar fills its top 32 points, and the page's viewport starts below it

#### Scenario: Page with a coloured header
- **WHEN** the active page starts with an orange header
- **THEN** the toolbar keeps its grey, and the line below it darkens the page's top row slightly

#### Scenario: Page full screen
- **WHEN** a video on the page enters full screen
- **THEN** the toolbar is hidden and the video fills the screen, and the toolbar returns when full screen ends

### Requirement: Toolbar controls
The toolbar SHALL hold, from its leading edge, the sidebar toggle, back, forward and reload, centred 21, 57.75, 94.75 and 132 points from the card's leading edge, and the host in the middle. At its trailing end it SHALL hold the site-controls button, centred 21 points from the card's trailing edge, with the pinned extensions and then the permission indicators to its left, 36 points apart. All of them SHALL be vertically centred in the toolbar.

#### Scenario: Leading controls
- **WHEN** a window shows the toolbar, with the sidebar shown or hidden
- **THEN** the sidebar toggle, back, forward and reload sit at the toolbar's leading end, 37 points apart, in the same place relative to the card's leading edge

#### Scenario: Trailing controls
- **WHEN** the active tab uses the camera and two extensions are pinned
- **THEN** from the trailing end, the toolbar shows the site-controls button centred 21 points from the card's edge, the second and first pinned extensions centred 57 and 93 points from it, and the camera indicator centred 129 points from it

### Requirement: Same controls in the toolbar or the sidebar
The toolbar's controls SHALL be the sidebar's browser controls, moved: its host is the URL field, and its toggle, back, forward, reload, indicators, pinned extensions and site-controls button are the sidebar's. Every requirement on those controls in other capabilities, including their behaviour, tooltips, VoiceOver labels, highlights, menus and what they act on while a Peek shows, SHALL apply wherever they show.

#### Scenario: History menu in the toolbar
- **WHEN** the toolbar is shown and the user right-clicks its back button after visiting two pages
- **THEN** the history menu opens under the button, as it does from the sidebar

#### Scenario: Reload in the toolbar
- **WHEN** the toolbar is shown and the active tab starts loading a page
- **THEN** the toolbar's reload shows as stop until loading ends, as the sidebar's does

### Requirement: Peek covers the toolbar
While a Peek shows, the toolbar SHALL stay part of the parent page's card: it SHALL shrink and wash out with the parent page behind the Peek, as in Arc. A click on it SHALL close the Peek, as a click on the rest of the washed page does.

#### Scenario: Opening a Peek
- **WHEN** the toolbar is shown and a Peek opens over the active tab
- **THEN** the toolbar shrinks and washes out with the parent page, behind the Peek

#### Scenario: Clicking the washed toolbar
- **WHEN** a Peek shows and the user clicks the washed toolbar
- **THEN** the Peek closes, and nothing in the toolbar runs

### Requirement: The Peek's own toolbar
While the toolbar preference is on, a Peek SHALL have its own toolbar across the top of its card, as in Arc. It SHALL hold back, forward and reload at the same places relative to the Peek's leading edge as the tab's toolbar, and the link icon and host centred on the Peek, all acting on the Peek's page. It SHALL have no sidebar toggle, extensions, indicators or site-controls button.

#### Scenario: Peek with the toolbar on
- **WHEN** the toolbar is shown and the user Shift+clicks a link to `iana.org`
- **THEN** the Peek's card starts with a toolbar showing back, forward, reload and `iana.org` centred on the Peek, and the Peek's page is below it

#### Scenario: Going back in a Peek
- **WHEN** the user follows a link inside a Peek and clicks the Peek toolbar's back button
- **THEN** the Peek's page goes back, and the tab's page stays as it was

#### Scenario: Peek with the toolbar off
- **WHEN** the toolbar preference is off and a Peek opens
- **THEN** the Peek has no toolbar, and the sidebar's controls act on the Peek's page

### Requirement: Host in the toolbar
The toolbar SHALL show the active tab's host as the URL field shows it, centred on the card, with a link icon before it that copies the URL and shows "Copied Current URL" as Copy URL does. While the page is not secure, the red not-secure icon SHALL show before the link icon. Clicking the host SHALL open the command bar, centred in the window as usual.

#### Scenario: Centred host
- **WHEN** the toolbar is shown on `https://example.com/`
- **THEN** the text `example.com` is centred on the card, with the link icon before it

#### Scenario: Hovering the host
- **WHEN** the pointer rests on the host
- **THEN** a rounded, darker background shows behind the host text, as in Arc

#### Scenario: Clicking the host
- **WHEN** the user clicks the host
- **THEN** the command bar opens in the middle of the window, holding the tab's full URL, all selected

#### Scenario: Copying from the link icon
- **WHEN** the user clicks the link icon before the host
- **THEN** the tab's URL is on the pasteboard, and the "Copied Current URL" popup shows

### Requirement: Toolbar buttons always shown
The toolbar's buttons, the site-controls button included, SHALL always show, not only while the pointer is over the sidebar.

#### Scenario: Pointer over the page
- **WHEN** the toolbar is shown and the pointer is over the page
- **THEN** the site-controls button shows

### Requirement: Pinned extensions in the toolbar
The toolbar SHALL show the pinned extensions as a single row of icon tiles, in their pinned order, before the site-controls button, each with its badge and with a rounded highlight under the pointer, as in Arc. The toolbar SHALL show no tile while none is pinned.

#### Scenario: Pinned extension with a badge
- **WHEN** the toolbar is shown and a pinned extension sets its badge text to "1"
- **THEN** its tile in the toolbar shows a "1" badge at its bottom-trailing corner

#### Scenario: Pinned extension
- **WHEN** the toolbar is shown and the user clicks a pinned extension's tile whose action has a popup
- **THEN** the popup window opens at the card's top-trailing corner, over the toolbar, as `extensions` defines

### Requirement: Toolbar in a narrow window
When the toolbar is too narrow for all its controls with the host centred on the card, it SHALL leave controls out, as Arc does, in this order: the pinned extensions, starting with the one farthest from the site-controls button; then reload and the link icon. The host SHALL stay centred and SHALL be truncated only once those are gone. Left-out extensions SHALL stay reachable from the Site Control Center.

#### Scenario: One extension too many
- **WHEN** two extensions are pinned and the window is about 620 points wide
- **THEN** the toolbar leaves out the extension farther from the site-controls button and keeps the other, with the host still centred on the card

#### Scenario: Narrower still
- **WHEN** two extensions are pinned and the window is about 520 points wide
- **THEN** the toolbar shows the sidebar toggle, back, forward, the host centred on the card and the site-controls button, without the extensions, reload or the link icon

#### Scenario: Left-out extension
- **WHEN** the toolbar has left out a pinned extension and the user opens the Site Control Center
- **THEN** the extension's tile is in its grid and runs its action

### Requirement: Sidebar toggle leads the toolbar
While the toolbar shows, the sidebar toggle SHALL be its first control, with the sidebar shown or hidden. The sidebar's top row SHALL then hold only the window controls. The toggle's tooltip SHALL read "Hide sidebar" while the sidebar is shown and "Show sidebar" while it's hidden, with ⌘S.

#### Scenario: Sidebar shown
- **WHEN** a window shows the toolbar and the sidebar
- **THEN** the sidebar's top row shows only the window controls, and the toggle leads the toolbar

#### Scenario: Hiding from the toolbar
- **WHEN** the user clicks the toolbar's sidebar toggle
- **THEN** the sidebar hides, the card grows towards the leading edge, and the toggle stays first in the toolbar

### Requirement: Revealed sidebar over the toolbar
While the toolbar shows, the hidden sidebar revealed over the page SHALL cover the toolbar's leading end, toggle included, as in Dia. Its top row SHALL hold only the window controls, with no sidebar toggle. Cmd+S and View › Show Sidebar SHALL dock it.

#### Scenario: Revealing
- **WHEN** the toolbar is shown, the sidebar is hidden, and the pointer rests on the window's leading edge
- **THEN** the sidebar slides in over the toolbar's leading end, and its top row shows the window controls and no toggle

#### Scenario: Docking
- **WHEN** the sidebar is revealed over the toolbar and the user presses Cmd+S
- **THEN** the sidebar docks, and the toolbar's toggle shows again at its leading end

### Requirement: Moving the window from the toolbar
Dragging the toolbar's blank areas SHALL move the window, whatever the window dragging preference, and double-clicking them SHALL act as a double-click on a title bar, zooming the window by default, as in Arc. Its controls SHALL take presses as buttons.

#### Scenario: Dragging the toolbar
- **WHEN** the user drags from blank space in the toolbar between reload and the host
- **THEN** the window moves with the pointer

#### Scenario: Preference off
- **WHEN** the window dragging preference is off and the user drags from blank space in the toolbar
- **THEN** the window moves with the pointer

#### Scenario: Double-click
- **WHEN** the user double-clicks blank space in the toolbar
- **THEN** the window zooms

#### Scenario: Clicking reload
- **WHEN** the user presses reload in the toolbar and moves the pointer slightly before releasing
- **THEN** the page reloads and the window doesn't move

### Requirement: Page-top strip below the toolbar
While the toolbar shows, the strip at the top of the page that moves the window (`browser-window`) SHALL be measured from the page's top edge below the toolbar, and SHALL NOT reach into the toolbar.

#### Scenario: Below the toolbar
- **WHEN** the toolbar is shown, the window dragging preference is on, and the user drags from empty space 20 points below the toolbar's line
- **THEN** the window moves with the pointer

#### Scenario: Below the strip
- **WHEN** the toolbar is shown and the user drags from empty space 70 points below the toolbar's line
- **THEN** the drag reaches the page and the window stays in place

### Requirement: Turning the toolbar on and off
View SHALL offer "Hide Toolbar", reading "Show Toolbar" while the toolbar is off, with ⇧⌘D, as in Arc. While the toolbar shows, right-clicking it, on its host or a blank area, SHALL open a menu with Copy URL and "Hide Toolbar". While it's off, the sidebar's URL field SHALL have that menu instead, with "Show as Toolbar". The toolbar's buttons SHALL keep their own menus. Each item SHALL change the toolbar preference.

#### Scenario: Menu bar
- **WHEN** the toolbar is shown and the user presses ⇧⌘D
- **THEN** the toolbar hides, the sidebar shows the browser controls, and View's item reads "Show Toolbar"

#### Scenario: Toolbar's context menu
- **WHEN** the toolbar is shown and the user right-clicks its host, or blank space in it
- **THEN** the menu offers Copy URL and "Hide Toolbar"

#### Scenario: A button's own menu
- **WHEN** the toolbar is shown and the user right-clicks its back button
- **THEN** the history menu opens, not the toolbar's menu

#### Scenario: Sidebar's URL field
- **WHEN** the toolbar is off and the user right-clicks the sidebar's URL field and chooses "Show as Toolbar"
- **THEN** the toolbar shows in every open window

### Requirement: Overlays below the toolbar
While the toolbar shows, views placed at the top of the card, namely find in page, the "Copied Current URL" popup and other notices, and infobars, SHALL sit below the toolbar, keeping their place relative to the page's top.

#### Scenario: Find in page
- **WHEN** the toolbar is shown and the user presses Cmd+F
- **THEN** the find field opens at the top-trailing corner of the page, below the toolbar

#### Scenario: Copy URL
- **WHEN** the toolbar is shown and the user presses Shift+Cmd+C
- **THEN** the "Copied Current URL" popup shows below the toolbar, at the page's top-trailing corner

### Requirement: Popups attach to the toolbar
While the toolbar shows, popups opened from its controls SHALL attach below them, with the sidebar shown, hidden or revealed. These are the Site Control Center, Chromium's permission prompts and page info, and the history menus. Extension popups open at the card's top-trailing corner instead (`extensions`). Chromium's bubbles SHALL fall back to the card's top-leading corner only while a page is in full screen.

#### Scenario: Permission prompt
- **WHEN** the toolbar is shown, the sidebar is hidden, and a page asks for the user's location
- **THEN** Chromium's permission prompt opens below the toolbar's site-controls button, and choosing Allow grants the permission

#### Scenario: Site Control Center
- **WHEN** the user clicks the toolbar's site-controls button
- **THEN** the Site Control Center opens below the button with its arrow pointing up at it
