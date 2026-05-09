# Working Memory Kit — Scaffold Prompt

> **What this is:** A self-contained prompt you can hand to Claude Code, GitHub Copilot, or any code-aware agent. It will scaffold a two-tier working memory into your project with the necessary agent configuration and hooks for both Claude Code and GitHub Copilot.
>
> **Works on:** Greenfield or brownfield projects. The scaffold detects existing structure and adapts.
>
> **For deeper hydration:** This prompt installs the structure and pre-populates obvious stack/structure facts. For a richer one-time content hydration that scans the codebase, recent git history, and existing docs, see [`guide/ai-assisted-hydration.md`](guide/ai-assisted-hydration.md) after the scaffold completes.

---

## Installation

From a GitHub-hosted repository (e.g., `yourorg/working-memory-kit`), consumers can install with a one-liner:

```bash
# Option A: npx degit (no git history, just files — macOS/Linux/Windows)
npx degit yourorg/working-memory-kit/template --force

# Option B: curl + tar (macOS/Linux)
curl -fsSL https://github.com/yourorg/working-memory-kit/releases/latest/download/scaffold.tar.gz \
  | tar -xz --strip-components=1

# Option C: init script (macOS/Linux)
curl -fsSL https://raw.githubusercontent.com/yourorg/working-memory-kit/main/init.sh | bash

# Option D: init script (Windows PowerShell)
irm https://raw.githubusercontent.com/yourorg/working-memory-kit/main/init.ps1 | iex

# Option E: gh skill (installs only the Copilot skill, not the full scaffold)
gh skill install yourorg/working-memory-kit
```

The repository structure for hosting this kit:

```
working-memory-kit/
├── README.md
├── init.sh                  # macOS/Linux installer
├── init.ps1                 # Windows installer
├── scaffold-prompt.md       # This file
└── template/                # What gets copied into the consumer's project
    ├── working-memory/
    │   ├── activeContext.example.md
    │   ├── projectOverview.md
    │   ├── decisionLog.md
    │   ├── dataContracts.md
    │   ├── conventions.md
    │   └── openQuestions.md
    ├── AGENTS.md
    ├── .claude/
    │   └── agents/
    │       └── working-memory-synchronizer.md
    ├── .github/
    │   ├── copilot-instructions.md
    │   ├── agents/
    │   │   └── working-memory-synchronizer.agent.md
    │   ├── skills/
    │   │   └── update-working-memory/
    │   │       └── SKILL.md
    │   ├── hooks/
    │   │   └── working-memory-hooks.json
    │   └── instructions/
    │       └── data-layer.instructions.md
    └── scripts/
        ├── working-memory-session-start.sh    # macOS/Linux hook
        ├── working-memory-session-start.ps1   # Windows hook
        ├── working-memory-session-end.sh
        ├── working-memory-session-end.ps1
        ├── update-working-memory.sh           # manual sync trigger
        └── update-working-memory.ps1
```

The `init.sh` (macOS/Linux) and `init.ps1` (Windows) installers should:

1. Check for existing `working-memory/`, `.claude/`, `.github/` directories
2. Prompt before overwriting anything
3. Merge into existing `copilot-instructions.md`, `AGENTS.md`, or `.github/agents/` if present
4. Copy `activeContext.example.md` → `activeContext.md` for the installing developer
5. Append `working-memory/activeContext.md` to `.gitignore`
6. Mark `.sh` scripts as executable (macOS/Linux only)
7. Run a quick project scan and pre-populate `projectOverview.md` with detected stack info
8. Verify parity: confirm that both Claude Code and Copilot configurations were created

---

## The Prompt

Paste everything below this line into your agent.

---

You are scaffolding a **two-tier working memory** into this project. The working memory gives AI agents persistent awareness of project state across sessions without bloating context on every turn.

> **Implementation note:** Before creating Copilot-specific files (`.github/agents/`, `.github/skills/`, `.github/hooks/`), search the web for the latest GitHub Copilot documentation on custom agents, agent skills, and hooks to verify that file formats, frontmatter schemas, and directory conventions have not changed. Key docs to check:
> - https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/create-custom-agents
> - https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/add-skills
> - https://docs.github.com/en/copilot/reference/hooks-configuration
> - https://code.visualstudio.com/docs/copilot/customization/hooks
>
> Note that GitHub's hooks doc and VS Code's hooks doc describe two different schemas (camelCase events + `bash`/`powershell` + `timeoutSec` vs. PascalCase events + `command` with `windows`/`linux`/`osx` overrides + `timeout`). Files placed at `.github/hooks/*.json` are loaded by the VS Code Copilot extension, so this kit uses the VS Code schema.

### Step 1 — Detect existing project structure

Before creating anything, scan the project root for:

- `package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`, or similar (detect stack)
- Existing `AGENTS.md`, `CLAUDE.md`, `COPILOT.md`, `.github/copilot-instructions.md`
- Existing `working-memory/` directory
- `.claude/` directory and any existing agent definitions
- `.github/agents/` directory and any existing `.agent.md` files
- `.github/skills/` directory and any existing skills
- `.github/hooks/` directory and any existing hook configurations
- `.github/instructions/` directory and any path-specific instruction files
- Source directory structure (src/, app/, lib/, etc.)
- Build/test/lint commands in package.json scripts, Makefile, etc.
- **Operating system** — detect whether the environment is macOS/Linux or Windows to determine which script variants to create (`.sh` vs `.ps1`). Create both by default if the OS is unknown or if the project is shared across platforms.

Report what you found before proceeding. If a working memory already exists, ask whether to reset or merge.

### Step 2 — Create the working memory directory

Create `working-memory/` at the project root with these six files:

#### `working-memory/activeContext.example.md`

This is the **committed template**. Each developer copies it to `activeContext.md` locally. The actual `activeContext.md` is gitignored because active context is per-developer — two people on the same team have different active contexts, and committing it creates constant meaningless merge conflicts on the most frequently updated file.

```markdown
# Active Context

<!-- HARD RULE: This file never exceeds 20 lines of content. -->
<!-- It is a queue, not an archive. Completed items move to decisionLog.md. -->
<!-- This file is LOCAL ONLY (.gitignored). Copy from activeContext.example.md to get started. -->

## Current Focus
_Not yet set._

## Last Decision
_None yet._

## Known Risks
_None yet._
```

After creating the example file, also create the developer's working copy:

```bash
cp working-memory/activeContext.example.md working-memory/activeContext.md
```

#### `working-memory/projectOverview.md`

```markdown
# Project Overview

## What This Is
<!-- One sentence. What does this project do? -->
_To be filled._

## Stack
<!-- Detected or manually entered. -->
- Language:
- Framework:
- Styling:
- Data layer:
- Deployment:

## Repository Structure
<!-- Top-level directory map. -->

## Key Constraints
<!-- Non-obvious things an agent must know: monorepo rules, legacy code boundaries, -->
<!-- API version requirements, browser support targets, etc. -->
```

Pre-populate the Stack and Repository Structure sections using what you detected in Step 1. For brownfield projects, note any areas of the codebase that should not be modified without explicit permission.

#### `working-memory/decisionLog.md`

```markdown
# Decision Log

<!-- Append-only. Most recent at top. -->
<!-- Format: -->
<!-- ## YYYY-MM-DD — [Short Title] -->
<!-- **Context:** Why this came up -->
<!-- **Decision:** What was decided -->
<!-- **Alternatives considered:** What was rejected and why -->

_No decisions logged yet._
```

#### `working-memory/dataContracts.md`

```markdown
# Data Contracts

<!-- Canonical shapes for data flowing through the application. -->
<!-- Agents must consume data through these contracts. -->
<!-- When mocking data, conform to these shapes exactly. -->

_No contracts defined yet._
```

#### `working-memory/conventions.md`

```markdown
# Conventions

<!-- Project-specific patterns agents must follow. -->
<!-- This is the "how we do things here" file. -->

## Naming
_Not yet defined._

## File Organization
_Not yet defined._

## Component Patterns
_Not yet defined._

## Error Handling
_Not yet defined._
```

#### `working-memory/openQuestions.md`

```markdown
# Open Questions

<!-- Things that are unresolved and should not be guessed at. -->
<!-- Agents encountering these should ask rather than assume. -->

_No open questions yet._
```

### Step 3 — Create or update AGENTS.md (thin root)

Create `AGENTS.md` at the project root. If one already exists, merge the working memory section into it without removing existing content.

The file must stay lean. It is the "sticky note on the monitor" — the agent reads this every session. The working memory is the filing cabinet it opens on demand.

```markdown
# AGENTS.md

## Stack
<!-- One line per layer. Detected from project. -->

## Build / Test / Lint
<!-- Copy exact commands so agents don't guess. -->

## Working Memory

This project uses a two-tier working memory at `working-memory/`.

### Always read on session start:
- `working-memory/activeContext.md` — Current focus, last decision, known risks (≤20 lines, local only / gitignored)

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

## Conventions
<!-- Populated from detection or manually. Keep to ≤10 rules. -->
```

Populate the Stack and Build/Test/Lint sections from what you detected.

### Step 4 — Claude Code configuration

#### 4a — Claude Code agent: working memory synchronizer

Create `.claude/agents/working-memory-synchronizer.md`:

```markdown
---
name: working-memory-synchronizer
description: >
  Synchronizes working memory with project state. Invoke after completing a feature,
  making an architectural decision, or when activeContext.md feels stale.
  Can also be triggered with /update-working-memory.
---

# Working Memory Synchronizer

You are a maintenance agent responsible for keeping the working memory accurate and lean.

## Process

1. Read all files in `working-memory/` (five committed files plus the local `activeContext.md`).
2. Scan recent changes in the working tree (`git diff --stat HEAD~5` or similar).
3. For each file, determine:
   - Is anything **stale** (describes something that no longer matches the code)?
   - Is anything **missing** (a recent decision, convention, or contract not captured)?
   - Is `activeContext.md` over 20 lines?

4. Propose changes as a batch. Group by file.

## Rules

- **activeContext.md**: Evict completed work to `decisionLog.md`. Keep ≤20 lines.
- **decisionLog.md**: Append only. Never edit past entries.
- **projectOverview.md**: Update stack/structure only when the project shape actually changes.
- **dataContracts.md**: Update when interfaces, schemas, or API shapes change.
- **conventions.md**: Update when a new pattern emerges or an old one is deprecated.
- **openQuestions.md**: Remove questions that have been answered (move the answer to the decision log).
- Never fabricate information. If unsure, add to `openQuestions.md`.
```

#### 4b — CLAUDE.md integration

If a `CLAUDE.md` file exists at the project root, append the following block to it. If it does not exist, create it with only this content:

```markdown
## Working Memory

On session start, always read `working-memory/activeContext.md`.
Read other working memory files as directed by the table in `AGENTS.md`.
After significant work, run the working-memory-synchronizer agent or manually update active context.
```

### Step 5 — GitHub Copilot configuration

Copilot supports custom agents, agent skills, lifecycle hooks, and path-specific instructions. This step creates equivalents of everything Claude Code gets, using Copilot's native primitives.

#### 5a — Copilot custom agent: working memory synchronizer

Create `.github/agents/working-memory-synchronizer.agent.md`:

```markdown
---
name: working-memory-synchronizer
description: >
  Synchronizes the working memory with project state. Use after completing a
  feature, making an architectural decision, or when context feels stale.
  Equivalent to running /update-working-memory.
---

# Working Memory Synchronizer

You are a maintenance agent responsible for keeping the working memory accurate and lean.

## Process

1. Read all files in `working-memory/` (five committed files plus the local `activeContext.md`).
2. Scan recent changes in the working tree (`git diff --stat HEAD~5` or similar).
3. For each file, determine:
   - Is anything **stale** (describes something that no longer matches the code)?
   - Is anything **missing** (a recent decision, convention, or contract not captured)?
   - Is `activeContext.md` over 20 lines?

4. Propose changes as a batch. Group by file.

## Rules

- **activeContext.md**: Evict completed work to `decisionLog.md`. Keep ≤20 lines.
- **decisionLog.md**: Append only. Never edit past entries.
- **projectOverview.md**: Update stack/structure only when the project shape actually changes.
- **dataContracts.md**: Update when interfaces, schemas, or API shapes change.
- **conventions.md**: Update when a new pattern emerges or an old one is deprecated.
- **openQuestions.md**: Remove questions that have been answered (move the answer to the decision log).
- Never fabricate information. If unsure, add to `openQuestions.md`.
```

#### 5b — Copilot agent skill: update-working-memory

Create `.github/skills/update-working-memory/SKILL.md`:

```markdown
---
name: update-working-memory
description: >
  Reads the current working memory state, diffs it against recent git changes,
  and proposes updates. Use when finishing a feature, resolving a decision,
  or when active context feels stale.
---

# Update Working Memory

When this skill is activated, perform the following:

1. Read `working-memory/activeContext.md` (local, may not exist yet — if missing, create from `activeContext.example.md`).
2. Read all other files in `working-memory/`.
3. Run `git diff --stat HEAD~5` to identify recent changes.
4. For each working memory file, determine if anything is stale or missing.
5. Enforce the 20-line hard limit on `activeContext.md` — evict completed items to `decisionLog.md`.
6. Propose all changes as a batch, grouped by file, and wait for confirmation before writing.

## File rules

| File | Update policy |
|---|---|
| `activeContext.md` | Queue, not archive. Evict completed items. ≤20 lines. |
| `decisionLog.md` | Append only. Never edit past entries. Most recent at top. |
| `projectOverview.md` | Update only when project shape changes (stack, structure). |
| `dataContracts.md` | Update when interfaces, schemas, or API shapes change. |
| `conventions.md` | Update when a new pattern emerges or an old one is deprecated. |
| `openQuestions.md` | Remove answered questions (move answers to decision log). |
```

Users can invoke this skill in VS Code by typing `/update-working-memory` in Copilot Chat, or it can be invoked by the working-memory-synchronizer agent.

#### 5c — Copilot lifecycle hooks

Create `.github/hooks/working-memory-hooks.json` using the VS Code hook schema (PascalCase event names, `command` field, `timeout` in seconds, with `windows` for the PowerShell variant):

```json
{
  "version": 1,
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "./scripts/working-memory-session-start.sh",
        "windows": "powershell -NoProfile -File ./scripts/working-memory-session-start.ps1",
        "timeout": 10
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "./scripts/working-memory-session-end.sh",
        "windows": "powershell -NoProfile -File ./scripts/working-memory-session-end.ps1",
        "timeout": 10
      }
    ]
  }
}
```

Create the hook scripts. These must have both bash and PowerShell variants for cross-platform support.

**`scripts/working-memory-session-start.sh`** (macOS/Linux):

```bash
#!/bin/bash
# Ensures activeContext.md exists at session start.
# If missing, copies from the example template.

set -eu

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WM_DIR="$REPO_ROOT/working-memory"

# Hooks fire on every session in every project, not just working-memory
# consumers. Bail quietly so unrelated repos don't see noise.
if [ ! -d "$WM_DIR" ]; then
  exit 0
fi

# {"systemMessage":"..."} on stdout is the hook protocol — the host surfaces
# it to the user. Plain echoes get ignored.
if [ ! -f "$WM_DIR/activeContext.md" ]; then
  if [ -f "$WM_DIR/activeContext.example.md" ]; then
    cp "$WM_DIR/activeContext.example.md" "$WM_DIR/activeContext.md"
    echo '{"systemMessage":"Created working-memory/activeContext.md from template. Update it with your current focus."}'
  else
    echo '{"systemMessage":"No activeContext.example.md found. Working memory may not be initialized."}'
  fi
else
  # 20 is the hard limit set by activeContext.example.md.
  LINE_COUNT=$(grep -c '[^[:space:]]' "$WM_DIR/activeContext.md" || true)
  if [ "${LINE_COUNT:-0}" -gt 20 ]; then
    echo "{\"systemMessage\":\"Warning: activeContext.md has $LINE_COUNT non-empty lines (limit is 20). Run /update-working-memory to prune it.\"}"
  fi
fi
```

**`scripts/working-memory-session-start.ps1`** (Windows): mirror the bash logic using `Test-Path`, `Copy-Item`, and `Write-Output` for the JSON envelope.

**`scripts/working-memory-session-end.sh`** (macOS/Linux):

```bash
#!/bin/bash
# Reminds the developer to update the working memory if significant work was done.

set -eu

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [ ! -d "$REPO_ROOT/working-memory" ]; then
  exit 0
fi

CHANGED_FILES=$(git -C "$REPO_ROOT" diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ' || echo 0)

# Five is a heuristic threshold for "this session did real work, nudge them
# to update working memory." Tune to taste.
if [ "${CHANGED_FILES:-0}" -gt 5 ]; then
  echo "{\"systemMessage\":\"You changed $CHANGED_FILES files this session. Consider running /update-working-memory or @working-memory-synchronizer to keep the working memory current.\"}"
fi
```

**`scripts/working-memory-session-end.ps1`** (Windows): mirror the bash logic.

Mark all shell scripts as executable:

```bash
chmod +x scripts/working-memory-session-start.sh scripts/working-memory-session-end.sh
```

On Windows, PowerShell scripts do not require a chmod equivalent — they execute based on the system's execution policy.

#### 5d — Copilot instructions (expanded)

Create or merge into `.github/copilot-instructions.md`:

```markdown
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
- You can invoke the `@working-memory-synchronizer` agent or type `/update-working-memory` to trigger a full sync.
```

If a `.github/copilot-instructions.md` already exists, insert the Working Memory section at the top without removing existing instructions.

#### 5e — Path-specific instructions (optional but recommended)

If the project has distinct areas that interact with the working memory differently (e.g., a `src/data/` directory that should always consult data contracts), create path-specific instruction files.

Create `.github/instructions/data-layer.instructions.md`:

```markdown
---
applyTo: "**/data/**,**/api/**,**/lib/data/**"
---

When working on files in the data layer, always read `working-memory/dataContracts.md` first.
All data-consuming code must conform to the interfaces defined there.
If you need to change a data shape, update `dataContracts.md` before modifying code.
```

Create additional `.instructions.md` files as needed for other areas of the codebase.

### Step 6 — Cross-platform utility scripts

Create a convenience script that works from both Claude Code and Copilot CLI contexts.

**`scripts/update-working-memory.sh`** (macOS/Linux): print activeContext.md status (line count vs. the 20 limit), modification times for each working-memory file, and a `git diff --stat HEAD~5` summary so the developer can see what changed before deciding what to update. Branch on `$OSTYPE` for `stat` flags, since BSD and GNU `stat` are not flag-compatible.

**`scripts/update-working-memory.ps1`** (Windows): same output, written with `Get-ChildItem` and `Get-Content`.

Mark the shell script as executable:

```bash
chmod +x scripts/update-working-memory.sh
```

### Step 7 — Git configuration

Add `activeContext.md` to `.gitignore` — it is per-developer local state. The example template remains committed so new contributors know the format.

```
# .gitignore (append)
working-memory/activeContext.md
```

If the project has a `.gitattributes` file, add:

```
working-memory/*.md merge=union
```

This reduces merge conflicts on append-only files like the decision log.

### Step 8 — Verify and report

After scaffolding, output a summary:

- Files created (with paths)
- Files modified (with description of changes)
- Pre-populated values (stack, commands, structure)
- Any conflicts or existing files that were preserved
- **Platform coverage**: Confirm that both `.sh` and `.ps1` script variants were created
- **Copilot parity check**: Confirm that for every `.claude/agents/*.md` file, a corresponding `.github/agents/*.agent.md` exists
- Suggested next step: "Open `working-memory/projectOverview.md` and fill in the 'What This Is' section, then you're ready to go."
- Remind the user: "`activeContext.md` is gitignored. Each team member should run `cp working-memory/activeContext.example.md working-memory/activeContext.md` (or `Copy-Item` on Windows) after cloning."
- Tip: "In VS Code, type `/update-working-memory` in Copilot Chat to sync the working memory. In Claude Code, invoke the `working-memory-synchronizer` agent or use `/update-working-memory`."
