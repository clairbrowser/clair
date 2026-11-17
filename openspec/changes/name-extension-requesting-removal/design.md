# Design

## Context

- `ExtensionUninstallDialog::ConfirmUninstallByExtension` stores a triggering extension that `triggering_extension()` returns. Its one caller is `chrome.management.uninstall` (`chrome_management_api_delegate.cc`). `management_api.cc` uses it only when the calling extension removes another one and isn't the Web Store app. A store web page, `chrome://extensions`, the Extensions menu and `uninstallSelf` call `ConfirmUninstall`, with no triggering extension.
- `native-window-hook.patch` makes `ExtensionUninstallDialogImpl::Show()` call `clair::ShowExtensionRemovePrompt(parent(), extension(), icon(), …)` first and return when a native window takes the prompt. Chromium's paragraph for the triggering extension comes after that return, so Clair's path never shows it.
- `clair_extensions.mm` fills a `ClairChromiumExtensionPrompt` snapshot (`ClairExtensionPrompt` in `ClairHost.h`), and `ExtensionPromptDialog.make(for:)` (`ExtensionPromptSheets.swift`) words the remove dialog itself, in Clair's English text. The dialog's `message` slot is empty for a removal.

## Goals / Non-Goals

**Goals:** the remove dialog names the extension that asked, in the cases Chromium's does; the hook in Chromium's file stays one call.

**Non-Goals:**
- The default button. "Remove Extension" stays the Return default whoever asked, as in Chromium's own dialog. Whether extension prompts should default to Cancel or hold their accept button is a separate decision, for all prompts at once.
- The requester's icon, and Chromium's "Report abuse" checkbox (the spec keeps that out).
- Prompts of kind "other" (re-enabling, permissions), which already show Chromium's own text.

## Decisions

### D1. The contract carries the requester's display name

`ClairExtensionPrompt` gains `@property(nonatomic, readonly, copy, nullable) NSString *requestedByName;`, nil unless another extension asked. The engine fills it with `GetFixupExtensionNameForUIDisplay(triggering_extension()->name())`, the same treatment as `extensionName`, so a name can't spoof layout with control or direction characters.

*Alternative:* a ready-made message string from the engine, as kind "other" uses. The install and remove dialogs are worded in ClairUI (`arc-extension-experience` D4), and splitting one dialog's text between two sides would leave the wording in two places.

*Alternative:* the requester's ID. ClairUI would have to look up the name, with no API for it, and the name is what the user recognizes.

### D2. The engine passes the triggering extension through the existing hook

`clair::ShowExtensionRemovePrompt` gains a `const extensions::Extension* requested_by` parameter, after `extension`. The patch passes `triggering_extension()`, which is null for every path but `chrome.management.uninstall` on another extension. The patch still adds one call in `Show()`; only its arguments change.

### D3. ClairUI shows the line as the dialog's message

For `.remove`, `ExtensionPromptDialog.make(for:)` sets the page's message to "“<requestedByName>” wants to remove this extension." when the name is non-nil and non-empty, and leaves it nil otherwise. Title, icon and buttons don't change. The message uses the dialog's existing secondary text style below the title, where Chromium puts its paragraph. The wording follows Clair's dialogs ("wants to"), not Chromium's "would like to".

## Risks / Trade-offs

- **[The contract changes]** ClairUI built against the new header with an older engine, or the reverse, won't link the property. → `ClairUI` ships inside the app with its engine; the pull request builds the engine for the new key, as every `ClairHost.h` change does.
- **[A malicious extension can still name itself after something trusted]** The dialog shows the name the extension chose. → The same as Chromium's dialog; the line still tells the user that an extension, not they, started the removal.
