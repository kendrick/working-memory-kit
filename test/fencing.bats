#!/usr/bin/env bats
# V1a: the installer fences its working-memory section in AGENTS.md, CLAUDE.md,
# and copilot-instructions.md, and only ever touches text between its own
# markers. The invariant under test everywhere: user content and any neighbor's
# block survive a (re)install byte-for-byte.

load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

START='<!-- working-memory:start -->'
END='<!-- working-memory:end -->'

@test "fresh install fences all three files exactly once" {
  run_installer
  for f in AGENTS.md CLAUDE.md .github/copilot-instructions.md; do
    [ "$(grep -c "$START" "$f")" -eq 1 ]
    [ "$(grep -c "$END" "$f")" -eq 1 ]
  done
}

@test "AGENTS.md fences only the working-memory section, not Conventions" {
  run_installer
  # ## Conventions must sit AFTER the end marker (outside the fence)
  sed -n "/$END/,\$p" AGENTS.md | grep -q '^## Conventions'
}

@test "re-install is idempotent (replace-between is a no-op)" {
  run_installer
  git add -A
  git commit -q -m base
  run_installer
  run git status --porcelain
  [ -z "$output" ]
}

@test "a neighbor's block outside the markers survives a re-install" {
  run_installer
  printf '\n<!-- other-tool:start -->\nNEIGHBOR DATA\n<!-- other-tool:end -->\n' >> AGENTS.md
  git add -A
  git commit -q -m base
  run_installer
  run git status --porcelain
  [ -z "$output" ]                      # nothing changed
  grep -q 'NEIGHBOR DATA' AGENTS.md      # neighbor still present
}

@test "legacy unfenced AGENTS.md migrates once, keeping Conventions" {
  printf '# AGENTS.md\n\n## Working Memory\n\nold unfenced content.\n\n## Conventions\n\nuser rule X.\n' > AGENTS.md
  run_installer
  [ "$(grep -c "$START" AGENTS.md)" -eq 1 ]
  ! grep -q 'old unfenced content' AGENTS.md
  grep -q 'user rule X.' AGENTS.md
  # a second pass stays idempotent
  git add -A; git commit -q -m base
  run_installer
  run git status --porcelain
  [ -z "$output" ]
}

@test "legacy CLAUDE.md migration keeps user H1 content outside the fence" {
  printf '## Working Memory\n\nold pointer.\nTo sync working memory, run old.\n\n# My Project\n\nuser content that must survive.\n' > CLAUDE.md
  run_installer
  [ "$(grep -c "$START" CLAUDE.md)" -eq 1 ]
  grep -q 'user content that must survive.' CLAUDE.md
  sed -n "/$END/,\$p" CLAUDE.md | grep -q 'user content that must survive.'
}

@test "legacy CLAUDE.md migration keeps heading-less user prose (sentinel-bounded)" {
  printf '## Working Memory\n\nold.\nTo sync working memory, see old docs.\n\nplain user prose, no heading, must survive.\n' > CLAUDE.md
  run_installer
  grep -q 'must survive.' CLAUDE.md
  sed -n "/$END/,\$p" CLAUDE.md | grep -q 'must survive.'
}

@test "an unboundable legacy section is left alone, not mangled" {
  printf '## Working Memory\n\nweird legacy, no end line, no other heading, just prose.\n' > CLAUDE.md
  run run_installer
  [ "$status" -eq 0 ]                                  # install still succeeds
  echo "$output" | grep -qi 'could not bound safely'   # warns
  ! grep -q "$START" CLAUDE.md                          # left unfenced
  grep -q 'weird legacy' CLAUDE.md                      # legacy content intact
}

@test "injecting into an existing AGENTS.md with no WM section adds it once" {
  printf '# AGENTS.md\n\n## Stack\n\nGo.\n' > AGENTS.md
  run_installer
  grep -q 'Go.' AGENTS.md                          # user content kept
  [ "$(grep -c "$START" AGENTS.md)" -eq 1 ]
  [ "$(grep -c '^## Working Memory' AGENTS.md)" -eq 1 ]
}
