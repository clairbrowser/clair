---
name: clair-fix
description: Fixes the findings of one /clair-review section report, named as its argument, one finding per invocation, most severe first. It checks that the finding still holds, fixes it on its own branch, records it as fixed, opens the pull request and stops. Use only when the owner asks to fix review findings; it changes code and opens pull requests.
argument-hint: "<report.md> [status | <finding id> | defer <id> <why> | drop <id> <why> | reopen <id>]"
disable-model-invocation: true
allowed-tools: Bash(./scripts/review.sh *)
---

# Clair fixer

The first argument is the file name of a section report, such as `04-release-chain.md`, that sits directly in `build/review/` of the main checkout (git ignores it). Its findings are headed `### S<section>-<number> [<Severity>] <title>`. `./scripts/review.sh work <report.md>` lists every finding in it below Info, most severe first and then by number, and keeps what became of each in `<report name>.work.txt` beside it. Which finding comes next is the script's rule, not your judgement. The script finds the reports from any worktree.

If no report name was given, list the `.md` files directly in `build/review/`, ask the owner which one to use, and stop.

Arguments: `$ARGUMENTS`

## Rules that hold throughout

- **One finding per invocation.** Check it, fix it, record it, open its pull request, and stop. Do not start the next one.
- **The reports are private and the repository is public.** Nothing from a report goes into anything that is pushed: no finding IDs, no quoted text, no severity, no account of how a weakness could be used, no mention that a review found it. A commit message, a pull request, an OpenSpec artifact and a code comment each describe what the code now does and why that is right, as they would for any change. The record of which finding a pull request settles is the report's `.work.txt`, and nowhere else.
- **A report is a claim about an older commit.** Its `- Commit:` line gives the commit that was reviewed. Code has moved since, some findings are wrong, and some recommendations do not fit. Verify before you change anything, and fix what is true now.
- **`CLAUDE.md` governs the work.** Branches, Conventional Commits, Changie fragments, when an OpenSpec change is required, engine builds, the checks to run before a pull request and the merge rules are all there. This skill overrides none of them.
- **Do not merge.** Merging is the owner's step unless they tell you to in this conversation.

## Arguments

| Argument | Do this |
|---|---|
| `<report.md>` alone | Run `./scripts/review.sh work <report.md> next` and act on its line, below. |
| `<report.md> status` | Bring the record up to date as under "Keeping the record", print `./scripts/review.sh work <report.md>`, and stop. |
| `<report.md> <finding id>` | Fix that finding now, as under "Fixing a finding", whatever `next` would have chosen. If it is already fixed, merged or dropped, say so and stop. |
| `<report.md> defer <id> <why>` | `./scripts/review.sh work <report.md> set <id> deferred <why>`. Print the list and stop. |
| `<report.md> drop <id> <why>` | `./scripts/review.sh work <report.md> set <id> dropped <why>`. Print the list and stop. |
| `<report.md> reopen <id>` | `./scripts/review.sh work <report.md> set <id> open`. Print the list and stop. |

## What `work next` prints

- `no-findings`: the report has no finding to fix. Say so and stop.
- `resume <id> <branch>`: an earlier invocation stopped part-way. Find the branch and its worktree, read what is there, and carry on from the step it reached.
- `fix <id> <severity>`: fix it, as below.
- `done`: every finding in the report is fixed, merged, dropped, deferred or with the owner. Print the list and stop.

## Fixing a finding

1. **Read the finding.** Read its entry in full in the report. Read the report's other findings only to see whether one shares its cause. Do not read other reports.

2. **Verify that the problem exists.** Fetch `origin/main`. Open the cited code as it is on `origin/main`, and use `git diff <reviewed commit> origin/main -- <cited files>` to see what changed since the review. Follow the path from cause to consequence yourself; for an engine finding, read the engine tree in `build/src` of the engine workspace (`/Volumes/My Shared Files/clair` unless `CLAIR_ENGINE_WORKSPACE` says otherwise). Whatever the outcome, begin what you tell the owner with the finding's header as the report gives it, without the `###`, such as `S03-01 [Medium] The store can install and update extensions but can no longer disable one it has flagged`. Then one of:
   - **It exists.** Tell the owner briefly what you found: the finding, whether and where it still holds on `origin/main`, and the fix you intend. Then stop and wait for their confirmation before going on to step 3. Record nothing yet. If they redirect the fix, follow what they say.
   - **It does not, or no longer does.** Record `work <report.md> set <id> dropped <reason>`, giving the commit or the line that settles it. Tell the owner and stop.
   - **It exists, but the recommended fix is wrong, not enough, or much larger than the report says.** Tell the owner what you found and what you would do instead, and stop before changing anything. Record nothing: the finding stays open.
   - **The fix lies outside the repository** (runner configuration, repository settings, secrets, signing keys). Do what can be done in the repository as below, give the owner the steps only they can take, in order, and record `work <report.md> set <id> owner <one line on what waits>`. If nothing in the repository changes, stop there.

3. **Start the branch.** Create a worktree (the EnterWorktree tool) on a new branch from `origin/main`, named for what the change does, never for the finding. The main checkout stays where it is: the reports live there. Record `work <report.md> set <id> started <branch>`.

4. **Fix it.** Make the smallest change that removes the cause, not one that hides the symptom where the report happened to notice it. If the report names other places with the same cause, fix those too. Add the test that would have caught it, at the cheapest level that can express it: a script's `*.test.sh`, a `ClairUI` unit test against the fakes, or a runtime test only when it needs a running browser. If no test can express it, say why in the pull request.

   If `CLAUDE.md` says the fix needs an OpenSpec change (new behaviour, a breaking `ClairHost.h` or data-format change, an architecture or security change), write no code: draft the change with the `openspec-propose` skill, phrased as design with nothing taken from the report's wording, and the pull request carries the proposal. If the fix needs a decision that is the owner's (a breaking change, a behaviour users will notice, a trade-off the report left open), ask before building on a guess.

   If another open finding turns out to share the cause and this change settles it, it is part of this fix.

5. **Check it.** Run the checks `CLAUDE.md` lists for the kind of change before pushing: the script tests and `shellcheck` for scripts, the `ClairUI` build and unit tests for Swift, `openspec validate --all --strict` for specs. Run `./scripts/engine-key.sh` and compare with `origin/main`'s: if the key changed, the pull request needs an engine build and a patch check, so tell the owner before you push, and push once with everything in it.

6. **Open the pull request and mark it fixed.** Commit, push and open one pull request. Then record `work <report.md> set <id> fixed <number>`, and the same for any other finding in the report that the change settles.

7. **Report and stop.** Tell the owner which finding it was, what you found when you verified it, what you changed and tested, anything you left out and why, and the pull request. That account is for the owner in this conversation only, so it may refer to findings by ID. Do not go on to the next finding.

## Keeping the record

States are `open` (no line in the record), `started <branch>`, `fixed <pr>`, `merged <pr>`, `dropped <why>`, `deferred <why>` and `owner <what waits>`. For `status`, look up each `fixed` pull request (`gh pr view <number> --json state,mergedAt`) and record a merged one with `work <report.md> set <id> merged <number>`. If one was closed without merging, tell the owner and ask whether to reopen or drop the finding; do not decide that yourself.

## When the report is wrong

Findings are verified once and are still wrong some of the time. Dropping a finding with the evidence is a good outcome, and so is telling the owner that the fix belongs somewhere other than where the report pointed. What is not acceptable is a change that makes the finding's wording untrue while the weakness stays: a check added at the cited line when three other callers reach the same code, or a test that asserts the new code runs without asserting what it protects.

## Preparing a machine

The reports are in the main checkout, so from a worktree every read of a report is outside the working directory and may prompt. To avoid that, allow the main checkout's `build/review/` by its absolute path in `.claude/settings.local.json`: `Read(//<path to the main checkout>/build/review/**)`.
