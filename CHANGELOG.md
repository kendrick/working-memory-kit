# Changelog

Notable changes to working-memory-kit, grouped by type and generated from the Conventional Commit history with [git-cliff](https://git-cliff.org). The kit installs from `main` and is not versioned yet, so changes sit under Unreleased until a release is tagged.

## Unreleased

### Features
- *(installer)* Register external spec tooling via flags and .working-memoryrc (#14)
- *(installer)* Detect spec-driven neighbors and wire the coexistence boundary (#13)
- *(installer)* Fence the working-memory section so re-installs stay collision-safe (#12)

### Bug Fixes
- *(installer)* Preserve line endings outside the working-memory fence (#22)
- *(installer)* Normalize line endings so Windows re-installs stay idempotent (#21)
- *(installer)* Repair PowerShell legacy migration and stack pre-fill (#19)
- *(installer)* Make init.ps1 path-portable and headless-drivable (#18)
- *(installer)* Make init.ps1 prompts non-interactive-safe and smoke it on Windows CI (#15)
- *(hooks)* Skip session-end nudge during an in-progress merge or rebase (#6)

### Documentation
- Retire scaffold-prompt.md in favor of the installer (#17)
- *(templates)* Surface the decisionLog format and sharpen the on-demand table (#8)

### Testing
- Add a Pester suite for the PowerShell installer and hooks (#20)
- Add a bats harness and CI for the installer and hooks (#11)

### CI & Build
- Run shellcheck on installer & hooks (#16)

## Initial development

The kit's foundation, before it adopted Conventional Commits. Summarized from git history rather than listed commit by commit.

- A two-tier working memory (`AGENTS.md` plus `_working-memory/`) installed by parallel bash and PowerShell scripts, with thin `CLAUDE.md` and `copilot-instructions.md` pointers.
- The hydration pipeline (the `hydrator` agent and five `hydrate-*` skills) ships into every install, so brownfield projects get the one-time onboarding surface, not just ongoing maintenance.
- Session hooks: a session-start directive so agents register the kit early, and a session-end nudge to refresh working memory after substantial work, with broken-pointer detection riding along.
- One canonical location per artifact that Claude Code and Copilot both read natively: `.claude/` for cross-tool agents and skills, `.github/` reserved for Copilot-only formats.
- Installers run under `curl | bash` and `iex (irm ...)`, reading prompts from the terminal rather than the piped script body.
