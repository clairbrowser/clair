# Tasks

Groups 1 and 2 change the engine key, so build the engine first and push docs afterwards, as `CLAUDE.md` describes. "CI" is the merge gate in `ci.yml`. D-numbers are `design.md`'s decisions.

## 1. Contract and ClairUI

- [x] 1.1 Add the nullable `requestedByName` to `ClairExtensionPrompt` in `native/ClairHost.h` (D1), and to `FakeExtensionPrompt`. Verify that the header compiles in `ClairHostObjCxxTests.mm` in CI.
- [x] 1.2 Show "“<requester>” wants to remove this extension." as the remove dialog's message when `requestedByName` is set (D3). Verify with `ExtensionPromptTests` in CI: the message with a requester; no message when it's nil or empty; the same title and buttons, with "Remove Extension" as the default, in both cases.

## 2. Engine

- [x] 2.1 Give `clair::ShowExtensionRemovePrompt` the `requested_by` parameter and fill `requestedByName` with its display name (D1, D2), in `clair_window_hooks.h` and `clair_extensions.mm`. Verify with the runtime test in 3.1.
- [x] 2.2 Pass `triggering_extension()` from `ExtensionUninstallDialogImpl::Show()` in `patches/clair/native-window-hook.patch` (D2). Verify that the patch check applies it.
- [x] 2.3 Build the engine with `gh workflow run engine.yml -f ref=<branch>`. Verify that `chromium-engine-<key>` is published and CI's engine check passes.

## 3. Tests and release notes

- [x] 3.1 Add a test extension to `tests/runtime/extensions/` with the `management` permission and a page that removes another loaded test extension by name, and a runtime test in `DialogTests.swift`: the dialog names the requester, Esc keeps the target installed, and the store-style title and buttons are unchanged. Verify with a `quality.yml` run on the branch.
- [x] 3.2 Add a Changie fragment. Verify that `openspec validate --all --strict` passes in CI.
