# Tests

bats tests for the installer (`init.sh`) and the shell hooks. Run them with:

```bash
npx bats test/
```

`npx` fetches bats from npm on demand, so there's nothing to install and no `package.json` involved; it only needs Node, which most dev machines and every CI runner already have. CI pins the version (`npx --yes bats@1.13.0 test/`) and runs on ubuntu and macOS, since the installer leans on perl over `sed` precisely because BSD and GNU diverge.

- `installer.bats`: fresh-install scaffold, idempotency (a second run is a no-op), no-clobber of a pre-existing AGENTS.md / CLAUDE.md, and stack detection.
- `hooks.bats`: the session-end nudge: fires above threshold, stays quiet below, reports broken dataContracts pointers, and skips during an in-progress merge (the regression for the #6 fix).
- `helpers.bash`: makes a throwaway git repo per test and runs the installer non-interactively.

The PowerShell side (`init.ps1` and the `.ps1` hooks) is covered separately in Pester on a Windows runner. See issue #9.
