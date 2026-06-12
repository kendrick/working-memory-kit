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

# Under `curl | bash`, stdin is the script body, not the keyboard. Re-open
# /dev/tty for prompts so the user can actually answer. If there's no tty
# (CI, fully non-interactive), TTY_FD stays empty and reads return empty,
# letting defaults take over.
TTY_FD=""
if { exec 3</dev/tty; } 2>/dev/null; then
  TTY_FD=3
fi

prompt_read() {
  local __var="$1"
  if [ -n "$TTY_FD" ]; then
    # shellcheck disable=SC2229
    read -r -u "$TTY_FD" "$__var"
  else
    read -r "$__var" 2>/dev/null || eval "$__var=''"
  fi
}

confirm() {
  local prompt="${1:-Continue?}"
  local default="${2:-y}"
  local hint reply
  if [ "$default" = "y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  printf "%s %s " "$prompt" "$hint"
  prompt_read reply
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

# w-m-k owns one fenced section in each agent file. A (re)install only reads and
# replaces the text BETWEEN these markers, so a user's surrounding content and
# any neighboring tool's block survive untouched. The span is the kit's to
# refresh on upgrade; don't hand-edit between the markers.
WM_START='<!-- working-memory:start -->'
WM_END='<!-- working-memory:end -->'

# The fenced-section merge lives in one perl program because the work is
# multi-line, and BSD vs GNU sed diverge there (same reason the Stack pre-fill
# below reaches for perl). It reads $WMK_DST, picks the case, and writes it
# back. Exit 3 means "found an unfenced section I could not bound safely" so the
# caller warns instead of risking the user's content.
WMK_PERL='
my ($start, $end, $pos, $sent) = @ENV{qw(WMK_START WMK_END WMK_POSITION WMK_SENTINEL)};
open my $bf, "<", $ENV{WMK_BLOCK_FILE} or die "block: $!";
my $block = do { local $/; <$bf> }; close $bf;
$block =~ s/\n+\z//;
open my $df, "<", $ENV{WMK_DST} or die "dst: $!";
my $doc = do { local $/; <$df> }; close $df;
my ($qs, $qe) = (quotemeta($start), quotemeta($end));

if ($doc =~ /$qs/) {
    # already fenced: swap the body, leave the markers and everything else
    $doc =~ s/$qs.*?$qe/$block/s;
}
elsif ($doc =~ /^## Working Memory[ \t]*$/m) {
    # legacy unfenced section: migrate it in place, exactly once
    my @l = split /\n/, $doc, -1;
    my ($si) = grep { $l[$_] =~ /^## Working Memory[ \t]*$/ } 0 .. $#l;
    my $ei;
    if (length $sent) {
        for my $i ($si .. $#l) {
            last if $i > $si && $l[$i] =~ /^## /;      # next H2 before the end line: bail
            if (index($l[$i], $sent) >= 0) { $ei = $i; last; }
        }
    } else {
        $ei = $#l;
        for my $i ($si + 1 .. $#l) { if ($l[$i] =~ /^## /) { $ei = $i - 1; last; } }
        $ei-- while $ei > $si && $l[$ei] eq "";   # keep the blank line before the next heading
    }
    exit 3 unless defined $ei;
    my @pre  = $si > 0     ? @l[0 .. $si - 1]   : ();
    my @post = $ei < $#l   ? @l[$ei + 1 .. $#l] : ();
    $doc = join "\n", @pre, split(/\n/, $block, -1), @post;
}
else {
    # no section yet: splice the fenced block in
    if ($pos eq "prepend") { $doc = "$block\n\n$doc"; }
    else { $doc =~ s/\n*\z//; $doc = "$doc\n\n$block\n"; }
}
open my $out, ">", $ENV{WMK_DST} or die "write: $!";
print $out $doc; close $out;
'

# Pull the START..END span (inclusive) out of a fenced template, to splice into
# an existing target.
extract_block() {
  WMK_START="$WM_START" WMK_END="$WM_END" perl -0777 -ne \
    'my ($s,$e)=(quotemeta($ENV{WMK_START}),quotemeta($ENV{WMK_END})); print $1 if /($s.*?$e)/s;' "$1"
}

# Create / refresh / migrate / inject the kit's fenced section in $dst.
#   fresh    = file copied verbatim when $dst is absent (the whole template, or the block)
#   block    = the fenced START..END span to splice into an existing file
#   position = append | prepend (only used when $dst has no section yet)
#   sentinel = end-of-section text that bounds a legacy migration in prepend files
upsert_fenced_section() {
  local dst="$1" fresh="$2" block="$3" position="$4" sentinel="${5:-}"
  if [ ! -f "$dst" ]; then
    mkdir -p "$(dirname "$dst")"
    cp "$fresh" "$dst"
    ok "created $dst"
    return
  fi
  local rc=0
  WMK_DST="$dst" WMK_BLOCK_FILE="$block" WMK_POSITION="$position" \
  WMK_SENTINEL="$sentinel" WMK_START="$WM_START" WMK_END="$WM_END" \
    perl -e "$WMK_PERL" || rc=$?
  case "$rc" in
    0) ok "updated working-memory section in $dst" ;;
    3) warn "$dst has an unfenced Working Memory section I could not bound safely; left it as-is. Fence it by hand or remove it and re-run." ;;
    *) fail "could not update the working-memory section in $dst"; exit 1 ;;
  esac
}

# ---------- neighbor registry (keep in sync with init.ps1) ----------

# External spec-driven / memory tooling the kit should coexist with. One row
# per tool: name | kind | trigger[:alt-trigger] | principles_file
#   process  coexist and wire (ownership map + AGENTS cross-ref + conventions deferral)
#   memory   warn only; two durable-memory systems don't divide cleanly
#   note     mention only (overlaps the kit, nothing to wire)
# Triggers are tool-unique top-level paths; a bare specs/ is never a trigger.
WMK_NEIGHBORS="Spec Kit|process|.specify|.specify/memory/constitution.md
OpenSpec|process|openspec|openspec/project.md
Kiro|process|.kiro|.kiro/steering/
BMAD|process|bmad-core:.bmad-core|bmad-core/data/technical-preferences.md
Agent OS|process|.agent-os|.agent-os/standards/
Task Master|process|.taskmaster|
Memory Bank|memory|memory-bank|
ADRs|note|docs/adr:docs/decisions|"

# Echoes matched rows (name|kind|found-path|principles_file), one per line, for
# whatever neighbors are actually present in the target. Mirrors detect_stack's
# scan-and-report shape.
detect_neighbors() {
  local name kind triggers principles trig found
  while IFS='|' read -r name kind triggers principles; do
    [ -z "$name" ] && continue
    found=""
    for trig in $(printf '%s' "$triggers" | tr ':' ' '); do
      [ -d "$TARGET_DIR/$trig" ] && { found="$trig"; break; }
    done
    [ -n "$found" ] && printf '%s|%s|%s|%s\n' "$name" "$kind" "$found" "$principles"
  done <<EOF
$WMK_NEIGHBORS
EOF
  return 0   # a trailing unmatched row must not look like failure under set -e
}

# Cross-reference paragraph for the fenced AGENTS section, built from the
# detected process neighbors. Empty when there are none. The literal
# _working-memory token is rewritten later if the user chose a custom dir.
build_process_xref() {
  local tools="" name kind found principles
  while IFS='|' read -r name kind found principles; do
    [ "$kind" = process ] || continue
    tools="${tools}${tools:+, }$name (\`$found/\`)"
  done <<EOF
$1
EOF
  [ -n "$tools" ] && printf 'Spec-driven tooling lives in %s. Per-feature specs and plans stay there; this Working Memory section is the durable project state. Boundary: see [`_working-memory/README.md`](_working-memory/README.md).' "$tools"
  return 0   # no process neighbors is normal, not a failure
}

# Prints the who-owns-what map for process/note neighbors and a warning for any
# memory neighbor. $1 is the detected-rows blob.
print_coexistence_summary() {
  local rows="$1" name kind found principles mapped=0
  while IFS='|' read -r name kind found principles; do
    [ -z "$name" ] && continue
    case "$kind" in
      process)
        if [ "$mapped" -eq 0 ]; then say ""; info "Coexistence: who owns what now that neighbors are present:"; mapped=1; fi
        say "  - $name ($found/): principles in ${principles:-its own dir}; per-feature specs stay in the tool."
        ;;
      note)
        if [ "$mapped" -eq 0 ]; then say ""; info "Coexistence: who owns what now that neighbors are present:"; mapped=1; fi
        say "  - $name ($found/): overlaps decisionLog.md; left as-is, nothing wired."
        ;;
      memory)
        warn "Two durable-memory systems detected (working-memory-kit + $name, in $found/). They overlap; pick one as canonical or consolidate. The kit won't auto-merge."
        ;;
    esac
  done <<EOF
$rows
EOF
  if [ "$mapped" -eq 1 ]; then
    say "  - working-memory-kit: _working-memory/ and the fenced AGENTS.md section (durable state, decisions, conventions)."
    say "    Promote cross-cutting decisions up into _working-memory/decisionLog.md. The kit labels these lanes; it doesn't enforce them."
  fi
  return 0
}

# ---------- locate template ----------

# Two install paths: a cloned kit (template/ next to this script) or curl-pipe
# (script alone, fetches the tarball). Local wins so kit devs can iterate
# without round-tripping GitHub. Under `curl | bash`, BASH_SOURCE[0] is unset
# and `$0` is "bash"; the :- default keeps `set -u` happy and SCRIPT_DIR stays
# empty so the local-template and dogfood checks both fall through.
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_SOURCE" ] && [ -f "$SCRIPT_SOURCE" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
else
  SCRIPT_DIR=""
fi
TARGET_DIR="$(pwd)"
TEMPLATE=""

if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/template" ]; then
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

# Hydration artifacts live at the kit root's .claude/, not inside template/,
# because they're also used by kit contributors working in the kit repo itself.
# Resolve KIT_ROOT (parent of template/) so the installer can pull them too.
KIT_ROOT="$(dirname "$TEMPLATE")"

# ---------- intro ----------

say ""
say "$(c_blue "working-memory-kit installer")"
say "Target: $TARGET_DIR"
say ""

if [ -n "$SCRIPT_DIR" ] && [ "$TARGET_DIR" = "$SCRIPT_DIR" ]; then
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

# ---------- detect neighbor tooling ----------

# Detected once here; the wiring (AGENTS cross-ref, conventions note) and the
# printed summary downstream all read this.
NEIGHBORS="$(detect_neighbors)"

# ---------- working-memory directory choice ----------

# Default is _working-memory (underscore prefix keeps it grouped near
# similarly-prefixed tooling directories at the top of file listings).
# Consumer can override at install time; on override, the installer
# substitutes the literal token in copied template files.
WM_DIR_DEFAULT="_working-memory"
WM_DIR="$WM_DIR_DEFAULT"
printf "Install working memory at %s/? [Y/n, or specify alternate path] " "$WM_DIR_DEFAULT"
prompt_read wm_reply
case "$wm_reply" in
  ""|y|Y|yes|YES) ;;
  n|N|no|NO)
    printf "Enter alternate path (relative to repo root): "
    prompt_read wm_custom
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
for f in README.md activeContext.example.md projectOverview.md decisionLog.md dataContracts.md conventions.md openQuestions.md antipatterns.md; do
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

# ---------- conventions deferral note (process neighbor with a principles file) ----------

# Point conventions.md at the neighbor's principles file so it stays tactical
# and doesn't restate principles. Marker-guarded so re-runs don't stack it.
# Uses the first process neighbor that actually ships a principles file.
CONV_FILE="$TARGET_DIR/$WM_DIR/conventions.md"
PRINCIPLES_ROW="$(printf '%s\n' "$NEIGHBORS" | awk -F'|' '$2=="process" && $4!="" {print; exit}')"
if [ -n "$PRINCIPLES_ROW" ] && [ -f "$CONV_FILE" ] && ! grep -qF 'coexistence:principles' "$CONV_FILE"; then
  P_NAME="$(printf '%s' "$PRINCIPLES_ROW" | cut -d'|' -f1)"
  P_FILE="$(printf '%s' "$PRINCIPLES_ROW" | cut -d'|' -f4)"
  CONV_NOTE="<!-- coexistence:principles -->
> Project principles live in \`$P_FILE\` ($P_NAME). Keep this file to tactical patterns; don't restate principles."
  CONV_NOTE="$CONV_NOTE" perl -i -pe \
    's{^(<!-- This is the "how we do things here" file\. -->)$}{$1\n\n$ENV{CONV_NOTE}}' \
    "$CONV_FILE"
  ok "pointed $WM_DIR/conventions.md at $P_NAME principles ($P_FILE)"
fi

# ---------- .working-memoryrc.example ----------

# We ship the example, not the rc itself. Defaults are baked into the hook
# scripts; the rc is opt-in for teams that want to override line limits or
# nudge thresholds. Devs cp it to .working-memoryrc when they need it.
copy_if_absent \
  "$TEMPLATE/.working-memoryrc.example" \
  "$TARGET_DIR/.working-memoryrc.example"

# ---------- AGENTS.md (merge or create) ----------

# Build the AGENTS source: the template with the neighbor cross-reference folded
# into its fenced section (before the end marker) when a process neighbor is
# present. Used for BOTH the fresh-copy and the splice paths so they agree,
# which keeps re-installs idempotent (the post-upsert alternative fought the
# merge's newline handling).
AGENTS_SRC="$TEMPLATE/AGENTS.md"
AGENTS_XREF="$(build_process_xref "$NEIGHBORS")"
if [ -n "$AGENTS_XREF" ]; then
  AGENTS_SRC=$(mktemp)
  WMK_XREF="$AGENTS_XREF" WMK_END="$WM_END" perl -pe \
    's/^\Q$ENV{WMK_END}\E\s*$/$ENV{WMK_XREF}\n\n$ENV{WMK_END}/' "$TEMPLATE/AGENTS.md" > "$AGENTS_SRC"
fi
AGENTS_BLOCK=$(mktemp)
extract_block "$AGENTS_SRC" > "$AGENTS_BLOCK"
upsert_fenced_section \
  "$TARGET_DIR/AGENTS.md" \
  "$AGENTS_SRC" \
  "$AGENTS_BLOCK" \
  append
rm -f "$AGENTS_BLOCK"
if [ "$AGENTS_SRC" != "$TEMPLATE/AGENTS.md" ]; then rm -f "$AGENTS_SRC"; fi

# Pre-fill the Stack section if (a) we detected a language and (b) the
# placeholder comment is still present. The comment is the idempotency
# marker — once a human fills it in, the placeholder is gone and we
# leave the section alone on re-runs.
if [ -n "$DETECTED_LANG" ] && grep -qF "<!-- One line per layer. Detected from project. -->" "$TARGET_DIR/AGENTS.md"; then
  STACK_BLOCK="- Language: $DETECTED_LANG"
  [ -n "$DETECTED_FRAMEWORK" ] && STACK_BLOCK="$STACK_BLOCK"$'\n'"- Framework: $DETECTED_FRAMEWORK"
  # Use perl rather than awk/sed: BSD awk rejects embedded newlines in -v
  # values, and BSD/GNU sed multiline replacements diverge. Perl is reliably
  # present on every macOS/Linux machine where this installer runs.
  STACK_REPL="$STACK_BLOCK" perl -i -pe \
    's{<!-- One line per layer\. Detected from project\. -->}{$ENV{STACK_REPL}}' \
    "$TARGET_DIR/AGENTS.md"
  ok "pre-populated AGENTS.md Stack with detected stack"
fi

# ---------- Claude Code config ----------

mkdir -p "$TARGET_DIR/.claude/agents" "$TARGET_DIR/.claude/skills/update-working-memory"
copy_if_absent \
  "$TEMPLATE/.claude/agents/working-memory-synchronizer.md" \
  "$TARGET_DIR/.claude/agents/working-memory-synchronizer.md"
copy_if_absent \
  "$TEMPLATE/.claude/skills/update-working-memory/SKILL.md" \
  "$TARGET_DIR/.claude/skills/update-working-memory/SKILL.md"

# Hydration surface: composite agent + five phase skills. Sourced from the kit
# root (not template/) since kit contributors use the same files. Optional —
# installs cleanly if the kit version doesn't ship them yet.
if [ -f "$KIT_ROOT/.claude/agents/hydrator.md" ]; then
  copy_if_absent \
    "$KIT_ROOT/.claude/agents/hydrator.md" \
    "$TARGET_DIR/.claude/agents/hydrator.md"
fi
if [ -d "$KIT_ROOT/.claude/skills" ]; then
  for skill_dir in "$KIT_ROOT/.claude/skills/hydrate-"*; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    if [ -f "$skill_dir/SKILL.md" ]; then
      copy_if_absent \
        "$skill_dir/SKILL.md" \
        "$TARGET_DIR/.claude/skills/$skill_name/SKILL.md"
    fi
  done
fi

# Build the fenced CLAUDE block: markers from the variable, body kept literal
# (quoted heredoc) so its backticks and slashes aren't interpreted by the shell.
CLAUDE_BLOCK=$(mktemp)
{
  printf '%s\n' "$WM_START"
  cat <<'EOF'
## Working Memory

**AGENT INSTRUCTION:** before deciding what to read, scan the on-demand table under `## Working Memory` in [`AGENTS.md`](AGENTS.md). If your task matches a row, that file is required reading before you proceed.

Always read `_working-memory/activeContext.md` on session start. AGENTS.md is the canonical source for the on-demand table and update rules.
To sync working memory, run `/update-working-memory` or invoke the `working-memory-synchronizer` agent.
EOF
  printf '%s\n' "$WM_END"
} > "$CLAUDE_BLOCK"
upsert_fenced_section \
  "$TARGET_DIR/CLAUDE.md" \
  "$CLAUDE_BLOCK" \
  "$CLAUDE_BLOCK" \
  prepend \
  "To sync working memory"
rm -f "$CLAUDE_BLOCK"

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

COPILOT_BLOCK=$(mktemp)
extract_block "$TEMPLATE/.github/copilot-instructions.md" > "$COPILOT_BLOCK"
upsert_fenced_section \
  "$TARGET_DIR/.github/copilot-instructions.md" \
  "$TEMPLATE/.github/copilot-instructions.md" \
  "$COPILOT_BLOCK" \
  prepend \
  "To sync working memory"
rm -f "$COPILOT_BLOCK"

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
  ".claude/skills/update-working-memory/SKILL.md" \
  ".claude/agents/hydrator.md" \
  ".claude/skills/hydrate-discover/SKILL.md" \
  ".claude/skills/hydrate-extract/SKILL.md" \
  ".claude/skills/hydrate-draft/SKILL.md" \
  ".claude/skills/hydrate-reconcile/SKILL.md" \
  ".claude/skills/hydrate-propose/SKILL.md"
do
  if [ -f "$TARGET_DIR/$f" ]; then
    ok "present: $f"
  else
    warn "missing: $f"
    CANONICAL_OK=0
  fi
done

# ---------- done ----------

# Coexistence summary: who owns what, plus any memory-tool overlap warning.
print_coexistence_summary "$NEIGHBORS"

say ""
say "$(c_green "done.")"
say ""
say "next steps:"
say "  1. Populate working memory (recommended for existing codebases):"
say "       In Claude Code or VS Code Copilot, invoke the hydrator agent"
say "       (or run /hydrate-discover to walk the five phases one at a time)."
say "       This scans your codebase, git history, README, and ADRs to fill"
say "       projectOverview / decisionLog / dataContracts / conventions."
say "       For a brand-new project, skip this step and edit the files by hand."
say "  2. Edit $WM_DIR/activeContext.md to reflect what you're working on."
say "  3. Teammates: after cloning, run:"
say "       cp $WM_DIR/activeContext.example.md $WM_DIR/activeContext.md"
say "  4. Ongoing sync: invoke the working-memory-synchronizer agent, or"
say "     run: ./scripts/update-working-memory.sh"
say "  5. To tune line limits or nudge thresholds:"
say "       cp .working-memoryrc.example .working-memoryrc   # then edit"

if [ "$CANONICAL_OK" -eq 0 ]; then
  say ""
  warn "some canonical artifacts are missing. Review the messages above."
fi
