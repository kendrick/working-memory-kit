#!/usr/bin/env bats
# Session-end hook behavior: the nudge fires on real work, stays quiet
# otherwise, and (the #6 regression) does not miscount during an in-progress
# merge. Thresholds are driven low via a fixture .working-memoryrc.

load helpers

setup() {
  setup_repo
  mkdir -p _working-memory
  HOOK="$KIT_ROOT/template/scripts/working-memory-session-end.sh"
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
