# Roadmap

What's planned for working-memory-kit, in rough priority order. The buckets are horizons, not
dates. Pace depends on available time, and nothing here is a commitment to ship by any particular
week. GitHub issues are the source of truth for each item; this file is the index that says what
matters most and why. New entries link to their issue once it is filed.

## Now

- **Testing foundation (v0).** The kit's whole promise is "idempotent, never clobbers your content," which is the hardest property to verify by eye and the easiest to regress. bats and Pester run the installer against fixture repos on an ubuntu/macOS/windows CI matrix. Gates the coexistence work below. · issue: #1
- **In this pass** (no issue): the session-end nudge no longer miscounts during a conflicted merge (was [D.2]); this `ROADMAP.md` and `CHANGELOG.md`; GitHub issue templates.

## Next

- **Coexistence with external spec-driven tooling, V1a.** Fence working-memory's section in `AGENTS.md`, `CLAUDE.md`, and `.github/copilot-instructions.md` with `<!-- working-memory:start/end -->` markers, so a re-install never touches another tool's content. The load-bearing, highest-risk piece; lands on the v0 test harness. · issue: #2
- **Coexistence, V1b.** Detect neighbors (Spec Kit, OpenSpec, Kiro, BMAD, Agent OS, Task Master; warn on rival memory tools) from a registry both installers read, print a who-owns-what map, and write the boundary doc. · issue: #2
- **Template legibility pass.** Move the highest-value guidance (the decisionLog entry format) out of HTML comments into a visible example, after a real onboarding agent walked right past the commented version. Sharpen the `AGENTS.md` on-demand table wording while we're in there. · issue: #3

## Later

- **Coexistence, V2.** The interactive ask-fallback for unknown tooling, `.working-memoryrc` persistence, and the conventions deferral note. Ships behind `--coexist-with` until then. · issue: #2
- **Freshness heuristic.** Nudge to review `projectOverview.md`'s Stack when `package.json` / `pyproject.toml` / lockfiles change. Conservative by design; a noisy freshness nudge is worse than none (was C.3). · issue: #4
- **npm/npx distribution spike.** Evaluate `npx working-memory-kit init` as an *additional* install path for version pinning and teams whose policy forbids `curl | bash`. Guardrail: it must never become the privileged path, since the kit stays language-agnostic. Decide, don't pre-commit. · issue: #5

## Deferred (not scheduled)

Recorded so they don't get re-litigated. Each was considered and parked on purpose.

- **Installer footprint flags** (`--claude-only` / `--copilot-only`). No real-world friction reported; adds installer surface for a hypothetical. Revisit if someone files it.
- **Claude-only skill auto-triggers.** Would tie the kit to one tool's trigger semantics with no Copilot equivalent. The cross-tool version (better on-demand-table prose) is folded into the legibility pass instead.
- **Convention auto-detection.** Already covered by the shipped hydration pipeline.
- **README "features" write-ups** of hook defensiveness and config layering. Marketing polish, low payoff.

[D.2]: ./CHANGELOG.md
