#!/usr/bin/env bats
# #81: free checks for the eval-only plugin manifest and the hydrator wording.
# The paid behavior checks are the `claude plugin eval` cases under evals/.

load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

# Read the hook command from the manifest so the "hook is silent" and "hook runs" tests can't drift from it.
hook_cmd() {
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["hooks"]["SessionStart"][0]["hooks"][0]["command"])' "$KIT_ROOT/.claude/.claude-plugin/plugin.json"
}

@test "eval plugin.json shape (#81, #82)" {
  run python3 - "$KIT_ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
m = json.load(open(os.path.join(root, ".claude/.claude-plugin/plugin.json")))
assert m["name"] == "working-memory-kit", m["name"]
# .claude/ already has the default skills/ and agents/ layout; a key would double-register them.
assert "skills" not in m and "agents" not in m
for ph in ("discover", "extract", "draft", "reconcile", "propose"):
    assert os.path.exists(os.path.join(root, ".claude/skills/hydrate-" + ph + "/SKILL.md")), ph
assert os.path.exists(os.path.join(root, ".claude/agents/hydrator.md"))
assert m["hooks"]["SessionStart"][0]["hooks"][0]["timeout"] == 10
assert "SessionEnd" not in m["hooks"]
assert not os.path.exists(os.path.join(root, ".claude-plugin/marketplace.json"))
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "hook is silent without the script (#81)" {
  cmd="$(hook_cmd)"
  [ -n "$cmd" ]  # an empty command would be silent for the wrong reason
  CLAUDE_PROJECT_DIR="$TESTDIR" run bash -c "$cmd"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hook runs the installed script (#81)" {
  run_installer >/dev/null
  cmd="$(hook_cmd)"
  [ -n "$cmd" ]
  CLAUDE_PROJECT_DIR="$TESTDIR" run bash -c "$cmd"
  [ "$status" -eq 0 ]
  [[ "$output" == *additionalContext* ]] || false
  [[ "$output" == *"On-demand reads, from AGENTS.md"* ]] || false
}

@test "hydrator names both skill forms (#81)" {
  f="$KIT_ROOT/.claude/agents/hydrator.md"
  grep -qF '.claude/skills/hydrate-{discover,extract,draft,reconcile,propose}/' "$f"
  grep -qF 'working-memory-kit:hydrate-<phase>' "$f"
  if grep -qF 'Each phase is a skill at' "$f"; then false; fi
  if awk '/^---$/{n++; next} n==1' "$f" | grep -q '^skills:'; then false; fi
}

@test ".gitignore ignores eval results (#81)" {
  git -C "$KIT_ROOT" check-ignore -q evals/results/x.json
}

@test "install-kit builds the eval workspace (#81)" {
  GIT_CONFIG_GLOBAL=/dev/null run bash "$KIT_ROOT/evals/hydrate-trigger/scaffold.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -d .git ]
  grep -qF '/api/v2/user-profiles' src/server.js
  [ -f scripts/working-memory-session-start.sh ]
  grep -qF '`conventions.md`' AGENTS.md
  naming="$(awk '/^## Naming/{f=1;next} /^## /{f=0} f' _working-memory/conventions.md)"
  [[ "$naming" == *kebab-case* ]] || false
  [[ "$naming" != *"_Not yet defined._"* ]] || false
}

@test "every case is complete (#81)" {
  for c in on-demand-conventions hydrate-trigger hydrate-non-trigger; do
    [ -d "$KIT_ROOT/evals/$c" ]
  done
  for d in "$KIT_ROOT"/evals/*/; do
    d="${d%/}"; c="$(basename "$d")"
    case "$c" in _shared|results) continue ;; esac  # results/ is gitignored eval output
    [ -f "$d/prompt.md" ]
    [ -f "$d/scaffold.sh" ]
    # A top-level scaffold_script is silently ignored, so the case runs in an empty workspace.
    grep -qx 'context:' "$d/case.yaml"
    grep -qxF '  scaffold_script: scaffold.sh' "$d/case.yaml"
    grep -q '^schema_version:' "$d/case.yaml"
    grep -qxF "name: $c" "$d/case.yaml"
    grep -qxF 'plugins: ["../../.claude"]' "$d/case.yaml"
    [ -n "$(ls "$d"/graders/*.md)" ]
  done
  [ ! -e "$KIT_ROOT/evals/_shared/case.yaml" ]
  [ ! -e "$KIT_ROOT/evals/_shared/prompt.md" ]
}

@test "on-demand case drops the Read grader (#81)" {
  d="$KIT_ROOT/evals/on-demand-conventions/graders"
  if grep -rqF 'type: tool_used' "$d"; then false; fi
  grep -qF 'weight: 2' "$d/first-call-targets-conventions.md"
  grep -qF 'target: trace' "$d/first-call-targets-conventions.md"
}

@test "agent-evals workflow gates on label or paths (#81)" {
  f="$KIT_ROOT/.github/workflows/agent-evals.yml"
  [ -f "$f" ]
  # Comments stripped, so a flag that's only mentioned in a comment doesn't count.
  live="$(sed -E -e '/^[[:space:]]*#/d' -e 's/[[:space:]]+#.*$//' "$f")"
  for s in '--max-cost-usd 3' '--ablation none' '--threshold 0.66' '--no-publish' \
           '--model claude-sonnet-5-5' 'secrets.ANTHROPIC_API_KEY' \
           "needs.changes.outputs.run == 'true'" "github.event.label.name == 'agent-evals'" \
           "github.event.label.name != 'agent-evals' && github.run_id || 'eval'"; do
    [[ "$live" == *"$s"* ]] || { echo "missing: $s"; false; }
  done
  # A paths filter also applies to `labeled` events, so it would stop the label from forcing a run.
  if grep -Eq '^[[:space:]]+paths(-ignore)?:' <<<"$live"; then echo "has a paths filter"; false; fi
  # Run the workflow's own path regex over sample paths rather than grepping its text.
  re="$(grep -F 'grep -qE' <<<"$live" | sed -E "s/.*grep -qE '([^']*)'.*/\1/")"
  [ -n "$re" ]
  for p in template/AGENTS.md init.sh template/scripts/working-memory-session-start.sh \
           .claude/skills/hydrate-discover/SKILL.md .claude/agents/hydrator.md \
           .claude-plugin/plugin.json .claude/.claude-plugin/plugin.json evals/hydrate-trigger/prompt.md; do
    grep -qE "$re" <<<"$p" || { echo "not gated: $p"; false; }
  done
  for p in README.md test/agent-evals.bats init.ps1 template/AGENTS.md.bak skills/init/SKILL.md; do
    if grep -qE "$re" <<<"$p"; then echo "gated but shouldn't be: $p"; false; fi
  done
}

@test "first-call grader matches only the first tool call's input (#81)" {
  # A batched message puts several tool_use objects on one trace line, so the
  # pattern must stop at the first call's input or a second call can pass it.
  run python3 - "$KIT_ROOT/evals/on-demand-conventions/graders/first-call-targets-conventions.md" <<'PY'
import json, re, sys
src = open(sys.argv[1]).read()
pat = re.search(r"^pattern: '(.*)'$", src, re.M).group(1).replace("''", "'")
def call(i, name, inp): return {"type": "tool_use", "id": f"t{i}", "name": name, "input": inp}
def line(*calls): return json.dumps({"type": "assistant", "message": {"content": list(calls)}}, separators=(",", ":"))
conv = {"file_path": "/w/_working-memory/conventions.md"}
cases = [
    (line(call(1, "Read", conv)), True),
    (line(call(1, "Glob", {"pattern": "**/{AGENTS.md,conventions.md}"})), True),
    (line(call(1, "Read", {"file_path": "/w/AGENTS.md"}), call(2, "Read", conv)), False),
    (line(call(1, "Grep", {"pattern": "route"})) + "\n" + line(call(2, "Read", conv)), False),
]
bad = [t for t, want in cases if bool(re.search(pat, t)) != want]
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
