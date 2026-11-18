# Proposal

## Why

Chromium compiles three sets of certificate data into the browser and trusts each one for 10 weeks only, expecting the component updater or a browser update to replace it before then:

- **The Certificate Transparency (CT) log list.** Once it's 10 weeks old, Chromium stops requiring that certificates be publicly logged, and every certificate passes without proof of logging.
- **Static key pins.** Once they're 10 weeks old, a certificate for a pinned domain such as `google.com` is accepted from any trusted certificate authority.
- **The HSTS preload list.** Once the build is 10 weeks old, the whole list is ignored. A first visit to a preloaded site can then be downgraded to plain HTTP, and its certificate errors can be clicked through.

Chrome refreshes the CT log list and the pins through its PKI metadata component, and the HSTS preload list through browser updates. Clair fetches only the certificate revocation list (CRLSet) through the component updater. The 10 weeks run from dates fixed in the Chromium source, not from when Clair builds, so rebuilding Clair doesn't reset them. On the current engine (Chromium 156.0.8078.79), the pins lapse on 2026-12-11, CT on 2026-12-14 and HSTS preload on 2027-01-06. Every later engine has the same 10-week window, and users who don't update straight away fall outside it sooner.

## What Changes

- **Clair fetches the PKI metadata component** with the same check as CRLSet: about a minute after launch, then every five hours. It applies the component's CT log list and key pins, so CT and pins stay enforced between engine releases, as in Chrome.
  - The component also carries the Chrome Root Store, which the macOS builds use to decide which certificate authorities to trust. Clair applies it as Chrome does, so roots that Chromium distrusts stop being trusted without waiting for an engine bump.
  - The fast-push variant of the component, which Chromium registers only when its Merkle Tree Certificates feature is on, stays unchecked.
- **The check sends no more than before.** Both components share one request, which names only their IDs, versions and package hashes, and goes over HTTPS only. The component is downloaded over HTTPS only, and Clair sends no event ping after it installs. There is no new request, field or identifier: the five-hourly check now names two components instead of one.
- **The HSTS preload list stays enforced whatever the build's age.** No component refreshes it. Enforcing an old list only risks keeping HTTPS forced on a site that has since asked to leave the list, while ignoring it drops protection on every site in it.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `chromium-engine`:
  - A new requirement, "Certificate transparency and key pins kept current", says Clair fetches the PKI metadata component and applies its CT log list, pins and root store.
  - A new requirement, "HSTS preload list enforced at any age", says Clair keeps using the compiled-in preload list.
  - "What a revocation check sends" becomes "What a certificate data check sends", and covers both components.
  - "Google services Clair turns back on" adds the PKI metadata component to its list.
  - "ungoogled-chromium privacy defaults preserved" allows the component check to name the PKI metadata component as well as the revocation list.

## Impact

- **Engine** (the engine key changes):
  - The update checker's filter in `patches/clair/restore-web-store.patch` lets the PKI metadata component's ID through, beside CRLSet's.
  - The PKI metadata policy requires HTTPS, so the HTTPS-only download rule that CRLSet uses covers it too.
  - `TransportSecurityState` treats the compiled-in preload list as always timely.
- **`ClairUI` and `ClairHost.h`:** no change.
- **Network:** no new request. The existing check names one more component. The first time, and whenever the data changes, Clair downloads it from Google's download hosts. Its size is measured in the implementation (task 1.1).
- **Disk:** a `PKIMetadata` folder in the data folder, plus the package Chromium keeps for patches.
- **Users:** sites that rely on CT, pins or HSTS preload stay protected while an engine ages. A certificate that isn't publicly logged, or that a pinned site doesn't allow, is refused with Chromium's certificate error, as in Chrome.
- **Docs:** a Changie fragment.
