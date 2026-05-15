# Copilot Project Instructions

## Working Memory

This project maintains a two-tier working memory at `_working-memory/` for cross-session context.

- **Always read on session start:** `_working-memory/activeContext.md` (≤20 lines, local only).
- **Read on demand:** see the table under `## Working Memory` in [`AGENTS.md`](../AGENTS.md). That file is the canonical source for which working-memory file to consult for which kind of work, and the update rules.
- **To sync working memory:** run `/update-working-memory` in Copilot Chat, or invoke the `working-memory-synchronizer` custom agent.
