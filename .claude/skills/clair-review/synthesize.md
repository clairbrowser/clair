# Writing the final report

Every section has been reviewed and the serious findings have been checked. Your job is to turn the section reports into one document the owner can act on. You are the only reader who sees all of them, so the value you add is what no single section could see: patterns that repeat across sections, findings that combine into something worse, questions one section asked that another section's report answers, and the overall shape of the system.

## What to read

- `run.md`, then every section report in the run directory and every file in `verify/`.
- `native/ClairHost.h`, `CLAUDE.md`, `docs/` and the index of `openspec/specs`, so the overview rests on the sources and not only on the reports.
- `focus.md`, for the questions this run set out to answer, and `upstream.txt` in the run directory, for the engine's age.

A section that was skipped has a `<id>.skipped` file and no report. Say so in the report's limits rather than writing around the gap.

Go back to the code whenever the reports leave something open. In particular:

- Each report ends with questions for other sections. Answer them, from the other reports where you can and from the code where you cannot.
- Where a verifier refuted a Critical or High finding, read both arguments and the code, and decide. Say which way you decided and why.
- Where two sections describe the same code differently, find out which is right.

## What to write

Write `REPORT.md` in the run directory. Lead each part with its conclusion.

1. **Summary.** Half a page: the state of the codebase, the few things that matter most, and what to do first. A reader who stops here should know the outcome.
2. **Architecture overview.** How Clair is built: the engine, the overlay, the contract and `ClairUI`; who owns which state; how a change travels from Chromium to the screen and from a click back to Chromium. Include a diagram as a Mermaid block if it clarifies the structure. Then say what is sound, what is strained, and where the design will not carry the next features.
3. **Findings.** Confirmed findings ranked by severity and then by how much depends on them, each with its ID, a one-paragraph statement, the evidence in brief, and the recommendation. Merge duplicates across sections and note which IDs you merged. List uncertain findings separately with what would settle each. List refuted ones in a short table so nobody re-raises them.
4. **Themes.** Problems that appear in several sections and share a cause. A theme is worth more to fix than its instances.
5. **Spec health.** The state of the living specs, the drift between specs and code that the sections found, and the decisions that live only in the archive.
6. **Security posture against stock Chromium.** What a user gives up, in protection, by running Clair instead of Chrome. Start with section 09's table of mitigations, then what was dropped knowingly, what was dropped by accident, and the surface Clair's own code adds for a compromised renderer or an extension, drawn from every section. End with patch lag from section 04: how old the reviewed engine is, the shortest and the realistic time from a Chromium fix to an installed copy, and what the delay hangs on.
7. **Readiness for the next features.** The answers to `focus.md`, combined across sections: for each feature it names, what exists to build on, what has to change first, and the profile-isolation guarantees as they stand today.
8. **Pre-release freeze list.** Everything that becomes expensive to change once Clair is installed, with a verdict on each: keep, or change before release.
9. **Test suite cost.** Where the runtime suite's time goes and the ranked options for cutting it.
10. **Recommended order of work.** A sequence the owner could follow. For each item say whether `CLAUDE.md`'s rule requires an OpenSpec change (new behaviour, a breaking contract or data-format change, an architecture or security change) or whether it can be fixed directly. Put anything touching release secrets or the CI runner first, and mark it as something to fix privately before any public issue or pull request mentions it, because the repository is public.
11. **Limits.** What the review did not cover, including skipped sections and anything left unverified.

Keep the IDs from the section reports so every statement can be traced back. Do not soften findings to make the summary read well, and do not raise a severity beyond what the evidence and the verifier support.

End with `Status: complete` on its own line.
