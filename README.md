# working-memory-kit

[![test](https://github.com/kendrick/working-memory-kit/actions/workflows/test.yml/badge.svg)](https://github.com/kendrick/working-memory-kit/actions/workflows/test.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A two-tier working memory that gives AI coding agents persistent project context across sessions.

The agent reads one short file on session start, then opens the other six only when the task calls for one. Your conventions and constraints stay written down instead of re-derived from raw source every conversation. Works with Claude Code and GitHub Copilot. Greenfield or brownfield. Installs with one command on both macOS and Windows.

<!-- Demo goes here: an asciinema cast or GIF of an install run, which shows the -->
<!-- stack detection, the coexistence map, and the reconcile pass better than    -->
<!-- prose does. Drop the file in and replace this comment with the embed.        -->

## Contents

- [Highlights](#highlights)
- [The problem](#the-problem)
- [The shape](#the-shape)
- [Install](#install)
- [How it works](#how-it-works)
- [Populating working memory after install](#populating-working-memory-after-install)
- [Customizing](#customizing)
- [Why these defaults](#why-these-defaults)
- [Compatibility](#compatibility)
- [Coexisting with spec-driven tooling](#coexisting-with-spec-driven-tooling)
- [Updating the kit](#updating-the-kit)
- [Repository layout](#repository-layout)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## Highlights

- **One file on session start, six opened on demand.** The always-read file is capped at 20 lines, and the agent opens the rest only when the task matches a row in the on-demand table.
- **Detects your spec tooling and draws the boundary.** The installer recognizes Spec Kit, OpenSpec, Kiro, BMAD, Agent OS, or Task Master, prints a who-owns-what map, and wires the boundary so the kit stays in the durable-memory lane. [Details below](#coexisting-with-spec-driven-tooling).
- **Never clobbers your content.** Managed sections live between fence markers, edited machinery files get a `.kitnew` sidecar rather than an overwrite, and your notes are seeded once and then left alone.
- **Real bash and PowerShell parity.** CI runs the bats suite on ubuntu and macOS and the Pester suite on Windows and macOS, so the two installers stay in step.
- **One canonical path per artifact.** Claude Code and VS Code Copilot both read `.claude/` natively, so shared agents and skills aren't duplicated per tool.

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
├── openQuestions.md
└── antipatterns.md
```

`activeContext.md` is the sticky note on the monitor: what you're working on right now, the last decision, known risks. The other six files are the filing cabinet, opened only when the agent needs them.

`decisionLog.md` and `antipatterns.md` are both append-only. The first records what you settled on; the second records what you tried that didn't work, so nobody re-litigates a closed loop.

## Install

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/kendrick/working-memory-kit/main/init.sh | bash

# Windows PowerShell
irm https://raw.githubusercontent.com/kendrick/working-memory-kit/main/init.ps1 | iex
```

A run against a fresh JS/TS project looks like this:

```
+------------------------------+
| working-memory-kit installer |
+------------------------------+
Target: /Users/you/code/demo

[info] detected: JavaScript/TypeScript
[info] No spec-driven tooling detected. If this project uses some, re-run with --coexist-with <path> to register it.
Install working memory at _working-memory/? [Y/n, or specify alternate path]

[info] scaffolding...
[ok] created _working-memory/README.md
[ok] created _working-memory/activeContext.example.md
[ok] created _working-memory/projectOverview.md
…
[ok] created your local _working-memory/activeContext.md from the template
[ok] pre-populated _working-memory/projectOverview.md with detected stack
[ok] created AGENTS.md
[ok] pre-populated AGENTS.md Stack with detected stack
…
[ok] marked scripts/*.sh executable
[ok] created .gitignore with activeContext.md entry

[info] verifying canonical artifacts...
[ok] present: .claude/agents/working-memory-synchronizer.md
[ok] present: .claude/skills/update-working-memory/SKILL.md
[ok] present: .claude/agents/hydrator.md
…

done.
```

The installer is the canonical setup. If your environment forbids piping `curl` to a shell, or you're offline, clone the repo and run `./init.sh` (or `./init.ps1`) instead. For an agent that can only edit files and can't run a script, copy `template/` into place and wrap the `## Working Memory` section of `AGENTS.md`, `CLAUDE.md`, and `.github/copilot-instructions.md` in `<!-- working-memory:start -->` / `<!-- working-memory:end -->` markers, which is what the installer does.

What lands in your project:

- `_working-memory/` with the seven template files plus a short `README.md` for new contributors
- `AGENTS.md` (creates one, or appends a section to your existing file). This is the canonical home for the on-demand table and update rules.
- `.claude/agents/` and `.claude/skills/` (read by both Claude Code and VS Code Copilot):
  - `working-memory-synchronizer` agent and `update-working-memory` skill—the **ongoing maintenance** surface.
  - `hydrator` agent and `hydrate-{discover,extract,draft,reconcile,propose}` skills—the **one-time onboarding** surface for brownfield installs.
- `.github/hooks/working-memory-hooks.json` and `.github/instructions/working-memory.instructions.md.example` if your project uses GitHub Copilot (these formats are Copilot-specific; the `.example` is an inert sample you copy to `working-memory.instructions.md` to switch on)
- `.github/copilot-instructions.md` (creates or prepends a thin pointer to `AGENTS.md`)
- `CLAUDE.md` (prepends a thin pointer to `AGENTS.md`)
- `scripts/` with cross-platform `.sh` and `.ps1` hooks
- `.working-memoryrc.example` for tuning thresholds

It also adds `_working-memory/activeContext.md` to `.gitignore`. `activeContext` is meant to be per-developer, not per-team.

The installer takes four flags: `--coexist-with`, `--coexist-principles`, `--no-coexist`, and `--overwrite-machinery`. [Coexisting with spec-driven tooling](#coexisting-with-spec-driven-tooling) and [Updating the kit](#updating-the-kit) cover what each one does.

## How it works

Every session starts with a read of `activeContext.md`. The session-start hook warns you if it's grown past the line limit.

The other six files load on demand. `AGENTS.md` or `.github/copilot-instructions.md` (depending on your project tooling) tell the agent which file to open for which kind of work:

- Schemas via `dataContracts.md`
- Prior decisions via `decisionLog.md`
- Project-wide patterns via `conventions.md`
- Rejected approaches via `antipatterns.md`

After meaningful work, you (or the synchronizer agent) move completed items out of `activeContext.md` and into `decisionLog.md`. The session-end hook nudges you when the diff suggests an update is overdue, by default when you've changed 5+ files **or** 200+ lines.

Manual sync: `/update-working-memory` in either Claude Code or GitHub Copilot Chat (both invoke the shared skill at `.claude/skills/update-working-memory/SKILL.md`), or `@working-memory-synchronizer` to invoke the custom agent. From any terminal, `./scripts/update-working-memory.sh` prints the active config and current state:

```
$ ./scripts/update-working-memory.sh
=== Working Memory Status ===

Active config:
  activeContext.md max lines: 20
  Nudge: > 5 files OR > 200 lines changed

activeContext.md: 10 non-empty lines (limit: 20)

Last modified:
  activeContext.md: 2026-09-14 19:04
  antipatterns.md: 2026-09-14 19:04
  conventions.md: 2026-09-14 19:04
…
```

## Populating working memory after install

The scaffold pre-populates stack info and a directory map. For an existing codebase, the next step is the **hydration pipeline**, which scans your code, git history, README, and any ADRs to draft proposed content for `projectOverview.md`, `decisionLog.md`, `dataContracts.md`, and `conventions.md`—staged as a commit (or PR for multi-developer projects) for human review.

The installer ships the pipeline into your repo. Two ways to run it:

- **Composite agent.** Ask your AI agent to "run the hydrator" (Claude Code) or "use the agent at `.claude/agents/hydrator.md`" (Copilot Chat). It orchestrates the five phases end-to-end.
- **Phase by phase.** Invoke the slash skills one at a time: `/hydrate-discover`, `/hydrate-extract`, `/hydrate-draft`, `/hydrate-reconcile`, `/hydrate-propose`. Useful when you want to review each phase's output before advancing.

Brand-new projects can skip hydration and edit the template files by hand. The pipeline expects a codebase to scan.

After hydration lands, the `working-memory-synchronizer` agent handles ongoing maintenance. See [`guide/ai-assisted-hydration.md`](guide/ai-assisted-hydration.md) for the full pipeline design, and [`examples/hydration-demo/`](examples/hydration-demo/) for a synthesized codebase you can run it against.

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
| VS Code Copilot Chat | Reference the agent file by path ("use the agent at `.claude/agents/hydrator.md`") and Copilot will read and follow it. `@` autocompletes Copilot-registered chat participants only (`@workspace`, `@terminal`, etc.)—not files in `.claude/agents/`. |

Slash skills (`/update-working-memory`, `/hydrate-discover`) are the most portable invocation surface—both tools surface them via the slash menu once the SKILL.md is in place.

## Coexisting with spec-driven tooling

The kit stays in the durable-memory lane, so it sits cleanly next to per-feature spec tools (Spec Kit, OpenSpec, Kiro, BMAD, Agent OS, Task Master). The installer detects a neighbor, prints a who-owns-what map, cross-references it from the fenced `AGENTS.md` section, and points `conventions.md` at the neighbor's principles file so conventions stays tactical. If it finds a second durable-memory system (such as Cline/Roo Memory Bank) it warns and wires nothing, since two memory systems don't divide cleanly. The full boundary, and the rule that the kit labels these lanes rather than enforcing them, lives in the [working-memory README](template/_working-memory/README.md#working-alongside-spec-driven-tooling) the installer ships.

For a tool the registry doesn't know, register it explicitly: `init.sh --coexist-with docs/specs` (optionally `--coexist-principles docs/specs/STANDARDS.md`), or `--no-coexist` to opt out. The answer is remembered in `.working-memoryrc` (`external_spec_tooling`, `external_spec_principles`, `coexistence_asked`), so re-runs don't need the flag. Through the piped installer, pass flags as `curl -fsSL … | bash -s -- --coexist-with docs/specs`; the `iex` path can't take flags, so set the keys in `.working-memoryrc` or use a clone there.

## Updating the kit

Re-run the installer. It detects an existing install and offers **Upgrade** or **Cancel**; a piped or headless run takes Upgrade on its own.

Upgrade adds any files the kit has gained since you installed, refreshes the managed section inside `AGENTS.md`, `CLAUDE.md`, and `.github/copilot-instructions.md` (the span between the `<!-- working-memory:start -->` / `<!-- working-memory:end -->` markers, so your surrounding content and any neighboring tool's block stay put), and reconciles the kit's own machinery: the skills, agents, hooks, and scripts.

Reconcile means the kit never clobbers a file you changed. A machinery file that still matches what the kit ships gets the newer version silently. One you've edited, the kit leaves alone: it writes its version beside yours as `<file>.kitnew` and lists what diverged at the end of the run. Diff the pair, merge what you want, then delete the `.kitnew`. Your working-memory notes (`projectOverview.md`, `decisionLog.md`, and the rest) are content, not machinery, so they're seeded once and never touched.

To take every kit version at once and skip the sidecars, re-run with `--overwrite-machinery` (through the pipe: `curl -fsSL … | bash -s -- --overwrite-machinery`). It still won't touch your notes.

Don't hand-edit between the fence markers; that span is the kit's to refresh. A section from a pre-fence install is migrated into the markers once on the next run.

[`CHANGELOG.md`](CHANGELOG.md) lists the released versions, and [`ROADMAP.md`](ROADMAP.md) covers what's planned.

## Repository layout

```
working-memory-kit/
├── init.sh                  # macOS/Linux installer
├── init.ps1                 # Windows installer
├── CLAUDE.md                # Kit-level agent context (also auto-loaded by VS Code Copilot)
├── CHANGELOG.md             # Generated from Conventional Commits by git-cliff (cliff.toml)
├── ROADMAP.md               # Horizons, not dates; GitHub issues are the source of truth
├── guide/                   # Practitioner-facing guides
│   └── ai-assisted-hydration.md  # Five-phase pipeline for deeper content extraction
├── .claude/
│   ├── agents/hydrator.md   # Composite agent orchestrating the 5 hydration skills
│   └── skills/              # Hydration reference skills (read natively by both tools)
│       └── hydrate-{discover,extract,draft,reconcile,propose}/
├── .github/
│   ├── copilot-instructions.md  # Thin pointer to CLAUDE.md
│   ├── workflows/test.yml       # bats, shellcheck, and Pester across three OSes
│   └── ISSUE_TEMPLATE/
├── examples/
│   └── hydration-demo/      # Synthesized codebase for demoing the pipeline
├── template/                # Files copied into the consumer's project
│   ├── _working-memory/
│   ├── AGENTS.md
│   ├── .claude/{agents,skills}/
│   ├── .github/{copilot-instructions.md,hooks,instructions}/
│   ├── scripts/
│   └── .working-memoryrc.example
├── test/                    # bats (bash) and Pester (PowerShell) suites, written in parity
├── LICENSE
└── README.md
```

## Development

The installers are the product, so the tests drive them against fixture repos and assert on the result. Three suites, all gated in CI on every push to `main` and every pull request:

```bash
# bash: installer, hooks, fencing, and coexistence behavior
npx --yes bats@1.13.0 test/

# lint the bash side
shellcheck init.sh template/scripts/*.sh

# PowerShell: the parity suite for init.ps1 and the .ps1 hooks
pwsh -c 'Install-Module Pester -MinimumVersion 5.5.0 -Force -SkipPublisherCheck -Scope CurrentUser; Invoke-Pester -Path test/ -CI'
```

bats runs through `npx` with no `package.json` and no per-OS install step. That's deliberate. The kit ships no manifest of its own, so Node stays a test-time tool and never becomes an install dependency for your project.

CI runs bats on ubuntu and macOS (macOS exists to catch BSD versus GNU divergence), and Pester on Windows and macOS. See [`test/README.md`](test/README.md) for how the fixtures are built.

## Contributing

Bug reports and feature requests are welcome through the [issue templates](.github/ISSUE_TEMPLATE/). A few things worth knowing before opening a PR:

- **`init.sh` and `init.ps1` move together.** Any installer change needs both sides, and the `template/` parity check inside each one is the canary.
- **Commits follow Conventional Commits.** `CHANGELOG.md` is generated from them by git-cliff, so the prefix determines whether your change shows up in the release notes.
- **Add a test for installer behavior.** The kit's whole promise is "idempotent, never clobbers your content," which is the hardest property to verify by eye and the easiest to regress.

[`CLAUDE.md`](CLAUDE.md) covers the agent surface conventions if you're working on the kit with Claude Code or Copilot.

## License

[MIT](LICENSE).
