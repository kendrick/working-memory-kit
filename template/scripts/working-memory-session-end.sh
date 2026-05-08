#!/bin/bash
# Reminds the developer to update the working memory if significant work was done.

set -eu

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Hooks fire on every session in every project. Skip silently outside
# working-memory consumers.
if [ ! -d "$REPO_ROOT/working-memory" ]; then
  exit 0
fi

# Reads a key from .working-memoryrc with a default. Parses key=value instead
# of sourcing the file, so a malicious rc can't execute arbitrary shell.
read_cfg() {
  local key="$1" default="$2" file="$REPO_ROOT/.working-memoryrc"
  local val=""
  [ -f "$file" ] && val=$(grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' "'\''')
  echo "${val:-$default}"
}

FILE_THRESHOLD="${WORKING_MEMORY_FILE_THRESHOLD:-$(read_cfg NUDGE_FILE_THRESHOLD 5)}"
LINE_THRESHOLD="${WORKING_MEMORY_LINE_THRESHOLD:-$(read_cfg NUDGE_LINE_THRESHOLD 200)}"

# --shortstat covers both signals in one git call. Format example:
#   " 5 files changed, 200 insertions(+), 50 deletions(-)"
DIFF_STATS=$(git -C "$REPO_ROOT" diff --shortstat HEAD 2>/dev/null || true)
CHANGED_FILES=$(echo "$DIFF_STATS" | grep -oE '[0-9]+ files? changed' | grep -oE '[0-9]+' || echo 0)
INSERTIONS=$(echo "$DIFF_STATS" | grep -oE '[0-9]+ insertions?' | grep -oE '[0-9]+' || echo 0)
DELETIONS=$(echo "$DIFF_STATS" | grep -oE '[0-9]+ deletions?' | grep -oE '[0-9]+' || echo 0)
LINES_CHANGED=$(( ${INSERTIONS:-0} + ${DELETIONS:-0} ))

# Either signal trips the nudge. Surface which one fired so the dev knows
# whether the session was wide (many files) or deep (one big refactor).
REASON=""
if [ "${CHANGED_FILES:-0}" -gt "$FILE_THRESHOLD" ] && [ "${LINES_CHANGED:-0}" -gt "$LINE_THRESHOLD" ]; then
  REASON="$CHANGED_FILES files and $LINES_CHANGED lines"
elif [ "${CHANGED_FILES:-0}" -gt "$FILE_THRESHOLD" ]; then
  REASON="$CHANGED_FILES files"
elif [ "${LINES_CHANGED:-0}" -gt "$LINE_THRESHOLD" ]; then
  REASON="$LINES_CHANGED lines"
fi

if [ -n "$REASON" ]; then
  echo "{\"systemMessage\":\"You changed $REASON this session. Consider running /update-working-memory or @working-memory-synchronizer to keep the working memory current.\"}"
fi
