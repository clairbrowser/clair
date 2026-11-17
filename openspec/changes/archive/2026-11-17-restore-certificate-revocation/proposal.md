# Proposal

## Why

When a certificate authority revokes a certificate, Chrome learns about it from CRLSet, Google's list of revoked certificates. Google rebuilds the list several times a day, mostly from revoked intermediate certificates and from leaf certificates revoked for key compromise. Chromium doesn't ask the CA itself by default, and doesn't use macOS's revocation checks.

Clair has no CRLSet:
- The list arrives only through the component updater, which ungoogled-chromium blocks.
- The built-in fallback (`CRLSet::BuiltinCRLSet()`) is empty, so a new Clair build doesn't carry one either.

So a revoked intermediate keeps working in Clair indefinitely. That lasts until Chromium distrusts the root or adds the certificate to its compiled-in blocklist, and Clair ships that engine.

Revocation data protects users from harm, so it qualifies under `chromium-engine`'s "Google services Clair turns back on", which `disable-flagged-store-extensions` adds. A hand-made update check, stripped as that change strips extension checks and sent as Chromium's `chromium` product ID, got back the current CRLSet (version 10908, 9.5 MB).

## What Changes

- **Clair fetches CRLSet** through Chromium's component updater:
  - about a minute after launch, then every five hours, as Chrome does;
  - stored once for the app in `CertificateRevocation` in the data folder;
  - applied to every connection, as in Chrome, so a certificate on the list fails with Chromium's revoked-certificate error.
- **CRLSet is the only component checked.** ungoogled-chromium still registers Chromium's other components (Widevine, optimization hints, origin trials and so on), and they stay unchecked. Only CRLSet's ID goes into a component update request.
- **The check sends no more than it needs:**
  - CRLSet's ID, version and the hash of the package Clair has;
  - Clair's Chromium version and channel;
  - the platform (`mac`, `arm64`);
  - random per-request IDs.

  It doesn't send the language, the macOS version, hardware details, install dates or IDs, cohorts or activity pings, and Clair sends no event pings. Checks and downloads use HTTPS only.
- **Updates arrive as patches** when Google has one, which matters here: the full list is about 9.5 MB and changes several times a day.
- **Every Clair launch now contacts Google**, profile or extensions aside: one check about a minute after launch and every five hours, and a download when the list has changed. `chromium-engine`'s idle-launch scenario changes to allow exactly that.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `chromium-engine`:
  - A new requirement, "Certificate revocation data kept current", says Clair fetches the revocation list and rejects the certificates on it.
  - A new requirement, "What a revocation check sends", says what the check may send.
  - "Google services Clair turns back on" adds the revocation list to its list.
  - "ungoogled-chromium privacy defaults preserved" allows the revocation check on an idle launch. The component updater checks only the revocation list.
  - "Built from a pinned ungoogled-chromium release" lets the list of files left out of domain substitution hold the update service's address file.

  This change builds on `disable-flagged-store-extensions`'s deltas. It must be implemented and archived after that change.

## Impact

- **Engine** (the engine key changes):
  - `utils/domain_substitution_exclude.list` gains `components/component_updater/component_updater_url_constants.cc`, so the component updater reaches `update.googleapis.com`.
  - The update checker's gate from `disable-flagged-store-extensions` also lets component checks through, carrying CRLSet's ID only.
  - The component updater's configurator requires HTTPS, sends no language and no event pings, and the CRLSet policy requires HTTPS downloads.
  - `disable-flagged-store-extensions`'s request stripping already covers component checks, since both share the serializer.
- **`ClairUI` and `ClairHost.h`:** no change.
- **Network:** a check to `update.googleapis.com` on every launch and every five hours, plus downloads from Google's download hosts when the list changes.
- **Disk:** about 10 MB in the data folder for the list, plus the package Chromium keeps for patches.
- **Users:** sites using a revoked intermediate or a key-compromised certificate stop loading, with Chromium's certificate error, as in Chrome.
- **Docs:** a Changie fragment.
