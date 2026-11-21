# Arc's update banners: reference screenshots

These were probed on 2026-11-20 with `tests/probe/` (`probe.sh start`, `record.sh`):
- the waiting banner in Arc 1.173.1, with 1.174.0 downloaded;
- the "Update Complete!" card in 1.174.0, after clicking Restart and Update.

Captures are at 2 px per point, in Light Mode, from the owner's 963 × 976 pt window with a 228 pt sidebar. Each crop is the sidebar's bottom 206–226 pt. Measurements are in points, taken from the PNGs with `build/probe/bin/measure`, and are accurate to about ±1 pt. Arc showed neither banner in Dark Mode, so Dark Mode wasn't probed.

Keep these screenshots. They move with the change when it's archived.

| File | Shows |
|---|---|
| banner-pill.jpg | The waiting banner: a capsule reading "New Arc Version Available", 212 × 24 pt including a 1 pt border, inset 8 pt from both sidebar edges. Its bottom is 8 pt above the 50 pt footer. The fill is about 3 % darker than the sidebar (233 against 241) and the border about 9 % darker (219). The text is about 13 pt, regular, near black and centred. The accessibility tree has only a static text, with no button. |
| banner-hover.jpg | The pointer on the pill. It has grown upward into a white card, 212 × 85 pt, with its bottom on the pill's bottom. The card holds the title, a hairline, an "Automatic Updates" checkbox, and a full-width accent-filled "Restart and Update" button, about 21 pt tall with white text. The card covers the tab list and doesn't move it. |
| banner-hover-frames.jpg | Frames of the hover: in at 1350–1700 ms, and out after the pointer leaves at about 2480 ms. The card is fully drawn within about 120 ms, overshoots by about 2 pt, and settles by about 300 ms. While it animates in, the button shows a blue-to-purple gradient that settles to solid accent. Collapsing takes about 150 ms, as the card shrinks and fades into the pill, which then settles about 8 pt lower. |
| update-complete.jpg | The first launch after the update. An open white card, 212 × 80 pt, sits in the same place: "Update Complete!" centred, with a close × (20 × 20 pt) at the trailing edge; a hairline; "See What's New" with a heart-in-circle glyph, in accent colour; and "Gift Arc" with a gift glyph, in grey. Small four-point sparkles twinkle along the top edge and around the title. |
| update-complete-frames.jpg | The card over 5 s, at first with the pointer on it. It stays open, the sparkles keep twinkling, and the heart and "See What's New" keep cycling between blue and pink. |
| update-complete-close-frames.jpg | Clicking the ×: the × gets a rounded grey hover highlight, and then the card slides down about 15 pt and fades out in about 120 ms. Moving the pointer away first (not shown) leaves the card open. |
| update-complete-closed.jpg | After closing it: nothing between the tab list and the footer. Arc then had `autoUpdateBannerDismissalCount = 1` in its defaults. |

The accessibility tree had these:
- the waiting pill: `StaticText` "New Arc Version Available";
- the update complete card: `StaticText` "Update Complete!", `Button` identifier `xmark`, label "Close", and the rows as unlabelled 196 × 16 buttons;
- the Arc menu's item: "Update Available…, 1 update".
