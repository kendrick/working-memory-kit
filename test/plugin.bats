#!/usr/bin/env bats
# shellcheck disable=SC2016  # ${...} below is literal skill text Claude Code substitutes, not a shell expansion
# #82: the kit root is a Claude Code plugin whose one skill, init, runs the bundled installer.
# Tests 4 and 5 run the command block out of SKILL.md itself, so a parity pass here can't come from a hand-written copy.

load helpers

SKILL="$KIT_ROOT/skills/init/SKILL.md"

skill_block() {
  awk -v open="\`\`\`$1" '$0 == open { f = 1; next } f && /^```$/ { exit } f' "$SKILL"
}

# relpath, mtime_ns and size of everything under $1 but .git; python3 because BSD and GNU stat disagree.
snapshot() {
  python3 - "$1" <<'PY'
import os, sys
root = sys.argv[1]
rows = []
for d, dirs, files in os.walk(root):
    dirs[:] = [x for x in dirs if x != ".git"]
    for n in dirs + files:
        p = os.path.join(d, n)
        st = os.lstat(p)
        rows.append("%s\t%d\t%d" % (os.path.relpath(p, root), st.st_mtime_ns, st.st_size))
print("\n".join(sorted(rows)))
PY
}

new_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name test
  git -C "$1" config commit.gpgsign false
}

# Both repos are named "my app" because the installer derives names from the target dir.
# The spaces are deliberate: each command must keep a spaced path as one argument.
setup_parity() {
  root="$BATS_TEST_TMPDIR/plugin root"
  cp -R "$KIT_ROOT/." "$root"
  # In a linked worktree .git is a file pointing at the real repo; drop it so nothing here can touch that index.
  rm -rf "$root/.git"
  if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then return 1; fi
  before="$(snapshot "$root")"
  a="$BATS_TEST_TMPDIR/a/my app"
  b="$BATS_TEST_TMPDIR/b/my app"
  new_repo "$a"
  new_repo "$b"
  elsewhere="$BATS_TEST_TMPDIR/elsewhere"
  mkdir -p "$elsewhere"
  cmd="$(skill_block bash)"
  [ -n "$cmd" ] || return 1
  cmd="${cmd//'${CLAUDE_PLUGIN_ROOT}'/$root}"
  cmd="${cmd//'${CLAUDE_PROJECT_DIR}'/$a}"
}

@test "root manifest ships only init (#82)" {
  run python3 - "$KIT_ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
m = json.load(open(os.path.join(root, ".claude-plugin/plugin.json")))
assert m["name"] == "working-memory-kit", m["name"]
# Each of these keys adds to its default location rather than replacing it, so any one would ship more than init.
for k in ("skills", "agents", "commands", "hooks", "mcpServers", "lspServers", "outputStyles"):
    assert k not in m, k
for p in ("agents", "commands", "hooks", "output-styles", ".mcp.json"):
    assert not os.path.exists(os.path.join(root, p)), p
assert sorted(os.listdir(os.path.join(root, "skills"))) == ["init"], os.listdir(os.path.join(root, "skills"))
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "claude resolves each manifest (#82)" {
  command -v claude >/dev/null || skip "claude CLI not installed"
  root_json="$(claude plugin validate "$KIT_ROOT" --json)"
  eval_json="$(claude plugin validate "$KIT_ROOT/.claude" --json)"
  run python3 - "$root_json" "$eval_json" <<'PY'
import json, sys
r, e = json.loads(sys.argv[1]), json.loads(sys.argv[2])
assert r["success"] is True
assert r["provides"]["skills"] == ["working-memory-kit:init"], r["provides"]["skills"]
assert r["provides"]["agents"] == [], r["provides"]["agents"]
assert r["provides"]["hooks"] == [], r["provides"]["hooks"]
assert e["success"] is True
want = ["working-memory-kit:hydrate-" + p for p in ("discover", "draft", "extract", "propose", "reconcile")]
assert sorted(e["provides"]["skills"]) == want, e["provides"]["skills"]
assert e["provides"]["agents"] == ["working-memory-kit:hydrator"], e["provides"]["agents"]
assert len(e["provides"]["hooks"]) == 1, e["provides"]["hooks"]
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "init skill is user-invoked only (#82)" {
  [ -f "$SKILL" ]
  fm="$(awk '/^---$/ { n++; next } n == 1' "$SKILL")"
  grep -qx 'name: init' <<<"$fm"
  grep -qx 'disable-model-invocation: true' <<<"$fm"
  for f in --coexist-with --coexist-principles --no-coexist --overwrite-machinery --formatter-override --no-formatter-override; do
    grep -qF -- "$f" "$SKILL" || { echo "missing $f"; false; }
  done
  grep -qF -- "--coexist-with='specs'" "$SKILL"  # the = form is accepted by both installers; refusing it was a review finding
  [ "$(grep -c '^```bash$' "$SKILL")" -eq 1 ]
  [ "$(grep -c '^```powershell$' "$SKILL")" -eq 1 ]
  block="$(skill_block bash)"
  [[ "$block" == *'${CLAUDE_PLUGIN_ROOT}/init.sh'* ]] || false
  [[ "$block" == *'</dev/null'* ]] || false
  # Claude Code substitutes only the braced form in skill text; the bare variable isn't in the Bash tool's env.
  [[ "$block" != *'$CLAUDE_PROJECT_DIR"'* ]] || false
  # Single quotes can't hold these, and PowerShell also ends a single-quoted string on the typographic ones.
  refusal="$(grep -F 'run nothing and tell the user the installer' "$SKILL")"
  for q in "\`'\`" "‘" "’" "‚" "‛"; do
    [[ "$refusal" == *"$q"* ]] || { echo "refusal misses $q"; false; }
  done
  # Each rule sits on its own line, so the PowerShell `''` can't be satisfied by the tail of `'\''`.
  grep -E '^- bash ' "$SKILL" | grep -qF "\`'\\''\`"
  ps="$(grep -E '^- PowerShell ' "$SKILL")"
  for q in "\`''\`" "‘" "’" "‚" "‛"; do
    [[ "$ps" == *"$q"* ]] || { echo "PowerShell rule misses $q"; false; }
  done
}

@test "init skill's bash command installs like init.sh (#82)" {
  setup_parity
  cd "$elsewhere"
  run bash -c "$cmd"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run bash -c "$cmd"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  cd "$b"
  run bash "$KIT_ROOT/init.sh" </dev/null
  [ "$status" -eq 0 ]
  run bash "$KIT_ROOT/init.sh" </dev/null
  [ "$status" -eq 0 ]
  [ -f "$a/AGENTS.md" ]  # an empty pair of trees would diff clean for the wrong reason
  run diff -r -x .git "$a" "$b"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$output" ]
  [ "$(snapshot "$root")" = "$before" ]
  [ -z "$(ls -A "$elsewhere")" ]
}

@test "init skill passes the = form of a value flag through (#82)" {
  setup_parity
  mkdir -p "$a/my specs" "$b/my specs"
  cd "$elsewhere"
  run bash -c "$cmd --no-formatter-override --coexist-with='my specs'"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  cd "$b"
  run bash "$KIT_ROOT/init.sh" --no-formatter-override --coexist-with="my specs" </dev/null
  [ "$status" -eq 0 ]
  run diff -r -x .git "$a" "$b"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -rq 'my specs' "$a" --exclude-dir=.git  # proves the value reached the installer, not just that both runs agree
}

@test "init skill passes flags through (#82)" {
  setup_parity
  cd "$elsewhere"
  run bash -c "$cmd --no-coexist --no-formatter-override"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  cd "$b"
  run bash "$KIT_ROOT/init.sh" --no-coexist --no-formatter-override </dev/null
  [ "$status" -eq 0 ]
  run diff -r -x .git "$a" "$b"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$output" ]
  grep -q coexistence_asked "$a/.working-memoryrc"
  [ "$(snapshot "$root")" = "$before" ]
}

# The agent writes flag values itself, so an apostrophe in one must be escaped, not refused.
@test "init skill escapes an apostrophe in a flag value (#82)" {
  setup_parity
  # The worked example in SKILL.md is the command fragment the agent is told to write.
  arg="$(grep -o -- "--coexist-with='team'\\\\''s specs'" "$SKILL" | head -1)"
  [ -n "$arg" ] || { echo "no bash example for an apostrophe in SKILL.md"; false; }
  c="$BATS_TEST_TMPDIR/c/my app"
  new_repo "$c"
  mkdir -p "$a/team's specs" "$b/team's specs" "$c/team's specs"
  cd "$elsewhere"
  run bash -c "$cmd --no-formatter-override $arg"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run bash -c "${cmd//"$a"/$c} --no-formatter-override ${arg/=/ }"  # the space form of the same value
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  cd "$b"
  run bash "$KIT_ROOT/init.sh" --no-formatter-override --coexist-with "team's specs" </dev/null
  [ "$status" -eq 0 ]
  run diff -r -x .git "$a" "$b"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run diff -r -x .git "$c" "$b"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qF "team's specs" "$a/.working-memoryrc"
}

# A $ or backtick in a substituted path must stay literal, or the kit can install into a sibling dir.
@test "init skill keeps shell-special characters in substituted paths literal (#82)" {
  unset WMK_REVIEW_UNSET
  root="$BATS_TEST_TMPDIR/plugin \$WMK_REVIEW_UNSET \`echo x\` \"q\""
  cp -R "$KIT_ROOT/." "$root"
  rm -rf "$root/.git"
  if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then false; fi
  before="$(snapshot "$root")"
  a="$BATS_TEST_TMPDIR/a/project\$WMK_REVIEW_UNSET"
  sibling="$BATS_TEST_TMPDIR/a/project"
  b="$BATS_TEST_TMPDIR/b/project\$WMK_REVIEW_UNSET"
  new_repo "$a"
  new_repo "$sibling"
  new_repo "$b"
  elsewhere="$BATS_TEST_TMPDIR/elsewhere"
  mkdir -p "$elsewhere"
  cmd="$(skill_block bash)"
  cmd="${cmd//'${CLAUDE_PLUGIN_ROOT}'/$root}"
  cmd="${cmd//'${CLAUDE_PROJECT_DIR}'/$a}"
  cd "$elsewhere"
  run bash -c "$cmd"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ls -A "$sibling")" = ".git" ]
  cd "$b"
  run bash "$KIT_ROOT/init.sh" </dev/null
  [ "$status" -eq 0 ]
  [ -f "$a/AGENTS.md" ]
  run diff -r -x .git "$a" "$b"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(snapshot "$root")" = "$before" ]
}
