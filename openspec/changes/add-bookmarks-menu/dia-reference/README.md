# Dia's bookmark editor: reference screenshots

Probed on 2026-11-15 in Dia 1.57.1 (`company.thebrowser.dia`) on macOS
27.2.1 with `tests/probe/` (`probe.sh start company.thebrowser.dia`), at
2 px per point, in Light Mode, in a 960 × 976 pt window. The menus were
read with System Events from an adapted copy of
`../../archive/2026-11-05-ship-plain-ungoogled-build/arc-reference/dump-arc-menus.applescript`.

Clair's folders differ from Dia's. Clair has one list, Chromium's Other Bookmarks, called "Bookmarks", and keeps the Bookmarks Bar empty. So its folder popup starts with "Bookmarks", not Bookmarks Bar, and New Folder… creates the folder at the top of Bookmarks.

Clair copies Dia's **controls and their layout** for its bookmark dialog:
the title with the page's icon, Name, Folder, Remove and Done. The dialog
itself is Clair's own (`dialogs`): a card centred on the dimmed window, with
Clair's insets, fonts and key capsules. It isn't a popover hanging from a URL
bar button, as Dia's is.

Keep these screenshots. They move with the change when it's archived.

| File | Shows |
|---|---|
| add.jpg | ⌘D on a page that isn't bookmarked. The bookmark is added **at once**, and the popover is titled "Bookmark added", with the name selected in its field. |
| edit.jpg | ⌘D on a bookmarked page. It's the same popover, titled "Edit bookmark": a globe or favicon at the title row's trailing end, the Name field (focused, text selected), the Folder popup showing the current folder, Remove at the bottom leading corner, and Done ↵, filled, at the bottom trailing corner. |
| measured.jpg | The same popover, captured whole for measuring (its name field had been emptied by the probe). |
| folder-popup.jpg | The Folder popup: Bookmarks Bar, its subfolder "Test Folder" indented under it, then "New Folder…" indented under it too, Other Bookmarks with a checkmark, a divider, and Manage Bookmarks. |
| new-folder.jpg | After choosing New Folder…, the popup turns into a text field with the placeholder "New folder name…" and a × button at its trailing end. |
| folder-popup-nested.jpg | After typing "Probe Folder" and Return: the folder is created inside **Bookmarks Bar** and selected, and the popover stays open with focus back in Name. |
| tab-menu.jpg | A bookmarked tab's context menu: Remove Bookmark and Move Bookmark › in their own group. (For reference only: Clair's tab menus follow the owner's choice, which is Add to Bookmarks… or Remove Bookmark after the pin items.) |

## Behaviour

- **One editor for adding and editing.** Only the title changes: "Bookmark added" after adding, "Edit bookmark" otherwise.
- **The bookmark is added before the editor shows**, into the folder last used ("Other Bookmarks" here). Remove deletes it.
- **Esc keeps the edits.** After renaming to "colour-renamed" and pressing Esc, the Bookmarks menu listed "colour-renamed". Done and Return do the same.
- **The Bookmarks menu's first item** is "Bookmark This Page" on a page that isn't bookmarked and "Edit Bookmark" on one that is, both on ⌘D. (Clair uses ⇧⌘B, keeping ⌘D for Pin Tab as in Arc, and adds an ellipsis because a dialog follows.)
- Dia's Bookmarks menu also has a "Recent Bookmarks" section between Manage Bookmarks and the folders. Clair leaves it out.

## Measurements (points, from measured.jpg)

These are from Dia's popover. Clair keeps its own card's insets and width (`ClairDialogView`: 450 pt wide, 38 / 38 / 26 / 28 pt insets) and uses these for the controls inside.

| Part | Dia |
|---|---|
| Card | 380 × 214, 16 pt padding on every side |
| Title | Bold, about 17 pt; the icon is 26 pt (its frame) at the title row's trailing end |
| Labels | "Name" and "Folder", secondary grey, in a column 68 pt wide before the fields |
| Fields | 36 pt tall, filling the rest of the row (280 pt); 12 pt between Name and Folder; rounded rectangle, a light fill, and the accent focus ring on Name |
| Folder popup | The same box as the field, with the folder's name and a chevron at the trailing end |
| Buttons | 80 × 36, 20 pt below the Folder row; Remove at the leading edge, Done ↵ at the trailing edge |
