# Tasks

## 1. Engine patch

- [ ] 1.1 Add `patches/clair/restore-network-safety-defaults.patch` to `patches/series` after Clair's existing patches, with the secure DNS hunks (D1, D2): the `kDnsOverHttpsMode` default set to `automatic`, and `kDnsOverHttpsUpgrade` enabled by default. Leave the provider list and the DNS probe host as ungoogled-chromium has them. Its header names the ungoogled-chromium patch it partly reverts. Verify that the patch check applies the series with no fuzz.
- [ ] 1.2 Build the engine (`gh workflow run engine.yml -f ref=<branch>`). Verify that it compiles and publishes `chromium-engine-<key>`.

## 2. Test and release notes

- [ ] 2.1 Add `NetworkDefaultsTests.swift` with the secure DNS default test (D3). Verify that the quality checks pass on the branch (`gh workflow run quality.yml --ref <branch>`).
- [ ] 2.2 Add a Changie fragment (`changie new`): secure DNS now defaults to automatic mode, so Clair uses DNS over HTTPS when the Mac's DNS server is a provider that offers it. Verify that it's in the PR.
- [ ] 2.3 Run the merge gate. Verify that CI passes.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.
