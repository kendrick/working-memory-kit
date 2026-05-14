# CLAUDE.md — working-memory-kit

Source-of-truth agent context for contributing to this kit. Auto-loaded by Claude Code at session start; auto-loaded by VS Code Copilot when `chat.useClaudeMdFile` is enabled[^vs-code-claude-md]. The thin [`.github/copilot-instructions.md`](.github/copilot-instructions.md) pointer backstops that setting.

## What this repo is

A two-tier working memory kit installed into consumer projects via [`init.sh`](init.sh) / [`init.ps1`](init.ps1). [`README.md`](README.md) captures the intent and shape; this file captures the agent surface conventions for working *on* the kit.

## Agent surface (Copilot and Claude)

Most artifacts live at a single canonical location both tools read natively:

- **Skills**: [`.claude/skills/hydrate-*/SKILL.md`](.claude/skills/). Read by Claude Code natively; read by VS Code Copilot natively[^copilot-reads-claude-skills].
- **Custom agents**: [`.claude/agents/`](.claude/agents/). Read by both natively[^copilot-reads-claude-agents]. Currently contains [`hydrator.md`](.claude/agents/hydrator.md) — the composite agent that orchestrates the five hydration skills.
- **Copilot-only formats** stay under `.github/`: [`copilot-instructions.md`](.github/copilot-instructions.md) (filename convention), and inside the template at `template/.github/`: `hooks/*.json` (VS Code schema), `instructions/*.instructions.md` (`applyTo` glob feature).

## Template surface vs. kit surface

Files under [`template/`](template/) are **not** part of this repo's own agent surface — they get copied into consumer projects by the installer. The conventions inside `template/` mirror the kit-level ones (`.claude/` canonical for cross-tool, `.github/` for Copilot-only formats), but apply to the consumer's project once installed. The template root uses `AGENTS.md` as universal root instructions because that's the consumer-facing convention; the kit itself uses `CLAUDE.md` because the kit's contributors are primarily working in Claude Code / Copilot.

## When working in this repo

- Read [`README.md`](README.md) for intent and shape.
- Read [`guide/ai-assisted-hydration.md`](guide/ai-assisted-hydration.md) for the hydration pipeline.
- Skill changes: edit at `.claude/skills/`; both tools read them automatically.
- Installer changes: keep `init.sh` and `init.ps1` in parity. The `template/` parity check in each is the canary.
- Scaffold-prompt changes: keep [`scaffold-prompt.md`](scaffold-prompt.md) in sync with what the installers actually do.

[^vs-code-claude-md]: VS Code Copilot auto-detects `CLAUDE.md` at the workspace root and applies it as always-on custom instructions, gated by the `chat.useClaudeMdFile` setting. See [VS Code: Use custom instructions](https://code.visualstudio.com/docs/copilot/customization/custom-instructions).

[^copilot-reads-claude-skills]: VS Code Copilot reads project skills from `.github/skills/`, `.claude/skills/`, and `.agents/skills/`. See [VS Code: Use Agent Skills](https://code.visualstudio.com/docs/copilot/customization/agent-skills); [GitHub Docs: Adding agent skills for GitHub Copilot](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/add-skills).

[^copilot-reads-claude-agents]: VS Code Copilot detects `.md` files in `.claude/agents/` and applies them as custom agents (Claude sub-agent format). See [VS Code: Custom agents](https://code.visualstudio.com/docs/copilot/customization/custom-agents).
