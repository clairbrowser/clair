# Tasks

## 1. Store checks through `UpdateService`, stripped

- [ ] 1.1 Add the routing and address hunks to `patches/clair/restore-web-store.patch`, each with a comment naming what it undoes or why:
  - `CanUseUpdateService` is true only for an installed extension whose update URL is the store's (D1);
  - `UpdateCheckerImpl::CheckForUpdates` returns early unless the product ID is the extension updater's (D2);
  - `extension_urls::GetWebstoreJsonUpdateUrl()` is added, following `--apps-gallery-update-url` when it's set (D3, D7);
  - `ChromeUpdateClientConfig::UpdateUrl()` returns it, passed as `url_override` only under the switch, and `PingUrl()` returns no address (D3, D4).

  Verify that `./build.sh fetch prepare` applies the series with no fuzz, on the patch check or locally against the engine workspace.
- [ ] 1.2 Add the stripping hunks to `components/update_client/protocol_serializer.cc` (D4): no `hw`, `os.version` or `domain_joined`, and no `install_date`, `install_id`, cohort fields, `enabled`, `disabled_reasons`, `ping` or `cached_hashes` on an app. Verify that the patch check applies it.
- [ ] 1.3 Build the engine (`gh workflow run engine.yml -f ref=<branch>`). Verify that it compiles and publishes `chromium-engine-<key>`.
- [ ] 1.4 Give `tests/runtime/server.py` a `POST /service/update2/json` handler (D7). It answers each requested app with `noupdate` plus the flags the test set through a `GET /update-flags?…` call, and keeps the last request body at `GET /update-request`. Make `run.sh` pack a `flagged` test extension whose `update_url` is the local store URL. Verify with `python3 -I -m py_compile` and by posting a sample request to it by hand.
- [ ] 1.5 Add `tests/runtime/ClairRuntimeTests/ExtensionUpdateTests.swift`. It launches with `--apps-gallery-update-url` pointing at the server, `--extensions-update-frequency` and the always-prompt install switch, installs `flagged.crx`, and waits for a check. Then it asserts that:
  - the request reached `/service/update2/json`, not the XML path;
  - its body has the extension's ID, version and install source, `mac` and `arm64`;
  - it has none of the fields `extensions`' "What a store update check sends" rules out.

  Verify by running the test locally, which is allowed on this Mac, and it passes.

## 2. Acting on the flags

- [ ] 2.1 Add the revert hunks of D5 to `restore-web-store.patch`, each naming `fix-building-without-safebrowsing.patch` and the hunk it undoes:
  - `BUILD.gn`'s `omaha_attributes_handler` files;
  - `ExtensionService`'s handler and `PerformActionBasedOnOmahaAttributes`, without the allowlist call;
  - `ChromeExtensionSystem`'s forwarding call;
  - the four `ExtensionRegistrar` handlers;
  - `UpdateService::OnCrxStateChange`'s attribute call.

  Verify that the engine builds (as in 1.3).
- [ ] 2.2 Add runtime tests in `ExtensionUpdateTests.swift`:
  - with `_malware` set, the extension stops running, its action leaves the sidebar's extensions, and `chrome://extensions`, read over CDP, lists it as blocklisted;
  - with `_policy_violation` set, it's disabled with the greylist reason, and turning it on through `chrome.management` or the page keeps it on after the next check;
  - clearing `_malware` loads it again.

  Verify by running them locally, and they pass.
- [ ] 2.3 Record in the PR what `chrome://extensions` shows for each flag (design's Open Question). Verify that the PR carries it.

## 3. The malware dialog

- [ ] 3.1 Add the hook in `CreateDefaultExtensionErrorUI` to `patches/clair/native-window-hook.patch`, and `overlay/chrome/browser/clair/window/clair_extension_error_ui.{h,mm}` as D6 describes:
  - an `ExtensionPromptKindOther` prompt with Chromium's title and item text, OK as accept and no cancel;
  - OK acknowledges the extensions;
  - with no Clair window, it waits for the profile's next window.

  Verify that the engine builds.
- [ ] 3.2 Add a `ClairUI` unit test in `ExtensionPromptTests.swift` that an `.other` prompt with an empty cancel label makes a page with one button, OK, as the default. Verify that it passes in CI.
- [ ] 3.3 Add runtime tests in `ExtensionUpdateTests.swift`:
  - when `_malware` is set, a dialog on the window says Clair found that the extension contains malware, and OK closes it;
  - relaunching with the same profile shows no dialog;
  - a `_policy_violation` flag shows no dialog.

  Verify by running them locally, and they pass.

## 4. Release notes and integration

- [ ] 4.1 Add a Changie fragment (`changie new`): Clair now turns off store extensions that Google has pulled as malware, policy-violating or unwanted, and says so for malware. Store update checks now go to Google's update service at `update.googleapis.com` and send no more than before. Verify that it's in the PR.
- [ ] 4.2 Add `tests/probe/omaha-flags.sh`, which sends the stripped request for one extension ID and version and prints the flags, and document it in `tests/probe/README.md` as the check to repeat at each engine bump. Verify with `shellcheck -S warning` and by running it for a pulled extension, which prints `_malware: true`.
- [ ] 4.3 Check by hand, with the test copy (`tests/probe/launch-clair.sh`) and the real store:
  - install a current store extension, and see that its update check goes to `update.googleapis.com` and succeeds with CUP on;
  - the netlog body matches 1.5's rules;
  - an idle new profile with no extensions sends no update check.

  Verify that each check passes, and note the results in the PR.
- [ ] 4.4 Run the merge gate, and start `quality.yml` on the branch with the last push. Verify that CI and the quality checks pass.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.
