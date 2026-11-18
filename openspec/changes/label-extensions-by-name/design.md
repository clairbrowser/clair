# Design

## Context

- `ClairExtensions::Snapshot` (`clair_extensions.mm`) fills each `ClairChromiumExtensionAction` with `name = action->GetTitle(tab_id)`, falling back to `extension->name()` when the title is empty. `ClairHost.h` documents `name` as "The action's title, which is its tooltip".
- ClairUI reads `name` for the Extensions menu's item titles and order (`ExtensionsMenu.swift`), the Site Control Center grid's order and its tiles' tooltips and VoiceOver labels (`SiteControlCenter.swift`), a pinned tile's tooltip and VoiceOver label (`PinnedExtensions.swift`), and the popup window's hidden title, which only VoiceOver and the window list read (`BrowserWindowController.showExtensionPopup`).
- The engine already sorts unpinned actions by `extension->name()` before ClairUI sorts them again by `name`.
- Chromium's toolbar keeps the two apart: `ExtensionActionViewModel::GetActionName()` is `extension->name()`, used by the extensions menu, and `GetTooltip()` and `GetAccessibleName()` are the action's title, falling back to the name. Arc's toolbar buttons and Extensions menu are also labelled with the extension's name.
- The install, remove and error dialogs already name extensions through `extensions::ui_util::GetFixupExtensionNameForUIDisplay(extension->name())`.

## Goals / Non-Goals

**Goals:** every label but an extension button's tooltip and VoiceOver label shows the name the extension was installed under; the buttons keep what Chromium shows there.

**Non-Goals:**
- Where an extension's popup opens, and what its window shows.
- The extension context menu, which Chromium builds and which already starts with the name.
- Shortening long action titles in tooltips. Chromium shows them whole, and a tooltip is attached to the extension's own icon.

## Decisions

### D1. `name` becomes the extension's name, and a new `title` carries the action's title

`ClairExtensionAction.name` is filled with `GetFixupExtensionNameForUIDisplay(extension->name())` and documented as "The extension's name, as `chrome://extensions` shows it". A new `@property(nonatomic, readonly, copy) NSString *title;` is the action's title for the active tab, or the name when that's empty, documented as the button's tooltip.

Keeping `name` for the name means the Extensions menu, both orders and the popup window's title are right without touching their code: only the two tiles change, from `name` to `title`.

*Alternative:* keep `name` as it is and add `extensionName`. Every place that should show the name would have to switch, and `name` would keep a meaning that reads wrong.

*Alternative:* send the raw title and let ClairUI fall back to the name. The fallback is Chromium's rule, and keeping it in the engine leaves ClairUI with one string per use.

### D2. A tile's VoiceOver label follows its tooltip

The pinned tile and the grid tile use `title` for both `.tooltip` and `.accessibilityLabel`. This keeps the sidebar's rule that an icon control's VoiceOver label uses its tooltip's words, and matches Chromium's toolbar button, whose accessible name is its tooltip's title. The Extensions menu, which VoiceOver also reads, uses the name.

### D3. The name goes through Chromium's display fixup

`GetFixupExtensionNameForUIDisplay` shortens a name to Chromium's display limit, as the install and remove dialogs already do, so a menu item can't grow to the width of the screen. The engine's own sort of unpinned actions keeps sorting by `extension->name()`; ClairUI's `localizedStandardCompare` on the fixed-up name decides the order shown.

## Risks / Trade-offs

- **[The contract changes]** ClairUI built against the new header with an older engine, or the reverse, won't link `title`. → `ClairUI` ships inside the app with its engine; the pull request builds the engine for the new key, as every `ClairHost.h` change does.
- **[An extension can still put any text in its tooltip]** → The tooltip is on the extension's own icon, where Chromium and Arc show the same text; the menu and orders, which aren't attached to an icon, no longer show it.
- **[Labels change for extensions whose title isn't their name]** Such an extension now appears in the Extensions menu under its name. → That's the name the store and `chrome://extensions` show, and the one Chromium's and Arc's menus use.
