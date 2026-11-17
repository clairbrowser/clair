# Design

## Context

See `proposal.md` for why. The current state in the engine tree (Chromium 156.0.8078.79):

- **Update routing.** `ExtensionUpdater::CanUseUpdateService` returns `false` for every extension (Clair's hunk in `restore-web-store.patch`, design D2 of `arc-extension-experience`). Store extensions are checked by `ExtensionDownloader` at `https://clients2.google.com/service/update2/crx`, and `safe_manifest_parser.cc` reads versions and package URLs from the XML answer. `chrome_extension_downloader_factory.cc` enables usage pings only for the substituted Google domain, so the XML route sends no activity data.
- **The update client is blocked.** ungoogled-chromium's `block-requests.patch` makes `UpdateCheckerImpl::CheckForUpdates` return at once without calling back. That stops every `update_client` check, both the component updater's and `UpdateService`'s.
- **The flag handling is gone.** ungoogled-chromium's `fix-building-without-safebrowsing.patch`:
  - drops `omaha_attributes_handler.{cc,h}` from `chrome/browser/extensions/BUILD.gn`;
  - removes `ExtensionService::PerformActionBasedOnOmahaAttributes`, and empties `ChromeExtensionSystem::PerformActionBasedOnOmahaAttributes`;
  - removes the attribute call in `UpdateService::OnCrxStateChange`;
  - empties `ExtensionRegistrar::OnBlocklistStateAdded`, `OnBlocklistStateRemoved`, `OnGreylistStateAdded` and `OnGreylistStateRemoved`.

  The same patch also removes these calls from the Safe Browsing and telemetry verdict handlers. Those stay removed, since their sources are compiled out.
- **The JSON service's address is substituted.** `UpdateService`'s default address comes from `component_updater_url_constants.cc` (`update.googleapis.com/service/update2/json`), which domain substitution rewrites. `ChromeUpdateClientConfig` takes an optional URL override, but an override also turns off CUP signing (`EnabledCupSigning`).
- **The alert.** Chromium tells the user about a blocklisted extension with `ExtensionErrorController`, which creates an `ExtensionErrorUIDesktop` (a `GlobalErrorWithStandardBubble` anchored to the toolbar's app menu). Clair's native window has neither. Its strings are already rebranded: "Clair found that "X" contains malware".
- **The probe.** A hand-made JSON request with only `appid`, `version`, `installsource`, the product and version, `@os`, `arch`, `os.platform` and `os.arch`, and random `sessionid` and `requestid`, got `"_malware":"true"` back for an extension Google pulled as malware. It did so as `chromiumcrx`, the ID a Chromium build sends.

Patches apply before domain substitution (`build.sh`), so a URL literal a Clair hunk writes survives only in a file on `utils/domain_substitution_exclude.list`.

## Goals / Non-Goals

**Goals:**
- Pulled store extensions are turned off from the update check's flags, with Chromium's own state, prefs and `chrome://extensions` display.
- Store update checks send no more about the user or the Mac than the XML checks did.
- Every Chromium change is a revert of ungoogled-chromium's removal, a routing hunk, a field-stripping hunk or a hook (`chromium-engine`).

**Non-Goals:**
- Safe Browsing's blocklist, the store metadata service, Enhanced Safe Browsing's allowlist (`_esbAllowlist`) and the off-store telemetry verdicts.
- The component updater, which stays blocked.
- Delta (differential) updates. Without cached hashes in the request, the service sends full packages, as the XML route does.
- Any change to self-hosted extensions, policy installs or first installs from the store.

## Decisions

### D1. Store extensions go through `UpdateService`, chosen by update URL

`CanUseUpdateService`'s `if ((true)) return false;` hunk becomes "true only for an installed extension whose update URL is the store's". Upstream also sends an extension with no update URL to the store. Clair keeps such extensions off it, because `extensions` says an extension with no update URL is never checked against the store. Pending installs (`!extension`) keep going to `ExtensionDownloader`, as upstream does.

*Alternatives:*
- **Teaching the XML parser the flags.** The XML answer doesn't carry them; the attributes exist only in the JSON protocol.
- **A separate JSON request just for flags, beside the XML check.** That would double the requests and add new code with no upstream counterpart.

### D2. The update checker runs extension checks only

ungoogled-chromium's early `return;` in `UpdateCheckerImpl::CheckForUpdates` becomes "return unless the configurator's product ID is the extension updater's (`UpdateQueryParams::CRX`)". The component updater stays exactly as blocked as before. Its address is substituted anyway, but this keeps it from even trying.

*Alternative:* **dropping the `return;`**. That would wake the component updater, against `chromium-engine`'s "Component updater stays off".

### D3. The JSON address is named in `extension_urls.cc`

A hunk adds `extension_urls::GetWebstoreJsonUpdateUrl()` (`https://update.googleapis.com/service/update2/json`) to `extension_urls.cc`, which is already left out of domain substitution. `ChromeUpdateClientConfig::UpdateUrl()` returns it, without going through `url_override_`, so CUP signing stays on. `component_updater_url_constants.cc` stays substituted.

*Alternatives:*
- **Leaving `component_updater_url_constants.cc` out of substitution.** That makes the component updater's address real too, which D2 of `arc-extension-experience` already rejected.
- **Passing the address as `url_override`.** That turns off CUP, which authenticates each answer, flags included, beyond TLS.

### D4. The request is stripped where it's built

`protocol_serializer.cc` builds the request structs that `protocol_serializer_json.cc` writes, and Clair's hunks change two of its functions:

- **`MakeProtocolRequest`** leaves out `hw`, `os.version` and `domain_joined`.
- **`MakeProtocolApp`** leaves out `install_date`, `install_id`, the cohort fields, `enabled`, `disabled_reasons`, `ping` and `cached_hashes`.

`ChromeUpdateClientConfig::PingUrl()` returns no address, so `PingManager` sends no events (it returns early on an empty list).

The `updaters` node is written only in Google Chrome builds, so it needs nothing. `lang` and `prodchannel` stay, matching the XML route's `GetExtraParams`. Since D2 confines the update client to extension checks, the stripping applies to nothing else.

*Alternatives:*
- **Stripping in `protocol_serializer_json.cc`.** That works too, but the fields would still be gathered, and the JSON writer has more upstream churn.
- **A `ChromeUpdateClientConfig` subclass in the overlay.** The hardware and OS fields don't come from the configurator, so it can't reach them.

### D5. The flag handling is reverted whole

These revert ungoogled-chromium's hunks as they were:
- `omaha_attributes_handler.{cc,h}` in `BUILD.gn`;
- `ExtensionService`'s handler member, its include and `PerformActionBasedOnOmahaAttributes`, without the `allowlist_` call (Enhanced Safe Browsing) but with `error_controller_->ShowErrorIfNeeded()`;
- `ChromeExtensionSystem`'s forwarding call;
- the four `ExtensionRegistrar` handlers;
- `UpdateService::OnCrxStateChange`'s attribute call.

Each hunk names the upstream patch and hunk it undoes, as the store hunks do. `OmahaAttributesHandler`'s UMA calls compile to no-ops in a build without metrics reporting.

*Alternative:* **writing Clair's own handler in the overlay.** It would duplicate `OmahaAttributesHandler` and the registrar's state machine, which upstream tests.

### D6. The malware alert is a Clair extension prompt

A hook in `CreateDefaultExtensionErrorUI` (`extension_error_controller.cc`) returns `clair::CreateExtensionErrorUI(delegate)` when that function returns one. It lives in `native-window-hook.patch`, beside the install prompt hook.

The new `overlay/chrome/browser/clair/window/clair_extension_error_ui.{h,mm}` implements `ExtensionErrorUI`:
- `ShowErrorInBubbleView` finds the profile's last active Clair window and shows a `ClairExtensionPromptKindOther` prompt:
  - the title is Chromium's alert title for the delegate's blocklisted extensions;
  - the permission lines are Chromium's item text (`GenerateMessage`'s strings);
  - the accept label is `IDS_EXTENSION_ALERT_ITEM_OK`;
  - the cancel label is empty, so `ExtensionPromptSheets` shows OK alone.
- Answering calls `OnAlertAccept`, then `OnAlertClosed`, which acknowledges the extensions in prefs, so the dialog isn't shown again.
- With no Clair window, it returns `true`, keeps waiting, and shows the prompt when the profile's next browser window opens. Chromium's version returns `false`, which drops the alert until the next launch.

There's no Details button. Chromium's opens `chrome://extensions`, which Manage Extensions… already reaches, and the dialog spec's Esc maps to cancel.

*Alternative:* **a new `ClairHost.h` call for notices.** The prompt protocol already carries a title, lines and a one-button form, so the contract doesn't change.

## Risks / Trade-offs

- **[The service may want a field Clair strips]** The probe showed the flags come back without the stripped fields. If Google later ties flags or updates to them, checks still return versions, but flags could stop arriving. → Accepted. Store extensions would still update, and the probe request in Context can be repeated if flags seem to stop.
- **[CUP keys or verification broken by pruning]** ungoogled-chromium edits `components/update_client/BUILD.gn` for pruned binaries. If CUP fails, every store check fails. → A broken CUP shows up as store extensions no longer updating. If it can't work, fall back to passing the address as an override and record the loss of CUP here.
- **[Google sees store checks at a new address]** `update.googleapis.com` is a different host from `clients2.google.com`. It's the same company and the same data. → The Changie fragment says so.
- **[Upstream churn]** `OmahaAttributesHandler`, the registrar handlers and the serializer change between Chromium versions. → No-fuzz patching names any hunk that stops applying, and each revert hunk names the upstream hunk to compare.
- **[A false flag turns off an extension the user trusts]** This is the same exposure Chrome users have. Policy and potentially-unwanted flags can be overridden in `chrome://extensions`, and malware can't, as in Chrome.
- **[Untested]** By the owner's decision, the change ships with no new tests: its tasks are verified by the engine build and the merge gate. → The reverted code is upstream's and has upstream's tests. The routing, stripping and dialog are small.

## Migration Plan

- After updating, the first store update check (within Chromium's usual startup delay) applies any current flags. Extensions installed from a CRX with the store's update URL are included. Extensions with no update URL are not.
- **Rollback:** a reverted build checks through `ExtensionDownloader` again. The blocklist and greylist bits stay in `Preferences`, but ungoogled-chromium's empty registrar handlers ignore them. `ExtensionRegistrar::AddExtension` still reads the blocklist bits at startup, so a malware-flagged extension stays unloaded, as Chrome would leave it. A greylisted one keeps its disable reason, and the user can turn it on. Removing the extension clears both.

## Open Questions

- Whether `chrome://extensions`'s malware and policy-violation wording survives ungoogled-chromium's string and Safe Browsing changes as Chromium's. If the wording is missing, the spec's scenarios still hold by the state the page shows, and the wording is a follow-up.
