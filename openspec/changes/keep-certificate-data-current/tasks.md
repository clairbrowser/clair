# Tasks

## 1. Fetching the PKI metadata component

- [x] 1.1 In `patches/clair/restore-web-store.patch`, turn the update checker's single allowed component ID into a list holding CRLSet's and the PKI metadata component's (`efniojlnjndmcbiieegkicadnoecjjef`), each with its comment (D1). Verify that the patch check applies the series with no fuzz.
- [x] 1.2 Add `patches/clair/keep-certificate-data-current.patch` after `clair/restore-certificate-revocation.patch` in `patches/series`, with a header saying what it does and a hunk making `PKIMetadataComponentInstallerPolicy::RequiresNetworkEncryption()` return `true` (D2). Verify that the patch check applies it.
- [x] 1.3 Build the engine (`gh workflow run engine.yml -f ref=<branch>`), run it with `scripts/run-local.sh`, and capture a component check and its downloads. Verify that the check names exactly the two components with only the fields "What a certificate data check sends" allows, that every download is over HTTPS, and that `PKIMetadata/<version>/` holds `ct_config.pb`, `kp_pinslist.pb` and `crs.pb`. Note the package's size in the PR.
- [ ] 1.4 Add a runtime test that launches Clair with a fresh data folder and waits up to three minutes for `PKIMetadata/<version>/` to hold the three files (D6). Verify that it passes in the quality checks on the branch (`gh workflow run quality.yml --ref <branch>`).

## 2. HSTS preload at any age

- [x] 2.1 In `patches/clair/keep-certificate-data-current.patch`, make `TransportSecurityState::IsBuildTimely()` return `true`, with a comment saying why (D4). Verify that the patch check applies it and the engine from 1.3 compiles with it.

## 3. Release notes and checks

- [x] 3.1 Add a Changie fragment (`changie new`): Clair keeps Chromium's Certificate Transparency log list, key pins and root store current with the same check it uses for the revocation list, sending nothing more, and keeps enforcing the HSTS preload list however old the engine is. Verify that it's in the PR.
- [ ] 3.2 Run the merge gate. Verify that CI passes.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.
