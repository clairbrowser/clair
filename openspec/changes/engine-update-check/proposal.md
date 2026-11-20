# Proposal

## Why

Clair's engine moves to a new ungoogled-chromium release only when someone notices the new tag and bumps the pin by hand. Nothing in the repository watches upstream, so new Chromium releases, which usually carry security fixes, can sit unnoticed for days. Engine builds and releases stay owner-started. The first steps of an update need no judgement and can run on their own: noticing the tag, bumping the pin and finding out whether Clair's patches still apply.

## What Changes

- **Daily check.** A scheduled workflow on a GitHub-hosted runner checks every day whether ungoogled-chromium has published a tag newer than the pinned one. It can also be started by hand, optionally naming a tag.
- **Draft pull request.** When a newer tag exists, the workflow opens a **draft** pull request that moves the pin to it and adds a Changie fragment for the engine update. It compiles and patches nothing itself.
- **CI's patch check decides.** The merge gate runs on that pull request as on any other, including its existing patch check. A second workflow reads that check's result once CI finishes:
  - if the patches apply, it marks the pull request ready for review and gives the command that builds its engine;
  - if they don't, the pull request stays a draft, and a comment says that Clair's patches need updating, names the patch that stopped the check and links the run.
- **Draft state follows the latest check.** When the owner pushes patch fixes to the branch and CI's patch check then passes, the pull request is marked ready. If a later push breaks it, the pull request goes back to draft.
- **One update in review.** While an engine update pull request is open, the scheduled check opens no other one. When a newer tag appears, it comments on the open pull request instead.
- **GitHub App token.** Pull requests are opened and updated with a GitHub App's token, so `ci.yml` runs on them. The App's credentials are held in an environment limited to `main`. The workflow that reacts to CI acts only on this repository's own update branches, and never checks out or runs their code.
- **Patch check names the failing patch.** `ci.yml`'s patch check reports the patch that stopped it as an annotation, so the result can be read without parsing logs.
- **Owner steps unchanged.** Engine builds, merges and releases stay with the owner.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `build-pipeline`: adds requirements for:
  - the scheduled upstream check and the draft pull request it opens;
  - marking that pull request ready or keeping it a draft from the merge gate's patch check;
  - one update in review at a time;
  - the credentials the update may use, and what the CI-triggered workflow may act on;
  - the patch check naming the patch that stopped it.

## Impact

- **Repository:**
  - two new workflows, `.github/workflows/engine-update.yml` (scheduled, opens the draft) and `.github/workflows/engine-update-result.yml` (`workflow_run` on CI, marks ready or comments);
  - new scripts with their `*.test.sh`: one picks the tag to update to, one opens or comments on the pull request, and one turns a patch check result into the pull request's state;
  - `ci.yml`'s `Patch check` job gains an annotation naming the failing patch;
  - `docs/building.md` ("Updating the engine") describes the automatic pull request and what the owner still does by hand: sync the files copied from ungoogled-chromium-macos, fix patches and build the engine.
- **Repository settings (owner):**
  - a GitHub App installed on this repository only, with contents and pull requests write access;
  - an `engine-update` environment limited to `main`, holding the App's ID and private key;
  - an `engine-update` label.
- **Runners:** only `ubuntu-latest`, for seconds per run. The patch check is `ci.yml`'s, run once per push as today. The self-hosted Mac is never used.
- **Specs:** the Purpose of `software-updates` currently says users stay on current engine security fixes. When this change is archived, that sentence is rewritten to describe what the repository actually does: it notices new engine releases and proposes the update.
