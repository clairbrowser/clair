# Tasks

Start once `disable-flagged-store-extensions`'s implementation has merged (D5).

## 1. Fetching CRLSet

- [x] 1.1 Add `components/component_updater/component_updater_url_constants.cc` to `utils/domain_substitution_exclude.list`, and update the list's header comment to match `chromium-engine`'s rule (D2). Verify that the patch check runs domain substitution without error and the file keeps `update.googleapis.com`.
- [x] 1.2 Extend the update checker's gate in `patches/clair/restore-web-store.patch` so component checks go through carrying CRLSet's app ID only, and no request is sent when nothing is left (D1). Verify that the patch check applies the series with no fuzz.
- [x] 1.3 Add the configurator and policy hunks (D3, D4):
  - `ChromeConfigurator` requires encryption, returns no language and no ping address;
  - `CRLSetPolicy::RequiresNetworkEncryption()` returns `true`;
  - the update checker drops HTTP download addresses from a component check's answer for components that require encryption, since Chromium 156 doesn't.

  Verify that the patch check applies them.

## 2. Build and release notes

- [x] 2.1 Build the engine (`gh workflow run engine.yml -f ref=<branch>`). Verify that it compiles and publishes `chromium-engine-<key>`.
- [x] 2.2 Add a Changie fragment (`changie new`): Clair now checks certificates against Chromium's revocation list, fetched from Google's update service shortly after launch and every five hours, sending only the list's version, the browser version and the platform. Verify that it's in the PR.
- [ ] 2.3 Run the merge gate. Verify that CI passes.

## Workflow follow-up

- Archive after `disable-flagged-store-extensions` (D5). After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.
