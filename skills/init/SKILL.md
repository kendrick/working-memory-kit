---
name: init
description: Install or upgrade the working-memory kit in the current project by running the installer bundled with this plugin.
argument-hint: "[--coexist-with <path>] [--coexist-principles <file>] [--no-coexist] [--overwrite-machinery] [--formatter-override | --no-formatter-override]"
disable-model-invocation: true
---

# Install the Working-Memory Kit

The installer bundled with this plugin does the work. Run it once against the project, then report what it printed.

## 1. Pick the Command

On Windows, use the PowerShell command. It calls `powershell.exe` to pin Windows PowerShell 5.1, the installer's floor, even when your PowerShell tool is pwsh 7. Everywhere else, use the bash command.

```bash
cd "${CLAUDE_PROJECT_DIR}" && bash "${CLAUDE_PLUGIN_ROOT}/init.sh" </dev/null
```

```powershell
Set-Location -LiteralPath '${CLAUDE_PROJECT_DIR}'; [Environment]::CurrentDirectory = (Get-Location).Path; powershell.exe -NoProfile -ExecutionPolicy Bypass -File '${CLAUDE_PLUGIN_ROOT}/init.ps1' --yes
```

Keep both paths exactly as written. Each command moves into the project directory first, then runs the plugin's own copy of the installer.

## 2. Add the User's Flags

The user's arguments are: `$ARGUMENTS`

Append each argument the user typed to the end of the command, in the order they typed it. Wrap each value (the `<path>` or `<file>` after a flag) in single quotes. The two value flags also take the `=` form (`--coexist-with=<path>`, `--coexist-principles=<file>`); keep that as one argument and quote the value after the `=`, as in `--coexist-with='specs'`. These are the installer's flags:

- `--coexist-with <path>`: register a spec-tooling folder the installer can't detect on its own.
- `--coexist-principles <file>`: the principles file that goes with `--coexist-with`.
- `--no-coexist`: opt out of coexistence wiring.
- `--overwrite-machinery`: take the shipped version of every kit-owned file and skip the `.kitnew` sidecars. Content files stay as they are.
- `--formatter-override` or `--no-formatter-override`: answer the Prettier/oxfmt question ahead of time.

If the user typed anything outside this list, run nothing. Tell them which argument isn't supported and list the flags above.

## 3. Run It Once

Run the one command. If it fails, show the user the installer's output and stop. Leave the project as the installer left it.

## 4. Report

Relay each `[ok]` and `[warn]` line the installer printed. Name every `.kitnew` sidecar it wrote, since the user merges those by hand.
