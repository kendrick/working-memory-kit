# Tests

bats tests for the installer (`init.sh`) and the shell hooks. Run them with:

```bash
npx bats test/
```

`npx` fetches bats from npm on demand, so there's nothing to install and no `package.json` involved; it only needs Node, which most dev machines and every CI runner already have. CI pins the version (`npx --yes bats@1.13.0 test/`) and runs on ubuntu and macOS, since the installer leans on perl over `sed` precisely because BSD and GNU diverge.

- `installer.bats`: fresh-install scaffold, idempotency (a second run is a no-op), no-clobber of a pre-existing AGENTS.md / CLAUDE.md, and stack detection.
- Upgrade flow (in `installer.bats`): a headless re-run resolves to upgrade; the Upgrade/Cancel menu maps a canned choice to the right mode; a diverged machinery file gets a `.kitnew` sidecar and an idempotent pointer while the live file and your content stay put; an unmodified file gets no sidecar; repeated upgrades are byte-stable; `--overwrite-machinery` takes the kit version; a missing content file is restored; the Copilot instructions example ships inert; a custom working-memory dir re-runs clean.
- `hooks.bats`: the session-end nudge: fires above threshold, stays quiet below, reports broken dataContracts pointers, and skips during an in-progress merge (the regression for the #6 fix).
- `helpers.bash`: makes a throwaway git repo per test and runs the installer non-interactively. `run_installer_tty` drives it through a pseudo-tty (`pty_run.py`) so the interactive prompts and the Upgrade/Cancel menu are reachable; `NO_COLOR` keeps the captured output plain.

The PowerShell side (`init.ps1` and the `.ps1` hooks) is covered separately in Pester on windows-latest and macos-latest. The interactive menu there uses the host's native `PromptForChoice`, so the Pester suite exercises the headless mode behavior and the machinery reconciliation rather than the menu keystrokes.
