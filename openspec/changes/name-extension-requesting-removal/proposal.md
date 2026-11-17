# Proposal

## Why

An extension with the `management` permission can ask to remove another extension with `chrome.management.uninstall`. Chromium then asks the user, and its dialog names the extension that asked ("“X” would like to remove this extension."). Clair's remove dialog (`arc-extension-experience` D4) shows only the extension being removed, so a removal another extension asked for looks the same as one the user started from the store or the Extensions menu. The user should know who is asking before they answer.

## What Changes

- **The remove dialog names the extension that asked for the removal**, when there is one, with the line "“<requester>” wants to remove this extension." under the title. The title, icon and buttons stay as they are: "Remove Extension" stays the default (Return) button, and "Cancel" (Esc).
- **The requester is only another extension.** Removals the user starts (the store's "Remove from Clair", the Extensions menu, `chrome://extensions`) and an extension removing itself show no such line, as in Chromium.
- **`ClairHost.h`:** `ClairExtensionPrompt` gains a nullable `requestedByName`. **BREAKING** for the contract: ClairUI and the engine must agree on the header, so the change ships with an engine build.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `extensions`: "Remove confirmation as a native sheet" names the requesting extension when another extension asked for the removal.

## Impact

- `native/ClairHost.h`: the new `requestedByName` property on `ClairExtensionPrompt`.
- `overlay/chrome/browser/clair/window/`: `ShowExtensionRemovePrompt` takes the requesting extension and fills the snapshot. The extension error alert's snapshot (`clair_extension_error_ui.mm`) declares the new property and leaves it nil.
- `patches/clair/native-window-hook.patch`: the uninstall dialog's hook passes `triggering_extension()`.
- `native/ClairUI/ExtensionPromptSheets.swift`: the remove dialog shows the line; `ExtensionPromptTests` and the fakes cover it.
- `tests/runtime/`: a test extension that asks to remove another, and a runtime test for the dialog.
- The engine key changes, so the pull request needs an engine build.
