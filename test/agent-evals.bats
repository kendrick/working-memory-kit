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
