# Design

## Context

See proposal.md, "Why". The behaviour is in `specs/split-view/spec.md`; this covers how. What shapes the approach:

- **Chromium 157 has split tabs.** `TabStripModel` keeps a split as a `SplitTabCollection` of adjacent tabs with a `SplitTabId` and `SplitTabVisualData` (layout and one `split_ratio`). It offers `AddToNewSplit`, `UpdateTabInSplit` (`kReplace`, `kSwap`), `ReverseTabsInSplit`, `UpdateSplitRatio`, `MoveSplitTo`, and `DetachSplitTabForInsertion` with `InsertDetachedSplitTabAt`. `AddToNewSplit` `CHECK`s for one or two indices, so a split holds two tabs.
- **Chromium saves splits.** The session service writes `kCommandSetSplitTab` and `kCommandSetSplitTabData`, and tab restore has a `Split` entry and a split ID on each tab.
- **Chromium already has a split-view click.** `ui::DispositionFromClick` and Blink's `NavigationPolicyFromEventModifiers` turn Cmd+Option+click into `WindowOpenDisposition::NEW_SPLIT_VIEW` (`kNavigationPolicySplitView`). Plain Option+click is `SAVE_TO_DISK`, a download.
- **Clair hides Chromium's split UI today.** `clair_window_hooks.mm` drops `IDC_CONTENT_CONTEXT_OPENLINKSPLITVIEW` from the page's menu, and `clair_native_window.mm` treats `IDC_NEW_SPLIT_TAB` as unavailable. Chromium's own split view is drawn by Views (`MultiContentsView`), which the native window doesn't host.
- **Clair doesn't use Chromium's pinned tabs or tab groups** (none of the overlay calls `SetTabPinned` or the group APIs). Chromium's rule that a split's tabs share pinned state and group therefore never comes up.
- **ClairUI was built expecting split view.** `add-page-toolbar` D1 gave `PageHeaderPolicy` a pane count, and D4 left `PageHeaderContent` room for pane variants. `ClairBrowser.pageView(for:)` already returns any tab's view, and Peek already shows two pages at once.
- **Peek is the nearest precedent.** `ClairPeeks` keeps a Peek next to its parent in the tab strip, catches Shift+click as `NEW_WINDOW` in `OpenURL`, keeps both pages visible, and draws over the card from `PageCardView`.

## Goals / Non-Goals

**Goals:**
- Use Chromium's split model, so saving, restoring, tab restore and moving tabs between windows come from Chromium.
- Lay panes out as a list in `ClairUI`, so going past two panes later is an engine change only ("Beyond two panes").
- Keep the patches to the click mapping (D6). Everything else goes in `overlay/` and `ClairUI`.

**Non-Goals:**
- Chromium's Views split UI, its split tab menu and its split metrics.
- Vertical (stacked) splits. `SplitTabLayout::kStacked` is never used.

## Decisions

### D1. Chromium's split model, not a table of Clair's own

`ClairSplits`, one per native window like `ClairPeeks`, wraps `TabStripModel`'s split calls and observes `TabStripModelObserver`'s split changes (`OnSplitTabChanged`). A Clair split *is* a Chromium split: its ID is the `SplitTabId`, its ratio is `split_ratio`, and its pane order is the tab order.

*Alternative:* a table of Clair's own, as for Peeks, with any number of panes, as Dia allows. Clair would then have to save splits itself, carry them through tab restore, keep them together across windows, and keep both pages visible. Chromium already does all of this for two tabs, and the MVP asks for two. See "Beyond two panes".

### D2. The contract

`ClairHost.h` gains:
- on `ClairTab`, `splitID` (an opaque string, or nil) and `splitRatio`;
- on `ClairBrowser`:
  - `splitTab:withTab:side:`, which puts the second tab on the given side (leading or trailing), focused, wherever each was;
  - `splitTabWithNewTab:`, which adds a new tab page as the trailing, focused pane, for Add Split View and New Tab;
  - `replacePaneOfTab:withTab:`, `swapSplitOfTab:`, `separateSplitOfTab:`, `closeSplitOfTab:` (both tabs) and `setSplitRatio:ofTab:`;
  - `canAddPaneToTab:`, for the "Cannot Add New Pane" toast.

Focusing a pane is the existing `activateTab:`. In Chromium, the focused pane is the active tab, and its partner is the other tab of its split.

The rows ClairUI lists come from `-tabsInSpace:` as now. `TabListLogic` folds two adjacent tabs with the same `splitID` into one row. A pinned section and the favorites can now hold a split item (D10).

### D3. Panes in `PageCardView`

`PageCardView` lays out `panes`, an array of one or two `PaneView`s, in place of its single page holder. Each `PaneView` holds:
- its own rounded card and shadow;
- a `PageToolbar` header;
- the tab's page view, still, crashed-page view and docked DevTools;
- its focus ring (2 pt, `controlAccentColor`), shown only while it has a partner and is focused.

A `SplitDivider` sits in the 10 pt gap (Arc's measurement in change 1's `arc-reference/look-and-behaviour.md`, 356 + 10 + 356). It shows a grabber and the resize cursor. While dragging, it sets the panes' widths locally, then calls `setSplitRatio` when the drag ends. The ratio is clamped so that each pane's page, below its header and inside its card, is at least about 210 pt wide, Dia's minimum as the owner measured it with DevTools. It needn't be exact. In a page area too narrow for that, the clamp gives way and the ratio holds. When a drag ends within 20 pt of the centre, the divider animates to it and the ratio is saved as 0.5.

`BrowserWindowModel.paneCount` becomes 2 while the active tab has a partner, so `PageHeaderPolicy` shows pane headers and hides the sidebar's controls with no further change (`add-page-toolbar` D1). The Peek, find field, loading indicator and toasts are measured against the page area, the union of the panes. Find is the exception: it uses the focused pane, as the spec says. The loading indicator follows the active tab, as now, and centres on that tab's pane.

### D4. Focus

Clicking in the other pane has to focus it and still reach the page. The engine sees this as `WebContentsObserver::OnWebContentsFocused` on the partner's contents, and `ClairSplits` activates that tab, as Chromium's `MultiContentsView` does. A click on a header focuses its pane from `ClairUI` (`activateTab:`). Activating a split tab is cheap: both pages stay visible, so only the window's commands, the focus ring and the URL change.

*Alternative:* a mouse-down monitor in `ClairUI`. That races with the page's own handling and misses keyboard focus moves such as Tab into the other pane.

### D5. Both pages visible

`ClairBrowserWindow::ActiveTabChanged` already marks the active tab and its shown Peek visible and everything else hidden. It now does the same for the active tab's partner. Switching between the two panes of a split changes nothing.

### D6. Option+click

One patch, `split-on-option-click.patch`, changes the click mapping on macOS in both places: Blink's `NavigationPolicyFromEventModifiers` and `ui::DispositionFromClick`. Option with no Shift now gives the split-view policy and `NEW_SPLIT_VIEW`, the same as Cmd+Option. The link then reaches `ClairBrowserWindow`'s `OpenURL` path as `NEW_SPLIT_VIEW`, like Shift+click's `NEW_WINDOW` for Peeks, and `ClairSplits::OpenURL` handles it:
- **from a page that isn't split:** a new foreground tab next to the source, then `AddToNewSplit` with the new tab trailing and active;
- **from a split pane:** load the URL in the partner as `CURRENT_TAB`, renderer-initiated off, as a new navigation that keeps its history, then activate it;
- **from a Peek:** `CURRENT_TAB` in the Peek.

Open Link in Split View (`IDC_CONTENT_CONTEXT_OPENLINKSPLITVIEW`) is no longer removed. It already opens with `NEW_SPLIT_VIEW`, so it takes the same path. `ClairPinnedLinkThrottle` only sees navigations in place, and a split's new tab is a new tab, so a pinned tab's Option+click makes a split, not a Peek.

*Alternative:* catch the download in `DownloadRequestLimiter` or `RenderFrameHostImpl::DownloadURL`. That runs after the renderer has decided "download", loses the click's context, and still needs a patch.

### D7. Tab order and Spaces

Chromium keeps a split's tabs adjacent in its tab strip. `ClairSpaceTabs` (the Space's row order across windows) keeps them adjacent too, and moves them together:
- a split moves as one with `MoveSplitTo` within a window;
- between windows, it moves with `DetachSplitTabForInsertion` and `InsertDetachedSplitTabAt`, which is how `share-tabs-across-windows` moves a tab when another window selects it;
- Move to Space moves both tabs.

The tab commands' row list (`spaces`) treats the pair as one row, as it treats a tab and its Peek.

New tabs still go to the top. A split's new tab is inserted next to its source with `ADD_FORCE_INDEX` (`clair::NewTabIndex`), as an expanded Peek is.

### D8. Dragging onto the page

`PageCardView` registers for the sidebar's existing tab drag type. Over the page:
- the drag image becomes a portrait card with the favicon and title (about 115×210 pt in Arc);
- the half under the pointer, or the pane under it while split, becomes a drop zone tinted with the accent colour at low opacity, with an accent border;
- the page animates to the other half.

The drop calls `splitTab:withTab:side:` with the half it was dropped on, so the dropped tab lands there, focused, or `replacePaneOfTab:withTab:` while split. The replaced tab stays where Chromium leaves it, right after the split, which is the row below the split's row.

The card size, the zone's tint and the slide's timing are to be measured from an Arc recording with `tests/probe/` (task 1.1), as for Peek.

### D9. The split button and menus

The split button takes Arc's slot, the trailing one (`add-page-toolbar` D4 measured Arc's split button there, 21 pt from the edge, with site controls 36 pt to its left). In the single-page toolbar, site controls, extensions and indicators each move one slot left. In a pane header, × takes the trailing slot and the split button the next. `ToolbarArrangement` takes the slots as a list, so its narrow-window rules are unchanged: the split button and site controls are never left out. The menu is an `NSMenu` built from the window model:
- **on a single page:** a section header "Split with Tab", the Space's Today tabs other than the shown one, a separator, then New Tab;
- **on a split:** Move Left or Move Right, Separate Tabs and Close This Tab.

`PageHeaderContent` gains `.pane(leading:focused:)`:
- the leading pane gets the toggle;
- the focused pane gets reload, the split button, site controls, extensions and indicators, and so does the other pane while the pointer is over it, anywhere in the pane (Arc shows them only near its header). Its hover tracking covers the whole `PaneView`. Clicking one of them focuses the pane first (`activateTab:`), so it acts on that pane's tab;
- every pane gets back, forward, the link icon, the host and ×, as Arc's unfocused pane shows.

In a pane, × is centred 21 pt from the pane's edge, the split button 57 pt, site controls 93 pt, and extensions and indicators follow at 36 pt steps, as now.

Menu bar items:
- Tabs › Split with Tab ›, and View › Add Split View, Close Split Pane and Separate Tabs, are added where the folder change added New Folder…, through the native window's menu install (`InstallNativeWindowMenus`) and `ExecuteCommand`.
- `IDC_NEW_SPLIT_TAB` stays hidden. Clair's own items replace it.

The tab context menus gain Split with Tab › from the menus `PinsLogic` and the sidebar already build.

**Wording:** Clair says "Separate Tabs" everywhere, as Dia does. Arc's View menu says "Separate Page from Split View".

### D10. Pinned and favorited splits

`ClairPinStore` gains a **split record**, `{id, sortKey, ratio}`, with the place a pin has: a Space's pinned section, a folder in it, or a profile's favorites. A folder holds pins and splits, still one level deep. Each of its two pins names the split and its index (0 or 1), instead of its own place. The format follows `add-tab-folders`' iCloud-ready records: a move rewrites the split record only.

In `ClairHost.h`, `ClairPinnedItem` gains a split kind holding its two pins and its ratio, and the favorites list returns items in place of bare pins. Selecting a split item binds or opens both pins' tabs and makes them a Chromium split with the saved ratio:
- **Closing one pane** unbinds that pin only. The split record stays, so selecting the row again reopens it into the split.
- **Separate** turns the record into two pins at its sort key, in pane order.
- **Unpin and Remove Favorite** move or remove both pins.
- **Restore Last Closed Tab** brings a removed split record back with its pins.

A Today split holding a pin-bound tab (the spec's "A split with a pinned tab or favorite") is a Chromium split whose rows the sidebar shows in Today. The pin keeps its binding, so its row or tile stays and selects the split.

### D11. Peeks in a split

`PeekLayout` is unchanged and measures from the page area (D3), so a Peek is centred over both panes. Only the parent's `PaneView` takes the shrink and wash, as in Arc; the other pane keeps its size and colour. Task 1.1 checks what a click on that other pane does in Arc. Open in Split View expands the Peek as Expand does (`ClairPeeks`), then calls `AddToNewSplit` with the parent. The button isn't built while the parent has a partner, since a split holds two tabs.

### D12. Closing

Closing a tab in a split dissolves the split in `TabStripModel`, and the other tab stays where it was. `ClairSplits` then activates it, so the spec's "other tab shows alone" holds whatever Clair's next-tab rule would pick. The split row's × closes both tabs: `CloseTabs` on the pair, each with its leave-page confirmation, so tab restore records one `Split` entry.

### D13b. The command bar's place

The command bar is placed against the window today. While `paneCount` is 2, its horizontal centre becomes the focused `PaneView`'s centre in window coordinates, clamped so that the bar stays inside the window's content. Its vertical place doesn't change. Add Split View and the Split with Tab menus' New Tab make the split first, with a new tab page in the new pane (`splitTabWithNewTab:`, without a URL), so the command bar then centres on that pane like any other. It opens in Cmd+L's mode on the new tab, so a chosen page loads there. Esc leaves the new tab page in its pane. Arc closes its empty pane on Esc instead; the owner chose the simpler behaviour for now.

### D13a. Link status with a modifier

The link status capsule is `ClairUI`'s, fed by the page's hovered URL. It now also reads the modifier flags, from `flagsChanged` on the window while a URL shows:
- Option gives "Open <URL> in Split View";
- Shift, while `opensPeekOnShiftClick` is on, gives "Open <URL> in Peek";
- in a Peek, either gives the URL alone, since there Option acts as a plain click and Shift opens a tab.

Both texts follow what D6 and Peek actually do with the click, so the capsule never promises something else. In a split, the capsule sits at the bottom-leading corner of the hovered link's pane.

### D13. Runtime identifiers

- `clair.pane.0` and `clair.pane.1`, with each header as `clair.paneToolbar.N`;
- `clair.splitButton`, `clair.splitDivider` and `clair.closePane`;
- `clair.splitRow` on the sidebar row, with `clair.splitChip.N`.

The single-page toolbar keeps `clair.toolbar`.

## Beyond two panes

Not in this change; kept for a later one. Dia (`dia-reference/README.md`) allows up to four panes side by side:
- dropping a tab on a split page adds a pane where it's dropped;
- Option+click adds a pane (Dia at the far end; Clair would add it beside the source pane);
- "Split with Tab" stays in the pane menu while there's room;
- a fifth pane shows "Cannot Add New Pane".

Arc allows four, also as a grid.

Chromium's split model can't hold this: it `CHECK`s for two tabs and keeps one ratio. Going past two means either patching `SplitTabCollection` and its session commands, or replacing D1 with a table of Clair's own, as Peeks have. The cost of the latter is saving, tab restore and cross-window moves. `ClairUI`'s panes are already a list (D3), the contract names panes by tab, not by side (D2), and the pin store's split record holds pins by index (D10), so the change is mostly in the engine. Its spec changes:
- dropping on a split page and Option+click would add panes instead of replacing or navigating;
- "Cannot Add New Pane" would come at five.

## Risks / Trade-offs

- **[Chromium's split code may assume Views]** Chromium's split features (`split_tabs` metrics, the split tab menu, scrims, `kSideBySide` checks) may call into `BrowserView` or check a feature flag. → Turn on `kSideBySide` if `TabStripModel` checks it. Audit the callers of `OnSplitTabChanged` and `AddToNewSplit` in `chrome/browser/ui` for `BrowserView` use, and guard them as D9 of change 1 guards other Views paths. Task 2.1 does this before anything is built on it.
- **[Session restore through Clair's Space session]** `space-session.patch` adds Clair's tags to what's saved. Splits are separate session commands, so they should survive, but restoring tabs into Spaces could reorder them apart. → `ClairSpaceTabs` re-pairs by `SplitTabId` when it restores, and the runtime suite covers relaunch and Reopen Closed Window.
- **[Contiguity across windows]** A Space's row order spans windows, but Chromium's contiguity is per tab strip. → Both tabs always live in the same window (D7). The Space order keeps them adjacent as one row.
- **[Mixed pin-bound splits]** A pin-bound tab inside a Today split blurs "a pin's tab". → The binding doesn't change (D10). Only the sidebar's rendering does, and Separate returns to the normal case.
- **[Option+click patch]** It changes the renderer's click mapping, in two files that can conflict on version bumps. → Two small hunks, next to the Cmd+Option split-view code that already exists.
- **[No more than two panes]** People coming from Dia expect up to four. → "Beyond two panes" keeps the path open.

## Migration Plan

Clair isn't released, so saved data isn't converted. Pin stores written before this change load as they are: they have no split records.

## Open Questions

- Arc's exact drop-UI metrics and timing (D8), and whether Arc animates a split's panes when separating. Measured in task 1.1; neither changes the specs.
