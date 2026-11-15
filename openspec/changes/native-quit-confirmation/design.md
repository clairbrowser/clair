# Design

## Context

- Chromium's `-[BrowserCrApplication terminate:]` (`chrome_browser_application_mac.mm`) is the entry point for every orderly quit: the Quit menu item and its Cmd+Q key equivalent, the Dock, Activity Monitor, logout and shutdown. It calls `-[AppController tryToTerminateApplication]`, which runs `-confirmQuitIfNeeded` (the hold-to-quit panel, keyboard quits only, gated by `prefs::kConfirmToQuitEnabled`), then Chromium's download warning, then closes the browsers.
- The Quit item is built in `main_menu_builder.mm` with tag `IDC_EXIT`, target `NSApp` and action `terminate:`, so a click on it reaches `-terminate:` with that item as the sender. The Dock and system quits arrive as Apple Events, without it.
- Cmd+Q never reaches the menu: the window's command dispatcher runs `IDC_EXIT`, and `chrome::Exit()` goes through `BrowserProcessPlatformPart::AttemptExit()`, which calls `-confirmQuitIfNeeded` with the key event still current and only then `-terminate:`.
- Settings › Advanced's toggle is already `-[ClairHost warnsBeforeQuitting]` over that pref (`add-profiles` D12).
- Clair's dialogs (`ClairDialog`) already look as Arc's, with ESC and ↩ keys on their buttons; Dia's sheet is laid out the same way, plus one button at the leading corner (`dia-reference/`).

## Goals / Non-Goals

**Goals:** Dia's wording, controls and layout; the hold-to-quit panel gone; the stored setting unchanged; two hook lines in Chromium files.

**Non-Goals:** Dia's look (Clair's dialogs keep theirs); asking on system or Dock quits; replacing Chromium's download warning.

## Decisions

### D1. Override the prompt, keep Chromium's pref

The setting stays `browser.confirm_to_quit` in Local State. Only the prompt changes: while ClairUI runs, `-confirmQuitIfNeeded` asks ClairUI instead of showing the hold-to-quit panel, and `-terminate:` asks for a menu click.

*Alternative:* a setting of Clair's own and a hook that bypasses Chromium entirely. It needs the same two hooks to silence the panel and catch `-terminate:`, plus a migration for users who turned the setting off, with no visible gain.

### D2. Which quits ask

Two hooks in `clair_native_layer.mm` find the user's own quits: `clair::MaybeConfirmKeyboardQuit()`, from `-confirmQuitIfNeeded`, for Cmd+Q (the current event maps to `IDC_EXIT`, as Chromium's own check), and `clair::MaybeConfirmQuit(sender)`, from `-terminate:`, for a click on Clair › Quit Clair (`sender` is the `NSMenuItem` tagged `IDC_EXIT`). Either asks only when all hold:

- ClairUI runs and Clair isn't already quitting;
- `kConfirmToQuitEnabled` is on;
- no download blocks shutdown (`DownloadCoreService::BlockingShutdownCountAllProfiles`), since Chromium's download warning follows and would be a second dialog;
- a native browser window is open.

Otherwise it returns false and the quit goes on as Chromium's would.

### D3. Where the dialog shows

`clair::ShowQuitConfirmation()` (`clair_window_hooks.mm`) picks the key native window, or else the most recently active one, which it activates (Chromium activates windows, per `ClairHost.h`'s rules), and calls `-[ClairWindow showQuitConfirmation]`. Dia shows its dialog as a sheet on the window, as Clair's dialogs already are; an app-modal `NSAlert` would stack three buttons vertically and can't take Dia's layout.

### D4. The contract

- `-[ClairWindow showQuitConfirmation]`: ClairUI shows `QuitConfirmation`'s dialog on that window's `ClairDialogPresenter`, unless one already shows or waits there, so a second Cmd+Q does nothing.
- `-[ClairHost quitWithoutWarning]`: `[NSApp terminate:nil]`. With no menu item as the sender and no Cmd+Q as the current event, D2 lets it through; Chromium's download warning still applies.
- Quit answers `.accepted` and calls `quitWithoutWarning`. Always quit sets `warnsBeforeQuitting = NO`, then does the same. Cancel, Esc and the window closing answer `.cancelled`.

### D5. `ClairDialogPage.leadingButton`

As `add-link-rules` D6 designs it: an optional button at the bottom leading corner, styled as Cancel, with no key and no keyboard shortcut, whose action is the only way it answers. Its runtime identifier is `clair.dialogLeading`. `add-link-rules` then needs only its destructive cancel button.

## Risks / Trade-offs

- **[`-terminate:` or `-confirmQuitIfNeeded` changes upstream]** → Each hook is one call at the method's top; the patch check fails loudly if one no longer applies, and the runtime test covers both paths.
- **[A dialog already waits on the window]** → The quit dialog queues behind it, as every Clair dialog does; answering the first shows it.
- **[Sparkle quits to install]** → Sparkle calls `-terminate:` without a menu item, so it never asks.

## Migration Plan

None: the pref is unchanged.
