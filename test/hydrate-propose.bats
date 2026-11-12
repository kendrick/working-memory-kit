#!/usr/bin/env bats
# #59: the printed `ltm propose` command must parse in the shell it is labeled for, so the skill states a quoting rule per shell.

load helpers

@test "hydrate-propose gives a quoting rule per shell (#59)" {
  skill="$KIT_ROOT/.claude/skills/hydrate-propose/SKILL.md"
  grep -qF 'bash/zsh' "$skill"
  grep -qF 'PowerShell' "$skill"
  # The POSIX rule and the PowerShell rule each sit on their own line, so the PowerShell `''` can't be satisfied by the tail of `'\''`.
  grep -F 'bash/zsh writes' "$skill" | grep -qF "'\\''"
  ps_rule="$(grep -F 'PowerShell writes' "$skill")"
  [[ "$ps_rule" == *"''"* ]] || false
  [[ "$ps_rule" != *"'\\''"* ]] || false
  # pwsh also closes a string at a typographic single quote, so the rule has to name all four.
  for q in ‘ ’ ‚ ‛; do
    [[ "$ps_rule" == *"$q"* ]] || false
  done
}
