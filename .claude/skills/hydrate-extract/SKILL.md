---
name: hydrate-extract
description: >
  Pull findings from a single source location. Each finding is one sentence
  about a fact, decision, convention, or contract, plus a pointer back to
  source. Deterministic for structured sources, AI semantic for prose.
---

# hydrate-extract

Input: one source location from `hydrate-discover` output.

When this skill is activated:

1. Determine extraction mode:
   - **Deterministic:** manifests (parse JSON/TOML), file structure (walk dirs), config files, conventional-commit prefixes
   - **AI semantic:** README prose, ADR bodies, PR descriptions
2. For each detected fact:
   - Identify the target file in working memory (see `hydrate-draft` mapping table)
   - Pull a one-sentence statement
   - Tag `scope`: a finding is `scope: org` exactly when it names more than one repo or a governing team outside this repo's. Everything else is `scope: repo`. A repo named twice under two names is still one repo, and this repo's own team governing it doesn't count as outside.
   - Write `scope_reason`: one line naming what triggered `org` (the second repo or the outside team), or `single repo, team-owned` for `repo`
   - Note source provenance: file path, commit hash, line range
3. Output one finding per fact as a small structured record.

## Output shape

```yaml
findings:
  - source: package.json
    target: projectOverview.md (Stack section)
    statement: 'Stack is React 18, TypeScript 5, Tailwind 3, vitest.'
    confidence: high
    scope: repo
    scope_reason: single repo, team-owned
  - source: src/api/types.ts
    target: dataContracts.md
    statement: 'User and Account interfaces define the canonical API response shapes.'
    confidence: high
    scope: repo
    scope_reason: single repo, team-owned
  - source: git log
    target: decisionLog.md
    statement: 'Migrated from Redux to Zustand on 2026-03-12 (commit a4f8e21).'
    confidence: medium
    scope: repo
    scope_reason: single repo, team-owned
  - source: docs/adr/0007-shared-auth.md
    target: decisionLog.md
    statement: "Orders, billing, and checkout services all authenticate through the platform team's gateway."
    confidence: high
    scope: org
    scope_reason: names three services and the platform team
```

## Common gotchas

- Inferring conventions from a single example. A pattern is a convention only when it shows up in multiple places.
- Treating outdated comments as current truth. Cross-check what comments claim against what the code actually does.
- Pulling debugging breadcrumbs into findings. "We had a flaky test on Tuesday" is session noise, not working memory.
