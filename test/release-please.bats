#!/usr/bin/env bats
# #89: a release PR bumps only what release-please knows to bump, so every tracked file that holds the release version has to be in extra-files.

load helpers

# The file list always comes from the real checkout, and the contents come from ROOT, so a test can scan an edited copy of the kit.
unlisted_release_files() {
  python3 - "$KIT_ROOT" "$1" "$2" <<'PY'
import json, os, re, subprocess, sys
kit, root, config = sys.argv[1:4]
ver = json.load(open(os.path.join(root, ".release-please-manifest.json")))["."]
listed = {
    e["path"]
    for e in json.load(open(config))["packages"]["."].get("extra-files", [])
    if isinstance(e, dict) and e.get("type") == "json" and e.get("jsonpath") == "$.version"
}
# The lookbehind keeps keys like schema_version out, and the optional quotes and [:=] let one pattern cover JSON, YAML and TOML.
pat = re.compile(r"""(?m)(?<![\w-])["']?version["']?\s*[:=]\s*["']?""" + re.escape(ver) + r"""["']?(?![\w.-])""")
paths = subprocess.run(["git", "-C", kit, "ls-files", "-z"], capture_output=True, check=True, text=True).stdout.split("\0")
missing = False
for p in paths:
    # CHANGELOG headings and the manifest itself carry the version, but release-please writes both on its own.
    if not p or p in ("CHANGELOG.md", ".release-please-manifest.json"):
        continue
    f = os.path.join(root, p)
    if os.path.islink(f) or not os.path.isfile(f):
        continue
    with open(f, encoding="utf-8", errors="ignore") as fh:
        if not pat.search(fh.read()):
            continue
    print("found: " + p)
    if p not in listed:
        print("missing: " + p)
        missing = True
sys.exit(1 if missing else 0)
PY
}

# Writes $BATS_TEST_TMPDIR/config.json: the real config after the python statement in $1 edits the parsed dict `c`.
edit_config() {
  python3 - "$KIT_ROOT/release-please-config.json" "$BATS_TEST_TMPDIR/config.json" "$1" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
exec(sys.argv[3])
json.dump(c, open(sys.argv[2], "w"), indent=2)
PY
}

# A copy of the kit at $BATS_TEST_TMPDIR/kit with the demo fixture's package.json version set to $1.
copy_kit_with_fixture_version() {
  cp -R "$KIT_ROOT/." "$BATS_TEST_TMPDIR/kit"
  rm -rf "$BATS_TEST_TMPDIR/kit/.git"   # a linked worktree's .git file would point git at the real index
  python3 - "$BATS_TEST_TMPDIR/kit/examples/hydration-demo/sources/codebase/package.json" "$1" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
p["version"] = sys.argv[2]
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
}

release_version() {
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["."])' "$KIT_ROOT/.release-please-manifest.json"
}

@test "every tracked file holding the release version is in extra-files (#89)" {
  run unlisted_release_files "$KIT_ROOT" "$KIT_ROOT/release-please-config.json"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # A scan that read nothing would also pass, so both manifests have to show up as found.
  [[ "$output" == *"found: .claude-plugin/plugin.json"* ]] || { echo "$output"; false; }
  [[ "$output" == *"found: .claude/.claude-plugin/plugin.json"* ]] || { echo "$output"; false; }
}

@test "dropping the eval manifest from extra-files fails (#89)" {
  edit_config 'x = c["packages"]["."]["extra-files"]; x[:] = [e for e in x if e["path"] != ".claude/.claude-plugin/plugin.json"]'
  run unlisted_release_files "$KIT_ROOT" "$BATS_TEST_TMPDIR/config.json"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"missing: .claude/.claude-plugin/plugin.json"* ]] || { echo "$output"; false; }
}

@test "dropping the root manifest from extra-files fails (#89)" {
  edit_config 'x = c["packages"]["."]["extra-files"]; x[:] = [e for e in x if e["path"] != ".claude-plugin/plugin.json"]'
  run unlisted_release_files "$KIT_ROOT" "$BATS_TEST_TMPDIR/config.json"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"missing: .claude-plugin/plugin.json"* ]] || { echo "$output"; false; }
}

@test "an entry without the JSON \$.version updater doesn't count (#89)" {
  edit_config '[e.update(jsonpath="$.name") for e in c["packages"]["."]["extra-files"] if e["path"] == ".claude/.claude-plugin/plugin.json"]'
  run unlisted_release_files "$KIT_ROOT" "$BATS_TEST_TMPDIR/config.json"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"missing: .claude/.claude-plugin/plugin.json"* ]] || { echo "$output"; false; }
}

@test "a fixture version that isn't the release version is ignored (#89)" {
  copy_kit_with_fixture_version 9.9.9
  run unlisted_release_files "$BATS_TEST_TMPDIR/kit" "$BATS_TEST_TMPDIR/kit/release-please-config.json"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a fixture holding the release version is caught (#89)" {
  copy_kit_with_fixture_version "$(release_version)"
  run unlisted_release_files "$BATS_TEST_TMPDIR/kit" "$BATS_TEST_TMPDIR/kit/release-please-config.json"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"missing: examples/hydration-demo/sources/codebase/package.json"* ]] || { echo "$output"; false; }
}

@test "release-please config holds the issue's settings (#89)" {
  run python3 - "$KIT_ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
c = json.load(open(os.path.join(root, "release-please-config.json")))
m = json.load(open(os.path.join(root, ".release-please-manifest.json")))
assert c["release-type"] == "simple", c["release-type"]
assert c["include-component-in-tag"] is False
assert c["bump-minor-pre-major"] is True
assert "draft" not in c
# release-please honors last-release-sha on every run, so it would outlive the first release; it ignores bootstrap-sha once a release PR merges.
assert "last-release-sha" not in c
assert c["bootstrap-sha"] == "1ba95c767ac0279515993b55e1ee8c8ce530b681", c["bootstrap-sha"]
want = [
    {"type": "feat", "section": "Features"},
    {"type": "fix", "section": "Bug Fixes"},
    {"type": "docs", "section": "Documentation"},
    {"type": "test", "section": "Testing"},
    {"type": "ci", "section": "CI & Build"},
    {"type": "perf", "section": "Performance"},
    {"type": "refactor", "section": "Refactor"},
    {"type": "chore", "section": "Chores"},
]
assert c["changelog-sections"] == want, c["changelog-sections"]
assert list(m) == ["."], list(m)
# release-please skips a missing version.txt instead of creating it, so the file has to exist and match.
assert open(os.path.join(root, "version.txt")).read() == m["."] + "\n"
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "release-please workflow runs on main with job-scoped write (#89)" {
  f="$KIT_ROOT/.github/workflows/release-please.yml"
  grep -q 'googleapis/release-please-action@v5' "$f"
  grep -qx '    branches: \[main\]' "$f"
  grep -qx 'permissions: {}' "$f"
  [ "$(grep -c 'contents: write' "$f")" = 1 ]
  [ "$(grep -c 'pull-requests: write' "$f")" = 1 ]
  if grep -qE '^  release:' "$f"; then false; fi
}
