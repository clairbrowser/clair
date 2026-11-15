# Dia's toolbar: reference screenshots

Probed on 2026-11-15 in Dia 1.57.1 (`company.thebrowser.dia`) on macOS
27.2.1 with `tests/probe/` (`probe.sh start company.thebrowser.dia`), at
2 px per point, Light Mode, in a 963 × 976 pt window with a 190 pt sidebar.
Dia always shows its toolbar.

Clair copies one thing from Dia: **the sidebar toggle always leads the
toolbar**, with the sidebar shown or hidden, and the floating sidebar
covers it while it's out. Arc instead keeps the toggle in the sidebar and
moves it to the toolbar only while the sidebar is hidden (see
`../arc-reference/`). Everything else follows Arc.

Keep these screenshots. They move with the change when it's archived.

| File | Shows |
|---|---|
| toolbar.jpg | Sidebar shown. The sidebar's top row holds only the window controls and the Space name ("Work"). The toolbar inside the card holds the sidebar toggle, back, forward, reload and the host, left-aligned, then Chat at the trailing end. |
| toolbar-sidebar-hidden.jpg | Sidebar hidden. The toggle stays in the same place relative to the card's leading edge, and the window controls are hidden. |
| toolbar-sidebar-revealed.jpg | Sidebar hidden, with the pointer on the window's leading edge. The floating sidebar slides in over the card and covers the toolbar's leading end, toggle included. It has **no toggle of its own**: only the window controls and the Space name. |

## Only the toggle's behaviour comes from here

Dia's toolbar height, its left-aligned host, its Chat button and its card
insets are **not** Clair's. The toolbar's look and metrics are Arc's
(`../arc-reference/README.md`). Arc's own toolbar already puts the toggle
21 pt from the card's leading edge while the sidebar is hidden, followed by
back, forward and reload at a 37 pt pitch. Clair uses that layout with the
sidebar shown too.

## Toolbar colour (probed 2026-11-15)

These are for comparison. The owner decided Clair's toolbar stays a fixed
grey in this change, as Arc's mostly is, and that following the page's
colour, as Dia does, is a future change. Each screenshot is the top 300 px of a
960 × 976 pt window.

| File | Page | Toolbar | Line below it | Page's top row |
|---|---|---|---|---|
| — | example.com | 238 238 238 | 230 230 230 | 238 238 238 |
| toolbar-colour-iana.jpg | iana.org | 235 239 241 | 226 232 235 | 235 239 241 |
| toolbar-colour-white.jpg | github.com (also apple.com, wikipedia.org, news.ycombinator.com) | 255 255 255 | 242 242 242 | 255 255 255 |
| toolbar-colour-black.jpg | spacex.com | 0 0 0 | 25 25 25 | 0 0 0 |
| toolbar-colour-dark-header.jpg | arstechnica.com, at the top | 35 36 40 | 42 43 48 | 35 36 40 |
| toolbar-colour-scrolled.jpg | arstechnica.com, scrolled down | 233 234 237 | — | photos |

- **Colour:** Dia's toolbar always takes the colour at the top of the page.
  None of these pages declares a `theme-color`.
- **Scrolling:** the toolbar follows the page as it scrolls. Scrolled past
  Ars Technica's dark header, it turned to the page's light background
  (233, 234, 237), not the colour of the photo under it. It looks like the
  page's background colour rather than a pixel sample.
- **Glyphs and buttons** switch to light on dark colours (white glyphs on
  SpaceX's black), so they stay legible.
- **The line** below the toolbar contrasts slightly with the colour:
  darker on light pages, lighter on black.
- **Arc** (`../arc-reference/README.md`) keeps a fixed grey on the same
  pages, except iana.org.

## Not checked

- **Docking the floating sidebar:** Cmd+S or the View menu presumably still
  works while it's out.
