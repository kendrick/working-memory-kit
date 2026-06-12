#!/usr/bin/env bats
# V1b: the installer detects spec-driven neighbors from its registry and wires
# the boundary (ownership map, AGENTS cross-ref inside the fence, conventions
# deferral), warns on a rival memory tool, and leaves a no-neighbor install
# exactly as before. Detection triggers only on a tool-unique top-level path.

load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

XREF='Spec-driven tooling lives in'
START='<!-- working-memory:start -->'
END='<!-- working-memory:end -->'

# cross-ref must land BETWEEN the fence markers
xref_inside_fence() {
  awk -v r="$XREF" '/working-memory:start/{s=1} index($0,r){print (s?"yes":"no")} /working-memory:end/{s=0}' AGENTS.md
}

@test "Spec Kit: detected, cross-referenced in the fence, conventions pointed at its principles" {
  mkdir -p .specify/memory
  run run_installer
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'who owns what'                       # ownership map printed
  grep -q "$XREF.*Spec Kit" AGENTS.md                            # cross-ref names it
  [ "$(xref_inside_fence)" = yes ]                               # ...inside the markers
  grep -q 'constitution.md' _working-memory/conventions.md       # conventions deferral
  [ "$(grep -c 'coexistence:principles' _working-memory/conventions.md)" -eq 1 ]
}

@test "coexistence wiring is idempotent" {
  mkdir -p .specify
  run_installer
  git add -A; git commit -q -m base
  run_installer
  run git status --porcelain
  [ -z "$output" ]
  [ "$(grep -c "$XREF" AGENTS.md)" -eq 1 ]
  [ "$(grep -c 'coexistence:principles' _working-memory/conventions.md)" -eq 1 ]
}

@test "OpenSpec is detected by its own trigger" {
  mkdir -p openspec
  run_installer
  grep -q "$XREF.*OpenSpec" AGENTS.md
}

@test "BMAD is detected by its alternate trigger (.bmad-core)" {
  mkdir -p .bmad-core
  run_installer
  grep -q "$XREF.*BMAD" AGENTS.md
}

@test "Task Master (no principles file) gets a cross-ref but no conventions note" {
  mkdir -p .taskmaster
  run_installer
  grep -q "$XREF.*Task Master" AGENTS.md
  ! grep -q 'coexistence:principles' _working-memory/conventions.md
}

@test "Memory Bank warns and wires nothing" {
  mkdir -p memory-bank
  run run_installer
  echo "$output" | grep -qi 'two durable-memory systems'
  ! grep -q "$XREF" AGENTS.md
  ! grep -q 'coexistence:principles' _working-memory/conventions.md
}

@test "ADRs are mentioned but wire no principles" {
  mkdir -p docs/adr
  run run_installer
  echo "$output" | grep -q 'ADRs'
  ! grep -q "$XREF" AGENTS.md
  ! grep -q 'coexistence:principles' _working-memory/conventions.md
}

@test "multiple neighbors are all named" {
  mkdir -p .specify openspec
  run_installer
  grep -qE "$XREF.*(Spec Kit.*OpenSpec|OpenSpec.*Spec Kit)" AGENTS.md
}

@test "no neighbor: no wiring, still idempotent, coexistence doc still shipped" {
  run run_installer
  ! grep -q "$XREF" AGENTS.md
  ! grep -q 'coexistence:principles' _working-memory/conventions.md
  ! echo "$output" | grep -q 'who owns what'                                  # no ownership map
  grep -q 'Working alongside spec-driven tooling' _working-memory/README.md   # doc is static, always present
  git add -A; git commit -q -m base
  run_installer
  run git status --porcelain
  [ -z "$output" ]
}

@test "a bare specs/ directory does not trigger detection" {
  mkdir -p specs
  run_installer
  ! grep -q "$XREF" AGENTS.md
}
