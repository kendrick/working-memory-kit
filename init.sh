#!/bin/bash
# working-memory-kit installer (macOS/Linux)
# Scaffolds a two-tier working memory into the current project, with config
# for both Claude Code and GitHub Copilot.

set -euo pipefail

# Replace REPO_DEFAULT before publishing the kit. Forks and private mirrors
# override at install time via the env vars below.
REPO_DEFAULT="kendrick/working-memory-kit"
REPO="${WORKING_MEMORY_KIT_REPO:-$REPO_DEFAULT}"
BRANCH="${WORKING_MEMORY_KIT_BRANCH:-main}"

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
    info "$dst already contains working-memory section, leaving alone"
    return
  fi
  printf "\n" >> "$dst"
  cat "$src" >> "$dst"
  ok "appended working-memory section to $dst"
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
    fail "set WORKING_MEMORY_KIT_REPO and WORKING_MEMORY_KIT_BRANCH if you forked"
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
say "$(c_blue "working-memory-kit installer")"
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

# ---------- working-memory directory choice ----------

# Default is _working-memory (underscore prefix keeps it grouped near
# similarly-prefixed tooling directories at the top of file listings).
# Consumer can override at install time; on override, the installer
# substitutes the literal token in copied template files.
WM_DIR_DEFAULT="_working-memory"
WM_DIR="$WM_DIR_DEFAULT"
printf "Install working memory at %s/? [Y/n, or specify alternate path] " "$WM_DIR_DEFAULT"
read -r wm_reply
case "$wm_reply" in
  ""|y|Y|yes|YES) ;;
  n|N|no|NO)
    printf "Enter alternate path (relative to repo root): "
    read -r wm_custom
    if [ -n "$wm_custom" ]; then
      WM_DIR="${wm_custom%/}"
    fi
    ;;
  *) WM_DIR="${wm_reply%/}" ;;
esac
info "working memory will be installed at $WM_DIR/"

# ---------- check existing structure ----------

EXISTING=()
[ -d "$TARGET_DIR/$WM_DIR" ] && EXISTING+=("$WM_DIR/")
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

# ---------- working-memory ----------

mkdir -p "$TARGET_DIR/$WM_DIR"
for f in activeContext.example.md projectOverview.md decisionLog.md dataContracts.md conventions.md openQuestions.md; do
  copy_if_absent "$TEMPLATE/_working-memory/$f" "$TARGET_DIR/$WM_DIR/$f"
done

# Each developer gets their own activeContext.md.
if [ ! -f "$TARGET_DIR/$WM_DIR/activeContext.md" ]; then
  cp "$TARGET_DIR/$WM_DIR/activeContext.example.md" "$TARGET_DIR/$WM_DIR/activeContext.md"
  ok "created your local $WM_DIR/activeContext.md from the template"
fi

# Skip pre-population if the placeholder marker is gone: the team has filled
# in their overview by hand and we shouldn't clobber it on re-run.
if [ -n "$DETECTED_LANG" ] && grep -q "^_To be filled._" "$TARGET_DIR/$WM_DIR/projectOverview.md" 2>/dev/null; then
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
  mv "$TMP_OVERVIEW" "$TARGET_DIR/$WM_DIR/projectOverview.md"
  ok "pre-populated $WM_DIR/projectOverview.md with detected stack"
fi

# ---------- .working-memoryrc.example ----------

# We ship the example, not the rc itself. Defaults are baked into the hook
# scripts; the rc is opt-in for teams that want to override line limits or
# nudge thresholds. Devs cp it to .working-memoryrc when they need it.
copy_if_absent \
  "$TEMPLATE/.working-memoryrc.example" \
  "$TARGET_DIR/.working-memoryrc.example"

# ---------- AGENTS.md (merge or create) ----------

append_section_if_missing \
  "$TEMPLATE/AGENTS.md" \
  "$TARGET_DIR/AGENTS.md" \
  "## Working Memory"

# ---------- Claude Code config ----------

mkdir -p "$TARGET_DIR/.claude/agents" "$TARGET_DIR/.claude/skills/update-working-memory"
copy_if_absent \
  "$TEMPLATE/.claude/agents/working-memory-synchronizer.md" \
  "$TARGET_DIR/.claude/agents/working-memory-synchronizer.md"
copy_if_absent \
  "$TEMPLATE/.claude/skills/update-working-memory/SKILL.md" \
  "$TARGET_DIR/.claude/skills/update-working-memory/SKILL.md"

CLAUDE_SECTION=$(mktemp)
cat > "$CLAUDE_SECTION" <<'EOF'

## Working Memory

On session start, always read `_working-memory/activeContext.md`.
Read other working memory files as directed by the table in `AGENTS.md`.
After significant work, run the working-memory-synchronizer agent or manually update active context.
EOF
append_section_if_missing "$CLAUDE_SECTION" "$TARGET_DIR/CLAUDE.md" "## Working Memory"
rm -f "$CLAUDE_SECTION"

# ---------- Copilot config ----------

mkdir -p \
  "$TARGET_DIR/.github/hooks" \
  "$TARGET_DIR/.github/instructions"

copy_if_absent \
  "$TEMPLATE/.github/hooks/working-memory-hooks.json" \
  "$TARGET_DIR/.github/hooks/working-memory-hooks.json"

copy_if_absent \
  "$TEMPLATE/.github/instructions/data-layer.instructions.md" \
  "$TARGET_DIR/.github/instructions/data-layer.instructions.md"

append_section_if_missing \
  "$TEMPLATE/.github/copilot-instructions.md" \
  "$TARGET_DIR/.github/copilot-instructions.md" \
  "## Working Memory"

# ---------- scripts ----------

mkdir -p "$TARGET_DIR/scripts"
for f in working-memory-session-start.sh working-memory-session-start.ps1 \
         working-memory-session-end.sh working-memory-session-end.ps1 \
         update-working-memory.sh update-working-memory.ps1; do
  copy_if_absent "$TEMPLATE/scripts/$f" "$TARGET_DIR/scripts/$f"
done
chmod +x "$TARGET_DIR/scripts/"*.sh 2>/dev/null || true
ok "marked scripts/*.sh executable"

# ---------- gitignore ----------

GITIGNORE="$TARGET_DIR/.gitignore"
GIT_LINE="$WM_DIR/activeContext.md"
if [ -f "$GITIGNORE" ]; then
  if grep -qxF "$GIT_LINE" "$GITIGNORE"; then
    info ".gitignore already excludes activeContext.md"
  else
    printf "\n# Local-only active context (working-memory-kit)\n%s\n" "$GIT_LINE" >> "$GITIGNORE"
    ok "added activeContext.md to .gitignore"
  fi
else
  printf "# Local-only active context (working-memory-kit)\n%s\n" "$GIT_LINE" > "$GITIGNORE"
  ok "created .gitignore with activeContext.md entry"
fi

# ---------- substitute WM_DIR token in copied files if user overrode default ----------

if [ "$WM_DIR" != "$WM_DIR_DEFAULT" ]; then
  info "substituting _working-memory -> $WM_DIR in copied template files"
  for f in \
    "AGENTS.md" \
    "CLAUDE.md" \
    ".claude/agents/working-memory-synchronizer.md" \
    ".claude/skills/update-working-memory/SKILL.md" \
    ".github/copilot-instructions.md" \
    ".github/instructions/data-layer.instructions.md" \
    "scripts/working-memory-session-start.sh" \
    "scripts/working-memory-session-end.sh" \
    "scripts/update-working-memory.sh" \
    "scripts/working-memory-session-start.ps1" \
    "scripts/working-memory-session-end.ps1" \
    "scripts/update-working-memory.ps1"
  do
    full="$TARGET_DIR/$f"
    if [ -f "$full" ]; then
      # BSD/GNU compatible: use -i with a backup extension, then drop the backup.
      # Single broad pattern catches every form: trailing slash, backslash,
      # closing quote in scripts (WM_DIR="$REPO_ROOT/_working-memory"), end of
      # line, etc. The token "_working-memory" only ever appears as the install
      # path; script filenames use "working-memory-" (no underscore prefix),
      # env vars use WORKING_MEMORY_*, and the rc file is .working-memoryrc.
      # None collide.
      sed -i.bak "s|_working-memory|$WM_DIR|g" "$full"
      rm -f "$full.bak"
    fi
  done
fi

# ---------- parity check ----------

say ""
info "verifying canonical artifacts..."
CANONICAL_OK=1
for f in \
  ".claude/agents/working-memory-synchronizer.md" \
  ".claude/skills/update-working-memory/SKILL.md"
do
  if [ -f "$TARGET_DIR/$f" ]; then
    ok "present: $f"
  else
    warn "missing: $f"
    CANONICAL_OK=0
  fi
done

# ---------- done ----------

say ""
say "$(c_green "done.")"
say ""
say "next steps:"
say "  1. Open $WM_DIR/projectOverview.md and fill in 'What This Is'."
say "  2. Edit $WM_DIR/activeContext.md to reflect what you're working on."
say "  3. Teammates: after cloning, run:"
say "       cp $WM_DIR/activeContext.example.md $WM_DIR/activeContext.md"
say "  4. To sync working memory: invoke the working-memory-synchronizer agent, or"
say "     run: ./scripts/update-working-memory.sh"
say "  5. To tune line limits or nudge thresholds:"
say "       cp .working-memoryrc.example .working-memoryrc   # then edit"

if [ "$CANONICAL_OK" -eq 0 ]; then
  say ""
  warn "some canonical artifacts are missing. Review the messages above."
fi
