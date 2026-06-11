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
