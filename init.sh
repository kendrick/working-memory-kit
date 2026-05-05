#!/bin/bash
# memory-bank-kit installer (macOS/Linux)
# Scaffolds a two-tier memory bank into the current project, with config
# for both Claude Code and GitHub Copilot.

set -euo pipefail

# Replace REPO_DEFAULT before publishing the kit. Forks and private mirrors
# override at install time via the env vars below.
REPO_DEFAULT="kendrick/memory-bank-kit"
REPO="${MEMORY_BANK_KIT_REPO:-$REPO_DEFAULT}"
BRANCH="${MEMORY_BANK_KIT_BRANCH:-main}"

# ---------- helpers ----------

c_blue()  { printf "\033[34m%s\033[0m" "$1"; }
c_green() { printf "\033[32m%s\033[0m" "$1"; }
c_yellow(){ printf "\033[33m%s\033[0m" "$1"; }
c_red()   { printf "\033[31m%s\033[0m" "$1"; }

say()   { printf "%s\n" "$*"; }
info()  { printf "%s %s\n" "$(c_blue "[info]")" "$*"; }
ok()    { printf "%s %s\n" "$(c_green "[ok]")" "$*"; }
warn()  { printf "%s %s\n" "$(c_yellow "[warn]")" "$*"; }
fail()  { printf "%s %s\n" "$(c_red "[error]")" "$*" >&2; }

confirm() {
  local prompt="${1:-Continue?}"
  local default="${2:-y}"
  local hint
  if [ "$default" = "y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  printf "%s %s " "$prompt" "$hint"
  read -r reply
  reply="${reply:-$default}"
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# Always prompts before overwriting. Re-running the installer to pick up
# kit upgrades is expected, and a silent overwrite would clobber local edits.
copy_if_absent() {
  local src="$1" dst="$2"
  if [ -e "$dst" ]; then
    if confirm "  $dst already exists. Overwrite?" "n"; then
      cp "$src" "$dst"
      ok "overwrote $dst"
    else
      info "kept existing $dst"
    fi
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    ok "created $dst"
  fi
}

# Idempotency relies on the marker line. If a user renames the heading the
# detection misses and a duplicate section gets appended on re-run, which is
# easier to spot than a silent skip. That's the trade we want.
append_section_if_missing() {
  local src="$1" dst="$2" marker="$3"
  if [ ! -f "$dst" ]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    ok "created $dst"
    return
  fi
  if grep -qF "$marker" "$dst"; then
    info "$dst already contains memory-bank section, leaving alone"
    return
  fi
  printf "\n" >> "$dst"
  cat "$src" >> "$dst"
  ok "appended memory-bank section to $dst"
}

# ---------- locate template ----------

# Two install paths: a cloned kit (template/ next to this script) or curl-pipe
# (script alone, fetches the tarball). Local wins so kit devs can iterate
# without round-tripping GitHub.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
TARGET_DIR="$(pwd)"
TEMPLATE=""

if [ -d "$SCRIPT_DIR/template" ]; then
  TEMPLATE="$SCRIPT_DIR/template"
  info "using local template at $TEMPLATE"
else
  info "downloading template from $REPO@$BRANCH"
  TMPDIR_=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_"' EXIT
  if ! curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH" \
      | tar -xz -C "$TMPDIR_"; then
    fail "could not download template from $REPO@$BRANCH"
    fail "set MEMORY_BANK_KIT_REPO and MEMORY_BANK_KIT_BRANCH if you forked"
    exit 1
  fi
  TEMPLATE="$(find "$TMPDIR_" -maxdepth 2 -type d -name template | head -n1)"
  if [ -z "$TEMPLATE" ] || [ ! -d "$TEMPLATE" ]; then
    fail "downloaded archive did not contain a template/ directory"
    exit 1
  fi
fi

# ---------- intro ----------

say ""
say "$(c_blue "memory-bank-kit installer")"
say "Target: $TARGET_DIR"
say ""

if [ "$TARGET_DIR" = "$SCRIPT_DIR" ]; then
  warn "you're running this from the kit's own repo."
  warn "this would scaffold the kit into itself (dogfood). Continue only if that's intentional."
  if ! confirm "Proceed?" "n"; then
    say "aborted."
    exit 0
  fi
fi

# ---------- detect stack ----------

detect_stack() {
  local lang="" framework="" pkg=""
  if [ -f package.json ]; then
    lang="JavaScript/TypeScript"
    if grep -q '"next"' package.json 2>/dev/null; then framework="Next.js"
    elif grep -q '"react"' package.json 2>/dev/null; then framework="React"
    elif grep -q '"vue"' package.json 2>/dev/null; then framework="Vue"
    elif grep -q '"svelte"' package.json 2>/dev/null; then framework="Svelte"
    fi
    pkg="package.json"
  elif [ -f pyproject.toml ]; then
    lang="Python"; pkg="pyproject.toml"
    if grep -q 'django' pyproject.toml 2>/dev/null; then framework="Django"
    elif grep -q 'fastapi' pyproject.toml 2>/dev/null; then framework="FastAPI"
    elif grep -q 'flask' pyproject.toml 2>/dev/null; then framework="Flask"
    fi
  elif [ -f Cargo.toml ]; then
    lang="Rust"; pkg="Cargo.toml"
  elif [ -f go.mod ]; then
    lang="Go"; pkg="go.mod"
  elif [ -f Gemfile ]; then
    lang="Ruby"; pkg="Gemfile"
    if grep -q 'rails' Gemfile 2>/dev/null; then framework="Rails"; fi
  fi
  printf "%s|%s|%s" "$lang" "$framework" "$pkg"
}

STACK_INFO="$(detect_stack)"
DETECTED_LANG="$(echo "$STACK_INFO" | cut -d'|' -f1)"
DETECTED_FRAMEWORK="$(echo "$STACK_INFO" | cut -d'|' -f2)"

if [ -n "$DETECTED_LANG" ]; then
  info "detected: $DETECTED_LANG${DETECTED_FRAMEWORK:+ ($DETECTED_FRAMEWORK)}"
else
  info "no recognized stack detected (no package.json/pyproject.toml/Cargo.toml/go.mod/Gemfile)"
fi

# ---------- check existing structure ----------

EXISTING=()
[ -d "$TARGET_DIR/memory-bank" ] && EXISTING+=("memory-bank/")
[ -d "$TARGET_DIR/.claude" ] && EXISTING+=(".claude/")
[ -d "$TARGET_DIR/.github" ] && EXISTING+=(".github/")
[ -f "$TARGET_DIR/AGENTS.md" ] && EXISTING+=("AGENTS.md")
[ -f "$TARGET_DIR/CLAUDE.md" ] && EXISTING+=("CLAUDE.md")

if [ "${#EXISTING[@]}" -gt 0 ]; then
  warn "found existing config: ${EXISTING[*]}"
  warn "files will be merged where possible. You'll be prompted before overwrites."
  if ! confirm "Continue?" "y"; then
    say "aborted."
    exit 0
  fi
fi

say ""
info "scaffolding..."

# ---------- memory-bank ----------

mkdir -p "$TARGET_DIR/memory-bank"
for f in activeContext.example.md projectOverview.md decisionLog.md dataContracts.md conventions.md openQuestions.md; do
  copy_if_absent "$TEMPLATE/memory-bank/$f" "$TARGET_DIR/memory-bank/$f"
done

# Each developer gets their own activeContext.md.
if [ ! -f "$TARGET_DIR/memory-bank/activeContext.md" ]; then
  cp "$TARGET_DIR/memory-bank/activeContext.example.md" "$TARGET_DIR/memory-bank/activeContext.md"
  ok "created your local memory-bank/activeContext.md from the template"
fi

# Skip pre-population if the placeholder marker is gone: the team has filled
# in their overview by hand and we shouldn't clobber it on re-run.
if [ -n "$DETECTED_LANG" ] && grep -q "^_To be filled._" "$TARGET_DIR/memory-bank/projectOverview.md" 2>/dev/null; then
  TMP_OVERVIEW=$(mktemp)
  REPO_NAME="$(basename "$TARGET_DIR")"
  cat > "$TMP_OVERVIEW" <<EOF
# Project Overview

## What This Is
<!-- One sentence. What does this project do? -->
$REPO_NAME — _add a one-sentence description here._

## Stack
- Language: $DETECTED_LANG
- Framework: ${DETECTED_FRAMEWORK:-_(none detected)_}
- Styling:
- Data layer:
- Deployment:

## Repository Structure
<!-- Top-level directory map. Update as the layout changes. -->
\`\`\`
$(ls -d */ 2>/dev/null | head -20 | sed 's|/$||' | sed 's|^|- |')
\`\`\`

## Key Constraints
<!-- Non-obvious things an agent must know: monorepo rules, legacy code -->
<!-- boundaries, API version requirements, browser support, etc. -->
EOF
  mv "$TMP_OVERVIEW" "$TARGET_DIR/memory-bank/projectOverview.md"
  ok "pre-populated memory-bank/projectOverview.md with detected stack"
fi

# ---------- .memory-bankrc.example ----------

# We ship the example, not the rc itself. Defaults are baked into the hook
# scripts; the rc is opt-in for teams that want to override line limits or
# nudge thresholds. Devs cp it to .memory-bankrc when they need it.
copy_if_absent \
  "$TEMPLATE/.memory-bankrc.example" \
  "$TARGET_DIR/.memory-bankrc.example"

# ---------- AGENTS.md (merge or create) ----------

append_section_if_missing \
  "$TEMPLATE/AGENTS.md" \
  "$TARGET_DIR/AGENTS.md" \
  "## Memory Bank"

# ---------- Claude Code config ----------

mkdir -p "$TARGET_DIR/.claude/agents"
copy_if_absent \
  "$TEMPLATE/.claude/agents/memory-bank-synchronizer.md" \
  "$TARGET_DIR/.claude/agents/memory-bank-synchronizer.md"

CLAUDE_SECTION=$(mktemp)
cat > "$CLAUDE_SECTION" <<'EOF'

## Memory Bank

On session start, always read `memory-bank/activeContext.md`.
Read other memory bank files as directed by the table in `AGENTS.md`.
After significant work, run the memory-bank-synchronizer agent or manually update active context.
EOF
append_section_if_missing "$CLAUDE_SECTION" "$TARGET_DIR/CLAUDE.md" "## Memory Bank"
rm -f "$CLAUDE_SECTION"

# ---------- Copilot config ----------

mkdir -p \
  "$TARGET_DIR/.github/agents" \
  "$TARGET_DIR/.github/skills/update-memory-bank" \
  "$TARGET_DIR/.github/hooks" \
  "$TARGET_DIR/.github/instructions"

copy_if_absent \
  "$TEMPLATE/.github/agents/memory-bank-synchronizer.agent.md" \
  "$TARGET_DIR/.github/agents/memory-bank-synchronizer.agent.md"

copy_if_absent \
  "$TEMPLATE/.github/skills/update-memory-bank/SKILL.md" \
  "$TARGET_DIR/.github/skills/update-memory-bank/SKILL.md"

copy_if_absent \
  "$TEMPLATE/.github/hooks/memory-bank-hooks.json" \
  "$TARGET_DIR/.github/hooks/memory-bank-hooks.json"

copy_if_absent \
  "$TEMPLATE/.github/instructions/data-layer.instructions.md" \
  "$TARGET_DIR/.github/instructions/data-layer.instructions.md"

append_section_if_missing \
  "$TEMPLATE/.github/copilot-instructions.md" \
  "$TARGET_DIR/.github/copilot-instructions.md" \
  "## Memory Bank"

# ---------- scripts ----------

mkdir -p "$TARGET_DIR/scripts"
for f in memory-bank-session-start.sh memory-bank-session-start.ps1 \
         memory-bank-session-end.sh memory-bank-session-end.ps1 \
         update-memory-bank.sh update-memory-bank.ps1; do
  copy_if_absent "$TEMPLATE/scripts/$f" "$TARGET_DIR/scripts/$f"
done
chmod +x "$TARGET_DIR/scripts/"*.sh 2>/dev/null || true
ok "marked scripts/*.sh executable"

# ---------- gitignore ----------

GITIGNORE="$TARGET_DIR/.gitignore"
GIT_LINE="memory-bank/activeContext.md"
if [ -f "$GITIGNORE" ]; then
  if grep -qxF "$GIT_LINE" "$GITIGNORE"; then
    info ".gitignore already excludes activeContext.md"
  else
    printf "\n# Local-only active context (memory-bank-kit)\n%s\n" "$GIT_LINE" >> "$GITIGNORE"
    ok "added activeContext.md to .gitignore"
  fi
else
  printf "# Local-only active context (memory-bank-kit)\n%s\n" "$GIT_LINE" > "$GITIGNORE"
  ok "created .gitignore with activeContext.md entry"
fi

# ---------- parity check ----------

say ""
info "verifying parity..."
PARITY_OK=1
for pair in \
  ".claude/agents/memory-bank-synchronizer.md|.github/agents/memory-bank-synchronizer.agent.md"
do
  CLAUDE_F="${pair%%|*}"
  COPILOT_F="${pair##*|}"
  if [ -f "$TARGET_DIR/$CLAUDE_F" ] && [ -f "$TARGET_DIR/$COPILOT_F" ]; then
    ok "parity: $CLAUDE_F <-> $COPILOT_F"
  else
    warn "parity miss: $CLAUDE_F or $COPILOT_F is absent"
    PARITY_OK=0
  fi
done

# ---------- done ----------

say ""
say "$(c_green "done.")"
say ""
say "next steps:"
say "  1. Open memory-bank/projectOverview.md and fill in 'What This Is'."
say "  2. Edit memory-bank/activeContext.md to reflect what you're working on."
say "  3. Teammates: after cloning, run:"
say "       cp memory-bank/activeContext.example.md memory-bank/activeContext.md"
say "  4. To sync the bank: invoke the memory-bank-synchronizer agent, or"
say "     run: ./scripts/update-memory-bank.sh"
say "  5. To tune line limits or nudge thresholds:"
say "       cp .memory-bankrc.example .memory-bankrc   # then edit"

if [ "$PARITY_OK" -eq 0 ]; then
  say ""
  warn "some parity checks failed. Review the messages above."
fi
