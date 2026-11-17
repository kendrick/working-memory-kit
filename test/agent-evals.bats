#!/usr/bin/env bats
# #81: free checks for the eval-only plugin manifest and the hydrator wording.
# The paid behavior checks are the `claude plugin eval` cases under evals/.

load helpers

# Read the hook command from the manifest so tests 2 and 3 can't drift from it.
hook_cmd() {
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["hooks"]["SessionStart"][0]["hooks"][0]["command"])' "$KIT_ROOT/.claude-plugin/plugin.json"
}

@test "plugin.json shape (#81)" {
  run python3 - "$KIT_ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
m = json.load(open(os.path.join(root, ".claude-plugin/plugin.json")))
assert m["name"] == "working-memory-kit", m["name"]
assert m["skills"] == ["./.claude/skills/"], m["skills"]
assert m["agents"] == ["./.claude/agents/hydrator.md"], m["agents"]
for p in m["skills"] + m["agents"]:
    assert os.path.exists(os.path.join(root, p)), p
assert m["hooks"]["SessionStart"][0]["hooks"][0]["timeout"] == 10
assert "SessionEnd" not in m["hooks"]
assert not os.path.exists(os.path.join(root, ".claude-plugin/marketplace.json"))
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "hook is silent without the script (#81)" {
  dir="$(mktemp -d)"
  CLAUDE_PROJECT_DIR="$dir" run bash -c "$(hook_cmd)"
  rm -rf "$dir"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hook runs the installed script (#81)" {
  setup_repo
  run_installer >/dev/null
  CLAUDE_PROJECT_DIR="$TESTDIR" run bash -c "$(hook_cmd)"
  teardown_repo
  [ "$status" -eq 0 ]
  [[ "$output" == *additionalContext* ]] || false
  [[ "$output" == *"On-demand reads, from AGENTS.md"* ]] || false
}

@test "hydrator names both skill forms (#81)" {
  f="$KIT_ROOT/.claude/agents/hydrator.md"
  grep -qF '.claude/skills/hydrate-{discover,extract,draft,reconcile,propose}/' "$f"
  grep -qF 'working-memory-kit:hydrate-<phase>' "$f"
  ! grep -qF 'Each phase is a skill at' "$f"
  ! awk '/^---$/{n++; next} n==1' "$f" | grep -q '^skills:'
}

@test ".gitignore ignores eval results (#81)" {
  git -C "$KIT_ROOT" check-ignore -q evals/results/x.json
}

@test "install-kit builds the eval workspace (#81)" {
  dir="$(mktemp -d)"
  cd "$dir"
  GIT_CONFIG_GLOBAL=/dev/null run bash "$KIT_ROOT/evals/hydrate-trigger/scaffold.sh"
  [ "$status" -eq 0 ] || { echo "$output"; rm -rf "$dir"; false; }
  [ -d .git ]
  grep -qF '/api/v2/user-profiles' src/server.js
  [ -f scripts/working-memory-session-start.sh ]
  grep -qF '`conventions.md`' AGENTS.md
  naming="$(awk '/^## Naming/{f=1;next} /^## /{f=0} f' _working-memory/conventions.md)"
  rm -rf "$dir"
  [[ "$naming" == *kebab-case* ]] || false
  [[ "$naming" != *"_Not yet defined._"* ]] || false
}

@test "every case is complete (#81)" {
  for c in on-demand-conventions hydrate-trigger hydrate-non-trigger; do
    d="$KIT_ROOT/evals/$c"
    [ -f "$d/prompt.md" ]
    [ -f "$d/scaffold.sh" ]
    grep -qF 'scaffold_script: scaffold.sh' "$d/case.yaml"
    [ -n "$(ls "$d"/graders/*.md)" ]
  done
  [ ! -e "$KIT_ROOT/evals/_shared/case.yaml" ]
  [ ! -e "$KIT_ROOT/evals/_shared/prompt.md" ]
}

@test "on-demand case drops the Read grader (#81)" {
  d="$KIT_ROOT/evals/on-demand-conventions/graders"
  ! grep -rqF 'type: tool_used' "$d"
  grep -qF 'weight: 2' "$d/first-call-targets-conventions.md"
  grep -qF 'target: trace' "$d/first-call-targets-conventions.md"
}
