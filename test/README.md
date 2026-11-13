# Tests

bats tests for the installer (`init.sh`), the shell hooks, and the text of the `hydrate-propose` skill. Run them with:

```bash
npx bats test/
```

`npx` fetches bats from npm on demand, so there's nothing to install and no `package.json` involved; it only needs Node, which most dev machines and every CI runner already have. CI pins the version (`npx --yes bats@1.13.0 test/`) and runs on ubuntu and macOS, since the installer leans on perl over `sed` precisely because BSD and GNU diverge.

- `installer.bats`: fresh-install scaffold, idempotency (a second run is a no-op), no-clobber of a pre-existing AGENTS.md / CLAUDE.md, and stack detection.
- Upgrade flow (in `installer.bats`): a headless re-run resolves to upgrade; the Upgrade/Cancel menu maps a canned choice to the right mode; a diverged machinery file gets a `.kitnew` sidecar and an idempotent pointer while the live file and your content stay put; an unmodified file gets no sidecar; repeated upgrades are byte-stable; `--overwrite-machinery` takes the kit version; a missing content file is restored; the Copilot instructions example ships inert; a custom working-memory dir re-runs clean.
- Claude Code hooks (in `installer.bats`): a fresh install writes the SessionStart and SessionEnd entries to `.claude/settings.json`, and the start hook runs and returns `additionalContext`; a re-install keeps a project's own hook and one copy of each kit entry, and swaps an old kit entry for the current one; the installer leaves an invalid file untouched and warns.
- `session-start-context.bats`: what `--claude` injects into `additionalContext` (the first `MAX_LINES` lines of `activeContext.md` and the AGENTS.md on-demand table), CRLF stripping, a bad line limit, and that the plain output stays the same.
- `hooks.bats`: the session-start `--claude` output (`additionalContext`, the size-warning condition, no `systemMessage`) and the session-end nudge: fires above threshold, stays quiet below, reports broken dataContracts pointers, and skips during an in-progress merge (the regression for the #6 fix).
- `hydrate-propose.bats`: the skill's `SKILL.md` gives a quoting rule for each shell it prints an `ltm propose` command for (#59): `'\''` for bash/zsh, and a doubled quote for PowerShell that covers the typographic single quotes too.
- `helpers.bash`: makes a throwaway git repo per test and runs the installer non-interactively. `run_installer_tty` drives it through a pseudo-tty (`pty_run.py`) so the interactive prompts and the Upgrade/Cancel menu are reachable; `NO_COLOR` keeps the captured output plain.

The PowerShell side (`init.ps1` and the `.ps1` hooks) is covered separately in Pester on windows-latest and macos-latest, and again under Windows PowerShell 5.1 (the `pester-desktop` job), since that's the engine the installed hooks launch. `installer.Tests.ps1` also parses each shipped script as Windows-1252, the way 5.1 reads a file with no BOM, so a non-ASCII literal that would break 5.1 fails the suite on any engine. The interactive menu there uses the host's native `PromptForChoice`, so the Pester suite exercises the headless mode behavior and the machinery reconciliation rather than the menu keystrokes.
