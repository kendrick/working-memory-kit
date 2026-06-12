# Parity twin of test/coexistence.bats (V1b + V2). The installer detects
# spec-driven neighbors from its registry and wires the boundary (ownership map,
# AGENTS cross-ref inside the fence, conventions deferral), warns on a rival
# memory tool, registers unknown tooling via flags + .working-memoryrc, and
# leaves a no-neighbor install exactly as before.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Common.ps1')
    $XREF = 'Spec-driven tooling lives in'
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
}
