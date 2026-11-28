# Browser import: reference screenshots

Probed on 2026-11-27 in Dia 1.58.2 (`company.thebrowser.dia`) with
`tests/probe/`, at 2 px per point, through Dia › Import from Another Browser….
Clair takes Dia's **flow** (pick a browser, then a step for that browser) and
its Safari instructions. Its look follows Clair's own dialogs, its title and
message are the owner's, and its buttons follow `dialogs`' stepped layout, not
Dia's full-width black button (`design.md` D9).

Keep these screenshots: they stay with the change when it's archived.

| File | Shows |
|---|---|
| 01-dia-pick-browser.jpg | The first step: serif title "Bring your stuff with you", "Pick a browser and everything comes with you. Tabs, passwords, bookmarks, extensions. All of it, in one step.", one card per browser (icon, name, radio) two per row, a full-width black "Continue ↩", a close × and painted artwork on the right. No per-item choices. |
| 02-dia-safari-export.jpg | Safari: "Open Safari and follow these steps to import your passwords, history, and bookmarks.", four numbered steps (Open Safari; File › Export Browsing Data to File…; Download and save; upload the .zip), a dashed "Choose .zip file or drag it here" area, Cancel and "Choose File… ↩". |
| 03-dia-arc-keychain.jpg | Arc: "Your Mac will ask for your password", priming the "Chrome Safe Storage"-style keychain prompt Dia raises to read Arc's passwords, with "Start Fresh" and "Import ↩". Clair imports no passwords, so Arc raises no prompt; Dia, whose tabs are encrypted, does (`design.md` D5). |

## Measurements (points, from the accessibility tree)

- Window 928 × 544, the left column 440 wide at a 32 inset; the artwork fills the right 478.
- Title at +56 from the top, 36 tall per line; message 16 below it.
- Browser cards 206.5 × 80, 11 apart, icon 52 at +19; the list scrolls at 280 tall.
- Buttons 44 tall, 32 from the bottom; Safari's Cancel 161 wide, its default 321.

Dia's own data, read for the design on the same day, isn't kept here: the
schema and walk are in `design.md` (Context, D5).
