# Verifying a section's findings

A reviewer has written a report on one section. Your job is to find out which of its serious findings are true. Review findings are wrong more often than their confident wording suggests, and the owner will act on these, so each one gets an independent check before it reaches the final report.

Your dispatch message names the section's report and the file to write your verdicts to.

## Which findings to check

- Every finding rated Critical or High.
- Every Medium finding whose `- Chromium:` line says `unverified`.

Leave the rest alone.

## How to check one

Start from the code, not from the report's account of it. Open the files the finding cites and read enough around the cited lines to understand them in context. Then try to refute the finding:

- Is the cited code what the report says it is, at that location?
- Does the path from cause to consequence hold at every step? Look for the guard, the null check, the earlier return, the caller that never passes that value, or the Chromium behaviour that stops it.
- Where the finding depends on Chromium, look in the engine tree at the `engine_src` path in `run.md` and settle it. This is the most common way a finding fails.
- Is the severity right for what can actually be shown, using the table in `report-format.md`?

You are checking the claim, not the reviewer's taste. A finding that is real but that you would have rated differently is confirmed, with a note on severity.

## Verdicts

Give each finding one verdict:

- **Confirmed**: you followed the path yourself and it holds.
- **Refuted**: you found the specific thing that stops it. Quote it with its file and line.
- **Uncertain**: you could neither follow the path to the end nor find what stops it. Say exactly what would settle it.

Do not confirm a finding because it sounds plausible, and do not refute one because the fix would be inconvenient. If you notice a serious problem the report missed while you are in the code, add it at the end under "Not in the report", with the same evidence a finding needs.

## What to write

```markdown
# Verification: section 03

### S03-01: Confirmed
- Severity: High, as reported | should be Medium, because ...

What you checked and what you found, with file and line.

### S03-02: Refuted

The guard at path/to/file.mm:210 returns before the cited line whenever ...

## Not in the report

(only if you found something)

Status: complete
```

End with `Status: complete` on its own line once every finding in scope has a verdict.
