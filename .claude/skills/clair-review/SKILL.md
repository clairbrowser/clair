---
name: clair-review
description: Runs Clair's whole-codebase architecture, code quality and security review. With no argument it works out where the current review run stands and runs the next step - preflight, the pilot section, a batch of section reviewers, verification, or the final synthesis. Use only when the owner asks to run or continue the review; it spends a lot of usage.
argument-hint: "[status | approve-pilot | max <n> | skip <id> | retry <key> | section <id> | rebase-run]"
disable-model-invocation: true
model: opus
effort: medium
allowed-tools: Bash(./scripts/review.sh *) Bash(git fetch origin main) Bash(gh run list *) Bash(gh run view *) Bash(gh api repos/ungoogled-software/*)
---

# Clair review orchestrator

You are traffic control for a review that other agents carry out. You decide nothing about the code and you read no report in full: `scripts/review.sh` tells you the next step from the files on disk, you dispatch `clair-reviewer` subagents to do it, and you tell the owner where things stand. Keeping your own context free of code and findings is what lets one cheap session steer a review that spans days.

The owner is rationing usage across several sessions. That shapes three rules:

- **One step per invocation.** Do the step `next` names, report, and stop. The owner runs `/clair-review` again when ready. The pilot is the one exception, described below.
- **Never retry inside an invocation.** If a reviewer comes back without a complete report, say so and stop. The script offers the work once more on the next run and blocks it after two attempts.
- **Never skip ahead.** If `next` says `blocked` or `drift`, stop and explain. Do not dispatch anything else.

Arguments: `$ARGUMENTS`

## If an argument was given

| Argument | Do this |
|---|---|
| `status` | Print `./scripts/review.sh status` and stop. |
| `approve-pilot` | `./scripts/review.sh approve-pilot`, then print the status and stop. |
| `max <n>` | `./scripts/review.sh set max <n>`: reviewers per batch, 1 to 8. |
| `skip <id>` | `./scripts/review.sh skip <id>`: leave a section out of this run. |
| `retry <key>` | `./scripts/review.sh retry <key>`: clear a block. The key is what `blocked` printed. |
| `section <id>` | Dispatch that one section now, as under "sections" below. If its report is already complete, ask before moving it to `stale/` in the run directory. |
| `rebase-run` | `./scripts/review.sh rebase-run`: accept the current commit as the reviewed one. Print which sections it marked to run again. |

After any of these, print the status and stop. Do not continue into the next step unless the argument was `section`.

## With no argument

Run `./scripts/review.sh next` and act on its one line of output.

### `preflight`

No run exists yet.

1. `git fetch origin main`, then `./scripts/review.sh preflight`. If anything fails, show the failing lines and stop. Every failure is the owner's to fix; the usual ones are an engine tree built from another commit, or a checkout that is not on `main`. If it prints a note about open OpenSpec changes, pass the note on: the owner decides whether any should be archived first.
2. `./scripts/review.sh init`. It prints the run directory.
3. Collect test timings for section 07. Find a recent successful run of `quality.yml` whose jobs include the runtime suite (`gh run list --workflow quality.yml --status success --limit 10 --json databaseId`, then `gh run view <id> --json jobs`; runs that finish in seconds skipped the suite). For each job that ran the suite, run `gh run view --job <job id> --log | ./scripts/review.sh timings` and append the output, under a heading naming the job and the run, to `timings.txt` in the run directory. If no such run can be found, write a line in `timings.txt` saying so and carry on: timings help section 07 but nothing waits on them.
4. Collect upstream versions for sections 04 and 09, which ask how far the engine lags behind Chromium and have no network. Run `gh api repos/ungoogled-software/ungoogled-chromium/releases --jq '.[] | "\(.published_at) \(.tag_name)"'` and the same for `ungoogled-chromium-macos`, and write both lists, each under a heading naming its repository, to `upstream.txt` in the run directory. A tag is the Chromium version followed by a revision. If a call fails, write a line in `upstream.txt` saying so and carry on.
5. Print the status and stop.

### `pilot <id>:<model>`

The first section runs alone so the owner can judge the report's quality and what it cost before the rest is spent.

1. Dispatch the section as under "sections".
2. Run `next` again. If it says `verify <id>`, dispatch the verifier as under "verify" in this same invocation, so the owner sees the pilot complete with its verdicts.
3. Stop with the pilot message below.

### `await-pilot-approval`

Tell the owner:

- where the pilot report and its verdicts are;
- to read the report and check two or three findings against the code;
- to look at what the pilot cost (`/usage` or `/cost`) before spending the rest;
- that the briefs in `sections/`, `report-format.md`, `threats.md` and `focus.md` can be adjusted now, before the other sections run;
- to continue with `/clair-review approve-pilot`.

### `sections <id>:<model> ...`

1. Print `./scripts/review.sh status` so the owner sees what is about to run.
2. `./scripts/review.sh dispatched <id> ...` with every id in the batch.
3. For each section print `Handing off: section <id> (<slug>) to <model>`.
4. Dispatch all of them in **one message**, each as an Agent call with `subagent_type: "clair-reviewer"`, `model` set to the model the script named (`fable` or `opus`), and `run_in_background: false`. Foreground matters: this skill's model and effort apply only to the turn that invoked it, and a background agent would hand the follow-up to whatever model the session is on.
5. Give each this prompt, with the paths made absolute:

   ```text
   Review section <id> (<slug>) of Clair.

   Run directory: <run directory>
   Your brief: .claude/skills/clair-review/sections/<id>-<slug>.md
   The files that are yours: <run directory>/files/<id>.txt
   Write your report to: <run directory>/<id>-<slug>.md
   ```

   For section 07 add the line `Test timings: <run directory>/timings.txt`. For sections 04 and 09 add the line `Upstream versions: <run directory>/upstream.txt`.
6. When they return, print one line per section with the outcome it reported, then the status, then stop.

### `verify <id> ...`

Same steps, with these differences: the keys for `dispatched` are `verify-<id>`, the model is always `opus`, and the prompt is:

```text
Verify the findings of section <id> (<slug>) of Clair.

Run directory: <run directory>
Your brief: .claude/skills/clair-review/verify.md
The report to check: <run directory>/<id>-<slug>.md
Write your verdicts to: <run directory>/verify/<id>.md
```

### `synthesize`

`./scripts/review.sh dispatched synthesize`, print `Handing off: synthesis to fable`, and dispatch one `clair-reviewer` with `model: "fable"` and this prompt:

```text
Write the final report of Clair's review.

Run directory: <run directory>
Your brief: .claude/skills/clair-review/synthesize.md
Write the report to: <run directory>/REPORT.md
```

When it returns, read only the Summary part of `REPORT.md`, relay it to the owner with the path, and stop.

### `done`

Say that the review is complete and where `REPORT.md` is, and that `/clair-fix` takes the report's work items one at a time once the owner has read it.

### `blocked <key>`

That piece of work failed twice. Say which, and that the owner can look at the partial file in the run directory, then either `/clair-review retry <key>` to try again or `/clair-review skip <id>` to go on without the section. If a rate limit or a permission prompt caused it, say so, because retrying before that is fixed will fail the same way.

### `drift <why>`

The checkout no longer matches the commit the run is reviewing, so later sections would review different code from earlier ones. Say what differs. The owner can check the reviewed commit out again, or run `/clair-review rebase-run` to accept the new commit, which re-runs only the sections whose files changed.

## Rules that hold throughout

- **Reports are private.** The repository is public and the reports describe unfixed security problems. They live in `build/review/`, which git ignores. Never commit them, quote them in a commit message, pull request or issue, or copy them anywhere else.
- **The review changes nothing.** Do not fix what the reports find and do not open issues. When the run is done, the owner decides what gets done, and the separate `/clair-fix` skill carries out the report's work items one at a time. Anything touching release secrets or the CI runner is fixed first and privately.
- **Do not start an engine build during a run.** It would change the Chromium tree under the reviewers. `preflight` checks that the tree matches the commit; nothing re-checks it mid-run.

## Setting up a machine

Reviewers read the engine build's workspace, the self-hosted runner's `_work/clair/clair` shared read-only at `/Volumes/My Shared Files/clair`: the patched tree in `build/src`, the ungoogled-chromium checkout beside it, and the `build/engine_key` and `build/compile_status` that `preflight` checks. They write reports under `build/review/`. Without permission rules every read of the share prompts. Add these to `.claude/settings.local.json`, adjusting the path if `CLAIR_ENGINE_WORKSPACE` points elsewhere:

```json
{
  "permissions": {
    "allow": [
      "Read(//Volumes/My Shared Files/clair/build/**)",
      "Read(//Volumes/My Shared Files/clair/ungoogled-chromium/**)",
      "Edit(/build/review/**)"
    ],
    "deny": [
      "Read(//Volumes/My Shared Files/clair/.git/**)",
      "Edit(//Volumes/My Shared Files/**)"
    ]
  }
}
```

Share the workspace, not anything above it: the runner's top folder holds its registration credentials. The `.git` deny is there because `actions/checkout` leaves a GitHub token in `.git/config` while a job runs. Keep the mapping fixed for the length of a run, since `run.md` records the paths every reviewer uses.

## Preparing a later run

The skill is reusable. Before a new run, edit `focus.md` for what is coming next. `threats.md` holds the security questions every code section answers, and section 09 compares the engine's hardening with stock Chromium's; both stay as they are between runs unless the threat model changes. When files were added since the last run, `./scripts/review.sh check` names any that `scope.txt` does not assign yet, and `./scripts/review.sh sizes` shows whether a section has outgrown one reviewer. `sections.txt` sets the dispatch order and each section's model.
