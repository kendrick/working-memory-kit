# memory-bank-kit

A two-tier memory bank that gives AI coding agents persistent project context across sessions, without forcing them to re-learn everything on every turn.

Works with Claude Code and GitHub Copilot. Greenfield or brownfield. Installs with one command on both macOS and Windows.

## The problem

AI coding agents lose context when a session ends. Asking them to re-derive your project's conventions, decisions, and constraints from raw source on every new conversation takes time, wastes tokens and produces inconsistent answers.

Cramming everything into a single `AGENTS.md` or `CLAUDE.md` doesn't scale either. Agents read those on session start, so every kB you add gets paid for by your context window for the rest of the session, whether the information is needed or not.

## The shape

Two tiers, both at the project root:

```
memory-bank/
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
curl -fsSL https://raw.githubusercontent.com/kendrick/memory-bank-kit/main/init.sh | bash

# Windows PowerShell
irm https://raw.githubusercontent.com/kendrick/memory-bank-kit/main/init.ps1 | iex
```

Replace `kendrick` with the GitHub org or wherever this repo is hosted.

The installer **detects your stack, prompts before overwriting anything, and drops the following** into your project:

- `memory-bank/` with six templates
- `AGENTS.md` (creates one, or appends a section to your existing file)
- `.claude/agents/memory-bank-synchronizer.md` if your project uses Claude Code
- `.github/agents/`, `skills/`, `hooks/`, `instructions/` if your project uses GitHub Copilot
- `.github/copilot-instructions.md` (creates or appends)
- `scripts/` with cross-platform `.sh` and `.ps1` hooks
- `.memory-bankrc.example` for tuning thresholds

It also adds `memory-bank/activeContext.md` to `.gitignore`. `activeContext` is meant to be per-developer, not per-team.

Prefer not to install via curl-pipe? Clone the repo and run `./init.sh` from inside your project directory, or use `npx degit kendrick/memory-bank-kit/template` to drop the template files in directly without the interactive installer.

## How it works

Every session starts with a read of `activeContext.md`. The session-start hook warns you if it's grown past the line limit.

The other five files load on demand. `AGENTS.md` or `.github/copilot-instructions.md` (depending on your project tooling) tell the agent which file to open for which kind of work:

- Schemas via `dataContracts.md`
- Prior decisions via `decisionLog.md`
- Project-wide patterns via `conventions.md`

After meaningful work, you (or the synchronizer agent) move completed items out of `activeContext.md` and into `decisionLog.md`. The session-end hook nudges you when the diff suggests an update is overdue, by default when you've changed 5+ files **or** 200+ lines.

Manual sync: `@memory-bank-synchronizer` in Claude Code, or `/update-memory-bank` in GitHub Copilot. Or run `./scripts/update-memory-bank.sh` from any terminal to see the active config and current bank state.

## Customizing

Defaults are baked into the hook scripts. Override per team via a committed `.memory-bankrc`:

```
MAX_ACTIVE_CONTEXT_LINES=20
NUDGE_FILE_THRESHOLD=5
NUDGE_LINE_THRESHOLD=200
```

… or per developer via env vars: `MEMORY_BANK_MAX_LINES`, `MEMORY_BANK_FILE_THRESHOLD`, `MEMORY_BANK_LINE_THRESHOLD`. **Environment variables override the file, and the file overrides the built-in defaults.**

Two named presets ship in `.memory-bankrc.example`:

- **strict** (15 / 3 / 100): early-stage projects iterating on architecture.
- **loose** (40 / 10 / 500): mature codebases with mostly incremental work.

## Why these defaults

Twenty lines is the cap because past that, `activeContext.md` has stopped being a queue and could have started being an archive. The point of the file is to be cheap to read and cheap to refresh. If your current focus needs more than twenty lines to describe, the bank itself may be doing the wrong job.

Five files **or** two hundred lines for the nudge because the two signals catch different sessions: lots of small touches (you spread changes across the surface area) versus one big diff (you refactored). Either way, the bank usually needs to know.

`activeContext.md` is gitignored because two devs on the same team rarely have the same active context, and committing it creates a permanent merge-conflict factory on the file you update most often.

## Compatibility

The kit ships separate configs for each tool so they don't conflict. Claude Code reads `.claude/agents/memory-bank-synchronizer.md` and `CLAUDE.md`; GitHub Copilot in VS Code reads `.github/agents/memory-bank-synchronizer.agent.md`, the skill at `.github/skills/update-memory-bank/`, and hooks at `.github/hooks/memory-bank-hooks.json` (VS Code schema). Any agent that respects `AGENTS.md` will pick up the on-demand table.

The hooks JSON uses VS Code's schema (`SessionStart` / `Stop`, `command` with a `windows` override, `timeout`) since `.github/hooks/*.json` is a VS Code workspace path. GitHub Copilot Cloud Agent uses a different hooks schema; if you need both, you'll need a second hook file.

## Updating the kit

Re-run the installer; it will prompt before overwriting individual files. Section merges into `AGENTS.md`, `CLAUDE.md`, and `.github/copilot-instructions.md` use a `## Memory Bank` marker check, so re-runs will be idempotent unless you've renamed the heading.

## Repository layout

```
memory-bank-kit/
├── init.sh                  # macOS/Linux installer
├── init.ps1                 # Windows installer
├── scaffold-prompt.md       # Standalone prompt you can hand to any agent
├── template/                # Files copied into the consumer's project
│   ├── memory-bank/
│   ├── AGENTS.md
│   ├── .claude/agents/
│   ├── .github/{agents,skills,hooks,instructions}/
│   ├── scripts/
│   └── .memory-bankrc.example
└── README.md
```

## License

MIT.
