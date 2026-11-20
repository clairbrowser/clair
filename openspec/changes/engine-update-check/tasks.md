# Tasks

## 1. Repository settings (owner)

- [ ] 1.1 Create a GitHub App installed on this repository only, with contents and pull requests write access, no workflows permission and no webhook. Verify that its installation lists only this repository.
- [ ] 1.2 Create the `engine-update` environment limited to `main`, with secrets `ENGINE_UPDATE_APP_ID` and `ENGINE_UPDATE_APP_PRIVATE_KEY`. Verify that `gh api repos/{owner}/{repo}/environments/engine-update` shows the `main` branch policy.
- [ ] 1.3 Create the `engine-update` label, and verify that `gh label list` shows it.

## 2. Shared patch check

- [ ] 2.1 Move `ci.yml`'s `Patch check` steps into `.github/workflows/patch-check.yml` (`workflow_call`, inputs `ref` and `ungoogled-tag`), uploading the first failing patch's name and a log excerpt on failure. Verify with `actionlint`.
- [ ] 2.2 Make `ci.yml` call it, keeping the job named `Patch check` and the `Engine check`'s handling of its result. Verify on a pull request that changes the engine key: both checks appear under their old names and report the same results as before.

## 3. Choosing the update

- [ ] 3.1 Write `scripts/find-engine-update.sh`, which prints `none`, `comment <pr> <tag>` or `update <tag>` from the pin, upstream's tags and the `engine-update` pull requests (design D1, D5). Verify with `scripts/find-engine-update.test.sh` using stub `git` and `gh`, covering:
  - no newer tag;
  - a newer patch-level tag, and a newer major version;
  - numeric ordering (`157.0.8103.9-1` older than `157.0.8103.78-1`);
  - invalid and malformed tags ignored, and none valid as an error;
  - an open update pull request, and a comment already posted for the tag;
  - a closed, unmerged pull request for the newest tag;
  - a hand-started run with an older or unknown tag.

  Also verify with `shellcheck -S warning`.

## 4. Opening the pull request

- [ ] 4.1 Write `scripts/open-engine-update.sh`. It creates `engine-update/<tag>`, moves the submodule pointer without checking it out, writes the Changie fragment, commits, pushes, and opens a ready or draft pull request with the description from design D6, or posts the comment. Verify with `scripts/open-engine-update.test.sh` using stub `git` and `gh`, covering:
  - a passed check, which opens a ready pull request;
  - a failed check, which opens a draft naming the patch;
  - a cancelled check, which opens nothing;
  - an existing branch, which is refused;
  - the comment path.

  Also verify that every input is validated before it reaches a branch, commit, YAML or Markdown, and run `shellcheck -S warning`.

## 5. The workflow

- [ ] 5.1 Add `.github/workflows/engine-update.yml` with the `plan`, `patch-check` and `propose` jobs, their permissions and the `engine-update` environment only on `propose` (design D1, D3). Verify with `actionlint`, and by reading it to confirm that no job other than `propose` references a secret or an environment.
- [ ] 5.2 Update `docs/building.md` ("Updating the engine") with the automatic pull request, the manual steps left, and how to start the check by hand. Verify that the documented `gh workflow run engine-update.yml` command matches the workflow's inputs.

## 6. Integration

- [ ] 6.1 After merging, start the workflow by hand on `main` and verify that it opens the expected pull request for the newest upstream tag, ready or draft depending on the patch check, and that `ci.yml` runs on it.
- [ ] 6.2 Verify that a scheduled run while that pull request is open opens nothing new.

## Workflow follow-up

- When archiving, rewrite the Purpose of `openspec/specs/software-updates/spec.md` so that it no longer promises current engine fixes by itself. It should say that the repository notices new engine releases and proposes the update (`build-pipeline`, "Upstream engine releases checked daily").
