#!/usr/bin/env bats
# Installer invariants: the scaffold lands, re-running is a no-op, and the
# installer never clobbers a user's pre-existing AGENTS.md / CLAUDE.md.

load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

@test "fresh install scaffolds the working memory" {
  run_installer
  [ -f _working-memory/decisionLog.md ]
  [ -f AGENTS.md ]
  grep -q '^## Working Memory' AGENTS.md
  grep -q 'activeContext.md' .gitignore
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
  git add -A; git commit -q -m base
  run_installer_tty $'mem\nu\n'                  # re-run, choose Upgrade
  run git status --porcelain
  [ -z "$output" ]
  run find . -name '*.kitnew'
  [ -z "$output" ]
}
