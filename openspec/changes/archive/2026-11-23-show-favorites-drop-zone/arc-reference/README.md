# Arc's favorites drop zone: reference screenshots

The owner recorded these on 2026-11-23 in Arc, in Light Mode, from a window whose profile had no favorites and whose "Drag to add Favorites" box had been dismissed. The probe's XCUITest `drag` doesn't start a tab drag in Arc, so it couldn't record them. The frames are about 2 px per point, and come from a sidebar about 229 pt wide. Measurements were taken with `build/probe/bin/measure` and are accurate to about ±1 pt. Dark Mode wasn't recorded.

Keep these screenshots. They move with the change when it's archived.

| File | Shows |
|---|---|
| drop-zone-appears-frames.jpg | A Today tab dragged up over the Space header, which shows its drop highlight. The box appears in one frame, with no animation, once the pointer goes above the header, pushing the Space down by its height. Before that, the pointer over the top row shows "+". |
| drop-zone.jpg | The box while the drag is elsewhere: the dismissable box's layout (94 pt tall, inset 8 pt, a star in an accent circle, "Drag to add Favorites" in bold, the message in grey), with no ×. The dashed border is fainter (172 against a 228 background, about 30 % accent), and the fill only slightly lighter than the sidebar (231 against 227, about 12 % white), not accent-tinted. |
| drop-zone-targeted.jpg | The drag over the box. The border turns solid, in the same colour, the fill lighter (235, about 30 % white), and the star, title and message fade to about half. The drag shows a square tile, about 45 pt, with the tab's icon. |
| drag-ends-frames.jpg | The drag going back down and dropping among the Today tabs. The box stays while the drag is anywhere else, and goes in one frame when the drag ends. |
| drop-frames.jpg | A drop on the box: the box goes at once, the drag image settles where the tile goes, and the tile appears, filling the row. |
