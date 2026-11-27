# tab-switcher Specification

## Purpose

Ctrl+Tab's switcher returns to recently used tabs, as in Arc: while Ctrl is held, a panel shows the window's five most recent tabs with previews of their pages, and releasing Ctrl shows the one selected.

## Requirements

### Requirement: Recent tabs
Each browser window SHALL keep its tabs in the order it last showed them, most recent first, across its Spaces. Today tabs, pinned tabs and favorites SHALL count; a tab and its Peek SHALL be one entry, and so SHALL the two tabs of a split. A tab SHALL leave the list when its page closes. Choosing a tab another window holds SHALL take it, as clicking its row does (`spaces`).

#### Scenario: Most recent first
- **WHEN** the window shows "Mail", then "News", then "Docs"
- **THEN** its recent tabs are "Docs", "News" and "Mail", in that order

#### Scenario: Across Spaces
- **WHEN** the window shows "Mail" in "Work", then switches to "Home" and shows "Recipes"
- **THEN** its recent tabs are "Recipes" and then "Mail"

#### Scenario: A pinned tab's page closes
- **WHEN** the recent tabs are "Docs", the pinned tab "Mail" and "News", and the user closes "Mail" with Close and Keep Pinned
- **THEN** the recent tabs are "Docs" and "News"

#### Scenario: A favorite
- **WHEN** the window shows the favorite "Calendar" and then "Docs"
- **THEN** its recent tabs are "Docs" and then "Calendar"

### Requirement: Opening the switcher
Ctrl+Tab SHALL open the switcher over the window: a panel with a card for each of the window's five most recent tabs, or fewer when it has fewer, the shown tab first. The second card SHALL be selected. Ctrl+Shift+Tab SHALL open it with the last card selected. With one recent tab or none, neither SHALL do anything. The switcher SHALL open in incognito and guest windows too.

#### Scenario: Seven recent tabs
- **WHEN** the recent tabs are "BBC", "Example", "MDN", "Cat", "Hacker News", "GitHub" and "Apple", and the user presses Ctrl+Tab and keeps Ctrl held
- **THEN** the switcher shows "BBC", "Example", "MDN", "Cat" and "Hacker News", and "Example" is selected

#### Scenario: Backwards
- **WHEN** the user presses Ctrl+Shift+Tab instead
- **THEN** "Hacker News" is selected

#### Scenario: Two recent tabs
- **WHEN** the recent tabs are "Docs" and "Mail", and the user presses Ctrl+Tab and keeps Ctrl held
- **THEN** the switcher shows "Docs" and "Mail", and "Mail" is selected

#### Scenario: One tab
- **WHEN** the window has shown only "Docs" and the user presses Ctrl+Tab
- **THEN** nothing happens

### Requirement: Moving the selection
While the switcher is open, Tab SHALL select the next card and Shift+Tab the previous one, Ctrl still held, wrapping from the last card to the first and from the first to the last. Ctrl+Tab and Ctrl+Shift+Tab SHALL reach the switcher before the page or any field in the window.

#### Scenario: Stepping
- **WHEN** the switcher shows five cards with the second selected, and the user presses Tab
- **THEN** the third card is selected

#### Scenario: Wrapping
- **WHEN** the last card is selected and the user presses Tab
- **THEN** the first card, the shown tab, is selected

#### Scenario: In a text field
- **WHEN** the focus is in a page's text area and the user presses Ctrl+Tab
- **THEN** the switcher opens, and the text area gets no keystroke

### Requirement: Choosing a tab
Releasing Ctrl SHALL close the switcher and show the selected tab, as clicking its row or tile does, and a tab of another Space SHALL first switch the window to that Space. A quick Ctrl+Tab, released at once, SHALL therefore show the previous tab. Selecting the first card and releasing Ctrl SHALL leave the window as it is.

#### Scenario: Releasing Ctrl
- **WHEN** the switcher has "MDN" selected and the user releases Ctrl
- **THEN** the switcher closes and the window shows "MDN"

#### Scenario: A quick Ctrl+Tab
- **WHEN** the window shows "Docs", which it showed after "Mail", and the user presses and releases Ctrl+Tab
- **THEN** the window shows "Mail"

#### Scenario: Another Space
- **WHEN** the window shows "Work", the switcher has "Recipes" of "Home" selected, and the user releases Ctrl
- **THEN** the window shows "Home" with "Recipes" active

### Requirement: Cancelling the switcher
Esc SHALL close the switcher without switching tabs, even while Ctrl is still held. So SHALL the window losing key status and the shown tab closing.

#### Scenario: Esc
- **WHEN** the switcher has "Example" selected and the user presses Esc, then releases Ctrl
- **THEN** the switcher closes and the window keeps showing the tab it showed

#### Scenario: Switching apps
- **WHEN** the switcher is open and another app becomes active
- **THEN** the switcher closes and the window keeps its tab

### Requirement: Choosing a card with the pointer
While the panel shows, clicking a card SHALL close the switcher and show that card's tab, as releasing Ctrl on it does, as in Arc. Ctrl is still held then, since releasing it closes the panel.

#### Scenario: Clicking a card
- **WHEN** the switcher shows "BBC", "Example", "MDN", "Cat" and "Hacker News", "Example" is selected, and the user clicks "Cat" with Ctrl held
- **THEN** the switcher closes and the window shows "Cat", and releasing Ctrl then changes nothing

### Requirement: A quick Ctrl+Tab shows no panel
The panel SHALL appear only once Ctrl has been held for 100 ms after Ctrl+Tab or Ctrl+Shift+Tab, or at once when Tab or Shift+Tab is pressed again within that time. Releasing Ctrl before the panel appears SHALL show the selected tab without the panel ever appearing.

#### Scenario: A quick tap
- **WHEN** the window shows "Docs", which it showed after "Mail", and the user presses Ctrl+Tab and releases Ctrl within 100 ms
- **THEN** the window shows "Mail", and no panel appeared

#### Scenario: Holding Ctrl
- **WHEN** the window has two or more recent tabs, and the user presses Ctrl+Tab, keeps Ctrl held and presses nothing else
- **THEN** the panel appears 100 ms after the press

#### Scenario: Two quick Tabs
- **WHEN** the window has three or more recent tabs, and the user presses Ctrl+Tab and, within 100 ms, Tab again, Ctrl still held
- **THEN** the panel appears at once, with the third card selected

### Requirement: Switcher panel
The panel SHALL lie over the window, centred on it and kept on its screen at least about 40 points from the screen's left and right edges, and SHALL hold its cards in one row, from left to right, as Arc's does (`arc-reference/`): about 27 points of padding on each side, cards about 157 points wide with about 24 points between them, a light rounded panel with a shadow. It SHALL appear, move its selection and close with no animation.

#### Scenario: Five cards
- **WHEN** the switcher shows five cards
- **THEN** the panel is about 938 by 189 points, centred on the window

#### Scenario: A window at the screen's edge
- **WHEN** the switcher shows five cards over a window about 963 points wide at the screen's left edge
- **THEN** the panel's left edge is about 40 points from the screen's, about 29 points right of the window's centre

#### Scenario: No animation
- **WHEN** the user presses Ctrl+Tab and holds Ctrl, pressing no other key
- **THEN** the panel shows at its full size and opacity in a single frame, 100 ms after the press

### Requirement: Cards
Each card SHALL show a preview of its tab's page, about 157 by 105 points with rounded corners, filled from the page's top edge, and below it the tab's favicon and its title or custom name, on one line, cut short with an ellipsis. A split's card SHALL show both pages side by side, in pane order, and both favicons with no title. The selected card SHALL show a rounded highlight in the window's accent colour around its preview and label, and its title SHALL be darker.

#### Scenario: A renamed tab
- **WHEN** the tab "Mail" has the custom name "Inbox" and its card shows
- **THEN** the card reads "Inbox"

#### Scenario: A split
- **WHEN** the recent tabs include a split of "News" and "Docs"
- **THEN** one card shows both pages, "News" on the left, and the favicons of "News" and "Docs" below

### Requirement: Page previews
A card's preview SHALL show the page as it was when the window last showed it, and the shown tab's card the page as it is. A tab with no preview yet SHALL show a blank card with its favicon in the middle. A crashed tab's card SHALL show a blank preview too.

#### Scenario: A background tab
- **WHEN** the user scrolls "News" to its comments, shows "Docs", and presses Ctrl+Tab
- **THEN** the card of "News" shows its comments

#### Scenario: No preview yet
- **WHEN** a tab restored at launch has never been shown and its card shows
- **THEN** the card shows a blank preview with the tab's favicon

### Requirement: Recents and the other tab commands
Next Tab (Opt+Cmd+Down), Previous Tab (Opt+Cmd+Up) and Cmd+1 to Cmd+9 SHALL keep stepping through the sidebar's rows as `spaces` defines, and showing a tab with them SHALL make it the most recent.

#### Scenario: Next Tab
- **WHEN** the window shows "Mail", the next row is "News", and the user presses Opt+Cmd+Down and then Ctrl+Tab
- **THEN** the window shows "News" and then "Mail"
