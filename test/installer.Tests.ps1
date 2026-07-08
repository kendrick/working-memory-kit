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

    # ---- upgrade flow (parity with the upgrade-flow tests in installer.bats;
    # the interactive Upgrade/Cancel menu is driven by pty on the bash side, so
    # here we cover the headless MODE behavior and the machinery reconciliation) ----

    It 'headless re-run resolves to upgrade automatically' {
        Invoke-Installer | Out-Null
        git add -A; git commit -q -m base
        Invoke-Installer | Should -Match 'upgrading'
    }

    It 'machinery divergence writes a .kitnew, keeps your edit, spares content' {
        Invoke-Installer | Out-Null
        Add-Content scripts/update-working-memory.ps1 "`n# local tweak"
        Add-Content _working-memory/decisionLog.md "`nMy own decision."
        Invoke-Installer | Out-Null
        'scripts/update-working-memory.ps1.kitnew' | Should -Exist
        Get-Content scripts/update-working-memory.ps1 -Raw | Should -Match 'local tweak'
        Get-Content scripts/update-working-memory.ps1 -Raw | Should -Match 'a newer version of this file shipped'
        Get-Content _working-memory/decisionLog.md -Raw | Should -Match 'My own decision\.'
    }

    It 'an unmodified machinery file gets no .kitnew' {
        Invoke-Installer | Out-Null
        git add -A; git commit -q -m base
        Invoke-Installer | Out-Null
        @(Get-ChildItem -Recurse -File | Where-Object { $_.Name -like '*.kitnew' }).Count | Should -Be 0
    }

    It 'a diverged upgrade is byte-stable on the next run' {
        Invoke-Installer | Out-Null
        Add-Content scripts/update-working-memory.ps1 "`n# local tweak"
        Invoke-Installer | Out-Null
        $before = Get-Content scripts/update-working-memory.ps1 -Raw
        Invoke-Installer | Out-Null
        Get-Content scripts/update-working-memory.ps1 -Raw | Should -BeExactly $before
        Get-MatchCount 'scripts/update-working-memory.ps1' 'a newer version of this file shipped' | Should -Be 1
    }

    It '--overwrite-machinery takes the kit version and spares content' {
        Invoke-Installer | Out-Null
        Add-Content scripts/update-working-memory.ps1 "`n# local tweak"
        Add-Content _working-memory/decisionLog.md "`nMy own decision."
        Invoke-Installer --overwrite-machinery | Out-Null
        Get-Content scripts/update-working-memory.ps1 -Raw | Should -Not -Match 'local tweak'
        Get-Content _working-memory/decisionLog.md -Raw | Should -Match 'My own decision\.'
    }

    It 'additive: a missing content file is restored on upgrade' {
        Invoke-Installer | Out-Null
        Add-Content _working-memory/decisionLog.md "`nMy own decision."
        Remove-Item _working-memory/antipatterns.md
        Invoke-Installer | Out-Null
        '_working-memory/antipatterns.md' | Should -Exist
        Get-Content _working-memory/decisionLog.md -Raw | Should -Match 'My own decision\.'
    }

    It 'the Copilot instructions example ships inert' {
        Invoke-Installer | Out-Null
        '.github/instructions/working-memory.instructions.md.example' | Should -Exist
        @(Get-ChildItem .github/instructions -File | Where-Object { $_.Name -like '*.instructions.md' }).Count | Should -Be 0
    }
}
