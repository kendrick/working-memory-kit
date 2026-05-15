# working-memory-kit

A two-tier working memory that gives AI coding agents persistent project context across sessions, without forcing them to re-learn everything on every turn.

Works with Claude Code and GitHub Copilot. Greenfield or brownfield. Installs with one command on both macOS and Windows.

## The problem

AI coding agents lose context when a session ends. Asking them to re-derive a project's conventions and constraints from raw source on every new conversation burns time and tokens, and the answers drift between sessions.

Cramming everything into a single `AGENTS.md` or `CLAUDE.md` doesn't scale either. Agents read those on session start, so every kB you add gets paid for by your context window for the rest of the session, whether the information is needed or not.

## The shape

Two tiers, both at the project root:

```
_working-memory/
├── activeContext.md       # always read on session start (ideally ≤20 lines, gitignored)
├── projectOverview.md     # read on demand
├── decisionLog.md
├── dataContracts.md
├── conventions.md
└── openQuestions.md
```

`activeContext.md` is the sticky note on the monitor: what you're working on right now, the last decision, known risks. The other five files are the filing cabinet, opened only when the agent needs them.

## Install

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/kendrick/working-memory-kit/main/init.sh | bash

# Windows PowerShell
irm https://raw.githubusercontent.com/kendrick/working-memory-kit/main/init.ps1 | iex
```

Replace `kendrick` with the GitHub org or wherever this repo is hosted.

- `_working-memory/` with the six template files plus a short `README.md` for new contributors
- `AGENTS.md` (creates one, or appends a section to your existing file). This is the canonical home for the on-demand table and update rules.
- `.claude/agents/` and `.claude/skills/` (read by both Claude Code and VS Code Copilot):
  - `working-memory-synchronizer` agent and `update-working-memory` skill — the **ongoing maintenance** surface.
  - `hydrator` agent and `hydrate-{discover,extract,draft,reconcile,propose}` skills — the **one-time onboarding** surface for brownfield installs.
- `.github/hooks/working-memory-hooks.json` and `.github/instructions/data-layer.instructions.md` if your project uses GitHub Copilot (these formats are Copilot-specific)
- `.github/copilot-instructions.md` (creates or prepends a thin pointer to `AGENTS.md`)
- `CLAUDE.md` (prepends a thin pointer to `AGENTS.md`)
- `scripts/` with cross-platform `.sh` and `.ps1` hooks
- `.working-memoryrc.example` for tuning thresholds

It also adds `_working-memory/activeContext.md` to `.gitignore`. `activeContext` is meant to be per-developer, not per-team.

## How it works

Every session starts with a read of `activeContext.md`. The session-start hook warns you if it's grown past the line limit.

The other five files load on demand. `AGENTS.md` or `.github/copilot-instructions.md` (depending on your project tooling) tell the agent which file to open for which kind of work:

- Schemas via `dataContracts.md`
- Prior decisions via `decisionLog.md`
- Project-wide patterns via `conventions.md`

After meaningful work, you (or the synchronizer agent) move completed items out of `activeContext.md` and into `decisionLog.md`. The session-end hook nudges you when the diff suggests an update is overdue, by default when you've changed 5+ files **or** 200+ lines.

Manual sync: `/update-working-memory` in either Claude Code or GitHub Copilot Chat (both invoke the shared skill at `.claude/skills/update-working-memory/SKILL.md`), or `@working-memory-synchronizer` to invoke the custom agent. From any terminal, `./scripts/update-working-memory.sh` prints the active config and current state.

## Populating working memory after install

The scaffold pre-populates stack info and a directory map. For an existing codebase, the next step is the **hydration pipeline**, which scans your code, git history, README, and any ADRs to draft proposed content for `projectOverview.md`, `decisionLog.md`, `dataContracts.md`, and `conventions.md` — staged as a commit (or PR for multi-developer projects) for human review.

The installer ships the pipeline into your repo. Two ways to run it:

- **Composite agent.** Ask your AI agent to "run the hydrator" (Claude Code) or "use the agent at `.claude/agents/hydrator.md`" (Copilot Chat). It orchestrates the five phases end-to-end.
- **Phase by phase.** Invoke the slash skills one at a time: `/hydrate-discover`, `/hydrate-extract`, `/hydrate-draft`, `/hydrate-reconcile`, `/hydrate-propose`. Useful when you want to review each phase's output before advancing.

Brand-new projects can skip hydration and edit the template files by hand. The pipeline expects a codebase to scan.

After hydration lands, the `working-memory-synchronizer` agent handles ongoing maintenance. See [`guide/ai-assisted-hydration.md`](guide/ai-assisted-hydration.md) for the full pipeline design.

## Customizing

Defaults are baked into the hook scripts. Override per team via a committed `.working-memoryrc`:

```
MAX_ACTIVE_CONTEXT_LINES=20
NUDGE_FILE_THRESHOLD=5
NUDGE_LINE_THRESHOLD=200
```

… or per developer via env vars: `WORKING_MEMORY_MAX_LINES`, `WORKING_MEMORY_FILE_THRESHOLD`, `WORKING_MEMORY_LINE_THRESHOLD`. **Environment variables override the file, and the file overrides the built-in defaults.**

Two named presets ship in `.working-memoryrc.example`:

- **strict** (15 / 3 / 100): early-stage projects iterating on architecture.
- **loose** (40 / 10 / 500): mature codebases with mostly incremental work.

## Why these defaults

Twenty lines is the cap because past that, `activeContext.md` has stopped being a queue and could have started being an archive. The point of the file is to be cheap to read and cheap to refresh. If your current focus needs more than twenty lines to describe, working memory itself may be doing the wrong job.

Five files **or** two hundred lines for the nudge because the two signals catch different sessions: lots of small touches (you spread changes across the surface area) versus one big diff (you refactored). Either way, working memory usually needs to know.

`activeContext.md` is gitignored because two devs on the same team rarely have the same active context, and committing it creates a permanent merge-conflict factory on the file you update most often.

## Compatibility

The kit puts shared artifacts at the one canonical location both tools natively read. Claude Code and VS Code Copilot both read `.claude/agents/working-memory-synchronizer.md` and `.claude/skills/update-working-memory/SKILL.md`. Copilot-only formats stay under `.github/`: hooks at `.github/hooks/working-memory-hooks.json` (VS Code schema), and path-scoped instructions at `.github/instructions/*.instructions.md`. Any agent that respects `AGENTS.md` will pick up the on-demand table.

The hooks JSON uses VS Code's schema (`SessionStart` / `Stop`, `command` with a `windows` override, `timeout`) since `.github/hooks/*.json` is a VS Code workspace path. GitHub Copilot Cloud Agent uses a different hooks schema; if you need both, you'll need a second hook file.

### Invoking agents

Both tools _read_ the agent files at `.claude/agents/`, but the _invocation patterns_ differ. Knowing this saves a "why doesn't `@hydrator` autocomplete?" moment:

| Tool                 | How to invoke a custom agent                                                                                                                                                                                                                            |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Claude Code          | Ask in chat ("run the hydrator", "use the working-memory-synchronizer"), use the `/agents` command if your build surfaces one, or invoke via the Agent tool in scripts. `@` is for file references, not agent mentions.                                 |
| VS Code Copilot Chat | Reference the agent file by path ("use the agent at `.claude/agents/hydrator.md`") and Copilot will read and follow it. `@` autocompletes Copilot-registered chat participants only (`@workspace`, `@terminal`, etc.) — not files in `.claude/agents/`. |

Slash skills (`/update-working-memory`, `/hydrate-discover`) are the most portable invocation surface — both tools surface them via the slash menu once the SKILL.md is in place.

## Updating the kit

Re-run the installer; it will prompt before overwriting individual files. Section merges into `AGENTS.md`, `CLAUDE.md`, and `.github/copilot-instructions.md` use a `## Working Memory` marker check, so re-runs will be idempotent unless you've renamed the heading.

## Repository layout

```
working-memory-kit/
├── init.sh                  # macOS/Linux installer
├── init.ps1                 # Windows installer
├── scaffold-prompt.md       # Standalone prompt you can hand to any agent
├── CLAUDE.md                # Kit-level agent context (also auto-loaded by VS Code Copilot)
├── guide/                   # Practitioner-facing guides
│   └── ai-assisted-hydration.md  # Five-phase pipeline for deeper content extraction
├── .claude/
│   ├── agents/hydrator.md   # Composite agent orchestrating the 5 hydration skills
│   └── skills/              # Hydration reference skills (read natively by both tools)
│       └── hydrate-{discover,extract,draft,reconcile,propose}/
├── .github/
│   └── copilot-instructions.md  # Thin pointer to CLAUDE.md
├── examples/
│   └── hydration-demo/      # Synthesized codebase for demoing the pipeline
├── template/                # Files copied into the consumer's project
│   ├── _working-memory/
│   ├── AGENTS.md
│   ├── .claude/{agents,skills}/
│   ├── .github/{copilot-instructions.md,hooks,instructions}/
│   ├── scripts/
│   └── .working-memoryrc.example
└── README.md
```

## License

MIT.
