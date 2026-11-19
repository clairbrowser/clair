# Design

## Context

- **The card** (`PageCardView`) holds a `container` with the `pageHolder`, in which `layoutSurface` stacks:
  - infobars at the top;
  - then the page, DevTools or the crashed view;
  - the drag strip, which is the top 59 pt of `pageView.frame`, so it follows the page wherever the page is laid out.

  Behind a Peek, `cardScaler` shrinks the whole card with a layer transform and a wash covers it.
- **The sidebar** (`SidebarView`) is one SwiftUI view hosted in `BrowserRootView`. It holds:
  - the top row (`TopRow`), with the window controls' room, the hide-sidebar button, back, forward and reload;
  - the `URLField` with its hover buttons;
  - the `ToolsRow` of pinned extensions.

  Its controls report their frames through `AnchorFramesKey`, in the `clair.sidebar` coordinate space. `BrowserWindowController.controlFramesChanged` stores them, and `AnchorResolver` turns them into a `BubbleAnchor` (`.trailing` for a sidebar control, or `.bottom` at the card's top-leading corner as the fallback).
- **`ClairHost.h`** already has `AnchorEdge.bottom`, and Chromium places a bubble below any rect with that edge.
- **`ExtensionPopupWindow`** only places a popup beside its anchor (`placeBesideAnchor`).
- **Overlays:** `BrowserRootView.layoutOverlays` puts find and the notice popup relative to the card's top edge.
- **Menus:**
  - View › Hide Sidebar is added by the engine (`clair_window_hooks.mm`, tag `kClairHideSidebarTag`), which also flips its title.
  - Edit › Copy URL is added from `ClairUI` (`MainMenuTitles.addCopyURL`), so `ClairUI` can add a menu item without the engine.
  - ⇧⌘D was Chromium's Bookmark All Tabs key. `ClairIsRemovedCommand` hides that item and clears its key, and `global_keyboard_shortcuts_mac.mm` doesn't bind ⇧⌘D, so the key is free.
- **Preferences** are `UserDefaults` keys with registered defaults (`WindowDragPreference`, `PeekPreference`). Settings binds them with `@AppStorage`, and windows read them live.
- **Reference:** Arc's toolbar metrics are in `arc-reference/README.md`, and the toggle's placement is in `dia-reference/README.md`.

## Goals / Non-Goals

**Goals:**
- One page-header view that split view can reuse per pane.
- One function that decides where the browser controls show.
- No engine change.
- The same runtime identifiers in both layouts.

**Non-Goals:**
- Split view.
- A toolbar coloured from the page, as Dia's is (`dia-reference/README.md`). The owner chose a fixed grey for this change and left page colours to a future change.
- Arc's Developer Mode toolbar for `localhost`.
- Show Full URL.
- Animating the switch between layouts. It's instant, and whether Arc animates it is unverified.

## Decisions

### D1. Where the controls show: one rule, ready for split view

`PageHeaderPolicy` is a pure function that takes the toolbar preference and the window's pane count (always 1 for now). It returns three things:
- whether each pane shows a header: `preference || paneCount > 1`;
- whether the sidebar shows its browser controls: not if any pane shows a header;
- which pane's header gets the sidebar toggle: the leading one.

`BrowserWindowModel` exposes the result as `showsPageHeader` and `sidebarShowsControls`. Every view reads only these two values. Split view will then change the pane count and nothing else.

*Alternative:* views read the preference directly. That's simpler today, but split view would have to find and change every one of those reads.

### D2. The toolbar is a page header inside the card

`PageToolbar` is a SwiftUI view hosted in an `NSHostingView`, placed in `PageCardView` above the `pageHolder`. While `showsPageHeader` is true:
- the toolbar takes the card's top 32 pt;
- `pageHolder`, `stillView` and everything `layoutSurface` lays out start below it;
- a 1 pt `DynamicFillView`, which ignores clicks (`hitTest` returns nil), draws the line over the page's top row, as Arc's does;
- the card's frame in `WindowLayout` doesn't change.

Because the drag strip is derived from `pageView.frame`, it moves below the toolbar with no change of its own.

`isBare` (page full screen) hides the toolbar. Window full screen keeps it.

*Alternative:* the toolbar as a separate view in `BrowserRootView` above the card. Rejected: the toolbar is inside the card's rounded mask in Arc, and a pane header must belong to its pane.

### D3. Peek and the toolbar

In Arc a Peek covers the toolbar, as the owner confirmed. The toolbar is in the card's `container`, inside `cardScaler`, so behind a Peek it shrinks and washes out with the parent page. The click catcher covers it, so a click on it closes the Peek like a click anywhere else on the washed card. `PeekLayout` is unchanged: the Peek's frame is still measured from the card.

*Alternative:* keep the toolbar above the wash, acting on the Peek. Rejected: Arc doesn't, and it would split the card's chrome from the card.

The Peek gets its own header instead (`arc-reference/screenshots/toolbar-peek.jpg`). It's a second `PageToolbar` at the top of `peekContainer`, with the Peek's page and surface below it, built only while `showsPageHeader` is true. In Arc it holds back, forward and reload, at the same offsets from the Peek's leading edge (21, 58, 95 pt), and the link icon and host centred on the Peek. It has no toggle, extensions, indicators or site controls: the Peek's own buttons stay beside its top-trailing corner. Its controls act on the Peek's page, as the sidebar's do today. `PeekLayout`'s frame doesn't change; the Peek's page just starts below its header.

### D4. The toolbar's content

`PageToolbar` reuses the sidebar's existing controls: `IconButton`, the history menus, `ReloadStopMode`, `URLDisplay` for the host, the not-secure icon, the indicators and `PinnedExtensionTile`. They keep their runtime identifiers (`clair.hideSidebar`, `clair.back`, `clair.forward`, `clair.reload`, `clair.urlField`, `clair.copyURL`, `clair.siteControls`), and the toolbar itself is `clair.toolbar`. The Peek's header is `clair.peekToolbar`, so tests can tell the two apart.

`PageToolbar` takes a `PageHeaderContent` that says which groups it shows:
- `.tab`: everything;
- `.peek`: back, forward, reload, the link icon and the host.

Split view will add its pane variants here: a focused pane with site controls, split and close, and an inactive pane with back, forward, the host and close.

The background is a fixed grey: 238 in Light Mode, which Arc shows on white, black and orange page tops alike. On iana.org, Arc's toolbar and its Peek's took the page's light blue-grey header colour (`toolbar-page-tint-iana.jpg`). That page declares no `theme-color`, and the rule behind it is unknown, so Clair doesn't copy it. Dia instead colours its toolbar from the page's background as it scrolls (`dia-reference/`). Following the page is a future change; the toolbar's background is one fill, so that change can replace it without touching the layout.

Layout, using Arc's metrics:
- **Leading group:** buttons centred at 21, 57.75, 94.75 and 132 pt from the card's leading edge.
- **Trailing group:** site controls centred 21 pt from the card's trailing edge, where Arc has its split-view button. To its left come the pinned extensions, then the indicators, each 36 pt further left: the distance between Arc's site-controls and split-view buttons (57.25 − 21.25). The pinned extensions are in pinned order, the first leftmost.
- **Host:** a custom SwiftUI `Layout`, `ToolbarLayout`, always keeps the host text centred on the card. When the controls on either side would come too close to it, the layout leaves controls out in Arc's order (`toolbar-narrow-620.jpg`, `toolbar-narrow-520.jpg`):
  1. the pinned extensions, starting with the one farthest from site controls;
  2. then reload and the link icon;
  3. only then does it truncate the host.

  It's unit-tested like `PinnedExtensionsGrid`.

The background has the same window drag and double-click handling as the sidebar's top row: `WindowDragGesture`, `TitleBarArea` and `.allowsWindowActivationEvents(true)`. It doesn't depend on `WindowDragPreference`. Buttons sit above the background, so they get the clicks.

### D5. The sidebar with the toolbar shown

While `sidebarShowsControls` is false:
- `TopRow` renders only the window controls' room, keeping its height so the window controls stay at Arc's place;
- the `URLField`, its `ToolsRow` and the compact "More" menu aren't built;
- everything below moves up, with favorites directly under the top row.

The revealed sidebar uses the same `SidebarView` in the floating panel, so it also has no toggle, which matches Dia. While revealed, it covers the toolbar's leading end.

### D6. Anchors for popups

The toolbar reports its controls' frames with the same `AnchorFramesKey`, in its own coordinate space. The controller converts each source's frames to window coordinates and keeps them in separate tables.

`AnchorResolver` gains `toolbarShown`:
- **Toolbar shown and the page not in full screen:** it resolves a control in the toolbar's table and returns `edge: .bottom`, with the sidebar shown, hidden or revealed.
- **Otherwise:** today's rule.

Extension popups don't attach to their tile while the toolbar shows. Arc opens every one at the same place, whichever tile opened it (`arc-reference/screenshots/toolbar-extension-popup.jpg` and `-2.jpg`): the window's top-trailing corner at the card's top edge, 40 pt in from the card's trailing edge, over the toolbar. In this case `showExtensionPopup` gives `ExtensionPopupWindow` two things:
- that corner, as a new placement next to `placeBesideAnchor`, kept on screen;
- the tile's rect as its anchor, so a click on the tile still closes the popup.

The Site Control Center is already a popover attached below its button, so nothing changes there.

### D7. Overlays below the toolbar

`PageCardView` exposes `contentTop`, which is 32 pt with the toolbar and 0 without. `layoutOverlays` uses it to place find and the notice popup. Infobars already sit inside the surface below the toolbar.

### D8. The preference and the three ways to change it

`ToolbarPreference` follows `WindowDragPreference`: the key is `ClairShowsToolbar`, its registered default is `true`, and it's read through `UserDefaults`. Windows observe `UserDefaults.didChangeNotification` and update `BrowserWindowModel`, so every way of changing it reaches every window at once. The three ways:

- **View menu:** `MainMenuTitles.addToolbarItem(to:)` adds "Hide Toolbar" (⇧⌘D) after the engine's Hide Sidebar. It finds the View menu by the item whose action is `toggleSidebar:`. Its target is a `ClairUI` object whose `validateMenuItem` flips the title to "Show Toolbar". It's added when `NativeLayer` starts, as Copy URL is.
- **Context menu:** while the toolbar shows, right-clicking the toolbar (its host or its blank areas) opens the menu with Copy URL and "Hide Toolbar". While it's off, the menu is the sidebar URL field's, with Copy URL and "Show as Toolbar". The toolbar's buttons keep their own menus: the history menus and the extension menu.
- **Settings › General:** `LocationBarPicker` binds the key with `@AppStorage`.

*Alternative:* an engine-side menu item, next to Hide Sidebar. Rejected: it changes the engine key and costs an engine build, for no gain.

### D9. The "Location bar" picker

The row is called "Location bar", matching File › Open Location Bar (`MainMenuTitles.focusLocationTitle`). `LocationBarPicker` shows two `LayoutThumbnail`s. Each thumbnail is drawn with SwiftUI shapes in a unit space, so it's sharp at any size, and its proportions come from Clair's own constants:
- sidebar width over the default window width (`SidebarState.defaultWidth`);
- `WindowLayout.shownInset`;
- the toolbar's height.

Colours are semantic: the window tint (`SidebarTint`), the card in the window background colour, and controls in `secondary`. Dark Mode and the system accent therefore just work.

Each thumbnail is a button with its label. The pair is an accessibility group labelled "Location bar", with the chosen one marked selected and both reachable by keyboard. Selection draws an accent ring and a bold label.

The component takes its size from its container, so a future first-run screen can embed it larger. Settings shows it at about 110 × 70 pt per thumbnail, in a `LabeledContent` row after Default browser.

*Alternative:* bitmap or PDF assets. Rejected: they don't follow the accent colour or appearance, and they drift from the real layout.

## Risks / Trade-offs

- **[The runtime suite assumes the sidebar layout]** → Identifiers are kept (D4), so most tests pass in the new default.
  - `NativeWindowStructureTests/testBrowserWindowLayout` checks the toolbar layout by default, and a toolbar-off case sets the preference with `defaults write` before launch, as `ClairRestoreWindows` does. The card's frames and insets are `WindowContentTests`' unit tests.
  - New tests cover ⇧⌘D, the picker and toolbar anchors.
  - The PR runs `quality.yml` on its branch, as `CLAUDE.md` requires for views the suite drives.
- **[Toolbar frames and sidebar frames both report through `AnchorFramesKey`]** → Separate tables per source (D6), so a hidden sidebar's stale frames can't win over the toolbar's.
- **[Narrow windows]** → `ToolbarLayout` leaves out extensions, then reload and the link icon, before anything overlaps, as Arc does (D4). The Site Control Center still lists every extension, and Cmd+R and Shift+Cmd+C still reload and copy.
- **[Chromium could bind ⇧⌘D somewhere new on an engine update]** → A runtime test presses ⇧⌘D and checks that the toolbar toggles and no bookmark UI opens.

## Migration Plan

None. Clair hasn't been released. A missing value reads as on, so existing development profiles get the toolbar.
