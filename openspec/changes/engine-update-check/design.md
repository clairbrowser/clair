# Design

## Context

- The engine is pinned by the `ungoogled-chromium` submodule (`https://github.com/ungoogled-software/ungoogled-chromium.git`). `docs/building.md` ("Updating the engine") describes the update by hand: move the pin, sync the files copied from ungoogled-chromium-macos, open a pull request, fix any patch the patch check names, and build the engine with `engine.yml`.
- `ci.yml` already has the patch check as its `Patch check` job. It runs on `xcode-27`, runs `.github/scripts/prepare-runner.sh` and `./build.sh fetch prepare`, and runs only when a pull request changes the engine key and that key's engine isn't published. Clair's series is applied without fuzz (`scripts/patch-no-fuzz.sh`). ungoogled-chromium's `utils/patches.py` stops at the first patch that doesn't apply and names it.
- `quality.yml` and `scripts/report-quality.sh` show the existing pattern for a workflow that writes to GitHub: a separate job with only the permissions it needs, and a tested script that calls `gh`.
- Pull requests and pushes made with a workflow's `GITHUB_TOKEN` start no other workflows, so an update pull request opened that way would never run `ci.yml`.
- Engine builds start only by hand and run only on the owner's Mac (`build-pipeline`, "Engine builds run on the owner's Mac when started by the owner"). Releases start by hand (`release-distribution`).

## Goals / Non-Goals

**Goals:**
- A new upstream tag turns into a pull request within a day, without anyone watching upstream.
- The pull request says up front whether it can go straight to an engine build or needs patch work first.
- The job that runs upstream's code gets no credentials.

**Non-Goals:**
- Syncing the files copied from ungoogled-chromium-macos (`downloads-arm64.ini`, `flags.macos.gn`, `retrieve_and_unpack_resource.py`, its patches). This stays a manual step. The pull request's description links ungoogled-chromium-macos's tags so the owner can see whether it has caught up.
- Fixing patches, building the engine, merging or releasing.
- Treating major versions differently. A new milestone usually fails the patch check and arrives as a draft, which is the signal it needs.

## Decisions

### D1. Three jobs, split by trust

`.github/workflows/engine-update.yml` runs on `schedule` (daily) and `workflow_dispatch` (optional input `tag`). Its top-level `permissions` are `contents: read`, and one `concurrency` group without cancellation lets two runs never race on the same branch.

1. **`plan`** (`ubuntu-latest`, read-only). It runs `scripts/find-engine-update.sh`, which:
   - reads the pinned tag (`git ls-tree HEAD ungoogled-chromium`, matched to a tag through `git ls-remote --tags` of the submodule's URL);
   - reads upstream's tags from the same `ls-remote`;
   - keeps the tags that match `^[0-9]+(\.[0-9]+){3}-[0-9]+$` and compares them numerically, field by field. The comparison is done in bash 3.2, since BSD `sort` has no reliable `-V`;
   - reads the open and closed pull requests labelled `engine-update` (`gh pr list`, read-only token).

   Its output is one of `none`, `comment <pr> <tag>` or `update <tag>`. Every tag is validated before it reaches an output, because it goes into a branch name, a commit message, a YAML fragment and Markdown.
2. **`patch-check`**. It calls the reusable patch-check workflow (D2) with `ref: main` and `ungoogled-tag: <tag>`, and has no secrets and no environment. It runs only for `update`.
3. **`propose`** (`ubuntu-latest`, `environment: engine-update`). It runs after `plan`, and after `patch-check` whatever that job's result. It:
   - mints a token with `actions/create-github-app-token`, pinned by commit, with `contents: write` and `pull-requests: write` on this repository;
   - runs `scripts/open-engine-update.sh` from `main`'s checkout, taking the patch check's result.

   The script creates the branch `engine-update/<tag>` from `main`, moves the submodule pointer (`git update-index --cacheinfo 160000,<sha>,ungoogled-chromium`, so the submodule is never checked out here), writes `.changes/unreleased/Updated-<tag>.yaml`, commits `build(engine): update to ungoogled-chromium <tag>`, pushes, and then:
   - when the check passed, opens a pull request ready for review;
   - when it failed, opens a draft whose description says the patches need updating, names the failing patch and links the run;
   - for `comment`, posts the comment on the open pull request.

   A `cancelled` patch-check result opens nothing.

*Alternative:* one job doing everything, as Crest's `chromium.yml` resolve step does. Rejected, because `./build.sh fetch prepare` runs ungoogled-chromium's Python from the new tag, and that job must not hold a write token.

### D2. One patch check, shared

The steps of `ci.yml`'s `Patch check` job (checkout with submodules, Python 3.13, `prepare-runner.sh`, `./build.sh fetch prepare`) move into `.github/workflows/patch-check.yml` (`workflow_call`, inputs `ref` and an optional `ungoogled-tag`). With a tag, it checks the submodule out at that tag before `fetch`.

- `ci.yml` calls it with the pull request's head commit, so its job name and the `Engine check`'s dependency on it stay as they are.
- The workflow also uploads the last lines of the failing log and the name of the first patch that failed, taken from `patches.py`'s output, as a small artifact. The `propose` job puts that name in the draft's description.

*Alternative:* copy the steps into the new workflow. Rejected, because two copies drift, and the update would then test something other than what the merge gate tests.

### D3. GitHub App token, not `GITHUB_TOKEN` or a personal token

`GITHUB_TOKEN` pull requests start no CI. A personal access token is tied to the owner's account and expires. A GitHub App installed on this repository alone, with contents and pull requests write access and no workflows permission, mints a token that expires within the hour and can't change workflow files.

The App's ID and private key are secrets of an `engine-update` environment that is limited to `main`, kept apart from the `release` environment, so a run from any other branch can't read them.

### D4. Patch check runs twice for a ready pull request

Once the pull request is open, `ci.yml` runs its own patch check on it, because the key's engine isn't published yet. That is about 20 more hosted minutes per update. It is accepted: `ci.yml`'s run is the required check, and the update workflow's run is what decides between draft and ready before anything is opened.

### D5. One update in review

This follows Crest's rule. The scheduled check finds any open pull request with the `engine-update` label and then only comments, once per newer tag, recognised by a hidden marker in the comment.

- A closed, unmerged pull request for the newest tag means the owner declined it, so the schedule leaves that tag alone.
- A run started by hand with a tag skips both rules, but still refuses to open a second pull request for a branch that already exists.

### D6. What the description says

Both kinds of pull request carry:
- the tag and Chromium version, with links to the upstream tag and to ungoogled-chromium-macos's tags;
- the run's URL;
- `gh workflow run engine.yml -f ref=engine-update/<tag>`;
- the manual steps from `docs/building.md` that still apply: syncing the macOS files and checking the SDK.

The draft adds the failing patch, the log excerpt and the instruction to fix the patch on the branch and mark the pull request ready.

## Risks / Trade-offs

- [The patch check passes but the engine still fails to compile, or the macOS files needed syncing] → The pull request is only a proposal. `engine.yml` and the engine check still gate the merge, and the description lists the manual sync.
- [A milestone update stays open as a draft for days, and patch-level fixes on newer tags queue behind it] → The comment on the open pull request names each newer tag. The owner can close the draft and start the check by hand on a patch-level tag, or retarget the draft's branch.
- [The App's private key leaks] → It lives only in the `engine-update` environment limited to `main`. The App can reach only this repository, can't edit workflows, and can't push to `main` past branch protection. Rotating it is an owner step listed in tasks.
- [ungoogled-chromium changes its tag format] → Tags that don't match the pattern are ignored. If none match, the run fails visibly rather than opening a wrong pull request.
- [Hosted macOS minutes] → The patch check runs only on days with a new tag, and a tag that already has an open pull request is skipped.

## Migration Plan

1. Merge the reusable patch-check workflow and `ci.yml`'s switch to it first, or in the same pull request, and confirm an engine-key pull request still runs `Patch check` and `Engine check` under the same names.
2. The owner creates the App, the environment and the label (tasks group 1).
3. Merge the update workflow, then start it by hand once and check the pull request it opens.

Rollback: disable the workflow in the Actions settings, or delete its file. Nothing else depends on it.
