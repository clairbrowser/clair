# Proposal

## Why

Taking a new ungoogled-chromium tag starts by hand today: someone has to notice the tag, move the pin, add the release note and open a pull request before the patch check says anything. A patch-level tag (a security update within the Chromium major Clair already uses, such as #71) is only the pin and a Changie fragment, yet it waits until the owner looks. A new major (such as #196) needs real work, and that work can't start until the patch check has named what broke, one patch per 20-minute run.

## What Changes

- A scheduled workflow checks ungoogled-chromium's tags every 6 hours. When a tag newer than the pin exists, it opens a draft pull request that moves the pin to it and adds the release note. Nothing else changes in that pull request: syncing the files copied from ungoogled-chromium-macos stays manual.
- There is one engine update pull request at a time, on the branch `engine-update`. A newer tag, of the same major or the next, adds a commit to it, so fixes the owner pushed carry over. Once the owner has started an engine build for that pull request, the pin stays where it is until it merges, unless the owner asks for the newer tag.
- After each CI run on that pull request, a second workflow reads the patch check's result. It marks the pull request ready when every patch applies, returns it to draft when one doesn't, and keeps one comment up to date with the patches that failed or the command that builds the engine. A fix the owner pushes re-runs CI, so the pull request turns ready by itself.
- The patch check tries every patch in Clair's series and lists all that don't apply, where it now stops at the first.
- The workflow acts as a GitHub App, because a pull request opened with a workflow's own token starts no checks.

Out of scope:
- Starting the engine build. It stays the owner's decision: any pin change compiles Chromium from scratch on the owner's Mac (about 4 hours).
- Syncing `downloads-arm64.ini`, `flags.macos.gn`, `retrieve_and_unpack_resource.py` and `patches/ungoogled-chromium-macos/` from ungoogled-chromium-macos. The pull request says whether that repository has tagged the version, and lists the steps.
- Fixing patches, and merging.
- Making a pin change build incrementally.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `build-pipeline`: adds requirements for the engine update pull request and for its draft and ready states, and changes "Patch check for engine changes" to name every patch that doesn't apply.

## Impact

- **Workflows:** new `engine-update.yml` (schedule and manual start) and `engine-update-status.yml` (after each `CI` run). `engine.yml` gains a run name that includes the branch it builds, and `ci.yml` one hosted job that runs the two new script tests on Linux, where the scripts run. The merge gate's existing jobs don't change.
- **Scripts:** new `scripts/engine-update.sh` and `scripts/engine-update-status.sh`, each with a `*.test.sh`. `scripts/patch-no-fuzz.sh` and `build.sh`'s `apply_layer` change so that every failing patch is listed.
- **Engine:** `build.sh` and `scripts/patch-no-fuzz.sh` are engine inputs, so the engine key changes once. The pin doesn't, so that engine build updates the tree in place and compiles nothing.
- **Repository settings (owner):** a GitHub App installed on this repository only, with read and write access to contents and pull requests, and an `engine-update` environment limited to `main` that holds its ID and private key.
- **Specs and docs:** `build-pipeline`, `docs/building.md`'s "Updating the engine" and `CLAUDE.md`.
- **Release notes:** none for this change. Each update pull request carries its own fragment.
