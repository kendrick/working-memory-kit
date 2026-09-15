# working-memory-kit

A two-tier working memory kit for AI coding agents, installed into consumer projects by [`init.sh`](init.sh) or [`init.ps1`](init.ps1).

**[`CLAUDE.md`](CLAUDE.md) holds the agent surface conventions for this repo. Read it before you edit anything under `.claude/`, `.github/`, or `template/`, and before you change either installer.** It covers which location is canonical for skills and agents, why `template/` is not this repo's own agent surface, and the parity rule binding `init.sh` to `init.ps1`.

Claude Code and VS Code Copilot both load `CLAUDE.md` natively. This file exists for agents that read `AGENTS.md` and nothing else.

Further reading, by task:

- Intent and shape of the kit: [`README.md`](README.md)
- The five-phase hydration pipeline: [`guide/ai-assisted-hydration.md`](guide/ai-assisted-hydration.md)
- How the bats and Pester fixtures are built: [`test/README.md`](test/README.md)
