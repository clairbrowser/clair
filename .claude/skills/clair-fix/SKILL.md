---
name: clair-fix
description: Works through the work items of a finished /clair-review run, one per invocation. It checks that the findings still hold, makes the fix on its own branch or drafts the OpenSpec change the item needs, opens the pull request and records the outcome. Use only when the owner asks to fix review findings; it changes code and opens pull requests.
argument-hint: "[status | <work id> | defer <id> <why> | drop <id> <why> | reopen <id>]"
disable-model-invocation: true
allowed-tools: Bash(./scripts/review.sh *)
---

# Clair fixer

`/clair-review` ends with `REPORT.md`, whose last part before the limits is a list of work items, `W01` onwards, in the order they should be done. Each names the findings it settles, whether it needs an OpenSpec change or can be fixed directly, and whether it must stay private until it is done. You take one item, do it properly, and stop.

`scripts/review.sh work` keeps the list and what became of each item, so which item comes next is a rule and not your judgement. The reports and that record are in `build/review/` of the main checkout, which git ignores. The script finds them from any worktree and prints the run directory.

Arguments: `$ARGUMENTS`

## Rules that hold throughout

- **One work item per invocation.** Do the item, open its pull request, record it, and stop. The owner reviews and merges, then runs `/clair-fix` again.
- **The reports are private and the repository is public.** Nothing from a report goes into anything that is pushed: no finding or work item IDs, no quoted text, no severity, no account of how a weakness could be used, no mention that a review found it. A commit message, a pull request, an OpenSpec artifact and a code comment each describe what the code now does and why that is right, as they would for any change. The record of which item a pull request settles is `work.txt`, and nowhere else.
- **A report is a claim about an older commit.** `run.md` in the run directory gives the commit that was reviewed. Code has moved since, some findings are wrong, and some recommendations do not fit. Check before you change anything, and fix what is true now.
- **`CLAUDE.md` governs the work.** Branches, Conventional Commits, Changie fragments, when an OpenSpec change is required, engine builds, the checks to run before a pull request and the merge rules are all there. This skill adds nothing to them and overrides none of them.
- **Do not merge.** Merging is the owner's step unless they tell you to in this conversation.

## If an argument was given

| Argument | Do this |
|---|---|
| `status` | Bring the record up to date as under "Before anything else", print `./scripts/review.sh work`, and stop. |
| `<work id>` | Do that item now, as under "Doing a work item", whatever `next` would have chosen. If it is already merged or dropped, say so and stop. |
| `defer <id> <why>` | `./scripts/review.sh work set <id> deferred <why>`: leave the item for later. Print the list and stop. |
| `drop <id> <why>` | `./scripts/review.sh work set <id> dropped <why>`: the item will not be done. Print the list and stop. |
| `reopen <id>` | `./scripts/review.sh work set <id> open`. Print the list and stop. |

## With no argument

### Before anything else

Run `./scripts/review.sh work`. For every item in state `pr`, look the pull request up (`gh pr view <number> --json state,mergedAt`). Record a merged one with `work set <id> merged <number>`. If one was closed without merging, tell the owner and ask whether to reopen or drop the item; do not decide that yourself.

Then run `./scripts/review.sh work next` and act on its one line.

### `no-run`, `no-report`

There is no finished review to work from. Say so, and that `/clair-review` produces one. Stop.

### `no-work-items`

`REPORT.md` is complete but has no items in the format `synthesize.md` describes, most likely because it was written before that format existed. Offer to add the work items to `REPORT.md` from its findings and its order of work, following `synthesize.md`, and do it only if the owner agrees. Stop.

### `malformed <id>`

The item lacks its `- Route:` or `- Private:` line. Read the item and its findings, propose both values to the owner with a sentence of reasoning each, and after they agree, add the lines to `REPORT.md`. Stop.

### `resume <id> <state> <detail>`

An item is under way and comes before anything new.

- `started <branch>`: an earlier invocation stopped part-way. Find the branch and its worktree, read what is there, and carry on from step 4 of "Doing a work item".
- `pr <number>`: the pull request is still open. Report its checks and review state. If checks fail, fix them on the branch. Otherwise say that it waits for the owner, and stop. Start nothing else: the owner can name another item with `/clair-fix <work id>` if they want two open at once.
- `change <name>`: the item is an OpenSpec change. If its proposal is not merged yet, treat it as `pr`. If it is, the implementation is the work now: say so, and that the `openspec-apply-change` skill carries it out. When the implementation has merged and the change is archived, record `merged` with the implementation's pull request number.

### `fix <id> <route> <private>`

Do the item, as below.

### `waiting <id> on <other>`

Every item left depends on one that is deferred or handed to the owner. Print the list and say which item holds the rest up.

### `done`

Every item is merged, dropped, deferred or with the owner. Print the list. If merged fixes touched code, say that `/clair-review rebase-run` on `main` reviews again only the sections whose files changed, which is how the fixes themselves get reviewed.

## Doing a work item

1. **Read the item.** In `REPORT.md`, read the work item and the entries of the findings it names. Then read each finding in full in its section report (`<section id>-<slug>.md` in the run directory; a finding `S04-02` is in section 04) and its verdict in `verify/<section id>.md` if there is one. Do not read the rest of the reports: they are long, and the other items are not your job today.

2. **Check that it still holds.** Fetch `origin/main`. For each finding, open the cited code as it is on `origin/main`, and use `git diff <reviewed commit> origin/main -- <cited files>` to see what changed since the review. Follow the path from cause to consequence yourself, as the verifier would. Then one of:
   - It holds. Carry on.
   - It no longer holds, or never did. Record `work set <id> dropped <reason>`, giving the commit or the line that settles it, tell the owner, and stop. If only some of the item's findings fell away, carry on with the rest and say which were dropped.
   - It holds, but the recommended change is wrong, would not be enough, or is much larger than the item says. Tell the owner what you found and what you would do instead, and stop before changing anything. Record nothing: the item stays open.
   - A verifier left a finding uncertain. Settling it is the first part of the work, and the answer decides whether there is a second part.

3. **Start the branch.** Create a worktree for the item (the EnterWorktree tool) on a new branch from `origin/main`, named for what the change does, never for the item or the finding. The main checkout stays where it is: the review run lives there. Record `work set <id> started <branch>`.

4. **Do the work, by route.**

   *Direct fix.* Make the smallest change that removes the cause, not one that hides the symptom at the place the report happened to notice it. Where the report names other places with the same cause, fix those too if they are part of this item, and say so if they are not. Add the test that would have caught it, at the cheapest level that can express it: a script's `*.test.sh`, a `ClairUI` unit test against the fakes, or a runtime test only when it needs a running browser. If no test can express it, say why in the pull request.

   *OpenSpec change.* Do not write code. Use the `openspec-propose` skill to draft the change: the proposal states the behaviour or the guarantee Clair should have, and the design holds the reasoning. Phrase both as design, with nothing taken from the report's wording. The pull request carries only the proposal. Record `work set <id> change <change name>` once the name exists.

   In either route, if the fix needs a decision that is the owner's (a breaking change to `ClairHost.h` or a stored format, a behaviour users will notice, a trade-off the report left open), ask before building on a guess.

5. **Private items stop here.** For an item marked private, do not push the branch and do not open a pull request. Much of such an item is usually outside the repository: branch protection, environment secrets, runner configuration, signing keys. Finish what can be done in the worktree, then give the owner two lists: the changes waiting on the branch, and the steps only they can take, in the order to take them. Record `work set <id> owner <one line on what waits>` and stop. The owner decides when and how the branch becomes public.

   While Clair is unreleased, a public item may be fixed in the open even when it is a security fix: nobody runs the code yet. `focus.md` in the clair-review skill says where Clair stands. Once Clair has users, treat every Critical or High security item as private, whatever its line says.

6. **Check it.** Run the checks `CLAUDE.md` lists for the kind of change before pushing: the script tests and `shellcheck` for scripts, the `ClairUI` build and unit tests for Swift, `openspec validate --all --strict` for specs. Run `./scripts/engine-key.sh` and compare with `origin/main`'s: if the key changed, the pull request needs an engine build and a patch check, so tell the owner before you push, and push once with everything in it.

7. **Open the pull request and record it.** One pull request for the item. After it exists, `work set <id> pr <number>`. For a change proposal the state stays `change`.

8. **Report and stop.** Tell the owner what the item was, what you found when you checked it, what you changed, what you tested, anything you left out and why, and the pull request. That account is for the owner in this conversation only, so it may refer to the item and its findings by ID.

## When the report is wrong

Findings are checked once by a verifier and are still wrong some of the time. Dropping an item with the evidence is a good outcome. So is telling the owner that a fix belongs somewhere other than where the report pointed. What is not acceptable is a change that makes the finding's wording untrue while the weakness stays: a check added at the cited line when three other callers reach the same code, or a test that asserts the new code runs without asserting what it protects.

## Preparing a machine

The run directory is in the main checkout, so from a worktree every read of a report is outside the working directory and may prompt. To avoid that, allow the main checkout's `build/review/` by its absolute path in `.claude/settings.local.json`, in the form the clair-review skill's `SKILL.md` uses for the engine tree: `Read(//<path to the main checkout>/build/review/**)`, and the same with `Edit` for the two cases above that amend `REPORT.md`.
