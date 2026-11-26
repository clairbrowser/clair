# Dia's split view: reference screenshots

Seen on 2026-11-25 in the owner's Dia, from window screenshots and the owner's own captures, at 2 px per point, Light Mode.

Clair takes these from Dia:
- side-by-side panes only;
- Option+click on a link opens it in a split;
- a tab dragged to the left or right side of the page makes a split, never one dropped on another tab (the drop UI itself is Arc's, see `../arc-reference/`);
- the split button's menu. Its place and visibility are Arc's: always shown, at the toolbar's trailing end or before a pane's ×.

Keep these screenshots. They move with the change when it's archived.

| File | Shows |
|---|---|
| split-two-panes.jpg | A split of example.com and wikipedia.org. Each pane has its own toolbar: back, forward, reload and the host, and × at its trailing end. The focused pane, the leading one, has a grey border. The sidebar shows the split as one row with a chip per page. |
| split-button-menu-split.jpg | The leading pane's split button (between the bookmark and link icons in its URL field, shown on hover) and its menu: Move Left (disabled), Move Right, a divider, Separate All Tabs, Close This Tab, a divider, the "Split with Tab" heading and New Tab. |
| split-button-menu-single.jpg | A page that isn't split. The split button's menu: the "Split with Tab" heading, the other Today tab ("Wikipedia"), a divider and New Tab. |

## What the owner checked

- **Option+click** on a link opens a new pane, which takes focus. While split, Dia adds another pane at the far right. Clair, with two panes, loads the link in the other pane instead.
- **"Split with Tab"** lists every Today tab, with no cap seen at eight tabs, and never pinned tabs or favorites, whichever tab's menu it is in.
- **The × on each pane** closes only that pane's tab.
- **Minimum width:** a pane's page stops at 210 px wide (CSS pixels, so 210 pt at 100% zoom), measured with DevTools.
- **Panes:** Dia allows up to four side by side, and shows "Cannot Add New Pane" past that. A tab dropped on a split page adds a pane where it's dropped. Clair keeps two panes for now (`../design.md`, "Beyond two panes").

## Not taken from Dia

- Its grey focus border: Clair uses Arc's accent ring.
- The menu item's wording: this capture reads "Separate All Tabs". Clair says "Separate Tabs" everywhere.
- The Chat button and Dia's toolbar look (see `add-page-toolbar`'s `dia-reference/`).
