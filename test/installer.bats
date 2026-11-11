#!/usr/bin/env bats
# Installer invariants: the scaffold lands, re-running is a no-op, and the
# installer never clobbers a user's pre-existing AGENTS.md / CLAUDE.md.

load helpers

# Exits 2 if the event isn't an array, so a shape regression fails loudly.
count_hook() {
  node -e '
    const s = require(process.cwd() + "/.claude/settings.json");
    const g = (s.hooks || {})[process.argv[1]] || [];
    if (!Array.isArray(g)) process.exit(2);
    console.log(g.flatMap(x => x.hooks || []).filter(h => (h.command || "").includes(process.argv[2])).length);
  ' "$1" "$2"
}

setup() { setup_repo; }
teardown() { teardown_repo; }

@test "fresh install scaffolds the working memory" {
  run_installer
  [ -f _working-memory/decisionLog.md ]
  [ -f AGENTS.md ]
  grep -q '^## Working Memory' AGENTS.md
  grep -q 'activeContext.md' .gitignore
}

@test "fresh install exposes Codex skills, hydrator, and lifecycle hooks" {
  run_installer
  [ -f .agents/skills/update-working-memory/SKILL.md ]
  [ -f .agents/skills/hydrate-discover/SKILL.md ]
  [ -f .agents/skills/hydrate-extract/SKILL.md ]
  [ -f .agents/skills/hydrate-draft/SKILL.md ]
  [ -f .agents/skills/hydrate-reconcile/SKILL.md ]
  [ -f .agents/skills/hydrate-propose/SKILL.md ]
  [ -f .codex/agents/hydrator.toml ]
  [ -f .codex/hooks.json ]
  cmp "$KIT_ROOT/template/.claude/skills/update-working-memory/SKILL.md" \
      .agents/skills/update-working-memory/SKILL.md
  for skill in hydrate-discover hydrate-extract hydrate-draft hydrate-reconcile hydrate-propose; do
    cmp "$KIT_ROOT/.claude/skills/$skill/SKILL.md" ".agents/skills/$skill/SKILL.md"
  done
  node -e '
    const hooks = require("./.codex/hooks.json");
    const start = hooks.hooks.SessionStart[0].hooks[0];
    const end = hooks.hooks.SessionEnd[0].hooks[0];
    if (!start.command || !start.commandWindows) process.exit(1);
    if (!end.command || !end.commandWindows || end.timeout !== 3) process.exit(1);
    if (!start.command.includes("working-memory-session-start.sh")) process.exit(1);
    if (!start.commandWindows.includes("working-memory-session-start.ps1")) process.exit(1);
    if (!end.command.includes("working-memory-session-end.sh")) process.exit(1);
    if (!end.commandWindows.includes("working-memory-session-end.ps1")) process.exit(1);
  '
}

@test "Codex machinery renders custom memory paths and reconciles hook edits" {
  run_installer_tty $'mem\n'
  grep -q 'mem/' .agents/skills/update-working-memory/SKILL.md
  printf '\n' >> .codex/hooks.json
  run_installer_tty $'mem\nu\n'
  [ -f .codex/hooks.json.kitnew ]
  ! cmp -s .codex/hooks.json .codex/hooks.json.kitnew
}

@test "install is idempotent" {
  # package.json exercises the stack pre-fill paths, which must also be a no-op
  # on the second run (they're guarded by placeholder markers).
  printf '{ "dependencies": { "react": "^18.0.0" } }\n' > package.json
  run_installer
  git add -A
  git commit -q -m base
  run_installer
  run git status --porcelain
  [ -z "$output" ]
}

@test "no-clobber: existing AGENTS.md keeps user content, section added once" {
  printf '# My Project\n\nCustom house rules.\n' > AGENTS.md
  run_installer
  grep -q 'Custom house rules.' AGENTS.md
  [ "$(grep -c '^## Working Memory' AGENTS.md)" -eq 1 ]
  # a second install must not duplicate the section or disturb user content
  run_installer
  grep -q 'Custom house rules.' AGENTS.md
  [ "$(grep -c '^## Working Memory' AGENTS.md)" -eq 1 ]
}

@test "no-clobber: existing CLAUDE.md is prepended, user content kept" {
  printf '# My CLAUDE\n\nProject specifics.\n' > CLAUDE.md
  run_installer
  grep -q 'Project specifics.' CLAUDE.md
  [ "$(grep -c '^## Working Memory' CLAUDE.md)" -eq 1 ]
}

@test "stack detection: package.json react lands in the stack" {
  printf '{ "dependencies": { "react": "^18.0.0" } }\n' > package.json
  run_installer
  grep -q 'React' AGENTS.md
  grep -q 'React' _working-memory/projectOverview.md
}

@test "stack detection: pyproject.toml lands Python" {
  printf '[project]\nname = "x"\ndependencies = ["django"]\n' > pyproject.toml
  run_installer
  grep -q 'Python' _working-memory/projectOverview.md
}

# ---- upgrade flow ----

@test "headless re-run resolves to upgrade automatically" {
  run_installer
  git add -A; git commit -q -m base
  run run_installer
  [[ "$output" == *"upgrading..."* ]]
}

@test "upgrade menu: choosing Cancel changes nothing" {
  run_installer
  git add -A; git commit -q -m base
  # feed the wm-dir prompt (enter = default), then 'c' for Cancel
  run run_installer_tty $'\nc\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"cancelled"* ]]
  run git status --porcelain
  [ -z "$output" ]
}

@test "upgrade menu: choosing Upgrade proceeds" {
  run_installer
  git add -A; git commit -q -m base
  run run_installer_tty $'\nu\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"upgrading"* ]]
}

@test "machinery divergence writes a .kitnew, keeps your edit, spares content" {
  run_installer
  printf '\n# local tweak\n' >> scripts/update-working-memory.sh
  printf '\nMy own decision.\n' >> _working-memory/decisionLog.md
  run_installer
  [ -f scripts/update-working-memory.sh.kitnew ]                       # sidecar written
  grep -q 'local tweak' scripts/update-working-memory.sh              # your edit kept
  grep -q 'a newer version of this file shipped' scripts/update-working-memory.sh  # pointer added
  [[ "$(head -1 scripts/update-working-memory.sh)" == '#!'* ]]         # pointer sits after the shebang
  grep -q 'My own decision.' _working-memory/decisionLog.md            # content untouched
}

@test "an unmodified machinery file gets no .kitnew" {
  run_installer
  git add -A; git commit -q -m base
  run_installer
  run find . -name '*.kitnew'
  [ -z "$output" ]
}

@test "a diverged upgrade is byte-stable on the next run" {
  run_installer
  printf '\n# local tweak\n' >> scripts/update-working-memory.sh
  run_installer                                  # first upgrade: .kitnew + pointer
  cp scripts/update-working-memory.sh "$BATS_TEST_TMPDIR/stable"
  run_installer                                  # second upgrade: live file must not move
  diff -q "$BATS_TEST_TMPDIR/stable" scripts/update-working-memory.sh
  [ "$(grep -c 'a newer version of this file shipped' scripts/update-working-memory.sh)" -eq 1 ]
}

@test "--overwrite-machinery takes the kit version and spares content" {
  run_installer
  printf '\n# local tweak\n' >> scripts/update-working-memory.sh
  printf '\nMy own decision.\n' >> _working-memory/decisionLog.md
  run_installer --overwrite-machinery
  ! grep -q 'local tweak' scripts/update-working-memory.sh            # kit version taken
  grep -q 'My own decision.' _working-memory/decisionLog.md           # content still spared
}

@test "additive: a missing content file is restored on upgrade" {
  run_installer
  printf '\nMy own decision.\n' >> _working-memory/decisionLog.md
  rm _working-memory/antipatterns.md
  run_installer
  [ -f _working-memory/antipatterns.md ]                             # restored
  grep -q 'My own decision.' _working-memory/decisionLog.md          # existing content untouched
}

@test "the Copilot instructions example ships inert" {
  run_installer
  [ -f .github/instructions/working-memory.instructions.md.example ]
  # nothing VS Code's active *.instructions.md glob would pick up
  run find .github/instructions -name '*.instructions.md'
  [ -z "$output" ]
}

@test "a custom working-memory dir re-runs clean" {
  run_installer_tty $'mem\n'                     # fresh install into mem/
  [ -d mem ]
  grep -qx 'WORKING_MEMORY_DIR="mem"' .working-memoryrc
  git add -A; git commit -q -m base
  run_installer_tty $'mem\nu\n'                  # re-run, choose Upgrade
  run git status --porcelain
  [ -z "$output" ]
  run find . -name '*.kitnew'
  [ -z "$output" ]
  run_installer                                  # headless re-run (#43)
  [ ! -d _working-memory ]
  [ "$(grep -c '_working-memory' AGENTS.md)" -eq 0 ]
  run git status --porcelain; [ -z "$output" ]
  run find . -name '*.kitnew'; [ -z "$output" ]
}

@test "deleting WORKING_MEMORY_DIR sends a headless re-run to _working-memory (#43)" {
  run_installer_tty $'mem\n'
  grep -qx 'WORKING_MEMORY_DIR="mem"' .working-memoryrc
  perl -i -ne 'print unless /^WORKING_MEMORY_DIR=/' .working-memoryrc
  run_installer
  [ -d _working-memory ]
}

@test "an unrelated rc key change leaves the custom dir alone (#43)" {
  run_installer_tty $'mem\n'
  printf 'NUDGE_FILE_THRESHOLD=9\n' >> .working-memoryrc
  git add -A; git commit -q -m base
  run_installer
  [ ! -d _working-memory ]
  grep -qx 'WORKING_MEMORY_DIR="mem"' .working-memoryrc
  run git status --porcelain; [ -z "$output" ]
}

@test "a default install writes no .working-memoryrc; an escaping rc dir is refused (#43)" {
  run_installer
  [ ! -f .working-memoryrc ]
  printf 'WORKING_MEMORY_DIR="../outside"\n' > .working-memoryrc
  run run_installer
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'WORKING_MEMORY_DIR'
  [ ! -d ../outside ]
}

@test "an absolute rc dir is refused and nothing is created there (#43)" {
  printf 'WORKING_MEMORY_DIR="%s"\n' "$BATS_TEST_TMPDIR/abs" > .working-memoryrc
  run run_installer
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "ignoring WORKING_MEMORY_DIR=\"$BATS_TEST_TMPDIR/abs\" in .working-memoryrc: it must be a relative path inside the repo"
  [ ! -e "$BATS_TEST_TMPDIR/abs" ]
  [ -d _working-memory ]
}

@test "a drive-letter or backslash-escaping rc dir is refused (#43)" {
  printf 'WORKING_MEMORY_DIR="C:/x"\n' > .working-memoryrc
  run run_installer
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'ignoring WORKING_MEMORY_DIR="C:/x" in .working-memoryrc: it must be a relative path inside the repo'
  [ ! -e C: ]
  printf 'WORKING_MEMORY_DIR="..\\x"\n' > .working-memoryrc
  run run_installer
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'ignoring WORKING_MEMORY_DIR="..\x" in .working-memoryrc: it must be a relative path inside the repo'
  [ ! -e '..\x' ]
}

@test "a prompt answer outside the repo is used but not saved (#43)" {
  # Install from a subdir so ../sib stays inside TESTDIR and teardown removes it.
  mkdir repo && cd repo && git init -q
  run run_installer_tty $'n\n../sib\n'
  [ -d ../sib ]
  echo "$output" | grep -qF 'not saving WORKING_MEMORY_DIR="../sib": a re-run only reuses a relative path inside the repo using only letters, digits, and . _ - / \'
  run grep -q '^WORKING_MEMORY_DIR=' .working-memoryrc
  [ "$status" -ne 0 ]
}

@test "an rc dir outside the allow-list is refused before it reaches a hook (#49)" {
  printf 'WORKING_MEMORY_DIR="x$(touch PWNED)"\n' > .working-memoryrc
  run run_installer
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'ignoring WORKING_MEMORY_DIR="x$(touch PWNED)" in .working-memoryrc: it must be a relative path inside the repo using only letters, digits, and . _ - / \'
  [ -d _working-memory ]
  run find . -name PWNED; [ -z "$output" ]
  run grep -rlF 'x$(touch' scripts; [ -z "$output" ]
}

@test "a typed dir with sed metacharacters can't inject a sed command (#49)" {
  run run_installer_tty $'x|g;1e touch PWNED;#\n'
  echo "$output" | grep -qF 'not saving WORKING_MEMORY_DIR="x|g;1e touch PWNED;#"'
  # GNU sed would run `e touch PWNED` unescaped; BSD sed has no `e`, so the render assert bites there.
  run find . -name PWNED; [ -z "$output" ]
  grep -qF 'x|g;1e touch PWNED;#/activeContext.md' '.claude/skills/update-working-memory/SKILL.md'
  grep -qF 'x|g;1e touch PWNED;#/' AGENTS.md
}

@test "a typed dir with & and a backslash renders literally (#49)" {
  run_installer_tty $'a&b\\c\n'
  grep -qF 'a&b\c/activeContext.md' '.claude/skills/update-working-memory/SKILL.md'
  grep -qF 'a&b\c/' AGENTS.md
}

@test "fresh install writes Claude Code session hooks that run (#36)" {
  run_installer
  [ "$(count_hook SessionStart working-memory-session-start.sh)" -eq 1 ]
  [ "$(count_hook SessionEnd working-memory-session-end.sh)" -eq 1 ]
  cmd="$(node -e 'console.log(require(process.cwd()+"/.claude/settings.json").hooks.SessionStart[0].hooks[0].command)')"
  CLAUDE_PROJECT_DIR="$PWD" bash -c "$cmd" | python3 -c 'import json,sys; assert json.load(sys.stdin)["systemMessage"]'
}

@test "re-install keeps one copy of each Claude hook and a pre-existing hook (#36)" {
  mkdir -p .claude
  printf '%s\n' '{"permissions":{"allow":["Bash(ls)"]},"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"echo mine"}]}]}}' > .claude/settings.json
  run_installer
  git add -A; git commit -q -m base
  run_installer
  [ "$(count_hook SessionStart 'echo mine')" -eq 1 ]
  [ "$(count_hook SessionStart working-memory-session-start.sh)" -eq 1 ]
  [ "$(count_hook SessionEnd working-memory-session-end.sh)" -eq 1 ]
  node -e 'const s=require(process.cwd()+"/.claude/settings.json"); if (s.permissions.allow[0] !== "Bash(ls)") process.exit(1)'
  run git status --porcelain; [ -z "$output" ]
}

@test "an invalid .claude/settings.json is left alone with a warning (#36)" {
  mkdir -p .claude
  printf '{ "hooks": ,\n' > .claude/settings.json
  cp .claude/settings.json "$BATS_TEST_TMPDIR/orig"
  run run_installer
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'not valid JSON'
  cmp .claude/settings.json "$BATS_TEST_TMPDIR/orig"
}

@test "re-install swaps an old kit entry for the current one and drops its duplicate (#36)" {
  mkdir -p .claude
  printf '%s\n' '{"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"echo mine"},{"type":"command","command":"bash scripts/working-memory-session-start.sh","timeout":5}]},{"hooks":[{"type":"command","command":"bash scripts/working-memory-session-start.sh"}]}]}}' > .claude/settings.json
  run_installer
  [ "$(count_hook SessionStart 'echo mine')" -eq 1 ]
  [ "$(count_hook SessionStart working-memory-session-start.sh)" -eq 1 ]
  node -e '
    const s = require(process.cwd() + "/.claude/settings.json");
    const t = require(process.argv[1]);
    const g = s.hooks.SessionStart;
    if (g.length !== 1 || g[0].matcher !== "startup") process.exit(1);
    const h = g[0].hooks[1], k = t.hooks.SessionStart[0].hooks[0];
    if (h.command !== k.command || h.timeout !== k.timeout) process.exit(1);
  ' "$KIT_ROOT/template/.claude/settings.json"
}
