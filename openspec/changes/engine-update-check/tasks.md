# Tasks

## 1. Repository settings (owner)

- [ ] 1.1 Create a GitHub App installed on this repository only, with contents and pull requests write access, no workflows permission and no webhook. Verify that its installation lists only this repository.
- [ ] 1.2 Create the `engine-update` environment limited to `main`, with secrets `ENGINE_UPDATE_APP_ID` and `ENGINE_UPDATE_APP_PRIVATE_KEY`. Verify that `gh api repos/{owner}/{repo}/environments/engine-update` shows the `main` branch policy.
- [ ] 1.3 Create the `engine-update` label, and verify that `gh label list` shows it.

## 2. Patch check names the failing patch

- [ ] 2.1 Make `ci.yml`'s `Patch check` step print `::error title=Patch did not apply::<patch>` from the last `* Applying` line when `./build.sh fetch prepare` fails, keeping its exit status (design D3). Put the extraction in a script with a `*.test.sh` covering:
  - a failing ungoogled-chromium patch;
  - a failing Clair patch;
  - a failure before any patch;
  - a successful run.

  Verify with the test, `shellcheck -S warning` and `actionlint`.

## 3. Opening the update

- [ ] 3.1 Write `scripts/find-engine-update.sh`, which prints `none`, `comment <pr> <tag>` or `update <tag> <commit>` (design D1, D5). Verify with `scripts/find-engine-update.test.sh` using stub `git` and `gh`, covering:
  - no newer tag;
  - a newer patch-level tag, and a newer major version;
  - numeric ordering (`157.0.8103.9-1` older than `157.0.8103.78-1`);
  - malformed tags ignored, and none valid as an error;
  - an open update pull request, and a comment already posted for the tag;
  - a closed, unmerged pull request for the newest tag;
  - a hand-started run with an older or unknown tag.

  Also verify with `shellcheck -S warning`.
- [ ] 3.2 Write `scripts/open-engine-update.sh`, which creates the branch, moves the submodule pointer without checking it out, writes the Changie fragment, commits, pushes, and opens the labelled draft with the description from design D6, or posts the comment. Verify with `scripts/open-engine-update.test.sh` using stub `git` and `gh`, covering:
  - the draft opened with the right files and label;
  - an existing branch refused;
  - the comment path;
  - every input validated before it reaches a branch, commit, YAML or Markdown.

  Also verify with `shellcheck -S warning`.
- [ ] 3.3 Add `.github/workflows/engine-update.yml` with the `plan` and `propose` jobs, and the `engine-update` environment only on `propose` (design D1, D4). Verify with `actionlint`, and by reading it to confirm that `plan` references no secret or environment.

## 4. Following CI's patch check

- [ ] 4.1 Write `scripts/engine-update-result.sh` with `plan` and `apply` (design D2). Verify with `scripts/engine-update-result.test.sh` using stub `gh`, covering:
  - passed, skipped, failed, cancelled and missing `Patch check` results;
  - a fork with an update branch's name;
  - a branch or pull request without the label;
  - a result for an older head commit;
  - a patch name that isn't a plain `.patch` path;
  - a ready pull request returned to draft;
  - no second comment for the same commit.

  Also verify with `shellcheck -S warning`.
- [ ] 4.2 Add `.github/workflows/engine-update-result.yml` on `workflow_run` of `CI` with the `filter` and `apply` jobs, the environment only on `apply`, and no checkout of the pull request. Verify with `actionlint`, and by reading it to confirm that no step checks out `head_sha` or `head_branch`.

## 5. Documentation

- [ ] 5.1 Update `docs/building.md` ("Updating the engine") with the automatic draft, how it turns ready, the manual steps left, and how to start the check by hand. Verify that the documented `gh workflow run engine-update.yml` command matches the workflow's inputs.

## 6. Integration

- [ ] 6.1 After merging, start `engine-update.yml` by hand on `main`. Verify that it opens a labelled draft for the newest upstream tag, that CI runs on it, and that once the patch check finishes the pull request is marked ready or gets the "patches need updating" comment naming the patch.
- [ ] 6.2 Verify that a scheduled run while that pull request is open opens nothing new.

## Workflow follow-up

- When archiving, rewrite the Purpose of `openspec/specs/software-updates/spec.md` so that it no longer promises current engine fixes by itself. It should say that the repository notices new engine releases and proposes the update (`build-pipeline`, "Upstream engine releases checked daily").
