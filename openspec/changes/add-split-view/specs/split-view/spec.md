# Spec Delta

## Purpose

Split view shows two tabs side by side in one window, as in Arc and Dia, so the user can read or work on two pages at once. A split shows as one row in the sidebar, can be pinned or favorited as one item, and comes back after a relaunch.

## ADDED Requirements

### Requirement: Two panes side by side
A split SHALL show two tabs' pages side by side in the window's page area, each in its own pane card with rounded corners, the panes separated by a gap of about 10 points, as in Arc. A split SHALL hold exactly two tabs, and SHALL never stack its panes top to bottom. Each pane SHALL be an ordinary tab, with its own history, Peek and DevTools.

#### Scenario: A new split
- **WHEN** the user makes a split of "News" and "Docs"
- **THEN** "News" shows in the leading pane and "Docs" in the trailing one, each in its own card, of equal width, with a gap between them

#### Scenario: Resizing the window
- **WHEN** the user resizes a window showing a split
- **THEN** both panes resize, keeping their share of the width

### Requirement: The focused pane
One pane of a split SHALL be focused. It SHALL have a 2-point ring in the accent colour, as in Arc. Clicking anywhere in the other pane, its header included, SHALL focus it. A newly made split SHALL focus the pane that was added.

#### Scenario: Clicking the other pane
- **WHEN** the leading pane is focused and the user clicks in the trailing pane's page
- **THEN** the trailing pane is focused and ringed, the click reaches its page, and the leading pane loses its ring

### Requirement: The window acts on the focused pane
The URL field, back, forward, reload and stop, Copy URL, find in page, DevTools, Print, zoom, site controls, page info, pinned extensions and permission indicators SHALL act on the focused pane's tab. Find SHALL open at the focused pane's top-trailing corner, and DevTools SHALL dock inside its tab's pane.

#### Scenario: Find in a split
- **WHEN** the trailing pane is focused and the user presses Cmd+F
- **THEN** the find field opens at the trailing pane's top-trailing corner and searches its page

#### Scenario: Cmd+L
- **WHEN** the leading pane is focused and the user presses Cmd+L, types a URL and presses Return
- **THEN** the leading pane loads the URL, and the trailing pane doesn't change

### Requirement: The command bar over the focused pane
While the page is split, the command bar SHALL open centred on the focused pane rather than on the window, however it's opened (Cmd+L, Cmd+T, a pane's host, or New Tab in a split menu), and SHALL stay inside the window when the pane is narrower than it.

#### Scenario: Cmd+L in the trailing pane
- **WHEN** a split's trailing pane is focused and the user presses Cmd+L
- **THEN** the command bar opens centred on the trailing pane, with its URL selected

#### Scenario: A narrow pane
- **WHEN** the focused pane is narrower than the command bar
- **THEN** the command bar opens as near the pane's centre as it can while staying inside the window

### Requirement: Pane headers
While the page is split, each pane SHALL have a header, whatever the toolbar preference, laid out as the toolbar (`page-toolbar`). Each SHALL hold back, forward, the link icon, the host and a close button centred 21 points from its trailing edge. The leading pane's header SHALL also lead with the sidebar toggle. The focused pane's SHALL also show reload and, left of the close button and 36 points apart, the split button, site controls, pinned extensions and indicators, as in Arc.

#### Scenario: Headers of a split
- **WHEN** the window shows a split with the trailing pane focused
- **THEN** the leading pane's header shows the sidebar toggle, back, forward, the link icon, its host and ×, and the trailing pane's shows back, forward, reload, the link icon, its host, the indicators, pinned extensions, site controls, the split button and ×

#### Scenario: Toolbar preference off
- **WHEN** the toolbar preference is off and the user makes a split
- **THEN** both panes show headers, and the sidebar shows no back, forward, reload or URL field until the split ends

### Requirement: Controls of the other pane
While the pointer is over the pane that isn't focused, its header SHALL show its reload, split button, site-controls button, pinned extensions and indicators too, fading in and out, as Arc does near its toolbar. Clicking one of them SHALL focus that pane and act on its tab.

#### Scenario: Hovering the other pane
- **WHEN** the leading pane is focused and the pointer moves over the trailing pane's page
- **THEN** the trailing pane's header shows its reload, split button, site-controls button, pinned extensions and indicators, and hides them once the pointer leaves the pane

#### Scenario: Clicking site controls there
- **WHEN** the user clicks the site-controls button in the header of the pane that isn't focused
- **THEN** that pane is focused, and the Site Control Center opens for its page

### Requirement: Resizing the panes
A divider in the gap between the panes SHALL show a grabber and the resize pointer. Dragging it SHALL resize both panes, stopping when either pane's page would be narrower than about 210 points, as in Dia. The split SHALL keep the ratio, across tab switches and relaunches. A new split SHALL start with equal panes, and a drag ending near the centre SHALL snap to equal panes. While the page area is too narrow for two such pages, the panes SHALL keep their ratio.

#### Scenario: Dragging the divider
- **WHEN** the user drags the divider of an equal split in a wide window 200 points toward the trailing edge
- **THEN** the leading pane widens and the trailing pane narrows by 200 points

#### Scenario: Past the limit
- **WHEN** the user keeps dragging toward the trailing edge
- **THEN** the trailing pane's page stops at about 210 points wide

#### Scenario: Snapping to the centre
- **WHEN** the user drags the divider to within about 20 points of the page area's centre and lets go
- **THEN** the panes become equal

#### Scenario: Coming back to the split
- **WHEN** the user resized a split, selects another tab and then selects the split again
- **THEN** the split shows with the ratio it had

### Requirement: Dragging a tab onto the page
Dragging a Today tab, pinned tab or favorite over the page SHALL turn the drag into a portrait card with the tab's favicon and title, as in Arc. While the page isn't split, the half under the pointer SHALL become a translucent drop zone with an accent border, the page sliding to the other half, and moving across SHALL swap them. Dropping SHALL make a split with the tab in that half.

#### Scenario: Dropping on the trailing half
- **WHEN** the window shows "News" and the user drags the Today tab "Docs" over the trailing half of the page and drops it
- **THEN** the window shows a split of "News" and "Docs", "Docs" trailing and focused

#### Scenario: Moving across
- **WHEN** the user drags a tab over the trailing half and then over the leading half
- **THEN** the drop zone moves to the leading half, and the page slides to the trailing half

#### Scenario: Leaving the page
- **WHEN** the user drags a tab over the page and then back over the sidebar
- **THEN** the drop zone closes, the page fills the page area again, and the drag shows the tab's row

### Requirement: Dropping on a split page
While the page is split, the pane under a dragged tab SHALL become the drop zone. Dropping SHALL put the dropped tab in that pane, focused, and the tab it replaces SHALL leave the split with its page and become its own row directly below the split's row. Dropping a tab on the page where it already shows SHALL do nothing.

#### Scenario: Replacing a pane
- **WHEN** the window shows a split of "News" and "Docs" and the user drops the Today tab "Mail" on the trailing pane
- **THEN** the split shows "News" and "Mail", "Mail" focused, and "Docs" is its own row below the split's row

#### Scenario: A tab already in the split
- **WHEN** the user drags the tab of the split's own row over the page
- **THEN** no drop zone shows

### Requirement: Option+click opens a split
In a native window, Option+clicking a link SHALL open it in a new tab beside the page it was clicked in, as the trailing pane of a split, focused, instead of downloading it. Opening a link from a pinned tab or favorite this way SHALL make a split, not a Peek. Option+click inside a Peek SHALL act as a plain click.

#### Scenario: A page that isn't split
- **WHEN** the window shows "News" alone and the user Option+clicks a link to `https://example.com/`
- **THEN** a split shows "News" leading and a new tab at `https://example.com/` trailing and focused, and nothing is downloaded

#### Scenario: A favorite
- **WHEN** the window shows the favorite "Mail" and the user Option+clicks a link to another site
- **THEN** the link opens in a split with "Mail", and no Peek opens

### Requirement: Option+click in a split
While the page is split, Option+clicking a link in either pane SHALL load it in the other pane as a new navigation and focus that pane. No tab SHALL be created, and Back in that pane SHALL return to the page it showed before.

#### Scenario: Option+click in the leading pane
- **WHEN** a split shows "News" and "Docs" and the user Option+clicks a link to `https://example.com/` in "News"
- **THEN** the trailing pane shows `https://example.com/` and is focused, the sidebar has no new row, and Back in that pane returns to "Docs"'s page

#### Scenario: Option+click in the trailing pane
- **WHEN** the user Option+clicks a link in the trailing pane
- **THEN** the link loads in the leading pane

### Requirement: The link status names the split
While Option is held and the pointer rests on a link in a page, the link status (`browser-window`) SHALL read "Open <URL> in Split View", where Option+click opens it in a split. Pressing or releasing Option while the status shows SHALL update it at once. Inside a Peek, where Option+click acts as a plain click, it SHALL show the URL alone.

#### Scenario: Holding Option over a link
- **WHEN** the pointer rests on a link to `https://example.com/` and the user holds Option
- **THEN** the link status reads "Open https://example.com/ in Split View"

#### Scenario: Releasing Option
- **WHEN** the user then releases Option
- **THEN** the link status reads `https://example.com/`

### Requirement: Link status in a split
While the page is split, the link status SHALL show at the bottom-leading corner of the pane holding the link.

#### Scenario: A link in the trailing pane
- **WHEN** the pointer rests on a link in the trailing pane
- **THEN** the link status shows at the trailing pane's bottom-leading corner

### Requirement: Open Link in Split View
A link's context menu SHALL offer Open Link in Split View, after Open Link in New Tab, which SHALL act as Option+click on that link.

#### Scenario: From the context menu
- **WHEN** the window shows "News" alone and the user chooses Open Link in Split View on a link
- **THEN** the link opens in a new tab as the trailing, focused pane of a split with "News"

### Requirement: The split button
The toolbar SHALL show a split button at its trailing end (`page-toolbar`), and a split's pane headers just before their close buttons (see "Pane headers"), as in Arc, with the tooltip "Split view". Clicking it SHALL open its menu below it. No split button SHALL show on a Peek's toolbar, nor while the toolbar preference is off and the page isn't split.

#### Scenario: The toolbar
- **WHEN** the toolbar shows a page that isn't split
- **THEN** the split button sits at its trailing end, with the site-controls button to its left

#### Scenario: Sidebar layout
- **WHEN** the toolbar preference is off, the page isn't split, and the pointer is over the URL field
- **THEN** no split button shows

#### Scenario: A Peek's toolbar
- **WHEN** a Peek is open with the toolbar shown
- **THEN** the Peek's toolbar shows no split button

### Requirement: The split button's menu on a single page
On a page that isn't split, the split button's menu SHALL offer the heading "Split with Tab", the Today tabs of the window's Space other than the shown tab, in the sidebar's order, each with its favicon and title, a divider and New Tab, as in Dia. Choosing a tab SHALL make a split with it trailing and focused. The list SHALL have no cap, and SHALL scroll when long.

#### Scenario: Two other Today tabs
- **WHEN** the window shows "Mail" and the Space's Today tabs are "News", "Mail" and "Docs"
- **THEN** the menu offers "Split with Tab", "News", "Docs", a divider and New Tab

#### Scenario: Choosing a tab
- **WHEN** the user chooses "Docs"
- **THEN** a split shows "Mail" leading and "Docs" trailing and focused, and the sidebar shows one row for both

### Requirement: Splitting with a new tab
New Tab in a Split with Tab menu, and View › Add Split View (⌃⇧=), SHALL make a split of the shown tab and a new tab on the new tab page, trailing and focused, and open the command bar centred on the new pane, as Arc does with its empty pane. Choosing a page SHALL load it in the new tab. Esc SHALL close the command bar and leave the new tab page in its pane. While the page is split, Add Split View SHALL show the toast "Cannot Add New Pane".

#### Scenario: Add Split View
- **WHEN** the window shows "News" alone and the user presses ⌃⇧=
- **THEN** a split shows "News" and a new tab page, the new tab trailing and focused, with the command bar centred on it

#### Scenario: Choosing a page
- **WHEN** the user then types `example.com` and presses Return
- **THEN** the trailing pane loads `example.com`

#### Scenario: Esc
- **WHEN** the user presses ⌃⇧= and then Esc
- **THEN** the command bar closes, and the split shows "News" and the new tab page

#### Scenario: Already split
- **WHEN** the page is split and the user presses ⌃⇧=
- **THEN** the toast "Cannot Add New Pane" shows, and the split doesn't change

### Requirement: The split button's menu on a split
On a split page, a pane's split button SHALL open a menu offering Move Left and Move Right, a divider, Separate Tabs and Close This Tab, as in Dia. Move Left SHALL be disabled in the leading pane and Move Right in the trailing pane. Moving SHALL swap the panes, keeping the moved pane focused.

#### Scenario: The leading pane's menu
- **WHEN** the user opens the split button's menu in the leading pane
- **THEN** it offers Move Left disabled, Move Right, a divider, Separate Tabs and Close This Tab

#### Scenario: Move Right
- **WHEN** the user chooses Move Right in the leading pane "News"
- **THEN** "News" shows in the trailing pane, focused, and the other tab in the leading pane

### Requirement: Split with Tab in the menus
Tabs › Split with Tab › SHALL list the Today tabs as the split button's menu does, with New Tab, and SHALL be disabled while the page is split. The menus of a Today tab, pinned tab and favorite SHALL offer Split with Tab ›, listing the Space's Today tabs other than that tab, in the sidebar's order, each with its favicon, then New Tab. Choosing one SHALL make a split of the menu's tab, leading, and the chosen tab, trailing and focused.

#### Scenario: From a tab's menu
- **WHEN** the user right-clicks the Today tab "News" and chooses Split with Tab › "Docs"
- **THEN** the window shows a split of "News" leading and "Docs" trailing and focused

#### Scenario: From the menu bar while split
- **WHEN** the page is split and the user opens the Tabs menu
- **THEN** Split with Tab is disabled

### Requirement: Closing a pane
Each pane's × in its header, Close This Tab in its split menu, Cmd+W and View › Close Split Pane (⌃⇧−) on the focused pane SHALL close that pane's tab only, with its leave-page confirmation. The other tab SHALL then show alone, active, in the split's place in the sidebar. A pinned tab's or favorite's pane SHALL close as Close and Keep Pinned does.

#### Scenario: × on a pane
- **WHEN** a split shows "News" and "Docs" and the user clicks × in the "Docs" pane's header
- **THEN** "Docs" closes, and "News" shows alone, active, in the split's place in the list

#### Scenario: A page that asks before it's left
- **WHEN** the pane's page asks before it's left and the user chooses to stay
- **THEN** the split stays as it was

### Requirement: Separating a split
Separate Tabs, in a pane's split menu, the split row's menu and View, SHALL end the split and keep both tabs with their pages, as two rows in the split's place, in pane order. The window SHALL show the tab of the focused pane alone.

#### Scenario: Separate Tabs
- **WHEN** a split shows "News" leading and "Docs" trailing and focused, and the user chooses Separate Tabs
- **THEN** the sidebar lists "News" and then "Docs" where the split's row was, and the window shows "Docs" alone

### Requirement: The split row
In the sidebar, a split SHALL show as one row with a chip per tab, in pane order, each with the tab's favicon and title (or custom name), truncated to share the row, as in Arc. While the split isn't selected, a thin divider SHALL separate the chips. While it's selected, the row SHALL be highlighted and each chip SHALL show as its own grey pill.

#### Scenario: A split in Today
- **WHEN** a Space has the Today tabs "Mail" and a split of "News" and "Docs"
- **THEN** the sidebar lists "Mail" and one row holding a "News" chip and a "Docs" chip

#### Scenario: The selected split
- **WHEN** the window shows the split
- **THEN** its row is highlighted, and each chip is a grey pill on it

### Requirement: Selecting the split row
Clicking anywhere on a split row SHALL show the split with the pane that was focused last focused. A chip SHALL NOT be selected on its own.

#### Scenario: Clicking a chip
- **WHEN** a split of "News" and "Docs" was last focused on "Docs", another tab is shown, and the user clicks the "News" chip
- **THEN** the window shows the split with "Docs" focused

### Requirement: Closing a split from its row
Hovering a split's row in Today SHALL show a close button at its trailing end, with the tooltip "Close tab" and ⌘W, which SHALL close both tabs, each with its leave-page confirmation. Middle-clicking the row SHALL do the same. Restore Last Closed Tab SHALL bring the split back as it was.

#### Scenario: Closing the row
- **WHEN** the user hovers the split's row and clicks its ×
- **THEN** both tabs close, and the row goes

#### Scenario: Restoring it
- **WHEN** the user then chooses Restore Last Closed Tab
- **THEN** the split comes back in its place, with both pages and its ratio

### Requirement: The split row's menu
Right-clicking a split row SHALL open the menu of its kind for the tab whose chip is under the pointer (Today tab menu, `pinned-tabs`, `favorites`), without Split with Tab ›, Back to Pinned URL or Edit Pinned Page ›, with Separate Tabs added. Pin Tab, Pin to Favorites, Unpin Tab, Remove Favorite and Move to Space SHALL act on the whole split.

#### Scenario: A Today split's menu
- **WHEN** the user right-clicks the "Docs" chip of a Today split
- **THEN** the menu offers the Today tab menu's items for "Docs", and Separate Tabs, and no Split with Tab

#### Scenario: Copy Link
- **WHEN** the user chooses Copy Link from that menu
- **THEN** the URL of "Docs" is copied

### Requirement: Dragging a split row
Dragging a split row SHALL move the whole split: within Today, into the pinned section, into, within and out of a folder (`tab-folders`), into the favorites, onto the Space header, and to another Space or window, as dragging a tab row does. A split row SHALL make no drop zone over the page. Chips SHALL NOT be dragged out of the row on their own.

#### Scenario: Reordering
- **WHEN** the user drags a split row above the first Today tab
- **THEN** the split is first in Today

#### Scenario: Into a folder
- **WHEN** the user drops a Today split row on the folder "Work"
- **THEN** the split is pinned as the first item of "Work", as one row

### Requirement: Tab commands treat a split as one row
The tab commands of `spaces` (Next Tab, Previous Tab, Ctrl+Tab, Cmd+1 to Cmd+9, Close Tabs Below, and Ctrl+Shift+PageDown and PageUp) SHALL count a split as one row. Selecting it SHALL show the split as clicking its row does.

#### Scenario: Ctrl+Tab
- **WHEN** Today lists "Mail", a split, and "Docs", "Mail" is shown, and the user presses Ctrl+Tab twice
- **THEN** the window shows the split and then "Docs"

### Requirement: A split moves as one
Moving a split to another Space, showing it in another window, closing its window and Clear Today SHALL treat both tabs as one: they SHALL stay a split, with their order and ratio, and never show in two windows at once.

#### Scenario: Move to Space
- **WHEN** the user chooses Move to Space › "Work" on a split row
- **THEN** both tabs move to the top of "Work"'s Today tabs as one split

#### Scenario: Another window
- **WHEN** two windows show the same Space and the user clicks a split row in the second
- **THEN** the split moves to the second window, both panes, and the first window shows another tab

### Requirement: Splits after a relaunch
Splits SHALL come back after a relaunch, with Reopen Closed Window and after a crash, as splits of the same tabs, in the same order and place, with their ratio and focused pane.

#### Scenario: Relaunch
- **WHEN** the user quits with a split of "News" and "Docs" at a 2:1 ratio and relaunches
- **THEN** the sidebar shows the split's row in its place, and selecting it shows "News" and "Docs" at a 2:1 ratio

### Requirement: Peeks in a split
Shift+clicking a link in either pane SHALL open a Peek of that pane's tab, centred over the whole page area, with only that pane shrinking and washing out behind it, as `peek` describes. Closing it SHALL show the split as it was.

#### Scenario: A Peek from the trailing pane
- **WHEN** a split shows "News" and "Docs" and the user Shift+clicks a link in "Docs"
- **THEN** a Peek opens centred on the page area, "Docs"'s pane shrinks and washes out behind it, and "News"'s pane doesn't change

#### Scenario: Closing it
- **WHEN** the user presses Esc
- **THEN** the Peek closes and the split shows as before

### Requirement: Open in Split View from a Peek
A Peek's Open in Split View button SHALL turn the Peek into a normal tab in a split with its parent, trailing and focused, keeping its page and history. While the parent is already in a split, the button SHALL NOT show, since a split holds two tabs.

#### Scenario: From a single page
- **WHEN** a Peek is open on "News", which isn't split, and the user clicks Open in Split View
- **THEN** a split shows "News" leading and the Peek's page trailing and focused

#### Scenario: From a split
- **WHEN** a Peek is open on the leading pane "News" of a split with "Docs"
- **THEN** the Peek shows Close and Expand only

### Requirement: A split with a pinned tab or favorite
A split made of a Today tab and a pinned tab's or favorite's page SHALL show as a split row in Today, as in Arc. The pinned tab's row or favorite's tile SHALL stay in its place, and selecting it SHALL show the split. Separating the split, or closing the Today tab's pane, SHALL leave the page with its pin.

#### Scenario: Dragging a favorite onto the page
- **WHEN** the window shows the Today tab "News" and the user drops the favorite "Mail" on the page's trailing half
- **THEN** a split row of "News" and "Mail" shows in Today, and "Mail"'s tile stays in the grid

#### Scenario: Separating
- **WHEN** the user chooses Separate Tabs on that split
- **THEN** "News" is a Today row and "Mail" shows from its tile alone

### Requirement: Pinning a split
Pin Tab (Cmd+D) on a split, Pin Tab in its row's menu, and dragging its row into the pinned section SHALL pin the split as one item, keeping its pages, ratio and selection. Pin to Favorites and dragging it onto the favorites SHALL make it one favorite. Unpin Tab and dragging it below the divider SHALL make it a Today split again.

#### Scenario: Cmd+D on a split
- **WHEN** the window shows a Today split of "News" and "Docs" and the user presses Cmd+D
- **THEN** the split is the last item of the pinned section, as one row, and stays shown

#### Scenario: Unpinning
- **WHEN** the user chooses Unpin Tab on a pinned split
- **THEN** it becomes the first Today row, still a split

### Requirement: The pinned split row
A pinned split SHALL show in the pinned section as a split row, with the titles each page had when last open. Hovering the selected pinned split SHALL show a − button, "Close and Keep Pinned", that closes both pages and keeps the row. Hovering one that isn't selected SHALL show ×, "Remove Pin", which removes it, and Restore Last Closed Tab SHALL bring it back.

#### Scenario: Close and Keep Pinned
- **WHEN** the window shows a pinned split and the user clicks its −
- **THEN** both pages close, the row stays in place, and the next tab shows as `spaces` defines

#### Scenario: Selecting it again
- **WHEN** the user then clicks the row
- **THEN** both pinned URLs load, as a split with its ratio

### Requirement: Pages of a pinned split
A pinned or favorited split SHALL keep a pinned URL for each page. Selecting it SHALL open each page that isn't open, as a split. Closing one pane SHALL keep it in the split; the other page SHALL show alone until the split is selected again. Its row or tile SHALL show no "/" and offer no Back to Pinned URL.

#### Scenario: Closing one pane
- **WHEN** a pinned split of "Mail" and "Calendar" shows and the user closes the "Calendar" pane
- **THEN** "Mail" shows alone, the row still holds both chips, and clicking the row opens "Calendar" again beside "Mail"

#### Scenario: Navigated away
- **WHEN** the "Mail" pane follows a link to another page of its site
- **THEN** the row shows the new title in its chip, with no "/", and Tabs › Back to Pinned URL is disabled

### Requirement: The favorite split tile
A favorited split SHALL take one tile in the favorites grid, divided into a segment per page by a thin line, each segment with its page's icon centred, as in Arc. While the window shows it, the tile SHALL turn white in Light Mode, or light grey in Dark Mode, with a 2-point ring that blends from the leading page's icon colour to the trailing page's.

#### Scenario: Not shown
- **WHEN** a profile's favorites are a split of "Verge" and "Ars" and the single favorite "Wikipedia"
- **THEN** the grid shows two tiles, the first divided into a "Verge" and an "Ars" segment

#### Scenario: Shown
- **WHEN** the window shows the favorited split
- **THEN** its tile is white with a ring blending from "Verge"'s colour to "Ars"'s

### Requirement: Separating a pinned or favorited split
Separate Tabs on a pinned split SHALL leave two pinned tabs in its place, in pane order. On a favorited split, it SHALL leave two favorites in its place. Each SHALL keep its pinned URL, name and page.

#### Scenario: A pinned split
- **WHEN** the pinned section lists "Mail", a pinned split of "News" and "Docs", and "Plan", and the user chooses Separate Tabs on the split
- **THEN** the pinned section lists "Mail", "News", "Docs" and "Plan"

#### Scenario: A favorited split
- **WHEN** the user chooses Separate Tabs on a favorited split of "Verge" and "Ars"
- **THEN** "Verge" and "Ars" are two favorites in its place in the grid

### Requirement: Pinned splits after a relaunch
Pinned and favorited splits SHALL come back after every relaunch, in their place, with each page's pinned URL, name and ratio. A page open when Clair quit SHALL come back open.

#### Scenario: Relaunch
- **WHEN** the user quits with a pinned split whose pages were closed, and relaunches
- **THEN** the pinned section lists the split row in its place, and selecting it opens both pinned URLs as a split

### Requirement: Splits in private windows
Incognito and guest windows SHALL support splits as other windows do, without the pin and favorite items.

#### Scenario: Incognito
- **WHEN** the user Option+clicks a link in an incognito window
- **THEN** the link opens as the trailing pane of a split in that window
