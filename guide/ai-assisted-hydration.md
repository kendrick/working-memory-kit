---
status: v0 draft
last_updated: 2026-05-08
---

# AI-Assisted Hydration

The [scaffold prompt](../scaffold-prompt.md) installs the working memory structure and pre-populates the easy parts (stack, build commands, repository structure). This page covers the deeper job: scanning the codebase, recent git history, and existing project docs to fill the working memory with content an agent will actually use across sessions.

The shape is five phases, run as a sequence of skills or as one combined agent depending on tooling. Each phase has a clear input and output; human review sits at the propose step before any working memory file is written.

## Where AI Helps, and Where It Doesn't

AI is good at:

- Scanning a codebase to extract stack, conventions, and data contracts
- Reading recent commits and PRs to identify decisions worth logging
- Drafting concise project-overview prose from a mix of READMEs, manifests, and code structure
- Flagging contradictions between extracted convention drafts and what the code actually does

AI should not:

- Write `activeContext.md` for you. That file is per-developer, in-the-moment, and gitignored.
- Promote working memory notes into a memory bank without human review. See the parallel page in `memory-bank/guide/ai-assisted-hydration.md` for the receiving side.
- Decide what stays in working memory versus what's just session noise. Working memory holds project-durable items; debugging breadcrumbs belong in commit messages, not here.

## The Pipeline

Five phases. The memory-bank kit's last phase (verify) doesn't apply here; working memory isn't retrieval-funnel-shaped, since the six files are read on-demand by `AGENTS.md` guidance rather than filtered by frontmatter.

| Phase | Input | Output |
| --- | --- | --- |
| **1. discover** | Repo state | Inventory of source locations: codebase files, manifests, README, ADRs folder if present, recent git history |
| **2. extract** | A specific source location | Raw findings, one per detected fact, decision, convention, or contract |
| **3. draft** | Raw findings | Filled sections of the six working memory files |
| **4. reconcile** | Drafts + existing working memory state | Annotated: net-new, would-overwrite, conflicts-with-code |
| **5. propose** | Reconciled drafts | Staged commit, or PR for multi-developer projects, for human review |

Reference skills live in [`skills/`](../skills/). Each is a single `SKILL.md` invocable as a Copilot skill. Adapt to Claude Code agent definitions or your tool's equivalent as needed.

### 1. discover

Inventory the source surface in this repo. Typical sources:

- **Manifests** (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`): stack
- **Code structure** (`src/`, `app/`, `lib/`): repository structure for `projectOverview.md`
- **README and docs**: prose project description for the "What This Is" section of `projectOverview.md`
- **ADRs folder if present**: structured decisions for `decisionLog.md` candidates
- **Recent git history** (`git log -50`): recent decisions, recurring patterns, gotchas
- **Code patterns** (type definitions, common imports, file naming): `conventions.md` and `dataContracts.md` candidates

The discover output is a list of source locations the rest of the pipeline targets. The existing scaffold prompt covers manifests and code structure; this guide adds the deeper sources.

### 2. extract

Pull findings from each source. Use deterministic parsing where possible (manifests, file structure, conventional-commit prefixes). Use AI semantic analysis where the source is prose (README, ADRs, transcripts, PR descriptions).

A finding is small: one sentence per detected fact, plus a pointer back to the source. Findings are not ready-to-write working memory yet; phase 3 shapes them.

### 3. draft

Map findings into the six-file template:

| Finding type | Lands in |
| --- | --- |
| Stack, framework, language, deployment | `projectOverview.md` (Stack section) |
| Repository structure, monorepo rules, off-limits areas | `projectOverview.md` (Repository Structure, Key Constraints) |
| Decisions made (with context) | `decisionLog.md` |
| Recurring patterns: naming, file organization, error handling | `conventions.md` |
| Type definitions, API shapes, schemas | `dataContracts.md` |
| Unresolved questions about the project's intent | `openQuestions.md` |

Drafts include the source as inline reference: a `decisionLog.md` entry citing the commit hash or ADR file it came from. Provenance keeps the working memory honest as the codebase evolves.

### 4. reconcile

Compare drafts against any existing working memory. For brownfield projects with prior working memory, annotate each draft as:

- **Net new.** No matching content; safe to add.
- **Would overwrite.** Existing content covers the same territory; surface the diff for review.
- **Conflicts with code.** The draft asserts something the codebase contradicts. Investigation needed before either side wins.

For greenfield projects, reconcile is trivial: every draft is net-new.

### 5. propose

Surface drafts for human review. Standard mechanism: a single commit (or PR for multi-developer projects) that updates the relevant working memory files in a reviewable batch. `activeContext.md` is excluded; the developer drives that file by hand.

After acceptance, the synchronizer agent (`@working-memory-synchronizer` in Claude Code, `/update-working-memory` in Copilot) takes over for ongoing maintenance. Hydration is the one-shot or periodic deeper job; synchronization is the continuous sweep.

## The Bridge to Memory Bank

Some working memory notes graduate into a memory bank as Decision, PolicyRule, Exception, or Context records. The signal is recurrence: a note that solves a problem you've solved on more than one project, or that recurs across teams, has earned promotion.

The promotion pipeline runs the memory-bank kit's hydration phases 2–5 with the working memory file as the source. The receiving side (how the bank governs incoming candidates) lives in `memory-bank/guide/ai-assisted-hydration.md`.

The producing side: a periodic scan of working memory across projects, led by an architect, scrum master, or the project itself, flags candidates. The friction is the feature; promotion has to earn its way in, and the human gate at propose is what keeps the memory bank's signal-to-noise high.

## What This Page Does Not Do

- It does not replace [scaffold-prompt.md](../scaffold-prompt.md). That prompt installs the structure and the easy stack-detection pre-population. This page covers the deeper content extraction.
- It does not auto-write working memory files. Every phase ends with a human-reviewable artifact.
- It does not specify per-tool integration details. Those live in `skills/`, one `SKILL.md` per phase, plus the existing Claude Code and Copilot agent definitions in `template/`.

## See Also

- [scaffold-prompt.md](../scaffold-prompt.md) for the structural bootstrap
- [README.md](../README.md) for the kit overview
- The parallel `ai-assisted-hydration.md` in `memory-bank/` (Layer 2 hydration; receiving side of the bridge)
