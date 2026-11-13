#!/usr/bin/env bats
# V1b: the installer detects spec-driven neighbors from its registry and wires
# the boundary (ownership map, AGENTS cross-ref inside the fence, conventions
# deferral), warns on a rival memory tool, and leaves a no-neighbor install
# exactly as before. Detection triggers only on a tool-unique top-level path.

load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

XREF='Spec-driven tooling lives in'
START='<!-- working-memory:start -->'
END='<!-- working-memory:end -->'

# cross-ref must land BETWEEN the fence markers
xref_inside_fence() {
  awk -v r="$XREF" '/working-memory:start/{s=1} index($0,r){print (s?"yes":"no")} /working-memory:end/{s=0}' AGENTS.md
}

@test "Spec Kit: detected, cross-referenced in the fence, conventions pointed at its principles" {
  mkdir -p .specify/memory
  run run_installer
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'who owns what'                       # ownership map printed
  grep -q "$XREF.*Spec Kit" AGENTS.md                            # cross-ref names it
  [ "$(xref_inside_fence)" = yes ]                               # ...inside the markers
  grep -q 'constitution.md' _working-memory/conventions.md       # conventions deferral
  [ "$(grep -c 'coexistence:principles' _working-memory/conventions.md)" -eq 1 ]
}

@test "coexistence wiring is idempotent" {
  mkdir -p .specify
  run_installer
  git add -A; git commit -q -m base
  run_installer
  run git status --porcelain
  [ -z "$output" ]
  [ "$(grep -c "$XREF" AGENTS.md)" -eq 1 ]
  [ "$(grep -c 'coexistence:principles' _working-memory/conventions.md)" -eq 1 ]
}

@test "OpenSpec is detected by its own trigger" {
  mkdir -p openspec
  run_installer
  grep -q "$XREF.*OpenSpec" AGENTS.md
}

@test "BMAD is detected by its alternate trigger (.bmad-core)" {
  mkdir -p .bmad-core
  run_installer
  grep -q "$XREF.*BMAD" AGENTS.md
}

@test "Task Master (no principles file) gets a cross-ref but no conventions note" {
  mkdir -p .taskmaster
  run_installer
  grep -q "$XREF.*Task Master" AGENTS.md
  ! grep -q 'coexistence:principles' _working-memory/conventions.md
}

@test "Memory Bank warns and wires nothing" {
  mkdir -p memory-bank
  run run_installer
  echo "$output" | grep -qi 'two durable-memory systems'
  ! grep -q "$XREF" AGENTS.md
  ! grep -q 'coexistence:principles' _working-memory/conventions.md
}

BANKLINE='ltm promote moves an entry from one to the other'

@test ".ltm.yaml prints the Bank line, wires nothing, and deleting it silences the line (#38)" {
  touch .ltm.yaml
  run run_installer
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "$BANKLINE"
  echo "$output" | grep -q 'long-term-memory-kit (.ltm.yaml)'
  ! grep -q "$XREF" AGENTS.md
  ! grep -q 'coexistence:principles' _working-memory/conventions.md
  git add -A; git commit -q -m base
  run_installer
  run git status --porcelain
  [ -z "$output" ]
  rm .ltm.yaml
  run run_installer
  ! echo "$output" | grep -qF "$BANKLINE"
}

@test "memory-bank/ with no .ltm.yaml prints only the Memory Bank warning (#38)" {
  mkdir -p memory-bank
  run run_installer
  echo "$output" | grep -qi 'two durable-memory systems'
  ! echo "$output" | grep -qF "$BANKLINE"
  ! echo "$output" | grep -q 'long-term-memory-kit'
}

@test ".ltm.yaml and memory-bank/ together print both lines (#38)" {
  touch .ltm.yaml; mkdir -p memory-bank
  run run_installer
  echo "$output" | grep -qF "$BANKLINE"
  echo "$output" | grep -qi 'two durable-memory systems'
}

@test "ADRs are mentioned but wire no principles" {
  mkdir -p docs/adr
  run run_installer
  echo "$output" | grep -q 'ADRs'
  ! grep -q "$XREF" AGENTS.md
  ! grep -q 'coexistence:principles' _working-memory/conventions.md
}

@test "multiple neighbors are all named" {
  mkdir -p .specify openspec
  run_installer
  grep -qE "$XREF.*(Spec Kit.*OpenSpec|OpenSpec.*Spec Kit)" AGENTS.md
}

@test "no neighbor: no wiring, still idempotent, coexistence doc still shipped" {
  run run_installer
  ! grep -q "$XREF" AGENTS.md
  ! grep -q 'coexistence:principles' _working-memory/conventions.md
  ! echo "$output" | grep -q 'who owns what'                                  # no ownership map
  grep -q 'Working alongside spec-driven tooling' _working-memory/README.md   # doc is static, always present
  git add -A; git commit -q -m base
  run_installer
  run git status --porcelain
  [ -z "$output" ]
}

@test "a bare specs/ directory does not trigger detection" {
  mkdir -p specs
  run_installer
  ! grep -q "$XREF" AGENTS.md
}

# --- V2: registering an unknown tool via flags + .working-memoryrc ---

@test "--coexist-with registers an unknown path, wires it, and persists it" {
  run run_installer --coexist-with docs/specs
  [ "$status" -eq 0 ]
  grep -q "$XREF.*docs/specs/" AGENTS.md
  [ "$(xref_inside_fence)" = yes ]
  echo "$output" | grep -q 'who owns what'
  grep -qE '^external_spec_tooling="docs/specs"$' .working-memoryrc   # exact format, no spaces around =
  grep -qE '^coexistence_asked=true$' .working-memoryrc
  # a re-run WITHOUT the flag reads the rc and stays idempotent
  git add -A; git commit -q -m base
  run_installer
  run git status --porcelain
  [ -z "$output" ]
  [ "$(grep -c "$XREF" AGENTS.md)" -eq 1 ]
}

@test "--coexist-principles points conventions.md at the principles file" {
  run_installer --coexist-with docs/specs --coexist-principles docs/specs/STANDARDS.md
  grep -q 'STANDARDS.md' _working-memory/conventions.md
  grep -qE '^external_spec_principles="docs/specs/STANDARDS.md"$' .working-memoryrc
}

@test "a remembered registration in .working-memoryrc is applied with no flag" {
  printf 'external_spec_tooling="docs/specs"\n' > .working-memoryrc
  run_installer
  grep -q "$XREF.*docs/specs/" AGENTS.md
}

@test "--no-coexist opts out: no wiring, no hint, remembered" {
  run run_installer --no-coexist
  ! grep -q "$XREF" AGENTS.md
  ! echo "$output" | grep -q 'No spec-driven tooling detected'
  grep -qE '^external_spec_tooling=false$' .working-memoryrc
  grep -qE '^coexistence_asked=true$' .working-memoryrc
}

@test "no neighbor, no flag, no rc: the hint points at --coexist-with" {
  run run_installer
  echo "$output" | grep -q 'coexist-with'
  ! grep -q "$XREF" AGENTS.md
}

@test "registering does not disturb existing .working-memoryrc keys" {
  printf 'MAX_ACTIVE_CONTEXT_LINES=15\n' > .working-memoryrc
  run_installer --coexist-with docs/specs
  grep -qE '^MAX_ACTIVE_CONTEXT_LINES=15$' .working-memoryrc
  grep -qE '^external_spec_tooling="docs/specs"$' .working-memoryrc
}

@test "a registered path with an internal space survives a re-run (#42)" {
  mkdir -p "docs/my specs"
  run_installer --coexist-with "docs/my specs"
  grep -qx 'external_spec_tooling="docs/my specs"' .working-memoryrc
  git add -A; git commit -q -m base
  run run_installer
  [ "$status" -eq 0 ]
  grep -q 'docs/my specs/' AGENTS.md
  [ "$(grep -c 'myspecs' AGENTS.md)" -eq 0 ]       # bash -e ignores a bare `! cmd`, so count instead
  echo "$output" | grep -q '(docs/my specs/)'      # coexistence map
  run git status --porcelain
  [ -z "$output" ]
}

@test "a CRLF .working-memoryrc value reads back without a carriage return (#42)" {
  mkdir -p "docs/my specs"
  printf 'external_spec_tooling="docs/my specs"\r\n' > .working-memoryrc
  run_installer
  grep -q 'docs/my specs/' AGENTS.md
  [ "$(grep -c $'\r' AGENTS.md)" -eq 0 ]
}

# --- #44: a formatter override that keeps the working-memory dir's metadata lines ---

FMT_GLOB='_working-memory/**/*.md'

# "<count> <files[0]> <proseWrap>" for the overrides array in $1, under the
# "prettier" key when $2 says so. One string, so a duplicate shows up as a count.
override_of() {
  node -e '
    const fs = require("fs");
    let j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (process.argv[2]) j = j[process.argv[2]];
    const o = j.overrides;
    console.log(o.length + " " + o[0].files[0] + " " + o[0].options.proseWrap);
  ' "$1" "${2:-}"
}

# bash -e ignores a bare `! cmd` mid-test, so negative checks go through run.
rc_has_fmt_key() { grep -qs '^formatter_override=' .working-memoryrc; }

@test ".prettierrc gets the override after a yes (#44)" {
  printf '{"proseWrap":"always"}\n' > .prettierrc
  run run_installer_tty $'\ny\n'
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '.prettierrc formats Markdown. Add an override so it keeps _working-memory/ metadata lines as written?'
  [ "$(override_of .prettierrc)" = "1 $FMT_GLOB preserve" ]
  grep -qx 'formatter_override=added' .working-memoryrc
}

@test ".prettierrc is unchanged after a no (#44)" {
  printf '{"proseWrap":"always"}\n' > .prettierrc
  cp .prettierrc "$BATS_TEST_TMPDIR/before"
  run run_installer_tty $'\nn\n'
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'Add an override'
  cmp .prettierrc "$BATS_TEST_TMPDIR/before"
  grep -qx 'formatter_override=declined' .working-memoryrc
}

@test ".oxfmtrc.json gets the override, from a path with a space and a quote (#44)" {
  mkdir "it's here"
  cd "it's here"
  printf '{}\n' > .oxfmtrc.json
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  [ "$(override_of .oxfmtrc.json)" = "1 $FMT_GLOB preserve" ]
  grep -qx 'formatter_override=added' .working-memoryrc
}

@test "a re-run doesn't duplicate the override or ask again (#44)" {
  printf '{"proseWrap":"always"}\n' > .prettierrc
  run_installer --formatter-override
  git add -A; git commit -q -m base
  run run_installer_tty $'\nu\n'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c 'Add an override')" -eq 0 ]
  run git status --porcelain
  [ -z "$output" ]
  run_installer --formatter-override           # a flag skips the recorded answer, so this reaches the edit
  run git status --porcelain
  [ -z "$output" ]
  [ "$(override_of .prettierrc)" = "1 $FMT_GLOB preserve" ]
}

@test "--no-formatter-override records declined and edits nothing (#44)" {
  printf '{"proseWrap":"always"}\n' > .prettierrc
  cp .prettierrc "$BATS_TEST_TMPDIR/before"
  run run_installer --no-formatter-override
  [ "$status" -eq 0 ]
  cmp .prettierrc "$BATS_TEST_TMPDIR/before"
  grep -qx 'formatter_override=declined' .working-memoryrc
}

@test "package.json prettier object gets the override, tabs kept (#44)" {
  printf '{\n\t"name": "demo",\n\t"prettier": {\n\t\t"semi": false\n\t},\n\t"version": "1.0.0"\n}\n' > package.json
  outside_prettier() { awk '/^\t"prettier"/{s=1} !s{print} s&&/^\t}/{s=0}' "$1"; }
  outside_prettier package.json > "$BATS_TEST_TMPDIR/outside"
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  [ "$(override_of package.json prettier)" = "1 $FMT_GLOB preserve" ]
  grep -q $'^\t\t"semi": false,$' package.json
  grep -q $'^\t\t"overrides": \\[$' package.json
  diff "$BATS_TEST_TMPDIR/outside" <(outside_prettier package.json)
}

@test "a package.json prettier key beats .prettierrc, as in Prettier (#44)" {
  printf '{\n  "name": "demo",\n  "prettier": {}\n}\n' > package.json
  printf '{"proseWrap":"always"}\n' > .prettierrc
  cp .prettierrc "$BATS_TEST_TMPDIR/before"
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  [ "$(override_of package.json prettier)" = "1 $FMT_GLOB preserve" ]
  cmp .prettierrc "$BATS_TEST_TMPDIR/before"
  # The edited file has to be the one Prettier itself loads.
  if command -v npx >/dev/null; then
    [ "$(npx --yes prettier@3 --find-config-path _working-memory/decisionLog.md)" = package.json ]
  fi
}

@test "init.sh and init.ps1 embed the same formatter node script (#44)" {
  sed -n "/^WMK_FMT_NODE=\$(cat <<'EOF'\$/,/^EOF\$/p" "$KIT_ROOT/init.sh" | sed '1d;$d' > sh.js
  sed -n "/^\$WmkFmtNode = @'\$/,/^'@\$/p" "$KIT_ROOT/init.ps1" | sed '1d;$d' > ps.js
  [ -s sh.js ]
  diff sh.js ps.js
}

@test "a string prettier key in package.json prints the snippet and edits nothing (#44)" {
  printf '{\n  "name": "demo",\n  "prettier": "@acme/prettier-config"\n}\n' > package.json
  cp package.json "$BATS_TEST_TMPDIR/before"
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '"proseWrap": "preserve"'
  echo "$output" | grep -qF 'or the shared config it names'
  cmp package.json "$BATS_TEST_TMPDIR/before"
  run rc_has_fmt_key
  [ "$status" -ne 0 ]
}

@test "a YAML .prettierrc prints the snippet and edits nothing (#44)" {
  printf 'proseWrap: always\n' > .prettierrc
  cp .prettierrc "$BATS_TEST_TMPDIR/before"
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '"proseWrap": "preserve"'
  cmp .prettierrc "$BATS_TEST_TMPDIR/before"
  run rc_has_fmt_key
  [ "$status" -ne 0 ]
}

@test "a custom dir gets its own glob (#44)" {
  printf 'WORKING_MEMORY_DIR="mem"\n' > .working-memoryrc
  printf '{}\n' > .prettierrc
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  [ "$(override_of .prettierrc)" = "1 mem/**/*.md preserve" ]
}

@test "a dir typed with a doubled slash gets a single-slash glob (#67)" {
  printf 'WORKING_MEMORY_DIR="a//b"\n' > .working-memoryrc
  printf '{}\n' > .prettierrc
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  [ "$(override_of .prettierrc)" = "1 a/b/**/*.md preserve" ]
  teardown_repo; setup_repo
  printf 'WORKING_MEMORY_DIR="a/b"\n' > .working-memoryrc
  printf '{}\n' > .prettierrc
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  [ "$(override_of .prettierrc)" = "1 a/b/**/*.md preserve" ]
  teardown_repo; setup_repo
  printf 'WORKING_MEMORY_DIR="a/c"\n' > .working-memoryrc
  printf '{}\n' > .prettierrc
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  [ "$(override_of .prettierrc)" = "1 a/c/**/*.md preserve" ]
}

@test "a dir with a trailing slash gets a single-slash glob (#67)" {
  printf 'WORKING_MEMORY_DIR="a/b/"\n' > .working-memoryrc
  printf '{}\n' > .prettierrc
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  [ "$(override_of .prettierrc)" = "1 a/b/**/*.md preserve" ]
}

@test "a backslash beside a slash collapses after the swap (#67)" {
  printf 'WORKING_MEMORY_DIR="docs\\/memory"\n' > .working-memoryrc
  printf '{}\n' > .prettierrc
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  [ "$(override_of .prettierrc)" = "1 docs/memory/**/*.md preserve" ]
}

@test "a snippet-only Prettier config and an editable oxfmt config record added (#44)" {
  printf 'proseWrap: always\n' > .prettierrc
  printf '{}\n' > .oxfmtrc.json
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  [ "$(override_of .oxfmtrc.json)" = "1 $FMT_GLOB preserve" ]
  grep -qx 'formatter_override=added' .working-memoryrc
}

@test "a dir with a backslash gets a forward-slash glob (#44)" {
  printf 'WORKING_MEMORY_DIR="docs\\memory"\n' > .working-memoryrc
  printf '{}\n' > .prettierrc
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  [ "$(override_of .prettierrc)" = "1 docs/memory/**/*.md preserve" ]
}

@test "an existing override without proseWrap preserve still gets one (#44)" {
  printf '{"proseWrap":"always","overrides":[{"files":["_working-memory/**/*.md"],"options":{"printWidth":100}}]}\n' > .prettierrc
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  [ "$(node -e 'const o=JSON.parse(require("fs").readFileSync(".prettierrc","utf8")).overrides; console.log(o.length, o[1].files[0], o[1].options.proseWrap)')" = "2 $FMT_GLOB preserve" ]
  grep -qx 'formatter_override=added' .working-memoryrc
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  [ "$(node -e 'console.log(JSON.parse(require("fs").readFileSync(".prettierrc","utf8")).overrides.length)')" = 2 ]
  command -v npx >/dev/null || skip "npx not available"
  printf '# Log\n\nstatus: superseded\nsuperseded_by: later\n' > _working-memory/decisionLog.md
  npx --yes prettier@3 --write _working-memory/decisionLog.md
  grep -qx 'status: superseded' _working-memory/decisionLog.md
  grep -qx 'superseded_by: later' _working-memory/decisionLog.md
}

@test "a later override that sets proseWrap shadows the kit's, so a new one is appended last (#44)" {
  printf '{"overrides":[{"files":["_working-memory/**/*.md"],"options":{"proseWrap":"preserve"}},{"files":["**/*.md"],"options":{"proseWrap":"always"}}]}\n' > .prettierrc
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  [ "$(node -e 'const o=JSON.parse(require("fs").readFileSync(".prettierrc","utf8")).overrides; console.log(o.length, o[o.length-1].files[0], o[o.length-1].options.proseWrap)')" = "3 $FMT_GLOB preserve" ]
  grep -qx 'formatter_override=added' .working-memoryrc
  command -v npx >/dev/null || skip "npx not available"
  printf '# Log\n\nstatus: superseded\nsuperseded_by: later\n' > _working-memory/decisionLog.md
  npx --yes prettier@3 --write _working-memory/decisionLog.md
  grep -qx 'status: superseded' _working-memory/decisionLog.md
  grep -qx 'superseded_by: later' _working-memory/decisionLog.md
}

@test "an override with excludeFiles is not reused, so the kit's is appended last (#44)" {
  printf '{"proseWrap":"always","overrides":[{"files":["_working-memory/**/*.md"],"excludeFiles":["_working-memory/decisionLog.md"],"options":{"proseWrap":"preserve"}}]}\n' > .prettierrc
  run run_installer --formatter-override
  [ "$status" -eq 0 ]
  [ "$(node -e 'const o=JSON.parse(require("fs").readFileSync(".prettierrc","utf8")).overrides; console.log(o.length, o[o.length-1].files[0], o[o.length-1].options.proseWrap, o[o.length-1].excludeFiles)')" = "2 $FMT_GLOB preserve undefined" ]
  grep -qx 'formatter_override=added' .working-memoryrc
}

@test "headless with no flag skips the override (#44)" {
  printf '{"proseWrap":"always"}\n' > .prettierrc
  cp .prettierrc "$BATS_TEST_TMPDIR/before"
  run run_installer
  [ "$status" -eq 0 ]
  cmp .prettierrc "$BATS_TEST_TMPDIR/before"
  [ "$(echo "$output" | grep -c 'Add an override')" -eq 0 ]
  run rc_has_fmt_key
  [ "$status" -ne 0 ]
}

@test "prettier keeps metadata lines under the override (#44)" {
  command -v npx >/dev/null || skip "npx not available"
  printf '{"proseWrap":"always"}\n' > .prettierrc
  run_installer --formatter-override
  cat > _working-memory/decisionLog.md <<'EOF'
# Decision Log

## 2026-11-12: Keep metadata lines intact
status: superseded
superseded_by: 2026-11-13: Keep metadata lines intact, take two

**Context:** A formatter running with proseWrap set to always joins consecutive lines of one paragraph, which would fold these metadata lines into a single line that no reader or hook can parse.
EOF
  cp _working-memory/decisionLog.md "$BATS_TEST_TMPDIR/before"
  # Not cmp: Prettier 3 always puts a blank line under the heading, override or
  # not. The override's job is keeping each metadata line whole.
  npx --yes prettier@3 --write _working-memory/decisionLog.md
  grep -qx 'status: superseded' _working-memory/decisionLog.md
  grep -qx 'superseded_by: 2026-11-13: Keep metadata lines intact, take two' _working-memory/decisionLog.md
  # Without the override the same run must join them, or this test proves nothing.
  cp "$BATS_TEST_TMPDIR/before" _working-memory/decisionLog.md
  printf '{"proseWrap":"always"}\n' > .prettierrc
  npx --yes prettier@3 --write _working-memory/decisionLog.md
  run grep -qx 'status: superseded' _working-memory/decisionLog.md
  [ "$status" -ne 0 ]
}
