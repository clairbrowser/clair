# Proposal

## Why

Clair's engine moves to a new ungoogled-chromium release only when someone notices the new tag and bumps the pin by hand. Nothing in the repository watches upstream, so new Chromium releases, which usually carry security fixes, can sit unnoticed for days. Release builds and engine builds stay owner-started, but the first steps of an update (noticing the tag, bumping the pin and finding out whether Clair's patches still apply) need no judgement and can run on their own.

## What Changes

- A scheduled workflow on a GitHub-hosted runner checks every day whether ungoogled-chromium has published a tag newer than the pinned one. It can also be started by hand, optionally naming a tag.
- When a newer tag exists, the workflow bumps the pin on a fresh branch and runs the patch check against it (`./build.sh fetch prepare`, the same check `ci.yml` runs), compiling nothing.
- If the patch check passes, the workflow opens a pull request that bumps the pin, with a Changie fragment for the engine update and the command that builds its engine.
- If the patch check fails, the workflow opens a **draft** pull request with the same bump. The pull request says that Clair's patches need updating for the new tag, names the patch that stopped the check and links the run.
- While an engine update pull request is open, the scheduled check opens no other one. When a newer tag appears, it comments on the open pull request instead.
- The pull requests are opened with a GitHub App's token, so `ci.yml` runs on them as on any other pull request. The App's credentials are held in an environment that only the job opening the pull request uses. The job that runs upstream's scripts holds no secrets and no write access.
- Engine builds, merges and releases are unchanged and stay with the owner.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `build-pipeline`: adds requirements for the scheduled upstream check, for the update pull request it opens (ready or draft, depending on the patch check), for one update in review at a time, and for the credentials the update may use.

## Impact

- **Repository:**
  - a new workflow, `.github/workflows/engine-update.yml`;
  - two new scripts, each with its `*.test.sh`: one picks the tag to update to, and one opens or comments on the pull request;
  - the patch check's steps move into a reusable workflow, so that `ci.yml` and the update workflow run the same check;
  - `docs/building.md` ("Updating the engine") describes the automatic pull request and what the owner still does by hand: sync the files copied from ungoogled-chromium-macos, fix patches and build the engine.
- **Repository settings (owner):**
  - a GitHub App installed on this repository only, with contents and pull requests write access;
  - an `engine-update` environment limited to `main`, holding the App's ID and private key;
  - an `engine-update` label.
- **Runners:** the check uses one hosted macOS runner (`xcode-27`) for about 20 minutes on days when a new tag appears, and a few seconds of `ubuntu-latest` otherwise. It never uses the self-hosted Mac.
- **Specs:** the Purpose of `software-updates` currently says users stay on current engine security fixes. When this change is archived, that sentence is rewritten to describe what the repository actually does: it notices new engine releases and proposes the update.
