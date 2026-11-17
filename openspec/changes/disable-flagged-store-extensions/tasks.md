# Tasks

## 1. Store checks through `UpdateService`, stripped

- [ ] 1.1 Add the routing and address hunks to `patches/clair/restore-web-store.patch`, each with a comment naming what it undoes or why:
  - `CanUseUpdateService` is true only for an installed extension whose update URL is the store's (D1);
  - `UpdateCheckerImpl::CheckForUpdates` returns early unless the product ID is the extension updater's (D2);
  - `extension_urls::GetWebstoreJsonUpdateUrl()` is added, and `ChromeUpdateClientConfig::UpdateUrl()` returns it (D3);
  - `ChromeUpdateClientConfig::PingUrl()` returns no address (D4).

  Verify that the patch check applies the series with no fuzz.
- [ ] 1.2 Add the stripping hunks to `components/update_client/protocol_serializer.cc` (D4):
  - no `hw`, `os.version` or `domain_joined`;
  - on each app, no `install_date`, `install_id`, cohort fields, `enabled`, `disabled_reasons` or `ping`. `cached_hashes` stays, for delta updates (D4).

  Verify that the patch check applies it.

## 2. Acting on the flags

- [ ] 2.1 Add the revert hunks of D5 to `restore-web-store.patch`, each naming `fix-building-without-safebrowsing.patch` and the hunk it undoes:
  - `BUILD.gn`'s `omaha_attributes_handler` files;
  - `ExtensionService`'s handler and `PerformActionBasedOnOmahaAttributes`, without the allowlist call;
  - `ChromeExtensionSystem`'s forwarding call;
  - the four `ExtensionRegistrar` handlers;
  - `UpdateService::OnCrxStateChange`'s attribute call.

  Verify that the patch check applies them.

## 3. The malware dialog

- [ ] 3.1 Add the hook in `CreateDefaultExtensionErrorUI` to `patches/clair/native-window-hook.patch`, and `overlay/chrome/browser/clair/window/clair_extension_error_ui.{h,mm}` as D6 describes:
  - an `ExtensionPromptKindOther` prompt with Chromium's title and item text, OK as accept and no cancel;
  - OK acknowledges the extensions;
  - with no Clair window, it waits for the profile's next window.

  Verify that the patch check applies the hook.

## 4. Build and release notes

- [ ] 4.1 Build the engine (`gh workflow run engine.yml -f ref=<branch>`). Verify that it compiles and publishes `chromium-engine-<key>`.
- [ ] 4.2 Add a Changie fragment (`changie new`): Clair now turns off store extensions that Google has pulled as malware, policy-violating or unwanted, and says so for malware. Store update checks now go to Google's update service at `update.googleapis.com` and send no more than before. Verify that it's in the PR.
- [ ] 4.3 Run the merge gate. Verify that CI passes.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.
