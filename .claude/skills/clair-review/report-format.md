# Section report format

Every section report has the same parts in the same order. The verifier and the synthesis pass rely on the layout, and `scripts/review.sh` reads three things from it literally: the finding headings, the `- Chromium:` line of each finding, and the final `Status: complete` line.

## Template

```markdown
# Section 03: extensions

- Commit: <the commit from run.md>
- Files read in full: <count>
- Files read in part or not at all: <list each with the reason, or "none">

## Summary

Three to six sentences: the state of this section, and the one or two things the owner most needs to know.

## Findings

### S03-01 [High] Short title that states the problem
- Category: security | architecture | quality | spec drift | test gap
- Where: path/to/file.mm:120-148
- Chromium: verified at chrome/browser/extensions/foo.cc:88 | unverified | none
- Confidence: high | medium | low
- Effort: small | medium | large
- Breaking: no | data format | ClairHost.h | both

What is wrong and how it comes about, with the code that matters quoted. Then
the consequence: who can trigger it, and what they gain or what breaks.

**Recommendation:** what to change, concretely.

## Architecture notes

How this section is built: its modules and what each is responsible for, which
object owns which state, what it depends on and what depends on it, and the
part of the ClairHost.h contract it uses. Say what is sound as well as what is
not. The synthesis pass builds the system overview from these notes.

## Spec drift

Code that contradicts a spec, behaviour no spec covers, and spec requirements
with no code behind them. Name the spec and the requirement.

## Forward look

Answers to the questions in focus.md that concern this section.

## Questions for other sections

Things you could not settle because the answer lies in another section's
files. Name the section and ask a question it could answer.

## Freeze list

Anything in this section that becomes expensive to change once people have
installed Clair, and whether it is in a state worth keeping.

## Limits

What you did not cover and why.

Status: complete
```

## Rules the script depends on

- A finding heading is `### S<section>-<number> [<Severity>] <title>`, with the severity spelled exactly Critical, High, Medium, Low or Info.
- Each finding has one `- Chromium:` line. Write `unverified` when the finding depends on Chromium behaviour you could not confirm in the engine tree, and `none` when it does not depend on Chromium at all.
- `Status: complete` is the last line, on its own, and appears only when the report covers the whole brief.

## Severity

Clair is a browser, so severity follows what an attacker or a failure can reach.

| Severity | Meaning |
|---|---|
| Critical | Web content, an extension or a network attacker can run code outside the sandbox, cross a profile or incognito boundary, alter or replace an update, or reach credentials and release secrets. |
| High | A security boundary holds only by luck or by an undocumented assumption; user data can be lost or corrupted; a design flaw that the planned features would build on and that gets much harder to fix after release. |
| Medium | A real defect or design weakness with limited reach: a crash, a leak, a spoofable surface that needs unusual conditions, a contract that invites misuse. |
| Low | A local quality problem: duplication, unclear ownership, a missing test, a misleading name. |
| Info | Worth knowing, with nothing to fix. |

Rate what you can show. If the worst case depends on something you could not verify, rate the part you can show and say what would raise it.

A weakened mitigation and a slow path for engine fixes have no exploit of their own to show. Rate them by what they turn the next Chromium bug into. High: a layer that contains a compromised renderer is off or can be bypassed (the sandbox, site isolation, the V8 sandbox), or nothing ensures that a published engine fix reaches users. Medium: a mitigation that makes exploitation harder is off, or a source of security data is stale or gone. Low: the build matches stock Chrome but nothing records the decision or would catch a regression.
