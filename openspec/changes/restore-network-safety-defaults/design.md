# Design

## Context

See `proposal.md` for why. Current state in the engine tree (ungoogled-chromium 157.0.8103.78-1):

- **The DoH default.** `doh-changes.patch` (in the `core` series) changes four files:
  - `default_dns_over_https_config_source.cc` sets the `kDnsOverHttpsMode` pref default to `off` instead of `automatic`;
  - `services/network/public/cpp/features.cc` makes `kDnsOverHttpsUpgrade` disabled on every platform. `NetworkService::ConfigureStubHostResolver` passes that flag to the host resolver as `allow_dns_over_https_upgrade`;
  - `doh_provider_entry.cc` deletes the `Google` and `GoogleDns64` providers;
  - `dns_probe_runner.cc` probes `example.com` instead of `google.com`.
- **Managed Macs.** `StubResolverConfigReader::ShouldDisableDohForManaged` forces automatic mode off when machine-level policies are installed and no policy sets the DoH mode. Neither ungoogled-chromium nor Clair changes this.
- **The resolver on macOS.** `kAsyncDns` is on for Mac. Chromium's built-in resolver reads the system's nameservers (`DnsConfigServicePosix`, `DnsConfigWatcher::CheckDnsConfig`), and uses `getaddrinfo` only when the configuration has options it can't handle.

## Goals / Non-Goals

**Goals:**
- Chrome's automatic secure DNS, with Google's providers still removed.
- The smallest patch that does it, applied after ungoogled-chromium's patches.

**Non-Goals:**
- Reading macOS's encrypted DNS configuration (DNS settings profiles or network extensions). Chromium can't do this, and it needs work of its own.
- A secure DNS control in Clair's own Settings window. `chrome://settings/security` keeps Chromium's control.
- Changing anything else in `doh-changes.patch`.

## Decisions

### D1. One Clair patch, after ungoogled-chromium's

A new `patches/clair/restore-network-safety-defaults.patch` holds the hunks, written against the tree as ungoogled-chromium leaves it. It's listed in `patches/series` with Clair's other patches. Its header names the ungoogled-chromium patch it partly reverts.

*Alternatives:*
- **Removing `doh-changes.patch` from the series.** Clair applies ungoogled-chromium's series unchanged ("Built from a pinned ungoogled-chromium release"). The same patch also removes the Google providers, which should stay removed.
- **A command-line switch or feature override from `ClairUI`.** A switch can't set a pref default, and a hidden override would make Clair's engine defaults depend on how it's launched.

### D2. Automatic mode and the upgrade mapping, as upstream

Two one-line hunks:
- `DefaultDnsOverHttpsConfigSource` sets the `kDnsOverHttpsMode` default to `SecureDnsMode::kAutomatic`.
- `kDnsOverHttpsUpgrade` is `FEATURE_ENABLED_BY_DEFAULT`. Clair builds only for macOS, so the upstream platform list isn't needed.

Both changes are needed. Automatic mode without the mapping uses DoH only for servers the user enters, and the mapping does nothing outside automatic mode.

The provider list keeps ungoogled-chromium's removal of Google's entries. A system DNS server at Google's addresses therefore gets no DoH upgrade, and `chrome://settings/security` doesn't offer Google. `dns_probe_runner.cc` also stays as ungoogled-chromium has it.

Only the pref's default changes. A user who has set the mode keeps the stored value, and policies still override it.

*Alternative:* **automatic mode with a fallback DoH provider for unknown DNS servers** (`kDnsOverHttpsAutomaticModeFallbackToDoh`). That changes the operator without the user choosing it, which is what ungoogled-chromium objected to. Upstream keeps it off too.

### D3. A runtime test

A new `tests/runtime/ClairRuntimeTests/NetworkDefaultsTests.swift` checks a fresh profile. A page at `chrome://settings/security` reads `chrome.settingsPrivate.getPref('dns_over_https.mode')`, and the test expects `automatic`. Whether a lookup is upgraded depends on the runner's DNS server, and the provider list has no runtime readout. So the upgrade feature and the provider list are checked by reading the hunks.

*Alternative:* **a C++ unit test in the engine.** Clair doesn't build Chromium's test targets, and the runtime test covers what users see.

## Risks / Trade-offs

- **[A broken DoH provider]** In automatic mode, a provider whose DoH endpoint misbehaves could slow lookups. → Chromium probes the DoH servers and falls back to the system's DNS when they fail, as in Chrome.
- **[Split DNS or a captive portal]** On a network that intercepts DNS, a known provider's address could resolve differently over DoH. → Same as Chrome. The upgrade applies only to the public providers' own addresses, Chromium turns automatic mode off on managed Macs, and the user can turn secure DNS off.
- **[Upstream churn]** ungoogled-chromium could rewrite `doh-changes.patch` in a later release. → No-fuzz patching names any hunk that stops applying, and the runtime test catches a lost default.

## Migration Plan

- After updating, profiles that never set secure DNS use automatic mode from the next launch. Profiles that set it keep their setting.
- **Rollback:** a reverted build goes back to ungoogled-chromium's default. No stored data changes.
