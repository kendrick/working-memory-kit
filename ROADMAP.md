# Roadmap

What's planned for working-memory-kit, and what's already done. The buckets are horizons, not dates. Pace depends on available time, and nothing here is a commitment to ship by any particular week. GitHub issues are the source of truth; this file is the index that says what matters most and why.

The v0 foundation has shipped: a re-runnable installer, a behavioral test suite proving it on both bash and PowerShell, and coexistence with external spec-driven tooling. What's left is two unscheduled explorations.

## Shipped

- **Session-end merge-guard.** The nudge no longer miscounts work during a conflicted `git pull`. While a merge or rebase is in progress, `git diff HEAD` counts the incoming side as if you wrote it, so a one-line edit could read as "7 files changed." It now stays quiet until the merge resolves, then measures cleanly. · #6
- **Testing foundation (bats).** The kit's whole promise is "idempotent, never clobbers your content," the hardest property to verify by eye and the easiest to regress. bats runs the installer and hooks against fixture repos on ubuntu and macOS, via `npx` with no install step. · #1
- **Coexistence with spec-driven tooling.** Fences working-memory's section in `AGENTS.md`, `CLAUDE.md`, and `copilot-instructions.md` with `<!-- working-memory:start/end -->` markers, so a re-install never touches another tool's content (V1a). Detects neighbors (Spec Kit, OpenSpec, Kiro, BMAD, Agent OS, Task Master, plus a warning on rival memory tools) from a shared registry and prints a who-owns-what map (V1b). Registers unknown tooling through `--coexist-with` and remembers it in `.working-memoryrc` (V2). · #2
- **Template legibility.** Moved the decisionLog entry format out of an HTML comment into a visible example, after a real onboarding agent walked straight past the commented version. Sharpened the on-demand table wording while in there. · #3
- **shellcheck at full strength.** Fixed the pre-existing warnings and dropped the `--severity=error` floor, so the installer and hook scripts lint clean. · #10
- **Retired scaffold-prompt.md.** The installer is the canonical, tested setup path; the standalone prompt duplicated template content and kept drifting, so it's gone rather than resynced. · #7
- **PowerShell parity.** Made `init.ps1` path-portable and headless-drivable (#18), then mirrored the full 35-case bats suite in Pester with windows-latest and macos-latest CI. The suite paid for itself immediately, catching bugs the old smoke test couldn't: a migration that wiped user content and a stack pre-fill that silently no-opped (#19), then two Windows line-ending fixes for re-install idempotency (#21, #22). · #9

## Next

Nothing is in flight. These are the two open issues, both unscheduled.

- **Freshness heuristic.** Nudge to review `projectOverview.md`'s Stack when `package.json` / `pyproject.toml` / lockfiles change. Conservative by design; a noisy freshness nudge is worse than none. · #4
- **npm/npx distribution spike.** Evaluate `npx working-memory-kit init` as an *additional* install path, for version pinning and teams whose policy forbids `curl | bash`. Guardrail: it must never become the privileged path, since the kit stays language-agnostic. Decide, don't pre-commit. · #5

## Deferred (not scheduled)

Recorded so they don't get re-litigated. Each was considered and parked on purpose.

- **Installer footprint flags** (`--claude-only` / `--copilot-only`). No real-world friction reported; adds installer surface for a hypothetical. Revisit if someone files it.
- **Claude-only skill auto-triggers.** Would tie the kit to one tool's trigger semantics with no Copilot equivalent. The cross-tool version (better on-demand-table prose) is folded into the legibility pass instead.
- **Convention auto-detection.** Already covered by the shipped hydration pipeline.
- **README "features" write-ups** of hook defensiveness and config layering. Marketing polish, low payoff.
