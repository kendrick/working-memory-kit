# Parity twin of test/fencing.bats (V1a). The invariant everywhere: user content
# and any neighbor's block survive a (re)install byte-for-byte, because the
# installer only ever touches text between its own start/end markers.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Common.ps1')
    $START = '<!-- working-memory:start -->'
    $END = '<!-- working-memory:end -->'
}

Describe 'fencing' {
    BeforeEach { $repo = New-TestRepo }
    AfterEach { Remove-TestRepo $repo }

    It 'fresh install fences all three files exactly once' {
        Invoke-Installer | Out-Null
        foreach ($f in @('AGENTS.md', 'CLAUDE.md', '.github/copilot-instructions.md')) {
            Get-MatchCount $f $START | Should -Be 1 -Because "$f should have one start marker"
            Get-MatchCount $f $END | Should -Be 1 -Because "$f should have one end marker"
        }
    }

    It 'AGENTS.md fences only the working-memory section, not Conventions' {
        Invoke-Installer | Out-Null
        # ## Conventions must sit after the end marker (outside the fence).
        Get-FromMarker 'AGENTS.md' $END | Should -Match '(?m)^## Conventions'
    }

    It 're-install is idempotent (replace-between is a no-op)' {
        Invoke-Installer | Out-Null
        git add -A; git commit -q -m base
        Invoke-Installer | Out-Null
        git status --porcelain | Should -BeNullOrEmpty
    }

    It "a neighbor's block outside the markers survives a re-install" {
        Invoke-Installer | Out-Null
        # Append with explicit CRLF, the way Add-Content does on Windows, and write
        # the bytes verbatim. This exercises the "never touch endings outside our
        # markers" invariant on every platform; Add-Content here would write LF on
        # macOS/Linux and pass trivially, hiding the regression until Windows CI.
        $neighbor = "`r`n<!-- other-tool:start -->`r`nNEIGHBOR DATA`r`n<!-- other-tool:end -->`r`n"
        [System.IO.File]::AppendAllText((Resolve-Path AGENTS.md).Path, $neighbor)
        git add -A; git commit -q -m base
        Invoke-Installer | Out-Null
        git status --porcelain | Should -BeNullOrEmpty
        Get-Content AGENTS.md -Raw | Should -Match 'NEIGHBOR DATA'
    }

    It 'legacy unfenced AGENTS.md migrates once, keeping Conventions' {
        Set-Content AGENTS.md "# AGENTS.md`n`n## Working Memory`n`nold unfenced content.`n`n## Conventions`n`nuser rule X.`n"
        Invoke-Installer | Out-Null
        Get-MatchCount 'AGENTS.md' $START | Should -Be 1
        Get-Content AGENTS.md -Raw | Should -Not -Match 'old unfenced content'
        Get-Content AGENTS.md -Raw | Should -Match 'user rule X\.'
        git add -A; git commit -q -m base
        Invoke-Installer | Out-Null
        git status --porcelain | Should -BeNullOrEmpty
    }

    It 'legacy CLAUDE.md migration keeps user H1 content outside the fence' {
        Set-Content CLAUDE.md "## Working Memory`n`nold pointer.`nTo sync working memory, run old.`n`n# My Project`n`nuser content that must survive.`n"
        Invoke-Installer | Out-Null
        Get-MatchCount 'CLAUDE.md' $START | Should -Be 1
        Get-Content CLAUDE.md -Raw | Should -Match 'user content that must survive\.'
        Get-FromMarker 'CLAUDE.md' $END | Should -Match 'user content that must survive\.'
    }

    It 'legacy CLAUDE.md migration keeps heading-less user prose (sentinel-bounded)' {
        Set-Content CLAUDE.md "## Working Memory`n`nold.`nTo sync working memory, see old docs.`n`nplain user prose, no heading, must survive.`n"
        Invoke-Installer | Out-Null
        Get-Content CLAUDE.md -Raw | Should -Match 'must survive\.'
        Get-FromMarker 'CLAUDE.md' $END | Should -Match 'must survive\.'
    }

    It 'an unboundable legacy section is left alone, not mangled' {
        Set-Content CLAUDE.md "## Working Memory`n`nweird legacy, no end line, no other heading, just prose.`n"
        $out = Invoke-Installer
        $out | Should -Match 'could not bound safely'
        Get-Content CLAUDE.md -Raw | Should -Not -Match 'working-memory:start'
        Get-Content CLAUDE.md -Raw | Should -Match 'weird legacy'
    }

    It 'injecting into an existing AGENTS.md with no WM section adds it once' {
        Set-Content AGENTS.md "# AGENTS.md`n`n## Stack`n`nGo.`n"
        Invoke-Installer | Out-Null
        Get-Content AGENTS.md -Raw | Should -Match 'Go\.'
        Get-MatchCount 'AGENTS.md' $START | Should -Be 1
        Get-MatchCount 'AGENTS.md' '^## Working Memory' | Should -Be 1
    }
}
