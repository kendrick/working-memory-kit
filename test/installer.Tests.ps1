# Parity twin of test/installer.bats: the installer invariants on PowerShell.

BeforeAll { . (Join-Path $PSScriptRoot 'Common.ps1') }

Describe 'installer' {
    BeforeEach { $repo = New-TestRepo }
    AfterEach { Remove-TestRepo $repo }

    It 'fresh install scaffolds the working memory' {
        Invoke-Installer | Out-Null
        'AGENTS.md' | Should -Exist
        '_working-memory/decisionLog.md' | Should -Exist
        Get-Content AGENTS.md -Raw | Should -Match 'working-memory:start'
        Get-Content .gitignore -Raw | Should -Match 'activeContext.md'
    }

    It 'install is idempotent' {
        Set-Content package.json '{ "dependencies": { "react": "^18.0.0" } }'
        Invoke-Installer | Out-Null
        git add -A; git commit -q -m base
        Invoke-Installer | Out-Null
        git status --porcelain | Should -BeNullOrEmpty
    }

    It 'no-clobber: existing AGENTS.md keeps user content, section added once' {
        Set-Content AGENTS.md "# My Project`n`nCustom house rules.`n"
        Invoke-Installer | Out-Null
        Get-Content AGENTS.md -Raw | Should -Match 'Custom house rules\.'
        Get-MatchCount 'AGENTS.md' '^## Working Memory' | Should -Be 1
        Invoke-Installer | Out-Null
        Get-Content AGENTS.md -Raw | Should -Match 'Custom house rules\.'
        Get-MatchCount 'AGENTS.md' '^## Working Memory' | Should -Be 1
    }

    It 'no-clobber: existing CLAUDE.md is prepended, user content kept' {
        Set-Content CLAUDE.md "# My CLAUDE`n`nProject specifics.`n"
        Invoke-Installer | Out-Null
        Get-Content CLAUDE.md -Raw | Should -Match 'Project specifics\.'
        Get-MatchCount 'CLAUDE.md' '^## Working Memory' | Should -Be 1
    }

    It 'stack detection: package.json react lands in the stack' {
        Set-Content package.json '{ "dependencies": { "react": "^18.0.0" } }'
        Invoke-Installer | Out-Null
        Get-Content AGENTS.md -Raw | Should -Match 'React'
        Get-Content '_working-memory/projectOverview.md' -Raw | Should -Match 'React'
    }

    It 'stack detection: pyproject.toml lands Python' {
        Set-Content pyproject.toml "[project]`nname = `"x`"`ndependencies = [`"django`"]`n"
        Invoke-Installer | Out-Null
        Get-Content '_working-memory/projectOverview.md' -Raw | Should -Match 'Python'
    }
}
