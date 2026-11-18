#!/usr/bin/env bash
# #91: a project keeps its own copy of the kit's machinery, so a plugin update never reaches it.
# Warn only when the project's marker is a strictly lower X.Y.Z than the plugin's version.txt, compared field by field as integers ("0.9.0" sorts after "0.10.0" as a string).
# Anything else stays silent and exits 0: no marker (a repo the kit never set up), a junk or hand-edited one, or no plugin version. A hook error would land in the user's session.
set -u

# CRs go because a Windows checkout with autocrlf gives version.txt, and so the marker, a CRLF.
read_ver() {
  local v
  { [ -f "$1" ] && [ -r "$1" ]; } || return 1
  v="$(tr -d '\r' < "$1" 2>/dev/null)" || return 1
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s' "$v"
}

# 10# keeps a leading zero from reading as octal.
older() {
  local a="$1." b="$2." x y
  while [ -n "$a" ]; do
    x=$((10#${a%%.*})) y=$((10#${b%%.*}))
    [ "$x" -lt "$y" ] && return 0
    [ "$x" -gt "$y" ] && return 1
    a="${a#*.}" b="${b#*.}"
  done
  return 1
}

[ -n "${CLAUDE_PROJECT_DIR:-}" ] || exit 0
here="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
proj="$(read_ver "$CLAUDE_PROJECT_DIR/.claude/working-memory-kit.version")" || exit 0
kit="$(read_ver "$here/../version.txt")" || exit 0

if older "$proj" "$kit"; then
  printf '{"systemMessage":"working-memory-kit: this project runs kit %s and the plugin has %s. Run /working-memory-kit:init to upgrade it."}\n' "$proj" "$kit"
fi
exit 0
