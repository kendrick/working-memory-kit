#!/bin/bash
# Session-start hook: ensures activeContext.md exists, and with --claude injects
# its contents plus the AGENTS.md on-demand table into the model's context.

set -eu

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WM_DIR="$REPO_ROOT/_working-memory"

# Hooks fire on every session in every project, not just working-memory
# consumers. Bail quietly so unrelated repos don't see noise.
if [ ! -d "$WM_DIR" ]; then
  exit 0
fi

# Session-end diffs against this commit so work committed mid-session still
# counts (#35). It lives in the git dir: never tracked, per-worktree. Claude
# Code refires SessionStart on compaction; resetting the base there would drop
# the session's earlier commits, so a compact keeps the old one. The -t guards
# a hand run with an open stdin. No HEAD (empty repo) means no base.
KEEP_BASE=0
if [ "${1:-}" = "--claude" ]; then
  IFS= read -r -t 2 -d '' INPUT || true
  if printf '%s' "${INPUT:-}" | grep -Eq '"source"[[:space:]]*:[[:space:]]*"compact"'; then
    KEEP_BASE=1
  fi
fi
if [ "$KEEP_BASE" -eq 0 ]; then
  BASE_SHA=$(git -C "$REPO_ROOT" rev-parse --verify -q HEAD 2>/dev/null || true)
  BASE_DIR=$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir 2>/dev/null || true)
  if [ -n "$BASE_SHA" ] && [ -n "$BASE_DIR" ]; then
    # A read-only git dir must not fail SessionStart; the nudge just falls back to HEAD.
    { printf '%s\n' "$BASE_SHA" > "$BASE_DIR/working-memory-session-base"; } 2>/dev/null || true
  fi
fi

# Reads a key from .working-memoryrc with a default. Parses key=value instead
# of sourcing the file, so a malicious rc can't execute arbitrary shell.
read_cfg() {
  local key="$1" default="$2" file="$REPO_ROOT/.working-memoryrc"
  local val=""
  [ -f "$file" ] && val=$(grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' "'\''')
  echo "${val:-$default}"
}

MAX_LINES="${WORKING_MEMORY_MAX_LINES:-$(read_cfg MAX_ACTIVE_CONTEXT_LINES 20)}"
# A typo in the rc must not abort the hook under set -e; head -n rejects it.
case "$MAX_LINES" in '' | *[!0-9]*) MAX_LINES=20 ;; esac

# The directive lands every session, regardless of file state. The kit can't
# enforce that the host tool auto-loaded AGENTS.md / CLAUDE.md at session
# start, so the hook plants the working-memory directive directly. Hosts
# that DID auto-load those files get a harmless duplicate — small cost
# next to the value of not silently failing on cold-start.
DIRECTIVE="Working memory at _working-memory/ is active. AGENT INSTRUCTION: before deciding what to read, scan the on-demand table in AGENTS.md's '## Working Memory' section. If your task matches a row, that file is required reading before you proceed."

# Compose any condition message on top of the directive.
CONDITION=""
if [ ! -f "$WM_DIR/activeContext.md" ]; then
  if [ -f "$WM_DIR/activeContext.example.md" ]; then
    cp "$WM_DIR/activeContext.example.md" "$WM_DIR/activeContext.md"
    CONDITION=" Created activeContext.md from template — update it with your current focus."
  else
    CONDITION=" Warning: no activeContext.example.md found; working memory may not be initialized."
  fi
fi

# The default limit (20) comes from activeContext.example.md. Past that,
# the file has stopped being a queue and started being an archive. An empty
# CONDITION means the file already existed, so a fresh copy never warns.
LINE_COUNT=0
[ -f "$WM_DIR/activeContext.md" ] && LINE_COUNT=$(grep -c '[^[:space:]]' "$WM_DIR/activeContext.md" || true)
if [ -z "$CONDITION" ] && [ "$LINE_COUNT" -gt "$MAX_LINES" ]; then
  CONDITION=" Warning: activeContext.md has $LINE_COUNT non-empty lines (limit is $MAX_LINES). Use the update-working-memory skill or the supplied update script to prune it."
fi

# A raw quote, backslash, or control char makes the host drop the message
# silently. The assignments stay unquoted because bash 3.2 keeps the inner
# quotes literally in a double-quoted ${s//"$c"/"$u"}.
json_escape() {
  local s="$1" i c u
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  for ((i = 1; i < 32; i++)); do
    printf -v c '%b' "\\0$(printf '%o' "$i")"
    printf -v u '\\u%04x' "$i"
    s=${s//"$c"/"$u"}
  done
  printf '%s' "$s"
}

# Copilot and Codex show systemMessage to the user, but Claude Code never
# passes it to the model; context there goes in via additionalContext.
msg="${DIRECTIVE}${CONDITION}"
if [ "${1:-}" = "--claude" ]; then
  # Only Claude Code gets the contents, because Copilot and Codex print
  # systemMessage on screen, where a dump of the file is noise. additionalContext
  # goes to the model alone, so nothing waits on the agent choosing to read (#28).
  ACTIVE="$WM_DIR/activeContext.md"
  if [ -f "$ACTIVE" ]; then
    msg="${msg}"$'\n\n'"Current _working-memory/activeContext.md:"$'\n'"$(tr -d '\r' < "$ACTIVE" | grep '[^[:space:]]' | head -n "$MAX_LINES")"
    if [ "$LINE_COUNT" -gt "$MAX_LINES" ]; then
      msg="${msg}"$'\n'"($((LINE_COUNT - MAX_LINES)) more non-empty lines in activeContext.md; read the file for the rest.)"
    fi
  fi
  # Strip \r (here and from activeContext.md above) so a CRLF checkout doesn't reach the JSON as \u000d.
  TABLE=$(awk '{ sub(/\r$/, "") } in_table && /^#/ { exit } in_table && /[^[:space:]]/ { print } $0 == "### Read on demand:" { in_table = 1 }' "$REPO_ROOT/AGENTS.md" 2>/dev/null || true)
  if [ -n "$TABLE" ]; then
    msg="${msg}"$'\n\n'"On-demand reads, from AGENTS.md:"$'\n'"${TABLE}"
  fi
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$(json_escape "$msg")"
else
  printf '{"systemMessage":"%s"}\n' "$(json_escape "$msg")"
fi
