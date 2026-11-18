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
- `agent-evals.bats`: free checks for the agent evals (#81). The eval-only plugin manifest has the expected shape, and its SessionStart hook prints nothing in a project the installer never touched. The shared scaffold builds a usable eval workspace, every case has its files, and the `agent-evals` workflow runs only on its label or its paths.
- `plugin.bats`: the shipped plugin (#82). `claude plugin validate` shows the root provides `working-memory-kit:init` and nothing else, while `.claude/` provides the hydrate skills, the hydrator, and one hook. The bash block from `skills/init/SKILL.md` installs the same tree as `init.sh` run directly, from a plugin root and a project whose paths contain spaces, and leaves the plugin root untouched. A `$`, backtick, or `"` in either path stays literal, so a project named `project$WMK_REVIEW_UNSET` gets the kit and its sibling `project` doesn't.
- `release-please.bats`: the release config (#89). Every tracked file with a `version` key that holds the release version from `.release-please-manifest.json` has to be in `extra-files` with the JSON `$.version` updater, so a release PR never leaves one behind. Dropping either `plugin.json` from a copy of the config fails the check, and so does a fixture that holds the release version. The other tests pin the config's settings, check that `version.txt` matches the manifest, and check that the workflow runs on pushes to `main` with write access on its one job only.
- `helpers.bash`: makes a throwaway git repo per test and runs the installer non-interactively. `run_installer_tty` drives it through a pseudo-tty (`pty_run.py`) so the interactive prompts and the Upgrade/Cancel menu are reachable; `NO_COLOR` keeps the captured output plain.

The PowerShell side (`init.ps1` and the `.ps1` hooks) is covered separately in Pester on windows-latest and macos-latest, and again under Windows PowerShell 5.1 (the `pester-desktop` job), since that's the engine the installed hooks launch. `plugin.Tests.ps1` runs the PowerShell block from `skills/init/SKILL.md` under `powershell.exe` and compares the tree with `Invoke-Installer`; it skips where `powershell.exe` is absent. `installer.Tests.ps1` also parses each shipped script as Windows-1252, the way 5.1 reads a file with no BOM, so a non-ASCII literal that would break 5.1 fails the suite on any engine. The interactive menu there uses the host's native `PromptForChoice`, so the Pester suite exercises the headless mode behavior and the machinery reconciliation rather than the menu keystrokes.

## Agent Evals

The `claude plugin eval` cases under `evals/` run a real agent in a workspace that `init.sh` just set up, and score what the agent does there. Each case fails when the wording that steers the agent regresses:

- `on-demand-conventions`: asked how API routes are named, the agent's first tool call should target `conventions.md`. A missing or broken `conventions.md` row in the on-demand table in `template/AGENTS.md` fails it.
- `hydrate-trigger`: "hydrate this repo's working memory" should fire the `hydrate-discover` skill. It fails when the hydrate skills or the hydrator agent lose their trigger wording.
- `hydrate-non-trigger`: a plain question about the current focus should fire no hydrate skill and no hydrator agent, so trigger wording that grows too broad fails it.

An eval run doesn't load the workspace's own `.claude/` or `CLAUDE.md`. `.claude/.claude-plugin/plugin.json` supplies what `init.sh` would have wired instead: the kit's skills, the hydrator agent, and a SessionStart hook that runs the installed `scripts/working-memory-session-start.sh` when that script exists. Each case loads it with `plugins: ["../../.claude"]`, because the root `.claude-plugin/plugin.json` is the shipped plugin and provides only `init`. The eval manifest isn't listed in a marketplace, since a listed plugin would load working memory twice in a workspace the installer already set up (#80).

Run the suite from the repo root:

```bash
claude plugin eval . --scaffold --trust-plugin --ablation none --runs 3 --threshold 0.66 --no-publish
```

The run bills your Anthropic account. On Sonnet, 3 runs of all three cases cost about $0.60. Without `--ablation none` the runner adds a no-plugin baseline arm, and the cost rises to about $1.25 (spike #32).

CI runs the suite in its own `agent-evals` workflow, never on every push. It runs on a manual dispatch, or on a pull request that carries the `agent-evals` label or touches `template/AGENTS.md`, `init.sh`, `template/scripts/working-memory-session-start.sh`, `.claude/`, `.claude-plugin/`, or `evals/`. Each CI run stops at $3 (`--max-cost-usd 3`).
