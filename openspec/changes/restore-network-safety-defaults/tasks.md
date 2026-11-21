# Tasks

## 1. Engine patch

- [ ] 1.1 Add `patches/clair/restore-network-safety-defaults.patch` to `patches/series` after Clair's existing patches, with the PAC hunks (D2): the size check in `PacFileFetcherImpl::ConsumeBytesRead` back as upstream has it, and `kDefaultMaxResponseBytes` at 16 MB. Its header names the ungoogled-chromium patches it partly reverts. Verify that the patch check applies the series with no fuzz.
- [ ] 1.2 Add the secure DNS hunks to the same patch (D3): the `kDnsOverHttpsMode` default set to `automatic`, and `kDnsOverHttpsUpgrade` enabled by default. Leave the provider list and the DNS probe host as ungoogled-chromium has them. Verify that the patch check applies the series with no fuzz.
- [ ] 1.3 Build the engine (`gh workflow run engine.yml -f ref=<branch>`). Verify that it compiles and publishes `chromium-engine-<key>`.

## 2. Tests and release notes

- [ ] 2.1 Add `NetworkDefaultsTests.swift` and the generated PAC files in `tests/runtime/server.py` (D4): a 2 MB file that applies, and a 17 MB file that doesn't. Verify that the quality checks pass on the branch (`gh workflow run quality.yml --ref <branch>`).
- [ ] 2.2 Add the secure DNS default test to `NetworkDefaultsTests.swift` (D4). Verify that it passes in the same quality run.
- [ ] 2.3 Add a Changie fragment (`changie new`): secure DNS now defaults to automatic mode, so Clair uses DNS over HTTPS when the Mac's DNS server is a provider that offers it, and proxy auto-config files over 16 MB are no longer loaded. Verify that it's in the PR.
- [ ] 2.4 Run the merge gate. Verify that CI passes.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.
