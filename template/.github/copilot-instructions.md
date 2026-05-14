# Copilot Project Instructions

## Working Memory

This project maintains a two-tier working memory at `working-memory/` for cross-session context.

### Always read on session start:
- `working-memory/activeContext.md` — Current focus, last decision, known risks (≤20 lines, local only)

### Read on demand:
| File | Read when... |
|---|---|
| `projectOverview.md` | Starting a new feature or onboarding |
| `decisionLog.md` | Making an architectural or scoping decision |
| `dataContracts.md` | Creating or modifying data-consuming components |
| `conventions.md` | Writing new code or reviewing patterns |
| `openQuestions.md` | Encountering ambiguity — check here before guessing |

### Updating working memory:
- After completing a feature or making a significant decision, update `activeContext.md` and the relevant on-demand file.
- `activeContext.md` is a queue: evict completed items to `decisionLog.md`.
- Never let `activeContext.md` exceed 20 lines.
- Type `/update-working-memory` in Copilot Chat (or invoke the `working-memory-synchronizer` custom agent) to trigger a full sync.
