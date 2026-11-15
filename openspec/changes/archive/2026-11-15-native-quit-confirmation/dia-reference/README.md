# Quit dialog: reference screenshots

Probed on 2026-11-15 in Dia 1.57.1 (`company.thebrowser.dia`) with
`tests/probe/` (`probe.sh start company.thebrowser.dia`, then `key q cmd`
and `tree`), at 2 px per point, with Dia's "Warn before quitting" on. Clair's
dialog copies Dia's **wording, controls and layout**. Its look is Clair's
own dialogs' (`dialogs` spec), which already show Arc's ESC and ↩ keys.

Keep these screenshots: they stay with the change when it's archived.

| File | Shows |
|---|---|
| quit-dialog.jpg | The dialog alone: Dia's icon, "Are you sure you want to quit Dia?", "You may lose unsaved work in your tabs.", then "Always quit" at the bottom leading corner and Cancel (ESC) and a red Quit (↩) at the trailing corner. |
| quit-dialog-window.jpg | The same dialog on its window: a sheet centred on the dimmed window, not an app-modal alert. |

## What it does

- **Cmd+Q and Dia › Quit Dia** both show it, on the window.
- **Quit** (Return) quits. **Cancel** (Esc) keeps Dia running.
- **Always quit** has no key. Its localization comment in Dia's binary reads "Always quit and don't present dialog again button": it quits and turns the setting off.
- **Downloads:** Dia's binary has a separate dialog with the same title and "You have 1 download in progress. If you quit now, this download will be cancelled." Clair keeps Chromium's own download warning for that case.

## Measurements (points, from the accessibility tree)

- Sheet 424 × 200. Icon 34 × 34, 23 in from the top and leading edge.
- Title and message text 376 wide, starting 64 below the sheet's top.
- Buttons 36 tall, 23 from the bottom: Always quit 103 wide at the leading inset; Cancel 106 wide and Quit 78 wide at the trailing inset, 6 apart.
