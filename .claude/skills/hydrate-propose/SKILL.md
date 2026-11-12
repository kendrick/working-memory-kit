---
name: hydrate-propose
description: >
  Stage reconciled drafts as a single commit (or PR for multi-developer projects)
  that updates the working memory files in a reviewable batch. activeContext.md
  is excluded. After acceptance, the synchronizer agent takes over for ongoing
  maintenance.
---

# hydrate-propose

Input: annotated drafts from `hydrate-reconcile`.

When this skill is activated:

1. Group drafts by target file. One commit (or PR) updates multiple working memory files in a coherent batch.
2. Write the proposed changes to each file:
   - Append-only updates to `decisionLog.md` (most recent at top)
   - Section updates in `projectOverview.md`, `conventions.md`, `dataContracts.md`
   - New entries in `openQuestions.md`
   - **Skip `activeContext.md`** entirely
3. Handle `scope: org` findings, which `hydrate-draft` and `hydrate-reconcile` passed through unchanged. If none arrived, say nothing about org memory.
   - With `.ltm.yaml` at the repo root, list them under an "Org memory candidates" heading in your output. Print one command per finding and don't run it. Print each in two blocks, one labeled `bash/zsh` and one labeled `PowerShell`, because the shells quote differently. Both use the same shape, `ltm propose --type <Decision|PolicyRule|Exception|Context> --title '<title>' --summary '<statement>' --source-ref '<source>' --body-file '<body-file>'`. `.ltm.yaml` is the only Bank signal; `ltm` on PATH doesn't count.
   - Write a body file per finding, holding its statement, source, and scope_reason, in a temp directory outside the repo (for example from `mktemp -d`). Never stage it with the working-memory batch, and print its path with the commands. Name it in `--body-file`.
   - `--title` is a short title taken from the statement.
   - Pick `--type` from the finding. A choice is a Decision, and a rule someone must follow is a PolicyRule. A bounded departure from a PolicyRule is an Exception. Background that agents need but that is neither a choice nor a rule is Context. Leave out `--applies-to`; the user adds it.
   - Single-quote every value in both blocks, so `$(…)` stays inert. Quote an embedded `'` by shell:
     - bash/zsh writes it as `'\''`.
     - PowerShell writes it as `''`.
   - Long text goes in the body file. So does any text with a `"`: keep `"` out of `--title` and `--summary` where you can, because Windows PowerShell 5.1 and pwsh 7.2 and earlier mangle an embedded `"` passed to a native program.
   - Without `.ltm.yaml`, add each one to `openQuestions.md` as an entry, "May belong in org memory: <statement> (source: <source>; <scope_reason>)", in the same staged batch. Skip a finding whose "May belong in org memory" line is already in `openQuestions.md`, so a second run doesn't duplicate it.
4. Write the proposed commit message: a one-line summary plus a body that lists each draft and its source provenance.
5. For solo or small-team repos: stage the commit and leave it for the developer to review and commit.
6. For multi-developer repos: open a PR. Tag reviewers based on CODEOWNERS or recent committers to the relevant files.

## Output

A staged commit (or open PR), with all drafts applied and a clear commit message.

## What this skill does NOT do

- It does not auto-commit. Solo flow: changes are staged for review. Team flow: PR awaits review.
- It does not run `ltm propose` or write into a Bank. It prints the commands and stops.
- It does not touch `activeContext.md`. That file is per-developer and gitignored.
- It does not run the synchronizer agent. Synchronization is ongoing maintenance; hydration is the deeper periodic job. Different cadences.

## Common gotchas

- Rewriting `decisionLog.md` instead of appending. The decision log is append-only; never edit past entries.
- Forgetting source provenance in the commit body. Reviewers use provenance to trust the drafts.
- Including `activeContext.md` in the proposed commit. It's gitignored and per-developer; never propose changes to it.
