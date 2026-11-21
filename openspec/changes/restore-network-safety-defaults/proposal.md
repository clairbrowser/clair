# Proposal

## Why

ungoogled-chromium changes two of Chromium's network defaults for reasons that don't apply to Clair, and each change leaves Clair less safe than Chromium:

- **Proxy auto-config files have no size limit.** Chromium stops downloading a proxy auto-config (PAC) file after 1 MB. ungoogled-chromium removes that limit (`remove-pac-size-limit.patch`), so a network that serves a PAC file can make the network service buffer as much as it sends. A Mac fetches a PAC file when its proxy settings name one or discover one automatically (WPAD).
- **Secure DNS is off.** Chrome's default is automatic mode: when the system's DNS server belongs to a provider that also serves DNS over HTTPS (DoH), such as Cloudflare at 1.1.1.1 or Quad9 at 9.9.9.9, Chrome sends its lookups to that same provider over DoH, and falls back to the system's DNS if DoH fails. ungoogled-chromium turns both the mode and the provider mapping off (`doh-changes.patch`), so that the browser "respects the system's DNS settings" and never "changes servers without the user's consent". On macOS neither reason holds:
  - Chromium's built-in resolver reads only the system's plain list of DNS servers and queries them directly. It never applies the encrypted DNS a user sets up in macOS, so turning DoH off doesn't defer to the system.
  - The mapping never changes the operator: it upgrades a provider's own DNS addresses to that same provider's DoH endpoint. The same patch also removes Google's DoH entries, so a user on Google's DNS keeps plain DNS to Google and nothing new goes to Google.

  So with DoH off, a user who chose a DoH-capable provider sends every lookup in clear text, where Chrome would encrypt it.

## What Changes

- **PAC downloads are bounded again.** Clair stops downloading a PAC file after 16 MB and treats it as a failed fetch, as Chromium does above its limit. The limit is higher than Chromium's 1 MB, so the large PAC files some users rely on (long lists of hosts to route through a proxy, which can run to several megabytes) keep working, but the memory a PAC file can take is bounded.
- **Secure DNS defaults to automatic mode** with Chromium's provider mapping, as in Chrome. The setting stays in `chrome://settings/security`, and a user who has already chosen a mode keeps it.
- **Google's DoH providers stay removed**, as ungoogled-chromium has them. The rest of `doh-changes.patch` also stays.
- **A new kind of engine patch:** reverting an ungoogled-chromium change that weakens a Chromium security default, but only for the defaults a new requirement lists. Neither of the two reverts contacts Google.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `chromium-engine`:
  - A new requirement, "Chromium safety defaults Clair restores", lists the ungoogled-chromium changes Clair reverts because they weaken a Chromium security default, and says a change must add to the list.
  - A new requirement, "Proxy auto-config downloads bounded", sets the 16 MB limit.
  - A new requirement, "Secure DNS automatic by default", sets the DoH default and keeps Google's providers out.
  - "ungoogled-chromium privacy defaults preserved" makes an exception for the restored defaults.
  - "Browser behavior as in ungoogled-chromium outside Clair's interface" allows the secure DNS default in its "Settings unchanged" scenario.
  - "Changes to Chromium limited to hooks and identity" allows patches that restore a listed default.

## Impact

- **Engine** (the engine key changes): a new `patches/clair/restore-network-safety-defaults.patch`, applied after ungoogled-chromium's series. It touches `net/proxy_resolution/pac_file_fetcher_impl.cc`, `chrome/browser/net/default_dns_over_https_config_source.cc` and `services/network/public/cpp/features.cc`.
- **`ClairUI` and `ClairHost.h`:** no change.
- **Network:** users whose system DNS server is a known DoH provider now send their lookups to that provider over HTTPS instead of plain DNS. Nobody gets a new DNS operator. A PAC file over 16 MB fails to load.
- **Users:** most see no difference. On a network whose PAC file is over 16 MB, Clair connects directly instead of through that PAC file.
- **Tests:** runtime tests for the PAC limit and the secure DNS default.
- **Docs:** a Changie fragment.
