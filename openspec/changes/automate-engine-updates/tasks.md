# Tasks

Two pull requests implement this change (design D9): tasks 1.x, then tasks 2.x to 4.x. Tasks 5.x run after the second merges.

## 1. The patch check lists every failing patch

- [x] 1.1 Give `scripts/patch-no-fuzz.sh` the `CLAIR_PATCH_FAILURES` mode (D8) and extend `scripts/patch-no-fuzz.test.sh`. Verify that the test covers: a patch that applies is applied; a patch that fails is recorded, leaves the tree unchanged and exits 0; without the variable a failing patch still exits non-zero; and a change to a hunk's outermost context line still counts as failing.
- [ ] 1.2 Make `build.sh`'s `apply_layer` set the variable for Clair's series, print one `clair-patch-failed: <path>` line per recorded patch, and exit 1 before the overlay is copied. Update `docs/building.md`'s description of the patch check. Verify, on a throwaway draft pull request that breaks one context line in each of two patches, that one `Patch check` run fails and its log names both and no others; then close it.
- [ ] 1.3 Verify that the merge gate passes on the pull request, after the owner builds its engine (`gh workflow run engine.yml -f ref=<branch>`), and that the engine run updated the tree in place.

## 2. Opening and updating the pull request

- [x] 2.1 Add `scripts/engine-update.sh` (D2 to D5) and `scripts/engine-update.test.sh`. Verify that the test covers: no newer tag; a patch-level tag and a new major, each with no open pull request; tag ordering across majors, builds, patches and revisions (`157.0.8103.100-1` is newer than `157.0.8103.78-2`); an annotated tag's commit; a tag name outside the pattern being ignored; a pin that matches no tag failing; a declined tag; an open pull request already on the target; a newer tag added on top of a commit that isn't the bot's; a held pull request, for an engine run that is running, one that failed and one that succeeded, each started after the pin last moved; an engine run from before the pin last moved, or for another branch, not holding; `take-newest` moving a held pin; a pull request that conflicts with `main`; a leftover branch with only the bot's commits, and one with other commits; deleting `main`'s unreleased engine fragment and adding a new one, adding one when there is none, and rewriting the bot's own fragment when the pin moves again; and a description edited outside the markers keeping that text. Verify that `shellcheck -S warning` passes.
- [x] 2.2 Add `.github/workflows/engine-update.yml` (D1, D6), and give `engine.yml` its run name (D1). Verify that `docs/building.md`'s and `CLAUDE.md`'s `gh workflow run engine.yml` commands still work unchanged. Verify that `actionlint` passes, that the job asks for no permission beyond D6's, and that the App's token is never written to the log or left in the checkout's git configuration.

## 3. Draft and ready

- [x] 3.1 Add `scripts/engine-update-status.sh` (D7) and `scripts/engine-update-status.test.sh`. Verify that the test covers each row of D7's table, including a patch check that timed out; a cancelled run changing nothing; a result for a commit that is no longer the head; a log line whose patch name doesn't match the pattern being dropped; a failure whose log names no patch; the comment being edited in place and not added twice; and the draft state being left alone when it is already right. Verify that `shellcheck -S warning` passes.
- [x] 3.2 Add `.github/workflows/engine-update-status.yml` (D1, D7). Verify that `actionlint` passes, that the job's condition excludes a run whose head repository isn't this one or whose head branch isn't `engine-update`, and that no step checks out or runs the pull request's code.
- [ ] 3.3 Find out whether a job's `GITHUB_TOKEN` with `pull-requests: write` can mark a pull request ready and convert it to draft (D6): try both on a scratch draft pull request from a `workflow_dispatch` run on a branch, then delete the scratch workflow. Verify that the status workflow uses the App's token for those calls only if the default token was refused, and record the result in D6.

## 4. Setup and docs

- [ ] 4.1 Owner: create the GitHub App, install it on this repository only, and create the `engine-update` environment limited to `main` with the App's ID and private key (D6). Verify that the environment lists `main` as its only deployment branch.
- [x] 4.2 Rewrite `docs/building.md`'s "Updating the engine" around the pull request the bot opens, keeping the manual steps for the macOS files and the SDK, and describe the App and its environment under the repository's settings. Update `CLAUDE.md`: the engine update pull request, its branch, and that pushing to it re-runs the patch check. Verify that both describe the workflows as merged.
- [ ] 4.3 Add the `ubuntu-latest` job to `ci.yml` that runs the two new script tests (D1). Verify that it passes, that the merge gate passes on the second pull request, and that its engine key equals `main`'s.

## 5. After merging

- [ ] 5.1 Start `engine-update.yml` by hand. Verify that it opens one draft pull request from `engine-update` for the newest tag, with only the pin and the fragment changed, that CI starts on it, and that a second run changes nothing.
- [ ] 5.2 Verify that, when that pull request's patch check fails, it stays a draft and its comment lists the failing patches; and that after a push that fixes one of them, the same comment lists one fewer.
- [ ] 5.3 Verify that, when its patch check first passes, the pull request turns ready within minutes and its comment gives the engine build command; and that no `engine.yml` run was started by anything but the owner.
- [ ] 5.4 After the owner starts that pull request's engine build, start `engine-update.yml` by hand. Verify that its log says the pull request is held and that the branch is unchanged.

## Workflow follow-up

- One docs-only pull request ticks the tasks the first update pull request verified, syncs the delta spec and archives this change.
