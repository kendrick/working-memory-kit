#!/usr/bin/env bats
# #28: --claude injects activeContext.md and the AGENTS.md on-demand table into
# additionalContext, so session start doesn't depend on the agent choosing to read.

load helpers

setup() {
  setup_repo
  mkdir -p _working-memory
  START="$KIT_ROOT/template/scripts/working-memory-session-start.sh"
}
teardown() { teardown_repo; }

# Decoded additionalContext, so assertions see what the model sees.
claude_ctx() {
  bash "$START" --claude </dev/null |
    python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'
}

@test "--claude injects activeContext.md's lines (#28)" {
  printf 'one\nsay "hi" \\ then\twith tab\nthree\n' > _working-memory/activeContext.md
  run claude_ctx
  [ "$status" -eq 0 ]
  tail_expected=$'\n\nCurrent _working-memory/activeContext.md:\none\nsay "hi" \\ then\twith tab\nthree'
  [[ "$output" == *"$tail_expected" ]] || false
}

@test "--claude injects the first MAX_LINES lines and counts the rest (#28)" {
  seq -f 'line %g' 1 25 > _working-memory/activeContext.md
  run claude_ctx
  [ "$status" -eq 0 ]
  expected="$(seq -f 'line %g' 1 20)"$'\n(5 more non-empty lines in activeContext.md; read the file for the rest.)'
  [[ "$output" == *$'Current _working-memory/activeContext.md:\n'"$expected" ]] || false
  [[ "$output" == *"has 25 non-empty lines (limit is 20)"* ]] || false
  [[ "$output" != *"line 21"* ]] || false
}

@test "--claude injects AGENTS.md's on-demand table (#28)" {
  printf 'x\n' > _working-memory/activeContext.md
  cp "$KIT_ROOT/template/AGENTS.md" AGENTS.md
  run claude_ctx
  [ "$status" -eq 0 ]
  # Literal rows, not a re-run of the hook's awk, so a change in the extraction rule fails.
  [[ "$output" == *$'\n\nOn-demand reads, from AGENTS.md:\n| File                 | Read when...'* ]] || false
  [[ "$output" == *$'\n| `projectOverview.md` | Before starting a feature, or onboarding to the codebase'* ]] || false
  [[ "$output" == *"| \`antipatterns.md\`    | Before proposing a refactor, library swap, or architectural change; check whether it's been tried  |" ]] || false
  table="${output#*"On-demand reads, from AGENTS.md:"$'\n'}"
  [ "$(printf '%s\n' "$table" | wc -l)" -eq 8 ]
}

@test "the table stops at end of file and survives CRLF (#28)" {
  printf 'x\n' > _working-memory/activeContext.md
  printf '# T\r\n\r\n### Read on demand:\r\n\r\n| File | When |\r\n| --- | --- |\r\n| `a.md` | now |\r\n' > AGENTS.md
  run claude_ctx
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\n\nOn-demand reads, from AGENTS.md:\n| File | When |\n| --- | --- |\n| `a.md` | now |' ]] || false
  [[ "$output" != *$'\r'* ]] || false
}

@test "no AGENTS.md, no table section; the JSON still parses (#28)" {
  printf 'x\n' > _working-memory/activeContext.md
  run claude_ctx
  [ "$status" -eq 0 ]
  [[ "$output" != *"On-demand reads"* ]] || false
}

@test "an activeContext created from the example is injected (#28)" {
  printf 'ex one\nex two\n' > _working-memory/activeContext.example.md
  run claude_ctx
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created activeContext.md from template"* ]] || false
  [[ "$output" == *$'Current _working-memory/activeContext.md:\nex one\nex two' ]] || false
}

@test "without --claude the output is unchanged (#28)" {
  printf 'x\n' > _working-memory/activeContext.md
  cp "$KIT_ROOT/template/AGENTS.md" AGENTS.md
  run bash "$START" </dev/null
  [ "$status" -eq 0 ]
  directive="Working memory at _working-memory/ is active. AGENT INSTRUCTION: before deciding what to read, scan the on-demand table in AGENTS.md's '## Working Memory' section. If your task matches a row, that file is required reading before you proceed."
  [ "$output" = "{\"systemMessage\":\"$directive\"}" ]
}

@test "a non-numeric line limit falls back to 20 and still emits JSON (#28)" {
  seq -f 'line %g' 1 25 > _working-memory/activeContext.md
  WORKING_MEMORY_MAX_LINES=abc run claude_ctx
  [ "$status" -eq 0 ]
  [[ "$output" == *"Current _working-memory/activeContext.md:"* ]] || false
  [[ "$output" == *"(limit is 20)"* ]] || false
}

@test "a CRLF activeContext.md reaches the model without carriage returns (#28)" {
  printf 'a\r\nb\r\n' > _working-memory/activeContext.md
  run claude_ctx
  [ "$status" -eq 0 ]
  [[ "$output" == *$'Current _working-memory/activeContext.md:\na\nb' ]] || false
  [[ "$output" != *$'\r'* ]] || false
}
