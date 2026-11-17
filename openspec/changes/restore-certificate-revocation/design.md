# Design

## Context

See `proposal.md` for why. This builds on `disable-flagged-store-extensions` (referred to below as *the store change*). That change:
- turns ungoogled-chromium's early `return;` in `UpdateCheckerImpl::CheckForUpdates` into a gate that lets extension checks through (its D2);
- strips the request in `protocol_serializer.cc`, keeping `cached_hashes` (its D4);
- adds "Google services Clair turns back on" to `chromium-engine` (its D7).

The current state in the engine tree (Chromium 156.0.8078.79):
- **Components are all registered.** `chrome/browser/component_updater/registration.cc` registers Chromium's components, CRLSet among them (`RegisterCRLSetComponent`), in one `ComponentUpdateService`. ungoogled-chromium leaves the registrations alone; its block in the update checker is what keeps them from ever checking. The component updater checks every registered component in one request: first about a minute after launch (`ConfiguratorImpl::InitialDelay`), then every five hours (`NextCheckDelay`).
- **CRLSet's installer.** `crl_set_component_installer.cc` installs to `CertificateRevocation/<version>/crl-set` in the user data folder. At startup and on each update, `ComponentReady` hands the bytes to the cert verifier service (`GetCertVerifierServiceFactory()->UpdateCRLSet`). `CertVerifyProcBuiltin` checks each chain against it. Its policy allows unencrypted transport (`RequiresNetworkEncryption` returns `false`).
- **No list by default.** `CRLSet::BuiltinCRLSet()` has no entries. ungoogled-chromium's patches don't touch CRLSet's installer or its use.
- **The address is substituted.** The component updater's address is in `components/component_updater/component_updater_url_constants.cc`: an HTTPS default and a plain-HTTP fallback for `update.googleapis.com/service/update2/json`, and nothing else. Domain substitution rewrites it. `ChromeConfigurator` builds its `ConfiguratorImpl` with `require_encryption = false`, so the HTTP fallback stays in the list.
- **Pings.** `ChromeConfigurator::PingUrl()` returns the update address when pings are on, which they are by default (`CommandLineConfigPolicy::PingsEnabled`). Its `GetLang()` returns the browser language.
- **The probe.** A stripped request for CRLSet's ID (`hfnkpimlhhgieaddgfemjhofmfblmnib`) at version `0.0.0.0`, as product `chromium`, got version 10908 back. That's a 9.5 MB full package, with download addresses over both HTTP and HTTPS.

## Goals / Non-Goals

**Goals:**
- Clair has and applies a current CRLSet, as Chrome does.
- The component updater checks nothing else.
- The check sends no more than CRLSet needs, and only over HTTPS.

**Non-Goals:**
- The PKI metadata component, which updates the Chrome Root Store and Certificate Transparency log list between releases. It's a protective feed too and could join the list in its own change. Root distrusts reach Clair with each engine bump.
- Online revocation checks (OCSP or CRL fetches from each CA). They contact the CA on every connection and fail open.
- A setting to turn the check off. Chrome has none, and Arc had none.

## Decisions

### D1. Component checks carry CRLSet's ID only

The store change's gate lets the extension updater's checks through. Here it also lets the component updater's checks through, but `CheckForUpdatesHelper` puts only CRLSet's app ID into a component request. The other registered components are left out, get no answer and stay as they are. If nothing is left after filtering, no request is sent.

The allowed ID is a single constant beside the gate, and the patch comment says which requirement lists it.

*Alternatives:*
- **Registering only CRLSet**, with a hook in `RegisterComponentsForUpdate`. Other code registers components outside that function (on-demand ones, for example). A filter at the one place requests are built catches all of them.
- **Dropping ungoogled-chromium's block.** That would check and install Widevine, optimization hints, origin trials and the rest, which "Google services Clair turns back on" doesn't allow.

### D2. The update service's address file leaves domain substitution

`utils/domain_substitution_exclude.list` gains `components/component_updater/component_updater_url_constants.cc`. The file holds only the update service's two addresses, and `chromium-engine`'s "Built from a pinned ungoogled-chromium release" now allows that. `scripts/filter-domain-substitution.sh` and its test need no change: the list is data.

The store change names its own copy of the address in `extension_urls.cc` (its D3). Once this lands, that copy could read from here instead. It stays as it is, so each change can be built alone.

*Alternative:* **naming the address in a Clair overlay file** behind a hook in `ConfiguratorImpl::UpdateUrl`. That's more code for the same result, and it hides the address from the file that holds it upstream.

### D3. HTTPS only, for checks and downloads

There are two one-line hunks:
- `ChromeConfigurator` builds its `ConfiguratorImpl` with `require_encryption = true`, which drops the HTTP fallback address.
- `CRLSetPolicy::RequiresNetworkEncryption()` returns `true`, which makes `update_client` drop the HTTP download addresses.

Both the answer (CUP) and the package (its hash in the answer and the CRX signature) are already authenticated. HTTPS keeps the request's fields off the wire for anyone watching the network, and so it keeps them from learning that this is Clair.

*Alternative:* **keeping the fallback** for networks that block HTTPS to Google. That's rare, and on such a network the user keeps the last list.

### D4. No language, no pings

There are two more hunks in `ChromeConfigurator`:
- `GetLang()` returns an empty string, which the serializer then leaves out. CRLSet is the same in every language.
- `PingUrl()` returns no address, as the store change does for extensions.

The store change's stripping hunks cover the rest, since the component updater shares `protocol_serializer.cc`. `prodchannel` stays, as in extension checks. `cached_hashes` stays, so CRLSet updates as patches: the full list is 9.5 MB and changes several times a day, and Chromium keeps the package for this either way.

*Alternative:* **leaving the language in,** as extension checks do. Extension checks keep it because the XML route always sent it. Here it serves no purpose.

### D5. Ordering with the store change

This change edits hunks the store change adds (the gate, the stripping) and requirements its deltas add. Its tasks start once the store change's implementation has merged, and it's archived after the store change, which the spec deltas need: archive refuses a MODIFIED block for a requirement main specs don't have yet.

## Risks / Trade-offs

- **[Every launch contacts Google]** Until now, a profile with no store extensions sent Google nothing. Now each running Clair sends a check every five hours. That tells Google, by IP address, that a Chromium-based browser at this version is running. → It's the minimum for current revocation data. The request carries no identifier, and the rule and the idle-launch scenario now say it plainly. The Changie fragment says so.
- **[A broken list blocks sites]** A list that wrongly revokes a certificate would block it in Clair as in Chrome. → Same exposure as Chrome. Google stages lists, and a fixed list arrives within five hours.
- **[Unanswered components]** The other registered components get no answer at every check. → `update_client` records an error for each and tries again next time. That's log noise only, and less than today, where ungoogled's block leaves the whole update engine waiting forever.
- **[Disk]** About 10 MB for the installed list and the cached package. → Acceptable for a browser, and Chrome keeps the same.
- **[Upstream churn]** The checker, the configurator and the CRLSet policy change between Chromium versions. → No-fuzz patching names any hunk that stops applying.

## Migration Plan

- After updating, the first check runs about a minute after launch. The list installs once and is used from then on, including at later launches before their first check.
- **Rollback:** a reverted build stops checking. The installed list stays in `CertificateRevocation` and is still loaded at startup, so it keeps protecting until it goes stale. Deleting the folder removes it.
