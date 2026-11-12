#!/usr/bin/env bats

load helpers

@test "hydrate-propose gives a quoting rule per shell (#59)" {
  skill="$KIT_ROOT/.claude/skills/hydrate-propose/SKILL.md"
  grep -qF 'bash/zsh' "$skill"
  grep -qF 'PowerShell' "$skill"
  # The POSIX rule and the PowerShell rule each sit on their own line, so
  # the PowerShell `''` can't be satisfied by the tail of `'\''`.
  grep -F 'bash/zsh writes' "$skill" | grep -qF "'\\''"
  ps_rule="$(grep -F 'PowerShell writes' "$skill")"
  [[ "$ps_rule" == *"''"* ]] || false
  [[ "$ps_rule" != *"'\\''"* ]] || false
}
