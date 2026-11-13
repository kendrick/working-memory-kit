# Parity twin of test/coexistence.bats (V1b + V2). The installer detects
# spec-driven neighbors from its registry and wires the boundary (ownership map,
# AGENTS cross-ref inside the fence, conventions deferral), warns on a rival
# memory tool, registers unknown tooling via flags + .working-memoryrc, and
# leaves a no-neighbor install exactly as before.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Common.ps1')
    $XREF = 'Spec-driven tooling lives in'
    $BANKLINE = 'ltm promote moves an entry from one to the other'
}

Describe 'coexistence' {
    BeforeEach { $repo = New-TestRepo }
    AfterEach { Remove-TestRepo $repo }

    It 'Spec Kit: detected, cross-referenced in the fence, conventions pointed at its principles' {
        New-Item -ItemType Directory -Path '.specify/memory' -Force | Out-Null
        $out = Invoke-Installer
        $out | Should -Match 'who owns what'
        Get-Content AGENTS.md -Raw | Should -Match "$XREF.*Spec Kit"
        Test-XrefInsideFence | Should -BeTrue
        Get-Content '_working-memory/conventions.md' -Raw | Should -Match 'constitution\.md'
        Get-MatchCount '_working-memory/conventions.md' 'coexistence:principles' | Should -Be 1
    }

    It 'coexistence wiring is idempotent' {
        New-Item -ItemType Directory -Path '.specify' -Force | Out-Null
        Invoke-Installer | Out-Null
        git add -A; git commit -q -m base
        Invoke-Installer | Out-Null
        git status --porcelain | Should -BeNullOrEmpty
        Get-MatchCount 'AGENTS.md' $XREF | Should -Be 1
        Get-MatchCount '_working-memory/conventions.md' 'coexistence:principles' | Should -Be 1
    }

    It 'OpenSpec is detected by its own trigger' {
        New-Item -ItemType Directory -Path 'openspec' -Force | Out-Null
        Invoke-Installer | Out-Null
        Get-Content AGENTS.md -Raw | Should -Match "$XREF.*OpenSpec"
    }

    It 'BMAD is detected by its alternate trigger (.bmad-core)' {
        New-Item -ItemType Directory -Path '.bmad-core' -Force | Out-Null
        Invoke-Installer | Out-Null
        Get-Content AGENTS.md -Raw | Should -Match "$XREF.*BMAD"
    }

    It 'Task Master (no principles file) gets a cross-ref but no conventions note' {
        New-Item -ItemType Directory -Path '.taskmaster' -Force | Out-Null
        Invoke-Installer | Out-Null
        Get-Content AGENTS.md -Raw | Should -Match "$XREF.*Task Master"
        Get-Content '_working-memory/conventions.md' -Raw | Should -Not -Match 'coexistence:principles'
    }

    It 'Memory Bank warns and wires nothing' {
        New-Item -ItemType Directory -Path 'memory-bank' -Force | Out-Null
        $out = Invoke-Installer
        $out | Should -Match 'two durable-memory systems'
        Get-Content AGENTS.md -Raw | Should -Not -Match $XREF
        Get-Content '_working-memory/conventions.md' -Raw | Should -Not -Match 'coexistence:principles'
    }

    It '.ltm.yaml prints the Bank line, wires nothing, and deleting it silences the line (#38)' {
        New-Item -ItemType File -Path '.ltm.yaml' | Out-Null
        $out = Invoke-Installer
        $out | Should -Match ([regex]::Escape($BANKLINE))
        $out | Should -Match ([regex]::Escape('long-term-memory-kit (.ltm.yaml)'))
        Get-Content AGENTS.md -Raw | Should -Not -Match $XREF
        Get-Content '_working-memory/conventions.md' -Raw | Should -Not -Match 'coexistence:principles'
        git add -A; git commit -q -m base
        Invoke-Installer | Out-Null
        git status --porcelain | Should -BeNullOrEmpty
        Remove-Item '.ltm.yaml' -Force
        $out = Invoke-Installer
        $out | Should -Not -Match ([regex]::Escape($BANKLINE))
    }

    It 'memory-bank/ with no .ltm.yaml prints only the Memory Bank warning (#38)' {
        New-Item -ItemType Directory -Path 'memory-bank' -Force | Out-Null
        $out = Invoke-Installer
        $out | Should -Match 'two durable-memory systems'
        $out | Should -Not -Match ([regex]::Escape($BANKLINE))
        $out | Should -Not -Match 'long-term-memory-kit'
    }

    It '.ltm.yaml and memory-bank/ together print both lines (#38)' {
        New-Item -ItemType File -Path '.ltm.yaml' | Out-Null
        New-Item -ItemType Directory -Path 'memory-bank' -Force | Out-Null
        $out = Invoke-Installer
        $out | Should -Match ([regex]::Escape($BANKLINE))
        $out | Should -Match 'two durable-memory systems'
    }

    It 'ADRs are mentioned but wire no principles' {
        New-Item -ItemType Directory -Path 'docs/adr' -Force | Out-Null
        $out = Invoke-Installer
        $out | Should -Match 'ADRs'
        Get-Content AGENTS.md -Raw | Should -Not -Match $XREF
        Get-Content '_working-memory/conventions.md' -Raw | Should -Not -Match 'coexistence:principles'
    }

    It 'multiple neighbors are all named' {
        New-Item -ItemType Directory -Path '.specify' -Force | Out-Null
        New-Item -ItemType Directory -Path 'openspec' -Force | Out-Null
        Invoke-Installer | Out-Null
        Get-Content AGENTS.md -Raw | Should -Match "$XREF.*(Spec Kit.*OpenSpec|OpenSpec.*Spec Kit)"
    }

    It 'no neighbor: no wiring, still idempotent, coexistence doc still shipped' {
        $out = Invoke-Installer
        Get-Content AGENTS.md -Raw | Should -Not -Match $XREF
        Get-Content '_working-memory/conventions.md' -Raw | Should -Not -Match 'coexistence:principles'
        $out | Should -Not -Match 'who owns what'
        Get-Content '_working-memory/README.md' -Raw | Should -Match 'Working alongside spec-driven tooling'
        git add -A; git commit -q -m base
        Invoke-Installer | Out-Null
        git status --porcelain | Should -BeNullOrEmpty
    }

    It 'a bare specs/ directory does not trigger detection' {
        New-Item -ItemType Directory -Path 'specs' -Force | Out-Null
        Invoke-Installer | Out-Null
        Get-Content AGENTS.md -Raw | Should -Not -Match $XREF
    }

    # --- V2: registering an unknown tool via flags + .working-memoryrc ---

    It '--coexist-with registers an unknown path, wires it, and persists it' {
        $out = Invoke-Installer --coexist-with docs/specs
        Get-Content AGENTS.md -Raw | Should -Match "$XREF.*docs/specs/"
        Test-XrefInsideFence | Should -BeTrue
        $out | Should -Match 'who owns what'
        Get-MatchCount '.working-memoryrc' '^external_spec_tooling="docs/specs"$' | Should -Be 1
        Get-MatchCount '.working-memoryrc' '^coexistence_asked=true$' | Should -Be 1
        git add -A; git commit -q -m base
        Invoke-Installer | Out-Null
        git status --porcelain | Should -BeNullOrEmpty
        Get-MatchCount 'AGENTS.md' $XREF | Should -Be 1
    }

    It '--coexist-principles points conventions.md at the principles file' {
        Invoke-Installer --coexist-with docs/specs --coexist-principles docs/specs/STANDARDS.md | Out-Null
        Get-Content '_working-memory/conventions.md' -Raw | Should -Match 'STANDARDS\.md'
        Get-MatchCount '.working-memoryrc' '^external_spec_principles="docs/specs/STANDARDS.md"$' | Should -Be 1
    }

    It 'a remembered registration in .working-memoryrc is applied with no flag' {
        Set-Content .working-memoryrc 'external_spec_tooling="docs/specs"'
        Invoke-Installer | Out-Null
        Get-Content AGENTS.md -Raw | Should -Match "$XREF.*docs/specs/"
    }

    It '--no-coexist opts out: no wiring, no hint, remembered' {
        $out = Invoke-Installer --no-coexist
        Get-Content AGENTS.md -Raw | Should -Not -Match $XREF
        $out | Should -Not -Match 'No spec-driven tooling detected'
        Get-MatchCount '.working-memoryrc' '^external_spec_tooling=false$' | Should -Be 1
        Get-MatchCount '.working-memoryrc' '^coexistence_asked=true$' | Should -Be 1
    }

    It 'no neighbor, no flag, no rc: the hint points at --coexist-with' {
        $out = Invoke-Installer
        $out | Should -Match 'coexist-with'
        Get-Content AGENTS.md -Raw | Should -Not -Match $XREF
    }

    It 'registering does not disturb existing .working-memoryrc keys' {
        Set-Content .working-memoryrc 'MAX_ACTIVE_CONTEXT_LINES=15'
        Invoke-Installer --coexist-with docs/specs | Out-Null
        Get-MatchCount '.working-memoryrc' '^MAX_ACTIVE_CONTEXT_LINES=15$' | Should -Be 1
        Get-MatchCount '.working-memoryrc' '^external_spec_tooling="docs/specs"$' | Should -Be 1
    }

    It 'a registered path with an internal space survives a re-run (#42)' {
        New-Item -ItemType Directory -Path 'docs/my specs' -Force | Out-Null
        Invoke-Installer --coexist-with 'docs/my specs' | Out-Null
        Get-Content .working-memoryrc | Should -Contain 'external_spec_tooling="docs/my specs"'
        git add -A; git commit -q -m base
        Invoke-Installer | Out-Null
        Get-Content AGENTS.md -Raw | Should -Match 'docs/my specs/'
        Get-Content AGENTS.md -Raw | Should -Not -Match 'myspecs'
        git status --porcelain | Should -BeNullOrEmpty
    }
}

# --- #44: a formatter override that keeps the working-memory dir's metadata lines ---
# Twins of the headless bats cases. The yes/no prompt cases and the Prettier
# end-to-end run stay bats-only: Pester can't drive a console, and one runner
# proving the formatter behavior is enough.

Describe 'formatter override' {
    BeforeAll {
        $FMT_GLOB = '_working-memory/**/*.md'
        # "<count> <files[0]> <proseWrap>", so a duplicate shows up as a count.
        function Get-Override ($path, $key) {
            $j = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            if ($key) { $j = $j.$key }
            $o = @($j.overrides)
            return "$($o.Count) $($o[0].files[0]) $($o[0].options.proseWrap)"
        }
        function Test-RcHasFmtKey { return (Get-MatchCount '.working-memoryrc' '^formatter_override=') -gt 0 }
    }
    BeforeEach { $repo = New-TestRepo }
    AfterEach { Remove-TestRepo $repo }

    It '.prettierrc gets the override with --formatter-override (#44)' {
        Set-Content .prettierrc '{"proseWrap":"always"}'
        Invoke-Installer --formatter-override | Out-Null
        Get-Override .prettierrc | Should -Be "1 $FMT_GLOB preserve"
        Get-MatchCount '.working-memoryrc' '^formatter_override=added$' | Should -Be 1
    }

    It '.oxfmtrc.json gets the override, from a path with a space and a quote (#44)' {
        New-Item -ItemType Directory -Path "it's here" | Out-Null
        Set-Location "it's here"
        [Environment]::CurrentDirectory = (Get-Location).Path
        Set-Content .oxfmtrc.json '{}'
        Invoke-Installer --formatter-override | Out-Null
        Get-Override .oxfmtrc.json | Should -Be "1 $FMT_GLOB preserve"
        Get-MatchCount '.working-memoryrc' '^formatter_override=added$' | Should -Be 1
    }

    It "a re-run doesn't duplicate the override (#44)" {
        Set-Content .prettierrc '{"proseWrap":"always"}'
        Invoke-Installer --formatter-override | Out-Null
        git add -A; git commit -q -m base
        $out = Invoke-Installer
        $out | Should -Not -Match 'Add an override'
        git status --porcelain | Should -BeNullOrEmpty
        $out = Invoke-Installer --formatter-override
        $out | Should -Match 'already has a proseWrap preserve override'
        git status --porcelain | Should -BeNullOrEmpty
        Get-Override .prettierrc | Should -Be "1 $FMT_GLOB preserve"
    }

    It '--no-formatter-override records declined and edits nothing (#44)' {
        Set-Content .prettierrc '{"proseWrap":"always"}'
        $before = Get-Content .prettierrc -Raw
        Invoke-Installer --no-formatter-override | Out-Null
        Get-Content .prettierrc -Raw | Should -BeExactly $before
        Get-MatchCount '.working-memoryrc' '^formatter_override=declined$' | Should -Be 1
    }

    It 'package.json prettier object gets the override, tabs kept (#44)' {
        [IO.File]::WriteAllText((Join-Path $repo 'package.json'), "{`n`t`"name`": `"demo`",`n`t`"prettier`": {`n`t`t`"semi`": false`n`t},`n`t`"version`": `"1.0.0`"`n}`n")
        Invoke-Installer --formatter-override | Out-Null
        Get-Override package.json prettier | Should -Be "1 $FMT_GLOB preserve"
        $lines = Get-Content package.json
        $lines | Should -Contain "`t`t`"semi`": false,"
        $lines | Should -Contain "`t`t`"overrides`": ["
        $lines[0..1] | Should -Be @('{', "`t`"name`": `"demo`",")
        $lines[-2..-1] | Should -Be @("`t`"version`": `"1.0.0`"", '}')
    }

    It 'a package.json prettier key beats .prettierrc, as in Prettier (#44)' {
        Set-Content package.json "{`n  `"name`": `"demo`",`n  `"prettier`": {}`n}"
        Set-Content .prettierrc '{"proseWrap":"always"}'
        $before = Get-Content .prettierrc -Raw
        Invoke-Installer --formatter-override | Out-Null
        Get-Override package.json prettier | Should -Be "1 $FMT_GLOB preserve"
        Get-Content .prettierrc -Raw | Should -BeExactly $before
    }

    It 'a string prettier key in package.json prints the snippet and edits nothing (#44)' {
        Set-Content package.json "{`n  `"name`": `"demo`",`n  `"prettier`": `"@acme/prettier-config`"`n}"
        $before = Get-Content package.json -Raw
        $out = Invoke-Installer --formatter-override
        $out | Should -Match ([regex]::Escape('"proseWrap": "preserve"'))
        $out | Should -Match 'or the shared config it names'
        Get-Content package.json -Raw | Should -BeExactly $before
        Test-RcHasFmtKey | Should -BeFalse
    }

    It 'a YAML .prettierrc prints the snippet and edits nothing (#44)' {
        Set-Content .prettierrc 'proseWrap: always'
        $before = Get-Content .prettierrc -Raw
        $out = Invoke-Installer --formatter-override
        $out | Should -Match ([regex]::Escape('"proseWrap": "preserve"'))
        Get-Content .prettierrc -Raw | Should -BeExactly $before
        Test-RcHasFmtKey | Should -BeFalse
    }

    It 'a snippet-only Prettier config and an editable oxfmt config record added (#44)' {
        Set-Content .prettierrc 'proseWrap: always'
        Set-Content .oxfmtrc.json '{}'
        Invoke-Installer --formatter-override | Out-Null
        Get-Override .oxfmtrc.json | Should -Be "1 $FMT_GLOB preserve"
        Get-MatchCount '.working-memoryrc' '^formatter_override=added$' | Should -Be 1
    }

    It 'a custom dir gets its own glob (#44)' {
        Set-Content .working-memoryrc 'WORKING_MEMORY_DIR="mem"'
        Set-Content .prettierrc '{}'
        Invoke-Installer --formatter-override | Out-Null
        Get-Override .prettierrc | Should -Be '1 mem/**/*.md preserve'
    }

    It 'a dir typed with a doubled slash gets a single-slash glob (#67)' {
        Set-Content .working-memoryrc 'WORKING_MEMORY_DIR="a//b"'
        Set-Content .prettierrc '{}'
        Invoke-Installer --formatter-override | Out-Null
        Get-Override .prettierrc | Should -Be '1 a/b/**/*.md preserve'
        Remove-TestRepo $repo; $script:repo = New-TestRepo
        Set-Content .working-memoryrc 'WORKING_MEMORY_DIR="a/b"'
        Set-Content .prettierrc '{}'
        Invoke-Installer --formatter-override | Out-Null
        Get-Override .prettierrc | Should -Be '1 a/b/**/*.md preserve'
        Remove-TestRepo $repo; $script:repo = New-TestRepo
        Set-Content .working-memoryrc 'WORKING_MEMORY_DIR="a/c"'
        Set-Content .prettierrc '{}'
        Invoke-Installer --formatter-override | Out-Null
        Get-Override .prettierrc | Should -Be '1 a/c/**/*.md preserve'
    }

    It 'a dir with a trailing slash gets a single-slash glob (#67)' {
        Set-Content .working-memoryrc 'WORKING_MEMORY_DIR="a/b//"'
        Set-Content .prettierrc '{}'
        Invoke-Installer --formatter-override | Out-Null
        Get-Override .prettierrc | Should -Be '1 a/b/**/*.md preserve'
    }

    It 'a backslash beside a slash collapses after the swap (#67)' {
        Set-Content .working-memoryrc 'WORKING_MEMORY_DIR="docs\/memory"'
        Set-Content .prettierrc '{}'
        Invoke-Installer --formatter-override | Out-Null
        Get-Override .prettierrc | Should -Be '1 docs/memory/**/*.md preserve'
    }

    It 'a dir with a backslash gets a forward-slash glob (#44)' {
        Set-Content .working-memoryrc 'WORKING_MEMORY_DIR="docs\memory"'
        Set-Content .prettierrc '{}'
        Invoke-Installer --formatter-override | Out-Null
        Get-Override .prettierrc | Should -Be '1 docs/memory/**/*.md preserve'
    }

    It 'an existing override without proseWrap preserve still gets one (#44)' {
        Set-Content .prettierrc '{"proseWrap":"always","overrides":[{"files":["_working-memory/**/*.md"],"options":{"printWidth":100}}]}'
        Invoke-Installer --formatter-override | Out-Null
        $o = @((Get-Content .prettierrc -Raw | ConvertFrom-Json).overrides)
        "$($o.Count) $($o[1].files[0]) $($o[1].options.proseWrap)" | Should -Be "2 $FMT_GLOB preserve"
        Get-MatchCount '.working-memoryrc' '^formatter_override=added$' | Should -Be 1
        Invoke-Installer --formatter-override | Out-Null
        @((Get-Content .prettierrc -Raw | ConvertFrom-Json).overrides).Count | Should -Be 2
    }

    It "a later override that sets proseWrap shadows the kit's, so a new one is appended last (#44)" {
        Set-Content .prettierrc '{"overrides":[{"files":["_working-memory/**/*.md"],"options":{"proseWrap":"preserve"}},{"files":["**/*.md"],"options":{"proseWrap":"always"}}]}'
        Invoke-Installer --formatter-override | Out-Null
        $o = @((Get-Content .prettierrc -Raw | ConvertFrom-Json).overrides)
        "$($o.Count) $($o[-1].files[0]) $($o[-1].options.proseWrap)" | Should -Be "3 $FMT_GLOB preserve"
        Get-MatchCount '.working-memoryrc' '^formatter_override=added$' | Should -Be 1
    }

    It "an override with excludeFiles is not reused, so the kit's is appended last (#44)" {
        Set-Content .prettierrc '{"proseWrap":"always","overrides":[{"files":["_working-memory/**/*.md"],"excludeFiles":["_working-memory/decisionLog.md"],"options":{"proseWrap":"preserve"}}]}'
        Invoke-Installer --formatter-override | Out-Null
        $o = @((Get-Content .prettierrc -Raw | ConvertFrom-Json).overrides)
        "$($o.Count) $($o[-1].files[0]) $($o[-1].options.proseWrap) $($null -eq $o[-1].excludeFiles)" | Should -Be "2 $FMT_GLOB preserve True"
        Get-MatchCount '.working-memoryrc' '^formatter_override=added$' | Should -Be 1
    }

    It 'headless with no flag skips the override (#44)' {
        Set-Content .prettierrc '{"proseWrap":"always"}'
        $before = Get-Content .prettierrc -Raw
        $out = Invoke-Installer
        Get-Content .prettierrc -Raw | Should -BeExactly $before
        $out | Should -Not -Match 'Add an override'
        Test-RcHasFmtKey | Should -BeFalse
    }
}
