#!/usr/bin/env bash
# Shared bats helpers for the working-memory-kit suite.

# The kit root is the parent of test/. init.sh and template/ live here.
KIT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export KIT_ROOT

# Each test gets its own throwaway git repo so tests can't contaminate each
# other or the kit checkout.
setup_repo() {
  TESTDIR="$(mktemp -d)"
  cd "$TESTDIR" || return 1
  git init -q
  git config user.email test@example.com
  git config user.name test
  git config commit.gpgsign false   # a global signing config would otherwise block test commits
}

teardown_repo() {
  cd / || return
  [ -n "${TESTDIR:-}" ] && rm -rf "$TESTDIR"
}

# Run the installer non-interactively. With stdin closed there's no tty, so the
# installer's prompts fall through to their defaults (keep _working-memory, an
# existing install resolves to the safe upgrade path). This is how the suite
# drives it without a test-only flag.
run_installer() {
  bash "$KIT_ROOT/init.sh" "$@" </dev/null
}

# Drive the installer through a pseudo-tty so its interactive prompts are
# reachable (the Upgrade/Cancel menu only appears with a real tty; a headless
# run always takes the upgrade default). $1 is the canned keystrokes fed to the
# prompts in order, newline-separated; the rest are installer args. NO_COLOR
# keeps the captured output plain so assertions match. python3 ships on the
# ubuntu-latest and macos-latest runners this suite targets.
run_installer_tty() {
  local input="$1"; shift
  WMK_TTY_INPUT="$input" WMK_KIT="$KIT_ROOT" NO_COLOR=1 \
    python3 "$KIT_ROOT/test/pty_run.py" "$@"
}
