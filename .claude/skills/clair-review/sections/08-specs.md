# Section 08: specs and decisions

## What this section is

Clair is planned as OpenSpec changes. `openspec/specs/` holds the living specs, one directory per capability, which describe what the app must do. `openspec/changes/` holds changes still open, and `openspec/changes/archive/` holds finished ones, whose delta specs were synced into the living specs when they were archived. `CLAUDE.md` and `docs/` carry the working rules.

Every future feature is written against these documents, by people and by models, so a contradiction or a gap here turns into a wrong implementation later. The code sections check whether the code matches the specs. This section checks whether the specs are sound in themselves.

## What to read

- Every living spec, in full.
- Each open change: `proposal.md`, `design.md` and its delta specs.
- For each archived change, `proposal.md` and `design.md` only. The archive is history, so do not review it for quality or suggest rewriting it. Read it for decisions.
- `CLAUDE.md`, `openspec/config.yaml` and `docs/`.

CI already runs `openspec validate --all --strict`, so the structure is valid. Spend the time on meaning.

## What to establish

**Consistency across the living specs**
- Requirements in different capabilities that contradict each other, or that describe the same behaviour in two places with different details. Quote both.
- Terms used with more than one meaning, and one concept under more than one name (Space, profile, window, tab, page card, peek and so on). Propose a glossary where it would help.
- Cross-references that point at a requirement that was renamed, moved or removed.
- Capabilities whose boundaries have blurred: requirements that sit in one spec and belong in another.

**Quality of the requirements**
- Requirements that cannot be tested as written: no observable outcome, or wording such as "as in Arc" with nothing saying what Arc does.
- Scenarios that only restate their requirement, and requirements with no scenario for the failure or edge case that matters.
- Requirements that describe an implementation rather than behaviour, which will go stale when the code changes.
- Security-relevant behaviour that no spec states: what a profile isolates, what an update must verify, what the address display must never show.

**Decisions that live only in the archive**
- `CLAUDE.md` says the archived first change holds the product decisions, the roadmap and the MVP feature list, and it cites design decisions by number. Find the decisions in archived proposals and designs that are still in force and are recorded nowhere else. List each with its source, and say where it should live so a reader of the living documents finds it.
- Find archived decisions that a later change overturned without saying so, and places where the archive and the living specs now disagree.
- Check the roadmap and the MVP list against what has shipped. What remains, and is anything on it now contradicted by a spec?

**The working rules**
- Does `CLAUDE.md` still describe the repository and the process accurately? Flag instructions that the specs, the docs or each other contradict.
- Are the open changes consistent with the living specs they modify, or have the specs moved since they were written?

**Readiness for the next two features**

Answer the questions in `focus.md` from the specification side. For link rules and for pinned favourites and tabs, list the questions their proposals will have to settle because the current specs are silent or ambiguous, naming the capability and requirement each one touches. `spaces`, `profiles`, `sidebar` and `command-bar` are the likely places.

## Reporting

Use the standard format. Give findings a `- Where:` that names the spec file and the requirement, and write `- Chromium: none`. Under "Architecture notes", describe how the capabilities fit together and which ones carry the most cross-references.
