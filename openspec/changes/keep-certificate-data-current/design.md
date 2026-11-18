# Design

## Context

See `proposal.md` for why. This builds on `restore-certificate-revocation` (archived 2026-11-17), referred to below as *the revocation change*. In the engine tree (Chromium 156.0.8078.79):

- **The filter.** `UpdateCheckerImpl::CheckForUpdatesHelper` (in `patches/clair/restore-web-store.patch`) leaves out of a component request every app ID except CRLSet's (`kClairCrlSetAppId`). It also drops HTTP download addresses from the answer for components whose policy requires network encryption. The configurator (in `patches/clair/restore-certificate-revocation.patch`) requires HTTPS, and sends no language and no pings. The request stripping in `protocol_serializer.cc` covers every check.
- **The PKI metadata component** (`efniojlnjndmcbiieegkicadnoecjjef`) is registered unconditionally by `MaybeRegisterPKIMetadataComponent`. ungoogled-chromium doesn't touch it, and today it's filtered out. It installs to `PKIMetadata/<version>/` in the user data folder. On `OnComponentReady`, `PKIMetadataComponentInstallerService`:
  - loads `ct_config.pb` and sends the log list to the network and cert verifier services, but only if CT is on (`kCertificateTransparencyAskBeforeEnabling`, which ungoogled-chromium turns on by default and exposes as `#enforce-certificate-transparency`) and the list is no older than the compiled-in one. The new list's timestamp becomes the date that `ChromeCTPolicyEnforcer::IsLogDataTimely` measures 10 weeks from.
  - loads `kp_pinslist.pb` and sends the pins to the network service if they're no older than `kPinsListTimestamp`. `TransportSecurityState::IsStaticPKPListTimely` then measures 10 weeks from the component's timestamp instead of the compiled-in one.
  - loads `crs.pb` (`ConfigureChromeRootStore`) for the cert verifier. macOS builds use the Chrome Root Store only (`chrome_root_store_only` in `net/features.gni`), and the verifier takes a component root store only if its version is newer than the compiled-in one.
  - Its policy allows unencrypted transport (`RequiresNetworkEncryption` returns `false`).
- **The fast-push component** (`oaanfgijljhkdknnacjidbpmmgnghhjj`) carries Merkle Tree Certificate metadata. It's registered only when `kVerifyMTCs` is on, which it isn't by default.
- **HSTS preload.** `TransportSecurityState::GetStaticSTSState` returns nothing when `IsBuildTimely()` is false, which happens 10 weeks after `base::GetBuildTime()`. For official builds, that's the time of the last Chromium commit. It has no other caller. No component carries the preload list.
- **The CT kill switch.** A `ct_config.pb` with `disable_ct_enforcement` set turns CT enforcement off. Google uses it in Chrome for emergencies.

## Goals / Non-Goals

**Goals:**
- CT, static pins and the root store stay as current in Clair as in Chrome, with no new request or field.
- HSTS preload never switches off because of the engine's age.

**Non-Goals:**
- **A release preflight on the engine's data dates.** With these feeds refreshed and HSTS preload enforced at any age, an old engine no longer drops any of them. A new install still starts from the compiled-in data until its first check, a minute after launch.
- **The fast-push component.** Its feature is off. If Chromium turns it on by default, a later change can add it.
- **Refreshing the HSTS preload list between engines.** Nothing in Chromium does that.

## Decisions

### D1. The filter lets through two IDs

The single `kClairCrlSetAppId` constant becomes a short list of the component IDs Clair checks: CRLSet's and the PKI metadata component's. Each is named, with a comment pointing at "Google services Clair turns back on". `CheckForUpdatesHelper` keeps every other component out, as now. The hunk stays in `restore-web-store.patch`, beside the gate it changes.

Both components go in the one request the component updater already sends every five hours, so Google sees no extra request. It sees the same request with one more app entry.

*Alternative:* **a second filter, or checking the component on demand.** More code, and it adds a request rather than sharing one.

### D2. HTTPS for the component's downloads

`PKIMetadataComponentInstallerPolicy::RequiresNetworkEncryption()` returns `true`, so the revocation change's rule (drop HTTP download addresses for components that require encryption) covers it with no new code. The hunk goes in a new patch, `patches/clair/keep-certificate-data-current.patch`, after `restore-certificate-revocation.patch` in `patches/series`. The patch's header says why, as the revocation change's does.

### D3. The root store comes with it

The component carries `crs.pb` beside the CT and pin data, and Clair applies all three. Chrome uses it to distrust certificate authorities between releases. Without it, a distrusted authority stays trusted in Clair until the next engine bump. Taking the CT and pin data while ignoring the root store would mean patching `OnComponentReady` to skip it, which leaves Clair less protected than Chrome for no privacy gain: the request and the download are the same either way.

*Alternative:* **skip `crs.pb`.** Rejected, as above.

### D4. HSTS preload is always timely

`TransportSecurityState::IsBuildTimely()` returns `true`, and the patch comment says why. Same patch as D2. Chromium expires the list so that a site that has left it isn't forced onto HTTPS forever. In Clair, that cost lasts at most until the next engine bump, while expiry would drop HTTPS enforcement on every preloaded site. Static pins have their own clock (`IsStaticPKPListTimely`), which D1 keeps current, so this doesn't touch them.

*Alternative:* **keep the expiry and bump the engine before it runs out.** Clair can make sure a release ships a current engine, but not that users install it. A user who updates late would lose HSTS preload.

### D5. Nothing more to strip

The request is built by the same serializer and configurator as CRLSet's: no language, no install or device IDs, no cohorts, no activity or event pings, HTTPS only. The new app entry carries the same fields as CRLSet's: ID, version, the hash of the cached package (so updates come as patches) and the random request IDs. No new hunk is needed. The implementation confirms this by capturing a check (task 1.3).

### D6. Tests

A runtime test launches Clair with a throwaway data folder and waits for `PKIMetadata/<version>/` to hold `ct_config.pb`, `kp_pinslist.pb` and `crs.pb`, which proves the filter lets the component through and that it installs over HTTPS. The first check runs about a minute after launch, so the test waits up to three minutes.

No test can express the 10-week rules without moving the clock that both the browser and its TLS stack read. The HSTS hunk is one line and is checked by reading it.

## Risks / Trade-offs

- **[Google can turn CT off in Clair]** The component's kill switch reaches Clair as it reaches Chrome. → Same exposure as Chrome, and it's only used for emergencies. Without the component, CT turns itself off anyway 10 weeks after each engine.
- **[Google can change Clair's trusted roots between releases]** → That's how Chrome's root program removes authorities. The component is signed with Chromium's pinned key, and the verifier takes only a root store newer than the compiled-in one.
- **[A stale HSTS entry]** A site removed from the preload list stays HTTPS-only in Clair until the next engine bump. → Rare, and the site still works over HTTPS.
- **[A wrong pin or log list blocks sites]** → Same as Chrome. A fixed component arrives within five hours.
- **[Upstream churn]** The installer, the policy and `TransportSecurityState` change between Chromium versions. → No-fuzz patching names any hunk that stops applying.

## Migration Plan

- After updating, the first check about a minute after launch fetches the component, and Clair applies it from then on, including at later launches before their first check.
- **Rollback:** a reverted build stops checking for the component and no longer enforces an old preload list. The installed component stays in `PKIMetadata` and is still loaded at startup until its 10 weeks run out. Deleting the folder removes it.
