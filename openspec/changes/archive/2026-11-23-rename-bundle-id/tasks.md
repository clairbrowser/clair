# Tasks

## 1. The identifier

- [x] 1.1 Replace `dev.joshuapark.Clair` with `com.clairbrowser.clair` in the engine patches and overlay, `ClairUI` and its tests, `package.sh`, the scripts and their tests, the runtime suite, the probe and the docs (`CLAUDE.md`, `docs/building.md`, `docs/updates.md`). Verify that `git grep -i joshuapark` finds it only in archived changes and `openspec/specs/` (synced on archive), and that the engine build on the branch publishes `chromium-engine-<key>`.
- [x] 1.2 Verify that CI passes (the scripts' tests, `package.test.sh`, `verify-app.sh`'s identifier checks, `ClairUI`'s tests), and by hand that the packaged test copy and its helpers report `com.clairbrowser.clair` and `com.clairbrowser.clair.`-prefixed identifiers.

## 2. Release notes and checks

- [x] 2.1 Add a Changie fragment: the bundle identifier changes, so settings and the default browser choice reset and macOS asks for keychain access again. Verify that it's in the PR.
- [x] 2.2 Run the merge gate and the quality checks on the branch (`gh workflow run quality.yml --ref <branch>`). Verify that CI and the quality checks pass.

## Workflow follow-up

- After the implementation PR merges, one docs-only PR ticks the tasks its last checks verified, syncs the delta specs and archives the change.
