---
name: update-working-memory
description: >
  Reads the current working memory state, diffs it against recent git changes,
  and proposes updates. Use when finishing a feature, resolving a decision,
  or when active context feels stale.
---

# Update Working Memory

When this skill is activated, perform the following:

1. Read `_working-memory/activeContext.md` (local, may not exist yet — if missing, create from `activeContext.example.md`).
2. Read all other files in `_working-memory/`.
3. Run `git diff --stat HEAD~5` to identify recent changes.
4. For each working memory file, determine if anything is stale or missing.
5. Enforce the 20-line hard limit on `activeContext.md` — evict completed items to `decisionLog.md`.
6. Propose all changes as a batch, grouped by file, and wait for confirmation before writing.

## File rules

| File | Update policy |
|---|---|
| `activeContext.md` | Queue, not archive. Evict completed items. ≤20 lines. |
| `decisionLog.md` | Append only. Never edit a past entry's body. To mark an entry superseded, add `status: superseded` and `superseded_by:` lines directly under its heading. Most recent at top. |
| `projectOverview.md` | Update only when project shape changes (stack, structure). |
| `dataContracts.md` | Update when interfaces, schemas, or API shapes change. |
| `conventions.md` | Update when a new pattern emerges or an old one is deprecated. |
| `openQuestions.md` | Remove answered questions (move answers to decision log). |
| `antipatterns.md` | Append only. Never edit a past entry's body. To mark an entry superseded, add `status: superseded` and `superseded_by:` lines directly under its heading. Add an entry when an approach was tried and abandoned; include a specific "Don't suggest" line so future agents avoid re-proposing it. |

## Entry headings

Start each entry in `decisionLog.md` and `antipatterns.md` with `## YYYY-MM-DD: Title`: ISO date, colon, space, title, no brackets. For example, `## 2026-10-01: Cap retries at three per request`. `ltm promote --entry` (from the [long-term-memory-kit](https://github.com/kendrick/long-term-memory-kit)) matches a bare title only on this shape.

## Superseding an Entry

When a new entry replaces an old one in `decisionLog.md` or `antipatterns.md`, follow these steps in order.

1. Check the old entry for a `promoted_to:` line in any of its forms: `promoted_to:`, `- promoted_to:`, or `**promoted_to:**`. If the old entry has one, leave it alone. Write the new entry, then tell the user that the old one lives in the Bank under that Record id and changes only through a Bank PR.
2. Otherwise, write the new entry on top. In the old entry, set `status: superseded`, replacing any `status:` line already under the heading. Then add `superseded_by:` followed by the new entry's full heading, without the leading `## `.
3. If the new entry is in the other log, name that file in the proposal to the user.

Put both lines directly under the old heading as plain `key: value` lines, with no bold, no bullets, and no blank line above them. When a blank line already follows the heading, insert the lines between the heading and that blank line, which then separates them from the body. Leave the body as it is. An entry with no `status:` line reads as `accepted`.

```markdown
## 2026-10-01: Cap retries at three per request
status: superseded
superseded_by: 2026-11-02: Cap retries at five for idempotent calls

**Decision:** Three attempts per request, then fail.
```
