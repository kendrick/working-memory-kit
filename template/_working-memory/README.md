# `_working-memory/`

A two-tier working memory for this project. AI coding agents read these files for project context, and so should you — `decisionLog.md`, `conventions.md`, and `antipatterns.md` in particular are first-class onboarding material for human contributors.

## What's here

| File                       | What it holds                                                                                                          |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `activeContext.md`         | Current focus, last decision, known risks. ≤20 lines. **Local-only — gitignored.** Each developer maintains their own. |
| `activeContext.example.md` | Starter content for new contributors to copy into `activeContext.md`.                                                  |
| `projectOverview.md`       | What this project is, its stack, repo layout, and constraints. Stable over weeks.                                      |
| `decisionLog.md`           | Append-only log of architectural and scoping decisions. Most recent first.                                             |
| `dataContracts.md`         | Canonical shapes for data flowing through the application — either pointer-to-types, schema sketch, or prose.          |
| `conventions.md`           | "How we do things here" — naming, file layout, error handling, anything pattern-shaped.                                |
| `openQuestions.md`         | Unresolved ambiguity. Check here before guessing; answers move into `decisionLog.md` when resolved.                    |
| `antipatterns.md`          | Things the team tried that didn't work. Append-only. Agents must check before proposing refactors or library swaps.    |

## When to update each file

- After completing a feature or making a meaningful decision, update `activeContext.md` and the relevant on-demand file.
- `activeContext.md` is a queue, not an archive. Evict completed items to `decisionLog.md` so the file stays under twenty lines.
- `decisionLog.md` and `antipatterns.md` are append-only. Never edit past entries — add a new entry that supersedes the old one.
- `projectOverview.md`, `dataContracts.md`, and `conventions.md` update when the project's _shape_ changes (new layer, new type, new pattern), not on every feature.

Agents follow the same rules. The full on-demand table lives in [`../AGENTS.md`](../AGENTS.md).

## For new contributors

After cloning this repo, copy the example file into your local one:

```bash
cp _working-memory/activeContext.example.md _working-memory/activeContext.md
```

`activeContext.md` is gitignored because two developers on the same team rarely have the same active context, and committing it makes the file a permanent merge-conflict factory.

## Editing by hand vs. invoking an agent

Both work. Edit directly when you know exactly what to add. Run `/update-working-memory` (or invoke the `working-memory-synchronizer` agent) when you want help proposing diffs based on recent git changes.

For a one-time deeper hydration of an existing codebase — scanning code, git history, README, and ADRs to populate the files end-to-end — invoke the `hydrator` agent. That's the recommended starting move on brownfield installs.

## Working alongside spec-driven tooling

If this project also runs a spec-driven process tool (Spec Kit, OpenSpec, Kiro, BMAD, Agent OS, Task Master), the two layers divide cleanly. That tool owns the per-feature verbs (constitution, specs, plans, tasks); working memory owns the durable, cross-feature project state. The installer detects a neighbor and prints a who-owns-what map; this is the boundary it encodes:

| Concern | Lives in |
|---|---|
| Inviolable principles | the neighbor's principles file (constitution / project.md / steering / standards) |
| Tactical "how we code" | `conventions.md`, which points at the principles file and never restates it |
| A feature's what and how | the neighbor's per-feature specs and plans |
| Cross-feature decisions | `decisionLog.md`; per-feature rationale stays in the neighbor's plan, promoted up as a one-line pointer when it's cross-cutting |
| Canonical data contracts | `dataContracts.md`, pointing at the neighbor's data model rather than duplicating it |
| Current focus | `activeContext.md` |
| Agent entry point | `AGENTS.md`; the kit's section is fenced, the neighbor keeps its own dirs |

Altitude rule: the principles file states a principle; `conventions.md` encodes the concrete pattern that honors it. They nest, they don't duplicate.

The kit's section in `AGENTS.md` (and in `CLAUDE.md` / `.github/copilot-instructions.md`) is wrapped in `<!-- working-memory:start -->` / `<!-- working-memory:end -->` markers, so a re-install refreshes only that span and never touches the neighbor's content. When a cross-cutting decision gets made inside a per-feature plan, promote it up into `decisionLog.md` with a one-line entry that points back down.

These boundaries are a convention this kit documents, not a rule it enforces. The kit labels the lanes; keeping to them is on you and your agents.

A second durable-memory system (such as Cline/Roo Memory Bank) is a different case. Two memory systems overlap, and the kit won't auto-merge them; pick one as canonical or consolidate.
