# Changelog

Notable changes to working-memory-kit. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The kit has no version numbers yet. It's installed from `main`, not published, so entries are
anchored on dates. A real versioning scheme would land with the npm/npx distribution spike on the
[roadmap](./ROADMAP.md), if that goes ahead.

## [Unreleased]

### Fixed

- Session-end nudge no longer miscounts work during a conflicted `git pull`. While a merge is in progress, `git diff HEAD` reports the incoming side of the merge as if the developer wrote it, so a one-line edit could read as "7 files changed." The nudge now skips while a merge or rebase is in progress and measures cleanly once it resolves.

### Added

- `ROADMAP.md` and this changelog.
- GitHub issue templates (`.github/ISSUE_TEMPLATE/`) for bug reports and feature requests.

## 2026-05-15: Onboarding and layout consolidation

The kit's shape as it stands today. Summarized from git history; this is where the changelog starts.

### Added

- The hydration pipeline (the `hydrator` agent and the five `hydrate-*` skills) now ships into every install, not just the kit repo. Brownfield projects get the one-time onboarding surface, not only the ongoing-maintenance one.
- `antipatterns.md` as a working-memory file: an append-only log of approaches the team already tried, checked before proposing refactors.
- A `_working-memory/README.md` aimed at human contributors, and a session-start directive so agents register the kit early.
- Broken-pointer detection in the session-end hook. When the nudge already fires, stale `dataContracts.md` links ride along as extra signal.

### Changed

- One canonical location per artifact that both Claude Code and Copilot read natively: `.claude/` for cross-tool agents and skills, `.github/` reserved for Copilot-only formats.
- `AGENTS.md` is the single source for the on-demand table. The `CLAUDE.md` and `copilot-instructions.md` sections are thin pointers to it, prepended rather than appended so they land inside an agent's read window.
- The working-memory directory is `_working-memory/` by default, with the install path overridable.
- Stack detection pre-fills `AGENTS.md` and `projectOverview.md`.

### Fixed

- Installers work under `curl | bash` and `iex (irm ...)`, reading prompts from `/dev/tty` (sh) and the console host (pwsh) instead of the piped script body.
