# Design

## Context

- The pin is the `ungoogled-chromium` submodule's commit. A tag looks like `158.0.8127.36-1`: Chromium major, two fixed numbers, build, patch, then ungoogled-chromium's revision. Upstream tags a major only until the next one is out.
- Two kinds of update, both a pin change:
  - **Patch-level** (same major, #71): two files, the pin and a Changie fragment. Clair's patches nearly always still apply.
  - **New major** (#196): 36 files over two weeks. The files copied from ungoogled-chromium-macos had to be synced, two Clair patches refreshed, and compile errors fixed after the patches applied. ungoogled-chromium-macos tags later than ungoogled-chromium: on 2026-11-20, `158.0.8127.36-1` had no macOS tag.
- Either kind compiles Chromium from scratch. `build.sh`'s `update` stage falls back to `fetch prepare` when the pin changes (`base_key`), and `prepare` deletes `build/src/out`. That is about 4 hours on the owner's Mac, and only the owner starts `engine.yml`.
- `ci.yml` runs the `Patch check` job for a pull request whose engine key changed and whose engine isn't published (about 20 minutes, hosted). `build.sh` applies Clair's series through ungoogled-chromium's `patches.py`, which stops at the first patch whose `PATCH_BIN` exits non-zero. `PATCH_BIN` is `scripts/patch-no-fuzz.sh`.
- The `Engine check` job fails until `chromium-engine-<key>` is published, and `engine.yml` re-runs it after publishing. `main`'s ruleset requires `Script tests and lint`, `Native layer build and tests` and `Engine check`.
- GitHub starts no workflow for events caused by a workflow's own `GITHUB_TOKEN`, so a pull request opened with it gets no CI run. Workflows on `schedule` and `workflow_run` always run the default branch's copy.
- ungoogled-chromium-macos tags only some of ungoogled-chromium's versions: of 157's `157.0.8103.38-1`, `157.0.8103.50-1` and `157.0.8103.78-1`, it tagged only `157.0.8103.78` (and `157.0.8103.78-1.1`). Its tags name the version alone, or with a suffix (`-1.1`, `_arm64`). Each pins ungoogled-chromium as a submodule: `157.0.8103.78` pins `8c886df`, the commit of `157.0.8103.78-1`.
- Release notes: `.changes/unreleased/` currently holds #196's fragment, `kind: Updated`, body `Update the engine to Chromium 157.0.8103.78 (ungoogled-chromium 157.0.8103.78-1)`.

## Goals / Non-Goals

**Goals:**
- A patch-level update reaches "every patch applies, build the engine" with no work from the owner.
- A new major's pull request exists as soon as ungoogled-chromium-macos tags it, and always shows the full list of patches left to fix.
- The owner's pushed fixes are never lost, and the bot never moves the pin under an engine build the owner has started.
- Nothing the bot does can start a job on the owner's Mac.

**Non-Goals:**
- Starting engine builds, merging, fixing patches, or syncing ungoogled-chromium-macos's files (see the proposal).
- Following more than one tag at a time.
- Detecting compile failures. "Ready" means the patches apply, not that the engine builds.

## Approaches

How the bot's pull request gets CI to run:

- **A. GitHub App token (chosen).** The scheduled workflow opens the pull request as an App, so CI runs as it does for any pull request and `ci.yml` is untouched. Costs a one-time setup and one long-lived key, kept in an environment only `main` can use. A fine-grained personal token would also work, but it expires and acts as the owner.
- **B. Make `ci.yml` startable with `workflow_dispatch`.** No secret, but the required merge gate gains a second trigger path: the base commit, branch name and pull request lookup each need a non-pull-request variant, and `engine.yml`'s re-run has to find both kinds of run. The risk lands on the gate every pull request depends on.
- **C. Run the patch check inside the scheduled workflow.** No secret and no change to `ci.yml`, but a pull request whose patches all apply would have none of its required checks until the owner closed and reopened it.

The owner chose A.

Which tags to follow: ungoogled-chromium's (as first built: a new major's pull request opens before ungoogled-chromium-macos's files exist to sync, as #212 did for `158.0.8127.36-1`), ungoogled-chromium-macos's, or ungoogled-chromium's within a major and ungoogled-chromium-macos's for a new one. The owner chose ungoogled-chromium-macos's on 2026-11-21: every pull request can then be synced, at the cost of the versions that repository skips.

How much of a new major the bot does: the pin only (chosen by the owner, to start), or the pin plus a copy of ungoogled-chromium-macos's files once it tags the version. The second removes most of #196's churn, but must keep Clair's edits to those files (the Rust hashes, `retrieve_and_unpack_resource.py`), so it waits until the first has run through a major.

## Decisions

### D1. Two workflows, with their logic in two scripts

- `engine-update.yml`: `schedule` (`23 */6 * * *`) and `workflow_dispatch` with one boolean input, `take-newest` (D3). One job on `ubuntu-latest` in the `engine-update` environment, concurrency group `engine-update` without cancelling. It checks out `main` with `persist-credentials: false` and runs `scripts/engine-update.sh`.
- `engine-update-status.yml`: `workflow_run` on `CI`, type `completed`. One job on `ubuntu-latest` that runs `scripts/engine-update-status.sh` from `main`. It never checks out or runs the pull request's code.

Both scripts follow the repository's rules for scripts (bash 3.2, BSD userland) and also run under the runner's bash and GNU tools, as `engine-key.sh` already does in `ci.yml`. Each has a `*.test.sh` with a scratch repository, a local stand-in for the upstream remote and a fake `gh`, as `prune-engines.test.sh` does. `ci.yml` runs the script tests on macOS only, so it gains one `ubuntu-latest` job, not a required check, that runs these two tests where the scripts will run.

`engine.yml` gains `run-name: "Engine: ${{ inputs.ref }}"`, so that a run's title names the branch it builds. The API doesn't expose a run's inputs, and D3 needs the branch.

### D2. Finding the tag to move to

`engine-update.sh` follows ungoogled-chromium-macos's tags. It lists them with `git ls-remote --tags`, with no clone, and keeps those matching `^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+([-_][A-Za-z0-9._-]+)?$`. It takes the newest version among them, by its four numbers, fetches that version's tags alone (`git fetch --depth 1`), and reads the `ungoogled-chromium` gitlink of each.

It names those commits with ungoogled-chromium's tags, listed with `git ls-remote --tags` on the URL in `.gitmodules`: tags matching `^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$`, each with its commit (the peeled `^{}` line when the tag is annotated), ordered by their five numbers.

- The **current tag** is the newest ungoogled-chromium tag whose commit is `main`'s pin. If no tag is, the run fails and says so.
- The **target** is the newest ungoogled-chromium tag on a commit that the newest ungoogled-chromium-macos version's tags pin. If none is, the run fails and names the ungoogled-chromium-macos tag. If the target isn't newer than the current tag, the run ends: nothing to do.
- The update is **patch-level** when the target's first number equals the current tag's, and a **new major** otherwise.

A tag's name reaches shell, a commit message, YAML and Markdown, so nothing but the patterns above is accepted.

### D3. One pull request, on the branch `engine-update`

The tag a branch is on is read from its `ungoogled-chromium` gitlink, never from a title or body.

| State | What the run does |
|---|---|
| No open pull request from `engine-update`, and a pull request for the target was closed without merging | Nothing. The owner declined that tag. A newer tag opens a new pull request. |
| No open pull request, otherwise | Creates `engine-update` from `main` with one commit (D4), and opens a draft pull request (D5). |
| Open pull request already on the target | Refreshes its description if that changed (D5). |
| Open pull request on an older tag, and it is **held** | Leaves the branch alone. The description says the newer tag exists and why the pull request stays where it is. |
| Open pull request on an older tag, not held | Adds one commit on top of the branch that moves the pin to the target (D4), converts the pull request to draft, and updates its title and description. |

A pull request is **held** once the owner has started an engine build for its current pin: an `engine.yml` run titled `Engine: engine-update` exists that was created after the branch's newest commit that changed the pin, whatever its state. That covers a build that is queued or running, one that failed at compile (its workspace can resume, and a pin change would discard it), and one that published an engine the owner has since pushed fixes on top of (the next build is in place, and a pin change would make it a full one). It also means the bot never works out an engine key, so the job that holds the App's key runs no code from the branch.

A held pull request is released by merging it, after which the next run opens a pull request for the newer tag, or by starting `engine-update.yml` by hand with `take-newest`, which moves the pin despite the hold.

An open pull request on a tag that ungoogled-chromium-macos hasn't tagged (opened before D2 followed that repository, as #212 was) is left alone while the target isn't newer than `main`'s pin. When ungoogled-chromium-macos tags that version at the same commit, it is already on the target.

A declined tag is recognised by a closed, unmerged pull request from `engine-update` whose description carries that tag in a marker (D5).

The bot never force-pushes, rebases or merges, and never pushes to `main`. If its push is rejected because the branch moved, the run fails and the next one tries again. If `engine-update` exists with no open pull request: when every commit it has ahead of `main` is the bot's, the bot deletes it and starts again from `main`; otherwise the run fails and names the branch, for the owner to delete or rename.

### D4. The commit

- The pin moves with `git update-index --cacheinfo 160000,<commit>,ungoogled-chromium`, so the submodule is never cloned.
- The release note is a new fragment, named as `changie new` names them, with the body `Update the engine to Chromium <version> (ungoogled-chromium <tag>)`. Any other fragment in `.changes/unreleased/` of kind `Updated` whose body starts with `Update the engine to Chromium ` is deleted in the same commit, so a release never lists two engine updates. Deleting it, where rewriting it would do, keeps the pull request mergeable after a release: the release deletes that fragment on `main` too, and two deletions don't conflict. When the pin moves again on the branch, the bot rewrites the fragment it added.
- The message is `build(engine): update to ungoogled-chromium <tag>`, and the author is the App's bot user. It is pushed over HTTPS with the App's token.

### D5. The pull request's title and description

The title is the commit message. The bot owns the part of the description between two marker comments and replaces only that part, so text the owner adds outside it stays. That part holds:

- a marker comment naming the tag, which D3 uses to recognise a declined tag
- the tag it moves from and to, whether it is patch-level or a new major, and a link to upstream's comparison of the two tags
- the ungoogled-chromium-macos tag it follows, with a link to it and to its comparison with the ungoogled-chromium-macos tag of `main`'s pin, when there is one: the files to sync are those it changed
- for a new major, the steps of `docs/building.md`'s "Updating the engine" as a checklist, naming that tag: sync the copied files, keep the Rust hashes, check the SDK
- that the engine build is a full one, of about 4 hours, started by the owner
- when held on an older tag (D3), the newer tag, the reason and how to take it anyway
- when the pull request conflicts with `main`, that CI can't run until the conflict is resolved: GitHub starts no pull request run then, so the comment of D7 would otherwise go stale without a word

The description never contains a bare `@name`.

### D6. The App and its key

The owner creates a GitHub App in the `clairbrowser` organisation with repository permissions "Contents: read and write" and "Pull requests: read and write", and installs it on this repository only. Its ID is a variable and its private key a secret of a new `engine-update` environment, whose deployment branches are limited to `main`. `engine-update.yml` gets a token with `actions/create-github-app-token`, asking for those two permissions only. The lookup of `engine.yml` runs uses the job's `GITHUB_TOKEN` with `actions: read`.

`engine-update-status.yml` uses no secret: its `GITHUB_TOKEN` has `actions: read` and `pull-requests: write`, and `contents: read` to check out `main`'s copy of its script. `engine-update.yml` checks out `main` with the App's token, so its `GITHUB_TOKEN` needs nothing beyond `actions: read`. GitHub refuses to change a pull request's draft state with that token: both `markPullRequestReadyForReview` and `convertPullRequestToDraft` fail with "Resource not accessible by integration" (task 3.3, tried from a job with `pull-requests: write` on 2026-11-21), while posting and editing comments and reading a run's jobs work. So the job runs in the `engine-update` environment and uses the App's token, asking for "Pull requests: write" only, for those two calls, and its own token for everything else.

### D7. Draft and ready

`engine-update-status.yml` runs only when the completed `CI` run was for a `pull_request` event, its head repository is this repository, and its head branch is `engine-update`. A fork's branch of the same name is therefore ignored. The script then finds the open pull request from `engine-update` and stops unless the run's head commit is the pull request's current head, so a late result for an old commit changes nothing.

If the run itself was cancelled (a newer push replaced it, or someone cancelled it), nothing changes. Otherwise it reads the run's jobs:

| `Engine key` | `Patch check` | Result |
|---|---|---|
| success | success, or skipped | Ready for review. The comment says every patch applies and gives `gh workflow run engine.yml -f ref=engine-update`, noting the full build. If the engine is already published, it says so instead. |
| success | anything else | Draft. The comment lists the patches that don't apply (D8). If the log names none, the check failed elsewhere (the fetch, the overlay, a logo path, domain substitution, a timeout), and the comment says that and links the job. |
| not success | any | Draft. The comment links the `Engine key` job. |

Only the patch check decides the state. The other jobs show in the pull request's checks as usual, and the merge gate is unchanged: a ready pull request still can't merge until its engine is published.

The script changes the draft state only when it differs, and keeps a single comment, found by a marker comment in its body and edited in place. Patch names come from the job's log (`gh api repos/<repo>/actions/jobs/<id>/logs`); a name is used only if it matches `^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*\.patch$`. Everything from the log is handled as data: passed in files or environment variables, never evaluated.

### D8. The patch check lists every patch that doesn't apply

`scripts/patch-no-fuzz.sh` gains a mode, on when `CLAIR_PATCH_FAILURES` names a file. It first runs `patch --fuzz=0 --dry-run` with the same arguments. If that fails, it prints `patch`'s output, appends the patch's path under `patches/` to the file, and exits 0 without changing the tree, so `patches.py` goes on to the next patch. If it succeeds, it applies the patch for real. Without the variable it behaves as today.

`build.sh`'s `apply_layer` sets the variable for Clair's series. When the file isn't empty afterwards, it prints one line per patch, `clair-patch-failed: <path>`, and exits 1 before the overlay is copied. This holds for `prepare` and `update`, so the engine build on the Mac gets the same list. `update` applies the layer to `build/next`, so `build/src` is untouched, as today.

A skipped patch can make a later one fail that builds on it, so the list can name more patches than need fixing. The comment says to fix them from the top. ungoogled-chromium's own series keeps `patch`'s defaults and still stops at its first failure: upstream tests it against its own tag.

### D9. Three pull requests implement this

1. The patch list (D8). It changes the engine key, so it needs an engine build: in place, with nothing to compile.
2. The two workflows and their scripts, and the docs. No engine input changes.
3. Following ungoogled-chromium-macos's tags (D2, D5), once the first update pull request had opened for a version that repository hadn't tagged. No engine input changes.

The workflows can't run before they are on `main`, so their logic is verified by the script tests, and the workflows themselves by the first runs after merging (tasks 5.x).

## Risks / Trade-offs

- **Versions ungoogled-chromium-macos skips are never offered.** `157.0.8103.38-1` and `157.0.8103.50-1` would not have been. Moving the pin to one stays manual (`docs/building.md`).
- **A security tag for the old major is skipped when a new major lands first.** With one pull request following the newest tag, an unmerged patch-level update becomes the new major's pull request. The hold in D3 keeps one whose engine build the owner has started, and upstream stops tagging the old major at that point anyway.
- **"Ready" isn't "builds".** #196's patches applied before its compile errors showed. The comment says what ready means.
- **The list can over-report** (D8).
- **Upstream's code runs unreviewed in the patch check.** It already does for any pin change: on a hosted runner, with a read-only token and no secrets. It never reaches the owner's Mac until the owner starts a build.
- **A long-lived App key.** It can write contents and pull requests in this repository. The environment limits it to workflows running from `main`, the ruleset keeps it from changing `main` without the required checks, and it isn't in the `release` environment.
- **A new major's pull request stays draft until the macOS files are synced**, since ungoogled-chromium-macos's patches fail first. Its description says so.
- **A scheduled run that fails** (upstream unreachable, a rejected push) changes nothing, and the next run retries. GitHub mails the owner about the failure.

## Left to the builder

- The names of the environment's variable and secret, and of the marker comments.
- The exact wording of the description and the comment.
- How the scripts split into functions, and how the tests fake `git ls-remote` and `gh`.
