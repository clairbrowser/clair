# Proposal

## Why

With "Warn before quitting" on, Clair shows Chromium's "Hold ⌘Q to Quit" panel, which nobody coming from Arc or Dia expects: the quit seems to fail unless the key is held. Dia asks in a dialog on the window instead, with a way to stop asking. Clair should do the same.

## What Changes

- **Cmd+Q and Clair › Quit Clair ask in a dialog** while "Warn before quitting" is on, with Dia's wording, controls and layout (`dia-reference/`): "Are you sure you want to quit Clair?", "You may lose unsaved work in your tabs.", "Always quit" at the bottom leading corner, and Cancel and a red Quit at the trailing corner. It's a Clair dialog on the key browser window, or the most recently active one.
  - **Quit** quits. **Cancel**, Esc or closing the window keeps Clair running.
  - **Always quit** turns "Warn before quitting" off and quits.
- **Chromium's hold-to-quit panel never shows.** The setting is still Chromium's `browser.confirm_to_quit` pref, so the Settings toggle and users' existing choice carry over.
- **Other quits never ask:** the Dock's Quit, logging out or shutting down, Activity Monitor, update relaunches, and a quit with no browser window open. With a download in progress, Chromium's own download warning asks instead, so there's never a second dialog.
- **Dialogs gain a leading button**, at the bottom leading corner with no key, as `add-link-rules` D6 designs it. Link Rules' "Add Rule" uses it too.
- **BREAKING (`ClairHost.h`):** the host gains `quitWithoutWarning`, and each window `showQuitConfirmation`.

**Out of scope:** Dia's combined downloads dialog (Chromium's stays), and asking on the Dock's Quit.

## Capabilities

### Modified Capabilities

- `settings-window`: "Warn before quitting toggle" asks in a dialog rather than requiring Cmd+Q to be held.
- `dialogs`: "Dialog buttons and keys" allows a button at the bottom leading corner.
