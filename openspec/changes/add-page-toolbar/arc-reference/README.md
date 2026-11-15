# Arc's toolbar: reference screenshots

Probed on 2026-11-15 in Arc 1.173.1 (90936) on macOS 27.2.1 with
`tests/probe/` (`probe.sh start`, then `key d shift,cmd` for View › Show
Toolbar), at 2 px per point, Light Mode, in a 959 × 976 pt window with a
228 pt sidebar. Measurements are in points, taken from the PNGs with
`build/probe/bin/measure`. Glyph centres are accurate to about ±1 pt.

Keep these screenshots. They move with the change when it's archived.

| File | Shows |
|---|---|
| toolbar-off.jpg | The default for contrast: back, forward and reload in the sidebar's top row, and the URL field below it. |
| toolbar-on.jpg | Toolbar on, sidebar shown, on example.com. The sidebar keeps only the window controls and its toggle. The URL field is gone, so favorites move up into its place. |
| toolbar-on-page-header.jpg | The same on Hacker News. The toolbar keeps its own grey rather than taking the page's white or orange header colour. |
| toolbar-sidebar-hidden.jpg | Toolbar on, sidebar hidden (Cmd+S): the sidebar toggle joins the toolbar at its leading edge, and no window controls show. |
| toolbar-url-menu.jpg | Right-clicking the host: Copy URL, Share ›, Capture…, Capture Full Page, —, Manage Extensions…, —, Show Full URL, **Hide Toolbar**, Disable Shared Quotes. |
| toolbar-host-hover.jpg | The pointer on the host: a rounded, darker pill behind the host text only (not the link icon). |
| toolbar-tooltip-back.jpg | The tooltip on back opens below the button, in the same style and wording as the sidebar's ("Go back ⌘ ["). |
| toolbar-site-controls-open.jpg | The Site Control Center hangs below its toolbar button, with its arrow pointing up. In the sidebar it opens to the right instead. |
| settings-advanced.jpg | Arc's Settings › Advanced. "Allow window dragging from the top of webpages" is on. "Show full URL when Toolbar is enabled" is off; it's the setting behind the host menu's Show Full URL. Arc has no toolbar row in Settings. |
| toolbar-command-bar.jpg | Cmd+L with the toolbar on: the command bar opens centred in the window, as with the toolbar off. It doesn't attach to the toolbar. |
| toolbar-extensions.jpg | Two pinned extensions, uBlock Origin Lite (with a "1" badge) and Dark Reader, left of the site-controls button, in a 960 pt window. |
| toolbar-extension-hover.jpg | The pointer on Dark Reader's icon: a rounded grey highlight about 32 × 28 behind it. No tooltip showed within 2 s. |
| toolbar-extension-popup.jpg | uBlock's popup: a small titled window over the toolbar, its top-trailing corner at the card's top edge, 40 pt in from the card's trailing edge. |
| toolbar-extension-popup-2.jpg | Dark Reader's popup, from the other icon, opens with its top-trailing corner at exactly the same place. Arc doesn't attach popups to their icon. |
| toolbar-narrow-620.jpg | The window at 620 pt: uBlock, the extension farther from site controls, is left out, and the host stays centred on the card. |
| toolbar-narrow-520.jpg | The window at 520 pt: both extensions, reload and the link icon are left out. The host is still centred and whole. |

For split view, where every pane gets this header whatever the setting,
see change 1's `arc-reference/screenshots/split-view-two-panes.jpg` and
`split-sidebar-hidden.jpg`
(`openspec/changes/archive/2026-11-05-ship-plain-ungoogled-build/`). A
focused pane's header is this toolbar plus a close button (×). An inactive
pane's header keeps back, forward, the host and ×.

## Toggling

- **Host context menu:** "Show as Toolbar" while it's off (listed in change
  1's `look-and-behaviour.md`), "Hide Toolbar" while it's on.
- **View › Show Toolbar**, ⇧⌘D (change 1's `menus-and-shortcuts.md`).
- The window and the card keep their frames. Whether the switch animates
  wasn't recorded.

## Layout

```
 sidebar 228                 card (frame unchanged)
+---------------------+ +------------------------------------------------+
| (o)(o)(o) [sb]      | | <-   ->   (R)       (link) host        [sc] [|]|  32 pt
|                     | |------------------------------------------------|  1 pt line
| favorites ...       | |  page                                          |
```

- **Card:** the same frame as with the toolbar off: 10 pt in from the top,
  trailing and bottom edges, touching the sidebar. The toolbar is inside
  the card, at its top.
- **Toolbar:** 32 pt tall, from the card's top. Its background is a fixed
  light grey (239, 239, 239 in Light Mode on both pages) that doesn't follow
  the page.
- **Line:** 1 pt below the toolbar, about 5% black, drawn over the page's
  top row. It reads 242 over white, 226 over #eee, and HN's orange × 0.95.
- **Glyph centres:** all sit on one line, 16 pt below the card's top.
- **Sidebar shown** (from the card's leading edge): back 20.75, forward
  57.75, reload 95. They're 37 pt apart.
- **Sidebar hidden** (card at x = 10): the sidebar toggle at 21, back
  57.75, forward 94.75, reload 132. The same pitch, shifted by one slot.
  Clair uses this layout whether the sidebar is shown or hidden: its toggle
  always leads the toolbar (see `../dia-reference/`).
- **Host:** the host text is centred on the card, within 0.5 pt. The link
  icon sits before it, about 10 pt from the text, so the icon and text
  together aren't centred. Not checked: whether it drops `www.`, as the
  sidebar's URL field does.
- **Trailing buttons** (from the card's trailing edge): site controls at
  57.25 and split view at 21.25. The site-controls button is always shown,
  not only on hover as in the sidebar's URL field. It fills with the accent
  colour when a Boost applies (Arc only).
- **Copy:** no separate copy button. The link icon before the host
  probably copies the URL, as the sidebar's link button does. Its click
  wasn't tested.

## Window dragging (checked by hand by the owner, 2026-11-15)

- **Toolbar:** its blank areas drag the window whatever the "Allow window
  dragging from the top of webpages" setting says, and a double-click on
  them zooms the window, as on a title bar. Its controls stay clickable.
- **Page strip:** with that setting on, the strip at the top of the page
  still works with the toolbar shown, over about the same area.

## Confirmed by the owner (2026-11-15)

- **Peek:** it covers the toolbar.
- **Pinned extensions:** they sit to the left of the site-controls button.
  Clair spaces them at the distance between Arc's site-controls and
  split-view buttons, 36 pt, which is also Arc's own pitch.
- **Context menu:** it's on the toolbar while the toolbar shows, and on the
  sidebar's URL field only while the toolbar is hidden.
- **Tooltip:** "Show sidebar" on the toolbar's toggle while the sidebar is
  hidden.

## Pinned extensions (probed 2026-11-15, two extensions the owner pinned)

From the accessibility tree, in a 960 pt window whose card ends at x = 950:

- **Icons:** each is 16 × 16 pt. Their centres sit 129 pt (uBlock) and 93 pt
  (Dark Reader) from the card's trailing edge, continuing the trailing
  buttons' 36 pt pitch: site controls at 57 and split view at 21.
- **Badge:** a small white badge at the icon's bottom-trailing corner.
- **Popup:** each opens as a titled window whose frame's top-trailing corner
  is at (card's trailing edge − 40, card's top), whichever icon opened it:
  uBlock 637…910 × 40…446, Dark Reader 634…910 × 40…652, in screen points.
- **Narrow windows:**
  - At 620 pt wide, the extension farther from site controls goes first.
  - At 520 pt wide, both extensions, reload and the link icon are gone.
  - The host stays centred on the card throughout, and isn't truncated at
    520 pt.
- **Link icon:** the icon before the host is a button labelled "Copy Current
  URL".
- **Sidebar mode:** with the toolbar off, Arc's sidebar shows no row of
  extension icons, unlike Clair's.

## Not captured yet

Probe these during implementation:

- **Other cases:** Dark Mode colours, a narrow window (host truncation,
  button overflow), and incognito.
- **Peek screenshot:** a Peek over the toolbar, for comparison.
- **Show Full URL:** what it shows.

## Probe traps

- **Localhost pages.** With the toolbar on, Arc shows its own **Developer
  Mode** toolbar for `localhost` pages in place of the normal one: a
  striped bar with the full URL and developer tools. `tests/probe/pages/`
  served by `serve.sh` therefore doesn't show the normal toolbar. Use a
  public site such as `https://example.com/` or
  `https://news.ycombinator.com/`. With the toolbar off, this wasn't
  checked.
- **Window drags can't be automated here.** On 2026-11-15 the probe's
  XCUITest `drag` moved neither the pointer nor Arc's window, even from the
  sidebar. CGEvent drags weren't tried. `build/probe/bin/drag`'s header
  says Arc ignores them, but `drag-window-from-page-top` measured Arc with
  CGEvent drags. The owner checked these drags by hand.
- **Restore Arc afterwards.** Arc remembers the toolbar setting: press
  ⇧⌘D again and close the tab you opened.
