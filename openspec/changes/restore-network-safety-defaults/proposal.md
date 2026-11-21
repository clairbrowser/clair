# Proposal

## Why

Chrome's secure DNS default is automatic mode. When the system's DNS server belongs to a provider that also serves DNS over HTTPS (DoH), such as Cloudflare at 1.1.1.1 or Quad9 at 9.9.9.9, Chrome sends its lookups to that same provider over DoH. If DoH fails, it falls back to the system's DNS.

ungoogled-chromium turns off both the mode and the provider mapping (`doh-changes.patch`). Its reasons are that the browser should "respect the system's DNS settings" and should never "change servers without the user's consent". On macOS neither reason holds:

- **Chromium doesn't defer to the system's DNS settings.** Its built-in resolver reads only the system's plain list of DNS servers and queries them directly. It never applies the encrypted DNS a user sets up in macOS, so turning DoH off doesn't hand lookups to the system.
- **The mapping never changes the operator.** It upgrades a provider's own DNS addresses to that same provider's DoH endpoint. The same patch removes Google's DoH entries, so a user on Google's DNS keeps plain DNS to Google, and nothing new goes to Google.

So with DoH off, a user who chose a DoH-capable provider sends every lookup in clear text, where Chrome would encrypt it.

## What Changes

- **Secure DNS defaults to automatic mode,** with Chromium's provider mapping, as in Chrome. The setting stays in `chrome://settings/security`, and a user who has already chosen a mode keeps it.
- **Google's DoH providers stay removed,** as ungoogled-chromium has them. The rest of `doh-changes.patch` also stays.
- **A new kind of engine patch:** reverting an ungoogled-chromium change that weakens a Chromium security default. Only the defaults a new requirement lists may be reverted, and the revert contacts no Google service.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `chromium-engine`:
  - A new requirement, "Chromium safety defaults Clair restores", lists the ungoogled-chromium changes Clair reverts because they weaken a Chromium security default. A change must add to the list.
  - A new requirement, "Secure DNS automatic by default", sets the DoH default and keeps Google's providers out.
  - "ungoogled-chromium privacy defaults preserved" makes an exception for the restored defaults.
  - "Browser behavior as in ungoogled-chromium outside Clair's interface" allows the secure DNS default in its "Settings unchanged" scenario.
  - "Changes to Chromium limited to hooks and identity" allows patches that restore a listed default.

## Impact

- **Engine** (the engine key changes): a new `patches/clair/restore-network-safety-defaults.patch`, applied after ungoogled-chromium's series. It touches `chrome/browser/net/default_dns_over_https_config_source.cc` and `services/network/public/cpp/features.cc`.
- **`ClairUI` and `ClairHost.h`:** no change.
- **Network:** if the system's DNS server is a known DoH provider, lookups now go to that provider over HTTPS instead of plain DNS. No user's lookups move to a different DNS operator.
- **Docs:** a Changie fragment.
