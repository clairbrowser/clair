# Proposal

## Why

ClairUI labels every extension with its action's title, which the extension sets with `chrome.action.setTitle`, per tab and at any time. So the Extensions menu's items, their order and the Site Control Center grid's order all show text the extension chooses at run time, rather than the name it was installed under. Chromium and Arc list extensions by that name, as the store, `chrome://extensions` and Clair's own install and remove dialogs show it, and keep the action's title for the toolbar button's tooltip, where extensions put status such as "3 logins for this site".

## What Changes

- **The Extensions menu lists each extension by its name** and sorts by it, whatever title the extension gives its action.
- **The Site Control Center's grid sorts unpinned extensions by name.**
- **An extension's button keeps its action's title** as its tooltip and VoiceOver label, falling back to the name when the title is empty, as in Chromium. That holds for a pinned extension's tile in the sidebar and a tile in the Site Control Center's grid.
- **`ClairHost.h`:** `ClairExtensionAction.name` becomes the extension's display name, and a new `title` carries the action's title for the active tab. **BREAKING** for the contract: ClairUI and the engine must agree on the header, so the change ships with an engine build.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `extensions`: "Extensions menu" lists and sorts extensions by name, not by their action's title.
- `site-control-center`: "Grid of extensions" sorts by name, and a tile's tooltip and VoiceOver label are the action's title.
- `sidebar`: "Tooltips in Arc's wording" gives a pinned extension's tile its action's title as its tooltip.

## Impact

- `native/ClairHost.h`: `name`'s meaning and the new `title` on `ClairExtensionAction`.
- `overlay/chrome/browser/clair/window/clair_extensions.mm`: the action snapshot fills both.
- `native/ClairUI/PinnedExtensions.swift` and `SiteControlCenter.swift`: tiles use `title` for their tooltip and VoiceOver label. `ExtensionsMenu.swift` and the grid's order keep using `name`, which now holds the extension's name.
- `native/ClairUITests/`: the fake action gains `title`.
- `tests/runtime/`: the badge test extension sets an action title different from its name, and the existing runtime tests check that the Extensions menu shows the name and the pinned tile's label shows the title.
- The engine key changes, so the pull request needs an engine build.
