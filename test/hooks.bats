#!/usr/bin/env bats
# Session-end hook behavior: the nudge fires on real work, stays quiet
# otherwise, and (the #6 regression) does not miscount during an in-progress
# merge. Thresholds are driven low via a fixture .working-memoryrc.

load helpers

setup() {
  setup_repo
  mkdir -p _working-memory
  HOOK="$KIT_ROOT/template/scripts/working-memory-session-end.sh"
  START="$KIT_ROOT/template/scripts/working-memory-session-start.sh"
}
teardown() { teardown_repo; }

# `git diff HEAD` needs a HEAD, so every test commits a base first, then makes
# the "session's work" on top of it.
commit_base() {
  git add -A
  git commit -q -m base
}

@test "session-end nudges above threshold" {
  printf 'NUDGE_FILE_THRESHOLD=1\nNUDGE_LINE_THRESHOLD=1\n' > .working-memoryrc
  commit_base
  printf 'a\n' > f1.txt
  printf 'b\n' > f2.txt
  git add -A
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'systemMessage'
  echo "$output" | grep -q 'update-working-memory'
}

@test "session-end is silent below threshold" {
  printf 'NUDGE_FILE_THRESHOLD=50\nNUDGE_LINE_THRESHOLD=5000\n' > .working-memoryrc
  commit_base
  printf 'a\n' > f1.txt
  git add -A
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-end skips during an in-progress merge (regression for #6)" {
  printf 'NUDGE_FILE_THRESHOLD=1\nNUDGE_LINE_THRESHOLD=1\n' > .working-memoryrc
  commit_base
  # a large change that would normally nudge...
  for i in 1 2 3 4 5 6; do printf 'x\n' > "big$i.txt"; done
  git add -A
  # ...but a merge is in progress, so the diff is polluted by the incoming side
  : > "$(git rev-parse --absolute-git-dir)/MERGE_HEAD"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a broken dataContracts pointer is reported when the nudge fires" {
  printf 'NUDGE_FILE_THRESHOLD=1\nNUDGE_LINE_THRESHOLD=1\n' > .working-memoryrc
  printf '# Data Contracts\n\nSee [types](src/missing.ts).\n' > _working-memory/dataContracts.md
  commit_base
  printf 'a\n' > f1.txt
  printf 'b\n' > f2.txt
  git add -A
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'broken pointer'
}

@test "session-end JSON survives a quote, a backslash, and a backslash-t in pointers (#41)" {
  printf 'NUDGE_FILE_THRESHOLD=1\nNUDGE_LINE_THRESHOLD=1\n' > .working-memoryrc
  printf '%s\n' '# Data Contracts' '' 'See [a](src/"x".ts), [b](src\y.ts), [c](src\t.ts).' > _working-memory/dataContracts.md
  commit_base
  printf 'a\n' > f1.txt; printf 'b\n' > f2.txt
  git add -A
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json, sys
m = json.load(sys.stdin)["systemMessage"]
for p in ["src/\"x\".ts", "src\\y.ts", "src\\t.ts"]:
    assert p in m, (p, m)
'
}

@test "session-end JSON escapes a real tab in a pointer (#41)" {
  printf 'NUDGE_FILE_THRESHOLD=1\nNUDGE_LINE_THRESHOLD=1\n' > .working-memoryrc
  printf '# Data Contracts\n\nSee [a](src/a\tb.ts).\n' > _working-memory/dataContracts.md
  commit_base
  printf 'a\n' > f1.txt; printf 'b\n' > f2.txt
  git add -A
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json, sys
m = json.load(sys.stdin)["systemMessage"]
assert "src/a\tb.ts" in m, m
'
}

@test "session-start JSON parses and keeps a backslash in a custom dir name (#41)" {
  mkdir 'mem\t'
  sed 's|_working-memory|mem\\t|g' "$KIT_ROOT/template/scripts/working-memory-session-start.sh" > start.sh
  printf 'x\n' > 'mem\t/activeContext.md'
  run bash start.sh
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json, sys
m = json.load(sys.stdin)["systemMessage"]
assert "mem\\t/" in m, m
assert "AGENTS.md\x27s" in m, m
'
}

# Claude Code ignores systemMessage for model context; SessionStart only injects
# hookSpecificOutput.additionalContext.
@test "session-start --claude emits additionalContext and no systemMessage" {
  START="$KIT_ROOT/template/scripts/working-memory-session-start.sh"
  printf 'x\n' > _working-memory/activeContext.md
  run bash "$START" --claude
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json, sys
o = json.load(sys.stdin)
assert list(o) == ["hookSpecificOutput"], o
h = o["hookSpecificOutput"]
assert h["hookEventName"] == "SessionStart", h
assert "AGENT INSTRUCTION" in h["additionalContext"], h
'
}

@test "session-start --claude carries the size-warning condition" {
  START="$KIT_ROOT/template/scripts/working-memory-session-start.sh"
  printf 'MAX_ACTIVE_CONTEXT_LINES=2\n' > .working-memoryrc
  printf 'a\nb\nc\nd\n' > _working-memory/activeContext.md
  run bash "$START" --claude
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json, sys
m = json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
assert "AGENT INSTRUCTION" in m and "has 4 non-empty lines (limit is 2)" in m, m
'
}

@test "session-start without --claude still emits systemMessage" {
  START="$KIT_ROOT/template/scripts/working-memory-session-start.sh"
  printf 'x\n' > _working-memory/activeContext.md
  run bash "$START"
  printf '%s' "$output" | python3 -c 'import json,sys; assert "systemMessage" in json.load(sys.stdin)'
}

# #35: commit-as-you-go sessions end with a clean tree, so the nudge has to
# count from the commit recorded at session start rather than HEAD.
make_files() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do printf 'x\n' > "w$i.txt"; done
}

@test "session-end counts work committed after session start (#35)" {
  printf 'NUDGE_FILE_THRESHOLD=5\nNUDGE_LINE_THRESHOLD=5000\n' > .working-memoryrc
  commit_base
  bash "$START" </dev/null
  make_files
  git add -A
  git commit -q -m work
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '10 files'
}

@test "session-end is silent when the only commit predates session start (#35)" {
  printf 'NUDGE_FILE_THRESHOLD=5\nNUDGE_LINE_THRESHOLD=5000\n' > .working-memoryrc
  make_files
  commit_base
  bash "$START" </dev/null
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-end falls back to HEAD when the recorded base is gone (#35)" {
  printf 'NUDGE_FILE_THRESHOLD=5\nNUDGE_LINE_THRESHOLD=5000\n' > .working-memoryrc
  commit_base
  printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' > "$(git rev-parse --absolute-git-dir)/working-memory-session-base"
  make_files
  git add -A
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '10 files'
}

@test "session-end reads a base file with no trailing newline (#35)" {
  printf 'NUDGE_FILE_THRESHOLD=5\nNUDGE_LINE_THRESHOLD=5000\n' > .working-memoryrc
  commit_base
  printf '%s' "$(git rev-parse HEAD)" > "$(git rev-parse --absolute-git-dir)/working-memory-session-base"
  make_files
  git add -A
  git commit -q -m work
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '10 files'
}

@test "session-start --claude keeps the base on a compact (#35)" {
  printf 'NUDGE_FILE_THRESHOLD=5\nNUDGE_LINE_THRESHOLD=5000\n' > .working-memoryrc
  commit_base
  bash "$START" </dev/null
  make_files
  git add -A
  git commit -q -m work
  echo '{"source": "compact"}' | bash "$START" --claude >/dev/null
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '10 files'
}

@test "session-start writes no base in a repo with no commits (#35)" {
  run bash "$START" </dev/null
  [ "$status" -eq 0 ]
  [ ! -e "$(git rev-parse --absolute-git-dir)/working-memory-session-base" ]
}

@test "session-start --claude resets the base when compact is only another value (#35)" {
  printf 'NUDGE_FILE_THRESHOLD=5\nNUDGE_LINE_THRESHOLD=5000\n' > .working-memoryrc
  commit_base
  bash "$START" </dev/null
  make_files
  git add -A
  git commit -q -m work
  echo '{"source":"startup","x":"compact"}' | bash "$START" --claude >/dev/null
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-start exits 0 when the git dir is read-only (#35)" {
  [ "$(id -u)" -ne 0 ] || skip "root ignores chmod"
  printf 'x\n' > seed.txt
  commit_base
  gd="$(git rev-parse --absolute-git-dir)"
  chmod a-w "$gd"
  run bash "$START" </dev/null
  chmod u+w "$gd"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'systemMessage'
}

@test "session-end exits 0 when the base file is unreadable (#35)" {
  [ "$(id -u)" -ne 0 ] || skip "root reads a mode-000 file"
  printf 'x\n' > seed.txt
  commit_base
  base="$(git rev-parse --absolute-git-dir)/working-memory-session-base"
  printf 'x' > "$base"
  chmod 000 "$base"
  run bash "$HOOK"
  chmod 600 "$base"
  [ "$status" -eq 0 ]
}

# #33: a Bank-connected repo (.ltm.yaml) that gains a decisionLog entry gets
# the ltm promote command. Thresholds are high so the size nudge stays off.
ltm_setup() {
  printf 'NUDGE_FILE_THRESHOLD=50\nNUDGE_LINE_THRESHOLD=5000\n' > .working-memoryrc
  printf 'bank: x\n' > .ltm.yaml
}

# Decoded systemMessage, so the assertions see what the host would show.
sysmsg() {
  printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["systemMessage"])'
}

promote_line() {
  printf 'working-memory: new decisionLog entry "%s". If it applies beyond this repo: ltm promote _working-memory/decisionLog.md --entry "%s"' "$1" "$1"
}

@test "session-end prints an ltm promote line per new decisionLog entry when .ltm.yaml exists (#33)" {
  ltm_setup
  commit_base
  bash "$START" </dev/null
  printf '## 2026-11-01: Cap retries at three per request\n\nbody\n\n## 2026-11-02: Drop the v1 API\n' > _working-memory/decisionLog.md
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  expected="$(promote_line 'Cap retries at three per request')
$(promote_line 'Drop the v1 API')"
  [ "$(sysmsg)" = "$expected" ]
}

@test "the promote nudge counts an entry committed during the session (#33)" {
  ltm_setup
  commit_base
  bash "$START" </dev/null
  printf '## 2026-11-01: Cap retries at three per request\n' > _working-memory/decisionLog.md
  git add -A
  git commit -q -m work
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(sysmsg)" = "$(promote_line 'Cap retries at three per request')" ]
}

@test "no .ltm.yaml, no promote line (#33)" {
  ltm_setup
  commit_base
  bash "$START" </dev/null
  printf '## 2026-11-01: Cap retries at three per request\n' > _working-memory/decisionLog.md
  rm .ltm.yaml
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a new heading in conventions.md prints nothing (#33)" {
  ltm_setup
  commit_base
  bash "$START" </dev/null
  printf '## 2026-11-01: Cap retries at three per request\n' > _working-memory/conventions.md
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "editing an existing entry's body prints nothing (#33)" {
  ltm_setup
  printf '## 2026-10-01: Use SQLite\n\nbody\n' > _working-memory/decisionLog.md
  commit_base
  bash "$START" </dev/null
  printf 'more reasoning\n' >> _working-memory/decisionLog.md
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a heading whose only change is case reads as new (#33)" {
  ltm_setup
  printf '## 2026-11-01: Cap Retries\n' > _working-memory/decisionLog.md
  commit_base
  bash "$START" </dev/null
  printf '## 2026-11-01: cap retries\n' > _working-memory/decisionLog.md
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(sysmsg)" = "$(promote_line 'cap retries')" ]
}

@test "the promote line keeps the JSON valid with a quote in the title (#33)" {
  ltm_setup
  commit_base
  bash "$START" </dev/null
  printf '## 2026-11-01: Use "at most once" delivery\n' > _working-memory/decisionLog.md
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(sysmsg)" = "$(promote_line 'Use "at most once" delivery')" ]
}

@test "the promote line follows the size nudge when both fire (#33)" {
  ltm_setup
  printf 'NUDGE_FILE_THRESHOLD=1\nNUDGE_LINE_THRESHOLD=1\n' > .working-memoryrc
  commit_base
  bash "$START" </dev/null
  printf '## 2026-11-01: Cap retries at three per request\n' > _working-memory/decisionLog.md
  printf 'a\n' > f1.txt
  git add -A
  git commit -q -m work
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  msg="$(sysmsg)"
  [ "$(printf '%s\n' "$msg" | sed -n 1p)" = "You changed 2 files and 2 lines this session. Use the update-working-memory skill or the supplied update script to keep working memory current." ]
  [ "$(printf '%s\n' "$msg" | sed -n 2p)" = "$(promote_line 'Cap retries at three per request')" ]
}
