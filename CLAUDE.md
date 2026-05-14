# CLAUDE.md — working-memory-kit

Agent context for working on this kit. Claude Code loads it at session start. VS Code Copilot loads it too when `chat.useClaudeMdFile` is on[^vs-code-claude-md]. The thin [`.github/copilot-instructions.md`](.github/copilot-instructions.md) pointer is there as a backstop in case that setting is off.

## What this repo is

A two-tier working memory kit that gets installed into consumer projects by [`init.sh`](init.sh) or [`init.ps1`](init.ps1). [`README.md`](README.md) covers the intent and shape. This file covers the agent surface conventions for working *on* the kit itself.

## Agent surface (Copilot and Claude)

Most artifacts live at one canonical location both tools read natively:

- **Skills**: [`.claude/skills/hydrate-*/SKILL.md`](.claude/skills/). Claude Code reads these natively. VS Code Copilot does too[^copilot-reads-claude-skills].
- **Custom agents**: [`.claude/agents/`](.claude/agents/). Both tools read this natively[^copilot-reads-claude-agents]. It currently holds [`hydrator.md`](.claude/agents/hydrator.md), the composite agent that runs the five hydration skills in order.
- **Copilot-only formats** stay under `.github/`: [`copilot-instructions.md`](.github/copilot-instructions.md) is a filename convention. Inside the template at `template/.github/`, `hooks/*.json` uses the VS Code schema and `instructions/*.instructions.md` uses the `applyTo` glob feature.

## Template surface vs. kit surface

Files under [`template/`](template/) are **not** part of this repo's own agent surface. The installer copies them into consumer projects. The conventions inside `template/` mirror the kit-level ones (`.claude/` is canonical for cross-tool work, `.github/` holds Copilot-only formats), but they apply to the consumer's project after install. The template root uses `AGENTS.md` for universal root instructions because that's the consumer-facing convention. The kit itself uses `CLAUDE.md` because contributors here mostly work in Claude Code or Copilot.

## When working in this repo

- Read [`README.md`](README.md) for intent and shape.
- Read [`guide/ai-assisted-hydration.md`](guide/ai-assisted-hydration.md) for the hydration pipeline.
- For skill changes, edit at `.claude/skills/`. Both tools pick them up automatically.
- For installer changes, keep `init.sh` and `init.ps1` in parity. The `template/` parity check inside each one is the canary.
- For scaffold-prompt changes, keep [`scaffold-prompt.md`](scaffold-prompt.md) in sync with what the installers actually do.

[^vs-code-claude-md]: VS Code Copilot auto-detects `CLAUDE.md` at the workspace root and applies it as always-on custom instructions, gated by the `chat.useClaudeMdFile` setting. See [VS Code: Use custom instructions](https://code.visualstudio.com/docs/copilot/customization/custom-instructions).

[^copilot-reads-claude-skills]: VS Code Copilot reads project skills from `.github/skills/`, `.claude/skills/`, and `.agents/skills/`. See [VS Code: Use Agent Skills](https://code.visualstudio.com/docs/copilot/customization/agent-skills); [GitHub Docs: Adding agent skills for GitHub Copilot](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/add-skills).

[^copilot-reads-claude-agents]: VS Code Copilot detects `.md` files in `.claude/agents/` and applies them as custom agents (Claude sub-agent format). See [VS Code: Custom agents](https://code.visualstudio.com/docs/copilot/customization/custom-agents).
