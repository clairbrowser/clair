# Proposal

## Why

Clair puts back, forward, reload, the URL and extensions in the sidebar only. Arc lets people move them into a toolbar above the page instead ("Show as Toolbar", ⇧⌘D), and many people coming from other browsers expect a toolbar. Split view, coming later, needs a header on every pane anyway: Arc's split-pane header *is* this toolbar. Building the toolbar now, as one header per page, gives split view its pane header.

Change 1's roadmap decided "URL bar only in the sidebar, with no top toolbar and no option to show one", and its `arc-reference/clair-menus.md` removed Show Toolbar. This change reverses both decisions. Clair hasn't been released, so the toolbar can be on by default.

## What Changes

- **The toolbar.** A toolbar, 32 pt tall, sits inside the top of the card, laid out as Arc's (`arc-reference/`). It holds:
  - leading: the sidebar toggle, then back, forward and reload;
  - centred on the card: the host, with its copy-link icon;
  - trailing: the site-controls button at the far end, where Arc has its split-view button, with the pinned extensions and then the permission indicators to its left, at the 36 pt spacing between Arc's two trailing buttons.

  While a Peek shows, it covers the toolbar, which shrinks and washes out with the page behind it, and the Peek has a toolbar of its own with back, forward, reload and its host, as in Arc.

  The page view moves below the toolbar, and the card's own frame doesn't change.
- **On by default** for every native window, incognito and guest included. With it on, the sidebar's top row keeps only the window controls, and the sidebar has no URL field and no row of pinned extensions. With it off, the sidebar is exactly as it is today.
- **The sidebar toggle always leads the toolbar**, whether the sidebar is shown or hidden, as in Dia (`dia-reference/`); Arc moves it there only while the sidebar is hidden. When the hidden sidebar slides out over the page, it covers the toggle and has no toggle of its own.
- **Turning it on and off** applies to open windows at once and is kept across launches. Three places change it:
  - View › Hide Toolbar / Show Toolbar, ⇧⌘D;
  - a context menu, as in Arc: on the toolbar while it shows, with "Hide Toolbar", and on the sidebar's URL field while it's off, with "Show as Toolbar";
  - a "Location bar" row on Settings › General, with two drawn thumbnails, "Toolbar" and "Sidebar". They're one scalable SwiftUI component, so a future first-run screen can reuse it.
- **Moving the window.** The toolbar's blank areas move the window and zoom it on a double-click, whatever the "Allow window dragging from the top of webpages" setting. The page-top drag strip keeps working, measured from the page's top, which is now below the toolbar. Both behaviours match Arc's, as checked by hand.
- **Popups and prompts attach to the toolbar's controls.** Chromium's bubbles and the Site Control Center open below the toolbar's controls, with the sidebar shown or hidden. Extension popups open where Arc opens them: over the toolbar, at the card's top-trailing corner, whichever tile opened them. Find, the "Copied Current URL" popup and infobars sit below the toolbar.
- **Narrow windows.** The host stays centred. As room runs out, the toolbar leaves out pinned extensions, then reload and the link icon, as Arc does.
- **Split view (future):** every pane will show this header whatever the setting, and the sidebar's controls will show only when no pane shows a header. The design keeps that rule in one place; split view itself isn't part of this change.

**Out of scope:** split view; a toolbar coloured from the page, as Dia's is (the toolbar stays a fixed grey, and page colours are a future change); Arc's "Show Full URL"; Arc's split-view button in the toolbar; and a first-run flow, which only gets the reusable picker.

## Capabilities

### New Capabilities

- `page-toolbar`: the toolbar above the page: its preference and the three ways to change it, what it holds and where, how it moves the window, where popups attach to it and what sits below it, and how the sidebar's controls and the toolbar's share one identity.

### Modified Capabilities

- `sidebar`: navigation controls, the URL field and its buttons, site controls, the extension row and its wrapping, tooltips and the revealed sidebar now depend on whether the toolbar is shown.
- `browser-window`: Chromium's bubbles attach to the toolbar's controls while it shows. The top row's layout from the window controls, and its place in window full screen, apply only with the toolbar off.
- `extensions`: newly installed extensions appear among the toolbar's pinned extensions, and their popups open at the card's top-trailing corner while the toolbar shows.
- `settings-window`: Settings › General gains the "Location bar" picker.

## Impact

- **`ClairUI` only.** The work is a new toolbar view hosted in `PageCardView`, plus:
  - changes to `SidebarView` and `BrowserRootView` (layout, the revealed sidebar);
  - `AnchorResolver` (toolbar anchors, `AnchorEdge.bottom`);
  - `ExtensionPopupWindow` (Arc's placement at the card's top-trailing corner);
  - `SettingsWindow` (the General row);
  - a new View-menu item added from `ClairUI`, as Edit › Copy URL is;
  - a new preference.
- **No engine change.** `ClairHost.h`'s `AnchorEdge.bottom` already exists, and ⇧⌘D is free: Chromium binds it only through Bookmark All Tabs' menu item, which Clair already hides and clears. Neither the engine key nor `ClairHost.h` changes.
- **Runtime suite:** `NativeWindowTests`, `PeekTests`, `PinsTests` and `SharedTabsTests` find `clair.urlField`, `clair.back`, `clair.reload` and `clair.siteControls`. The toolbar keeps those identifiers. Tests that assume the sidebar layout change, and new tests cover both modes. The PR runs `quality.yml` on its branch.
- **Docs:** `docs/native-window.md`, and a Changie fragment.
