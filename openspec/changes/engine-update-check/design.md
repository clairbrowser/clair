# Design

## Context

- **How the pin moves today.** The engine is pinned by the `ungoogled-chromium` submodule (`https://github.com/ungoogled-software/ungoogled-chromium.git`). `docs/building.md` ("Updating the engine") describes the update by hand: move the pin, sync the files copied from ungoogled-chromium-macos, open a pull request, fix any patch the patch check names, and build the engine with `engine.yml`.
- **The existing patch check.** `ci.yml`'s `Patch check` job runs `./build.sh fetch prepare` on `xcode-27` when a pull request changes the engine key and that key's engine isn't published. ungoogled-chromium's `utils/patches.py` logs `* Applying <patch> (n/N)` before each patch and stops at the first one that fails. Clair's series is applied without fuzz (`scripts/patch-no-fuzz.sh`). CI's `concurrency` cancels a run in progress when the pull request gets a new push.
- **The existing write pattern.** `quality.yml` and `scripts/report-quality.sh` show how a workflow writes to GitHub here: a separate job with only the permissions it needs, and a tested script that calls `gh`.
- **Default tokens start no CI.** Pull requests and pushes made with a workflow's `GITHUB_TOKEN` start no other workflows.
- **`workflow_run` runs `main`'s code.** It starts the default branch's copy of a workflow when another workflow completes, with that default branch's secrets. Its event names the triggering run's head branch, head repository, head commit and pull requests.
- **The owner's steps.** Engine builds start only by hand and run only on the owner's Mac (`build-pipeline`, "Engine builds run on the owner's Mac when started by the owner"). Releases start by hand (`release-distribution`).

## Goals / Non-Goals

**Goals:**
- A new upstream tag turns into a pull request within a day, without anyone watching upstream.
- The patch check runs once per commit, through the merge gate that already exists.
- The pull request's draft state tells the owner whether it can go straight to an engine build.
- Nothing holding write credentials runs code from the update branch or upstream.

**Non-Goals:**
- **Syncing the macOS files.** The files copied from ungoogled-chromium-macos (`downloads-arm64.ini`, `flags.macos.gn`, `retrieve_and_unpack_resource.py`, its patches) stay a manual sync. The description links ungoogled-chromium-macos's tags so the owner can see whether it has caught up.
- **The owner's later steps.** Fixing patches, building the engine, merging and releasing stay manual.
- **Special handling for major versions.** A new milestone usually fails the patch check and stays a draft, which is the signal it needs.

## Decisions

### D1. `engine-update.yml`: notice the tag and open a draft

`.github/workflows/engine-update.yml` runs on a daily `schedule` and on `workflow_dispatch` (optional input `tag`). Its top-level `permissions` are `contents: read`, and a `concurrency` group without cancellation stops two runs racing.

1. **`plan`** (`ubuntu-latest`, read-only, no environment) runs `scripts/find-engine-update.sh`, which:
   - reads the pinned commit (`git ls-tree HEAD ungoogled-chromium`) and upstream's tags (`git ls-remote --tags` of the submodule's URL), and maps the pin to its tag;
   - keeps tags matching `^[0-9]+(\.[0-9]+){3}-[0-9]+$` and compares them numerically, field by field, in bash 3.2, since BSD `sort` has no reliable `-V`;
   - reads the open and closed pull requests labelled `engine-update` (`gh pr list`);
   - prints `none`, `comment <pr> <tag>` or `update <tag> <commit>`.

   Every tag is validated before output, because it goes into a branch name, a commit message, a YAML fragment and Markdown.
2. **`propose`** (`ubuntu-latest`, `environment: engine-update`) runs only for `comment` or `update`. It mints a token with `actions/create-github-app-token`, pinned by commit, with `contents: write` and `pull-requests: write`. It then runs `scripts/open-engine-update.sh` from `main`'s checkout, which:
   - creates `engine-update/<tag>` from `main`;
   - moves the submodule pointer with `git update-index --cacheinfo 160000,<commit>,ungoogled-chromium`, so upstream's tree is never checked out;
   - writes `.changes/unreleased/Updated-<tag>.yaml` (`Update the engine to Chromium <version> (ungoogled-chromium <tag>)`);
   - commits `build(engine): update to ungoogled-chromium <tag>`, pushes, and opens a **draft** pull request labelled `engine-update`.

   For `comment`, it posts the comment on the open pull request instead.

No job in this workflow runs code from upstream.

### D2. `engine-update-result.yml`: follow CI's patch check

`.github/workflows/engine-update-result.yml` runs on `workflow_run` of `CI`, `types: [completed]`.

1. **`filter`** (`ubuntu-latest`, `actions: read`, `pull-requests: read`, no environment) runs `scripts/engine-update-result.sh plan` with the event's fields. It continues only when:
   - the event is `pull_request`;
   - `head_repository.full_name` equals the repository;
   - `head_branch` matches `^engine-update/[0-9]+(\.[0-9]+){3}-[0-9]+$`;
   - the open pull request for that branch carries the `engine-update` label;
   - its head commit equals the run's `head_sha`, so a result for an older push is ignored.

   It then reads the `Patch check` job's conclusion from the run's jobs (`gh api .../runs/<id>/jobs`), not the run's overall conclusion, since the `Engine check` fails until the engine is published. When the conclusion is `failure`, it reads the job's annotations through the check-runs API (D3).

   It prints `ready`, `draft <patch or empty>` or `nothing`. `cancelled`, a missing job and anything else give `nothing`. `skipped` (the engine is already published) counts as passed.
2. **`apply`** (`ubuntu-latest`, `environment: engine-update`) runs only for `ready` or `draft`. It mints the App token and runs `scripts/engine-update-result.sh apply`:
   - `ready`: `gh pr ready`, plus a comment with `gh workflow run engine.yml -f ref=<branch>`;
   - `draft`: `gh pr ready --undo` when the pull request is ready, plus a comment that the patches need updating, naming the patch when there is one, linking the run and the steps in `docs/building.md`.

   Each comment carries a hidden marker with the head commit, so a re-run for the same commit doesn't comment twice.

Neither job checks out the pull request. The only text it takes from the run is the patch name, accepted only when it matches `^[A-Za-z0-9_][A-Za-z0-9_./-]*\.patch$` and contains no `..`.

`workflow_run` uses `main`'s copy of the workflow, so a pull request can't change what this workflow does on its own run. Marking a pull request ready doesn't trigger `ci.yml`, because its `pull_request` trigger has the default types, which leave out `ready_for_review`. The check therefore runs once per push.

*Alternative:* the update workflow runs the patch check itself before opening a ready or draft pull request. Rejected, because CI would then run the same 20-minute check again on the new pull request. Avoiding that would need a lookup that lets CI reuse a result for the same engine key, which adds more code for no gain.

### D3. The patch check names its failing patch

`ci.yml`'s `Patch check` step tees `./build.sh fetch prepare`'s output. On failure, it takes the last `* Applying <patch>` line and prints `::error title=Patch did not apply::<patch>`. This covers both ungoogled-chromium's series and Clair's, since both are applied through `patches.py`. The step's exit status doesn't change.

An annotation is structured and short-lived: reading one needs `checks: read` on the run's check suite, rather than downloading a log and parsing it inside a job that later holds a token.

### D4. GitHub App token

A pull request opened with `GITHUB_TOKEN` starts no CI. A personal access token is tied to the owner's account and expires. A GitHub App installed on this repository alone, with contents and pull requests write access and no workflows permission, mints tokens that expire within the hour and can't change workflow files.

The App's ID and private key are secrets of an `engine-update` environment limited to `main`, kept apart from the `release` environment. Both workflows' `apply`/`propose` jobs run on `main`'s ref: a scheduled or dispatched run on `main`, or a `workflow_run`, which always uses the default branch.

### D5. One update in review

This follows Crest's rule. The scheduled check finds any open pull request labelled `engine-update` and only comments on it, once per newer tag, recognised by a hidden marker.

- A closed, unmerged pull request for the newest tag means the owner declined it, so the schedule leaves that tag alone.
- A run started by hand with a tag skips both rules, but still refuses to reuse a branch that exists.

### D6. What the description says

The draft's description gives:
- the tag and Chromium version, with links to the upstream tag and to ungoogled-chromium-macos's tags;
- the run that opened it;
- the manual steps from `docs/building.md` that still apply: syncing the macOS files and checking the SDK;
- a note that the pull request turns ready by itself when the patch check passes.

## Risks / Trade-offs

- [`workflow_run` jobs hold credentials and are triggered by pull requests] → `filter` holds none and stops every run that isn't an update branch of this repository, labelled `engine-update` and at its pull request's head commit. Nothing from the pull request is checked out or run, and the only text taken from it is a validated patch path.
- [Someone with push access names a branch `engine-update/<tag>` and labels a pull request by hand] → The worst the workflow can do is mark that pull request ready or draft and comment on it, which that person could already do.
- [The patch check passes, but the engine fails to compile or the macOS files needed syncing] → The pull request is only a proposal. `engine.yml` and the engine check still gate the merge, and the description lists the manual sync.
- [A milestone update stays a draft for days, and patch-level fixes on newer tags queue behind it] → The comment on the open pull request names each newer tag. The owner can close the draft and start the check by hand on a patch-level tag.
- [The App's private key leaks] → It lives only in the `engine-update` environment limited to `main`. The App reaches only this repository, can't edit workflows, and can't push to `main` past branch protection. Rotating it is an owner step listed in tasks.
- [ungoogled-chromium changes its tag format] → Tags that don't match the pattern are ignored. If none match, the run fails visibly.

## Migration Plan

1. The owner creates the App, the environment and the label (tasks group 1).
2. Merge the patch check's annotation, the scripts and both workflows.
3. Start `engine-update.yml` by hand on `main`, and check the draft it opens and the state change after CI.

Rollback: disable both workflows in the Actions settings. Nothing else depends on them, and the annotation in `ci.yml` is harmless on its own.
