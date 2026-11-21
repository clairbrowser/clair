# Design

## Context

See `proposal.md` for why. Current state in the engine tree (ungoogled-chromium 157.0.8103.78-1):

- **The PAC limit.** `PacFileFetcherImpl` has a `max_response_bytes_` member, set to `kDefaultMaxResponseBytes` (1 MB) and changed only by `SetSizeConstraint`, which only tests call. `remove-pac-size-limit.patch` (in ungoogled-chromium's `extra` series) deletes the one check that uses it in `ConsumeBytesRead`. That check sets `ERR_FILE_TOO_BIG` and cancels the request. The member and the constant are still there.
- **The DoH default.** `doh-changes.patch` (in the `core` series) changes four files:
  - `default_dns_over_https_config_source.cc` sets the `kDnsOverHttpsMode` pref default to `off` instead of `automatic`;
  - `services/network/public/cpp/features.cc` makes `kDnsOverHttpsUpgrade` disabled on every platform. `NetworkService::ConfigureStubHostResolver` passes that flag to the host resolver as `allow_dns_over_https_upgrade`;
  - `doh_provider_entry.cc` deletes the `Google` and `GoogleDns64` providers;
  - `dns_probe_runner.cc` probes `example.com` instead of `google.com`.
- **Managed Macs.** `StubResolverConfigReader::ShouldDisableDohForManaged` forces automatic mode off when machine-level policies are installed and no policy sets the DoH mode. Nothing in ungoogled-chromium or Clair changes this.
- **The resolver on macOS.** `kAsyncDns` is on for Mac, so Chromium's built-in resolver reads the system's nameservers (`DnsConfigServicePosix`, `DnsConfigWatcher::CheckDnsConfig`) and uses `getaddrinfo` only when the configuration has options it can't handle.

## Goals / Non-Goals

**Goals:**
- A bounded PAC download that still fits multi-megabyte PAC files.
- Chrome's automatic secure DNS, with Google's providers still removed.
- The smallest patch that does both, applied after ungoogled-chromium's.

**Non-Goals:**
- Reading macOS's encrypted DNS configuration (DNS settings profiles or network extensions). Chromium can't do this, and it needs work of its own.
- A secure DNS control in Clair's own Settings window. `chrome://settings/security` keeps Chromium's control.
- Changing anything else in `doh-changes.patch`.

## Decisions

### D1. One Clair patch, after ungoogled-chromium's

A new `patches/clair/restore-network-safety-defaults.patch`, listed in `patches/series` with Clair's other patches, holds three hunks against the tree as ungoogled-chromium leaves it. Its header says which ungoogled-chromium patch each hunk reverts.

*Alternatives:*
- **Removing ungoogled-chromium's patches from the series.** Clair applies ungoogled-chromium's series unchanged ("Built from a pinned ungoogled-chromium release"). Also, `doh-changes.patch` holds the Google provider removal, which stays.
- **A command-line switch or feature override from `ClairUI`.** A switch can't set a pref default, and a hidden override would make Clair's engine defaults depend on how it's launched.

### D2. The PAC check returns with a 16 MB limit

The patch puts back the check `ConsumeBytesRead` lost, as upstream has it, and sets `kDefaultMaxResponseBytes` to 16 MB. An oversized file then fails with `ERR_FILE_TOO_BIG`, and the proxy resolver handles that as any failed PAC fetch: with no PAC script, requests go direct, unless the PAC setting is mandatory.

16 MB is well above the largest PAC files in use (lists of hosts to route through a proxy run to a few megabytes), and small against the network service's memory.

*Alternatives:*
- **Chromium's 1 MB.** That would break the large PAC files ungoogled-chromium removed the limit for, and Clair would be the browser that broke them.
- **No limit.** Leaves the memory a network can make Clair use unbounded.

### D3. Automatic mode and the upgrade mapping, as upstream

Two one-line hunks:
- `DefaultDnsOverHttpsConfigSource` sets the `kDnsOverHttpsMode` default to `SecureDnsMode::kAutomatic`.
- `kDnsOverHttpsUpgrade` is `FEATURE_ENABLED_BY_DEFAULT`. Clair builds only for macOS, so the upstream platform list isn't needed.

Both changes are needed. Automatic mode without the mapping uses DoH only for servers the user enters. The mapping without automatic mode does nothing.

The provider list keeps ungoogled-chromium's removal of Google's entries. So a system DNS server at Google's addresses has no DoH upgrade, and `chrome://settings/security` doesn't offer Google. `dns_probe_runner.cc` also stays as ungoogled-chromium has it.

Only the pref's default changes. A user who has set the mode keeps the stored value, and policies keep overriding it.

*Alternative:* **automatic mode, but with a fallback DoH provider for unknown DNS servers** (`kDnsOverHttpsAutomaticModeFallbackToDoh`). That changes the operator without the user choosing it, which is what ungoogled-chromium objected to. Upstream keeps it off too.

### D4. Tests in the runtime suite

The PAC limit and the DoH default only show in a running browser, so both tests go in a new `tests/runtime/ClairRuntimeTests/NetworkDefaultsTests.swift`:

- **PAC.** `tests/runtime/server.py` serves two generated PAC files. Each sends one test host to a proxy address that refuses connections, and is padded with a comment: one to 2 MB, one to 17 MB. Clair launches with `--proxy-pac-url` naming each in turn, and with `--host-resolver-rules` mapping the test host to the local server. Loopback addresses skip the proxy, so the test host needs a name. With the 2 MB file, loading the test host fails with a proxy connection error, which shows the file applied. With the 17 MB file, it loads directly from the server.
- **Secure DNS.** On a fresh profile, a page at `chrome://settings/security` reads `chrome.settingsPrivate.getPref('dns_over_https.mode')`, and the test expects `automatic`. The upgrade feature and the provider list have no runtime readout that doesn't depend on the runner's DNS server, so they're checked by reading the hunks.

*Alternative:* **a C++ unit test in the engine.** Clair doesn't build Chromium's test targets, and the runtime test covers the behavior users see.

## Risks / Trade-offs

- **[A broken DoH provider]** In automatic mode, a provider whose DoH endpoint misbehaves could slow lookups. → Chromium probes the DoH servers and falls back to the system's DNS when they fail, as in Chrome.
- **[Split DNS or a captive portal]** A known provider's address on a network that intercepts DNS could resolve differently over DoH. → Same as Chrome. The upgrade applies only to the public providers' own addresses, Chromium turns automatic mode off on managed Macs, and the user can turn secure DNS off.
- **[A PAC file over 16 MB]** It stops working. → Rare. Chromium connects directly instead, as with an unreachable PAC file, and a net log shows the fetch failing with `ERR_FILE_TOO_BIG`.
- **[Upstream churn]** ungoogled-chromium could rewrite either patch in a later release. → No-fuzz patching names any hunk that stops applying, and the runtime tests show a lost default.

## Migration Plan

- After updating, profiles that never set secure DNS use automatic mode from the next launch. Profiles that set it keep their setting.
- **Rollback:** a reverted build goes back to ungoogled-chromium's defaults. No stored data changes.
