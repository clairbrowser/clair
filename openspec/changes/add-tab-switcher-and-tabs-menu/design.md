# Design

## Context

- **Ctrl+Tab today** is the key equivalent of Chromium's Tab › Select Next Tab (`IDC_CYCLE_TO_NEXT_TAB`, from `accelerators_cocoa.mm`). `ClairBrowserWindow::ExecuteTabCommand` runs it over the sidebar's rows. Chromium's own shortcut table (`global_keyboard_shortcuts_mac.mm`) has no Ctrl+Tab entry, so the menu is the only route.
- **Chromium's Tab menu** (`IDC_TAB_MENU`, title "Tab") holds Chromium's items. `PinsMenu` hides Chromium's pin items and adds Clair's (Pin Tab, New Folder…, Back to Pinned URL, Close and Keep Pinned, Clear Today), and `SplitMenu` adds Split with Tab ›. `AppController` looks the menu up by tag on every main-window change: its `TabMenuBridge` appends the open tabs, and the vertical-tab code checks its items.
- **Context menus** come from `PinsLogic.todayMenu`, `pinnedMenu` and `favoriteMenu` as lists of items, with `nil` for a divider, grown one item at a time.
- **Pages of background tabs** have no surface to copy. Chromium's `ThumbnailTabHelper` captures a tab as it's hidden, but only with `kTabHoverCardImages`, which is off on macOS. Clair already copies a visible page for the still (`ClairBrowserWindow::CopyPage`).
- **Arc's switcher** was probed on 2026-11-26 (`arc-reference/README.md`).

## Goals / Non-Goals

**Goals:**
- Arc's Ctrl+Tab switcher: keys, contents, layout and the absence of animation.
- The owner's Tabs menu and context menu layouts, with Chromium's Tab menu and every Clair customization of it gone.

**Non-Goals:**
- Choosing cards with the pointer. A setting for the old Ctrl+Tab.
- Arc's other menus.

## Decisions

### D1. Recents live in ClairUI, one list per window

`BrowserWindowController` keeps a `RecentTabs` value: up to 16 entry IDs, most recent first, where an entry is the row's tab ID. A split counts once, through its leading pane, as `RowOf` does. A Peek counts as its parent. On `activeTabDidChange`, the shown row moves to the front. The still's placeholder tab never enters the list.

On every `tabsDidChange` and pins change, an entry whose tab no longer exists is dropped, in any Space or favorites. A closed page, a closed tab and a tab of a removed Space all go this way. On a profile swap (`shownSpaceDidChange(…swappedInFor:)`), the incoming window takes the outgoing window's list, as it takes its sidebar. The list belongs to the window as the user sees it.

`RecentTabs` is pure logic, unit-tested with `FakeHost`, which reports tabs of every Space.

Kept in the engine instead, the list would need a new observer call for something ClairUI already sees in full.

### D2. The keys: a local event monitor

`TabSwitcher` installs one `NSEvent` local monitor for `.keyDown` and `.flagsChanged`. It handles events only while the key window is a normal browser window with no Clair dialog or sheet up:

| Event | Effect |
|---|---|
| Ctrl+Tab or Ctrl+Shift+Tab, with no other modifier | Opens the switcher with the second card selected (Shift: the last). With fewer than two entries, swallowed and nothing happens. |
| Tab or Shift+Tab, switcher open | Steps the selection, wrapping. |
| Esc, switcher open | Cancels. |
| Other keys, switcher open | Swallowed. |
| `flagsChanged` without Control, switcher open | Commits. |

Every handled event returns nil, so the page, the command bar and Chromium never see it. The window resigning key or the shown tab closing cancels. A second monitor, active only while the switcher is open, swallows mouse downs, as Arc ignores clicks then.

With Chromium's Tab menu deleted (D5), Chromium no longer has Ctrl+Tab at all.

The open/step/commit/cancel state is a pure `SwitcherState` with unit tests. The monitor is thin glue.

### D3. The panel

A borderless, non-activating `NSPanel`, a child window of the browser window, hosting SwiftUI. It is laid out from Arc's measurements:

- **Panel:** 27 pt padding, cards 157.5 × 105 pt with a 24 pt pitch gap, label row below each card. About 938 × 189 pt for five cards. Light background (`windowBackgroundColor` at Arc's #F2F2F2 in light mode), about 22 pt corner radius, hairline border and shadow.
- **Selection:** a 12 pt inset rounded highlight, about 12 pt radius, in the accent colour at the sidebar's selection opacity. The selected title is in the primary colour, the others secondary.
- **Labels:** favicon 16 pt, then the title or custom name at the sidebar's title size, medium weight, one line, with an ellipsis.
- **Position:** centred on the window, then moved inside the screen's visible frame. Arc centred a two-card panel on the window, but its five-card panel sat about 29 pt right of centre in a 963 pt window; centring is the simpler rule.

Shown with `orderFront` and no animation, 100 ms after Ctrl+Tab (a timer `SwitcherState` starts on opening), or at once on a second Tab or Shift+Tab. A commit before the timer fires never shows the panel, so a quick Ctrl+Tab just switches, as in Arc, whose delay measured between 90 and 130 ms. The panel is re-rendered in place as the selection moves. Previews arriving late replace the placeholder in place. Dark mode uses the system's dark window background. Arc wasn't probed in dark mode.

### D4. Page previews from the engine

The contract (`ClairHost.h`, `ClairBrowser`):

```objc
// A preview of the tab's page for the tab switcher, `size` in points. The
// shown tab's page as it is now; any other tab's as it was when this or
// another window last hid it; nil when there is none (never shown, crashed,
// or a copy that failed). `completion` runs once, on the main thread.
- (void)requestPreviewOfTab:(ClairTabID)tabID
                       size:(NSSize)size
                 completion:(void (^)(NSImage *_Nullable preview))completion;
```

- **Capture.** The engine copies a tab's page with `CopyPage` as the tab stops being shown. That happens in `ClairBrowserWindow`'s active-tab change, before Chromium hides it, which is where `TabStripModel` asks `ThumbnailTabHelper` for its own. The copy is scaled to 2× the card's width, cut to the card's 3:2 shape from the top, and kept on the tab as `WebContents` user data (`ClairTabPreview`).
- **Lifetime and memory.** One image per tab, replaced on each hide, freed with the tab: about 100 KB each.
- **The shown tab** is copied live on request.
- **Peeks.** A tab with a Peek gets the parent's page; the still's convention is followed.

Turning on `kTabHoverCardImages` was rejected: it needs a patch to a Chromium default, and brings JPEG compression and background video capture that Clair doesn't need.

A split's card asks for both panes and draws them side by side in pane order.

### D5. Delete Chromium's Tab menu, add Clair's Tabs menu

The engine deletes Chromium's Tab menu (the main menu item tagged `IDC_TAB_MENU`) in `clair_window_hooks.mm`, where it already reworks the main menu at start-up, before any window becomes main. ClairUI's new `TabsMenu` inserts its "Tabs" menu before the Window menu (`IDC_WINDOW_MENU`), where Chromium's sat.

This needs no patch to a Chromium file. Nothing else breaks either: `AppController` finds the menu by tag on each main-window change, and with nil, `TabMenuBridge` and `onVerticalTabStripModeChanged` do nothing (every call is a nil message, and the latter returns early).

Deleting beats hiding. A hidden item still fires its key equivalent (as `clair_window_hooks.mm` notes), so hiding would also mean clearing every key equivalent and leaving `TabMenuBridge` to fill a menu nobody sees. Deleting takes Ctrl+Tab, Ctrl+Shift+Tab and Search Tabs' shortcut away from Chromium with the menu.

The items:

| Item | Action | Enabled |
|---|---|---|
| Pin Tab / Unpin Tab ⌘D | `PinsLogic.MainMenuCommand.togglePin` | as today |
| Pin to Favorites | new `.pinToFavorites` → `favorite(tab:at:)` at the end | Today or pinned tab, not private |
| New Folder… | `.newFolder` | as today |
| Next Tab ⌥⌘↓, Previous Tab ⌥⌘↑ | `commandDispatch:` with `IDC_SELECT_NEXT_TAB` / `IDC_SELECT_PREVIOUS_TAB`, target nil | validated by Chromium. Chromium's shortcut table handles the keys first (`space-shortcuts.patch`), so the menu only shows them. |
| Split with Tab › | moved from `SplitMenu` | as today |
| Move to Space › | `move(tab:toSpace:)` on the shown row | other Spaces exist, not a favorite, not private |
| Clear Unpinned Tabs ⇧⌘K | `.clearToday` | as today |

- **Moves out of other menus:** `PinsMenu` keeps only View › Collapse Pinned Tabs. `SplitMenu` keeps only its View items.
- **Removed:** `MainMenuCommand.backToPinnedURL` and `.closeKeepingPin`. Their row and keyboard routes stay.
- **Tags:** `TabsMenu` takes the tag range `0x436C_5200`.

### D5a. Remove every customization of Chromium's Tab menu

With Chromium's Tab menu deleted, nothing Clair did to it or for it is needed. Each was checked against Chromium's `main_menu_builder.mm`, `accelerators_cocoa.mm` (which only sets menu key equivalents) and `global_keyboard_shortcuts_mac.mm`: each command below is reachable only through that menu.

**ClairUI**

| Where | Goes |
|---|---|
| `PinsMenu.install` | Hiding Chromium's Pin Tab items (`IDC_WINDOW_PIN_TAB` 35013, `IDC_PIN_TARGET_TAB` 35051) and clearing their key equivalents. Inserting Pin Tab, New Folder…, Back to Pinned URL, Close and Keep Pinned and Clear Today into the Tab menu. `tabMenuTag` goes too. `PinsMenu` keeps only View › Collapse Pinned Tabs. |
| `SplitMenu.install` | Inserting Split with Tab › into the Tab menu. The item moves to `TabsMenu`. |
| `SplitTests`, `FoldersTests` (unit) | Their fake "Tab" menus. They test `TabsMenu` instead. |
| Runtime `PinsTests.tabMenu` | `menuBarItems["Tab"]` becomes "Tabs". Clear Today becomes Clear Unpinned Tabs. Back to Pinned URL moves to the row's icon or Edit Pinned Page ›. `FoldersTests` and `SplitViewTests` follow through `tabMenuItem`. |

**Engine (`engine/overlay`)**

| Where | Goes |
|---|---|
| `clair_window_hooks.mm` | Gains the deletion of the Tab menu (D5). |
| `ClairBrowserWindow::ExecuteTabCommand` | `IDC_CYCLE_TO_NEXT_TAB` and `IDC_CYCLE_TO_PREV_TAB` (Tab › Select Next/Previous Tab, Ctrl+Tab). `IDC_WINDOW_CLOSE_TABS_TO_RIGHT` (Close Tabs to the Right) and `IDC_WINDOW_CLOSE_OTHER_TABS` (Close Other Tabs). Close Tabs Below stays, through `-closeTabsBelowTab:`. `IDC_SELECT_NEXT_TAB` and `IDC_SELECT_PREVIOUS_TAB` stay for Opt+Cmd+Down and Up and for Tabs › Next and Previous Tab. |
| `ClairPeeks::ExecuteCommand` | `IDC_DUPLICATE_TAB` and `IDC_MOVE_TAB_TO_NEW_WINDOW` (Tab › Duplicate Tab and Move Tab to New Window). |
| `ClairWindowCommandHandler` validation | `IDC_DUPLICATE_TAB`, `IDC_MOVE_TAB_TO_NEW_WINDOW`, `IDC_WINDOW_CLOSE_OTHER_TABS` and `IDC_WINDOW_CLOSE_TABS_TO_RIGHT` in the modal-dialog list. |
| `ClairIsRemovedCommand` | `IDC_TAB_SEARCH`, `IDC_WINDOW_GROUP_TAB`, `IDC_GROUP_TARGET_TAB` and `IDC_NEW_SPLIT_TAB`, which it listed only to hide the Tab menu's items. With the menu gone, nothing sends them. Its other entries live in other menus and stay. |

**Docs:** `docs/native-window.md`'s "Rows and commands" stops listing Ctrl+Tab among the row commands.

Before deleting each engine case, the implementation greps the Chromium tree for other senders of the command (extension APIs, context menus Clair shows). A command with another sender keeps its case.

### D6. Context menus in groups

`PinsLogic` builds each menu as groups (`[[MenuItem]]`), and a helper joins non-empty groups with dividers. A group left empty (no pin items in private windows, no Close Tab on a closed pin) drops out with its divider.

| Menu | Groups |
|---|---|
| Today | [Pin Tab, Pin to Favorites] · [Copy Link, Duplicate] · [Split with Tab ›, Move to Space ›] · [Rename…, Mute] · [Close Tab, Close Tabs Below] |
| Pinned | [Unpin Tab, Pin to Favorites] · [Copy Link, Duplicate] · [Split with Tab ›, Move to Space ›] · [Rename…, Mute, Edit Pinned Page ›] · [Close Tab when open] |
| Favorite | [Remove Favorite] · [Copy Link, Duplicate] · [Split with Tab ›] · [Rename…, Mute, Edit Pinned Page ›] · [Close Tab when shown] |
| Split chip | its kind's menu, Separate Tabs in Split with Tab's place, no Edit Pinned Page |

- **Pinned Close Tab** runs Close and Keep Pinned on that pin.
- **Edit Pinned Page ›** gains Back to Pinned URL first (a new `MenuCommand.backToPinnedURL`), so a favorite navigated away keeps a way back now the Tabs menu item is gone. Favorites have no icon button.

### D7. Runtime identifiers

- **Panel:** `clair.tabSwitcher`.
- **Cards:** `clair.tabSwitcherCard`, with the title as the label, and the selected one with the selected trait.
- **Menu:** the menu bar item is titled "Tabs".

### D8. The probe gets real key events

`tests/probe/tools/keys.swift`, from this change's scratch tool, posts real key events with modifiers held across steps (`ctrldown tab sleep:0.5 shot:… ctrlup`), which XCUITest's `typeKey` can't do. Arc took them. The README gains it beside `drag` and `mouse`.

## Risks / Trade-offs

- **[A hide copy can miss]** If the surface is gone before `CopyFromSurface` answers, the tab keeps its older preview or none. → Fall back to a blank card with the favicon (spec), and check timing in the hand check.
- **[The local monitor sees every key]** → It returns early unless Control is down or the switcher is open, so the cost per key is one flag test.
- **[A later Chromium looks the Tab menu up without a nil check]** → The engine-update patch check won't catch it, but the runtime suite's window activation would crash. Grep for `IDC_TAB_MENU` on each engine update (a note in `docs/building.md`'s "Updating the engine").
- **[Arc's horizontal position]** Arc's panel wasn't centred on the probe window. → Centred and kept on screen. Revisit if the owner sees a difference.

## Migration Plan

None: Clair isn't released. The engine key changes with `ClairHost.h`, so the engine is rebuilt.

## Open Questions

None.
