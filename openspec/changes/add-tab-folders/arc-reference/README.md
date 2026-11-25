# Arc's folders: reference screenshots

These were probed on 2026-11-23 in Arc 1.170, with `tests/probe/` (`probe.sh`, and `build/probe/bin/drag` for drags, which Arc takes only as real mouse events). Captures are at 2 px per point, in Light Mode, from the owner's 963 × 976 pt window with a 228 pt sidebar, cropped to the part that matters.

Keep these screenshots. They move with the change when it's archived.

| File | Shows |
|---|---|
| plus-menu.jpg | The footer's + menu: New Space, New Folder, a divider, New Easel and New Boost, a divider, New Split and New Tab (⌘T). New Folder has no shortcut. |
| new-folder-inline.jpg | New Folder from the + menu: a folder row "Untitled", open, last in the pinned section, its name in a field with keyboard focus and the text selected. The field's placeholder is "Folder Title". Return keeps the name. |
| sidebar-menu-empty.jpg | Right-clicking the empty sidebar below the tabs: the Space header's menu, at the pointer. |
| sidebar-menu-new-tab.jpg | Right-clicking the "New Tab" row: the same menu, and the row shows its hover pill. |
| folder-menu-empty.jpg | An empty folder's menu: Share Folder…, New Nested Folder…, Turn "Reading" into Space, Change Icon…, Rename…, Duplicate, Move to ›, Delete. |
| folder-menu.jpg | A folder with a tab: the same, with Copy All Links after Turn into Space. |
| folder-closed.jpg | A click on an open folder closes it: the icon is drawn closed. An empty folder shows nothing below it either way. |
| new-folder-dialog.jpg | Tabs › New Folder… (menu item identifier `newListMenuItem`): a dialog titled "New Folder…", a field with the placeholder "What are you organizing?", Cancel (ESC) and Create (↩), which is disabled while the field is empty. |
| new-folder-dialog-created.jpg | Create: the folder "Inbox" is added open, last in the pinned section, below "Reading", though the first pinned tab was selected. |
| drop-on-folder.jpg | A Today tab dropped on the open, empty folder's row: it becomes the folder's tab, indented 16 pt, pinned and still selected. |
| folder-closed-selected.jpg | The folder closed while its tab's page is open: the tab stays listed under it, and the folder's icon shows "•••". A closed folder lists every tab whose page is open, selected or not (confirmed in Arc by the owner, 2026-11-25). |
| close-this-folder.jpg | Hovering the folder while its tab's page is open: a − button with the tooltip "Close This Folder". |
| close-this-folder-after.jpg | After clicking −: the tab's page is closed, the closed folder no longer lists it, and its icon is plain again. The window shows no page. |
| delete-folder-dialog.jpg | Delete on a folder with a tab: "Delete your "Inbox" folder?", "Deleting this folder will archive the tabs inside it.", Cancel (ESC) and a red Delete Folder (↩). An empty folder is deleted without asking. |
| drop-below-last-tab.jpg | A Today tab dragged just below an open folder's last tab, with the pointer at the sidebar's leading edge: the insertion line shows there. |
| drop-below-last-tab-after.jpg | The drop: the tab became the folder's last tab, not a pinned tab after the folder. |
| drag-out-above.jpg | A folder's tab dragged above the folder: it's a pinned tab outside the folder, keeping its page. |
| turn-into-space-menu.jpg | Turn "Trip" into Space, on a folder with one tab. |
| turn-into-space-after.jpg | After choosing it, with no confirmation: a new Space "Trip" is last in the switcher, the window shows it, and the folder's tab is its pinned tab, with its page. The folder left the first Space. |

Not observed: the folder row's exact sizes and colours, Dark Mode, a drag of a folder, a drop on a closed folder, and what Esc does in the inline name field.
