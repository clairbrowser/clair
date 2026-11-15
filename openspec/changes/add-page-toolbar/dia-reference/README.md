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

## Not checked

- **Docking the floating sidebar:** Cmd+S or the View menu presumably still
  works while it's out.
