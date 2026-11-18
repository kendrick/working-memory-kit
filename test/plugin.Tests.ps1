# Parity twin of test/plugin.bats test 4 (#82): the PowerShell block in skills/init/SKILL.md must
# leave the same tree as init.ps1 run directly. The block is read out of SKILL.md, so a pass
# can't come from a hand-written copy. Needs powershell.exe (5.1 on Windows), so it skips elsewhere.

BeforeDiscovery { $script:HasWinPs = [bool](Get-Command powershell.exe -ErrorAction SilentlyContinue) }

BeforeAll {
    . (Join-Path $PSScriptRoot 'Common.ps1')

    # Files: relpath|mtime ticks|size. Directories: relpath only, since NTFS dir mtimes keep settling after Copy-Item.
    function Get-Snapshot ($root) {
        $n = $root.TrimEnd('\', '/').Length + 1
        return @(Get-ChildItem -LiteralPath $root -Recurse -Force |
            ForEach-Object { $_.FullName.Substring($n) + $(if ($_.PSIsContainer) { '' } else { '|' + $_.LastWriteTimeUtc.Ticks + '|' + $_.Length }) } |
            Sort-Object)
    }

    function Get-TreeHashes ($root) {
        $n = $root.TrimEnd('\', '/').Length + 1
        return @(Get-ChildItem -LiteralPath $root -Recurse -Force -File |
            Where-Object { $_.FullName.Substring($n) -notmatch '^\.git([\\/]|$)' } |
            ForEach-Object { $_.FullName.Substring($n) + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } |
            Sort-Object)
    }

    function New-GitDir ($path) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        git -C $path init -q 2>$null
        git -C $path config user.email test@example.com
        git -C $path config user.name test
        git -C $path config commit.gpgsign false
        # Same pin as New-TestRepo: windows-latest's autocrlf=true would make the trees differ for the wrong reason.
        git -C $path config core.autocrlf false
    }
}

Describe 'init skill (#82)' {
    It "PowerShell command installs like init.ps1 (#82)" -Skip:(-not $script:HasWinPs) {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wmk-plugin-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
        try {
            # Spaces in both names are deliberate: each path must stay one argument.
            $root = Join-Path $tmp 'plugin root'
            $a = Join-Path $tmp 'a\my app'
            $b = Join-Path $tmp 'b\my app'
            $elsewhere = Join-Path $tmp 'elsewhere'
            New-Item -ItemType Directory -Path $root, $elsewhere -Force | Out-Null
            # In a linked worktree .git is a file pointing at the real repo; don't copy it.
            Get-ChildItem -LiteralPath $KitRoot -Force | Where-Object { $_.Name -ne '.git' } |
                Copy-Item -Destination $root -Recurse -Force
            $before = Get-Snapshot $root
            New-GitDir $a
            New-GitDir $b

            $lines = @(Get-Content -LiteralPath (Join-Path $KitRoot 'skills/init/SKILL.md'))
            $open = [array]::IndexOf($lines, '```powershell')
            $open | Should -BeGreaterOrEqual 0
            $body = @()
            for ($i = $open + 1; $i -lt $lines.Count -and $lines[$i] -ne '```'; $i++) { $body += $lines[$i] }
            $cmd = $body -join "`n"
            $cmd | Should -Not -BeNullOrEmpty
            # Claude Code substitutes forward slashes on Windows.
            $cmd = $cmd.Replace('${CLAUDE_PLUGIN_ROOT}', $root.Replace('\', '/')).Replace('${CLAUDE_PROJECT_DIR}', $a.Replace('\', '/'))

            Set-Location $elsewhere
            [Environment]::CurrentDirectory = $elsewhere
            powershell.exe -NoProfile -Command $cmd *>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0

            Set-Location $b
            [Environment]::CurrentDirectory = $b
            Invoke-Installer | Out-Null

            Test-Path (Join-Path $a 'AGENTS.md') | Should -BeTrue  # two empty trees would match for the wrong reason
            Compare-Object (Get-TreeHashes $a) (Get-TreeHashes $b) | Should -BeNullOrEmpty
            Get-Snapshot $root | Should -Be $before
            @(Get-ChildItem -LiteralPath $elsewhere -Force) | Should -HaveCount 0
        }
        finally { Remove-TestRepo $tmp }
    }
}

# The plugin's SessionStart hook (#91), mirroring the version hook cases in test/plugin.bats.
Describe 'version hook (#91)' {
    BeforeAll {
        $script:Warn = '{"systemMessage":"working-memory-kit: this project runs kit 0.9.0 and the plugin has 0.10.0. Run /working-memory-kit:init to upgrade it."}'

        # Spaces in both names are deliberate: each path must stay one argument.
        function New-HookFixture ($projectVer, $pluginVer) {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wmk-hook-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
            $root = Join-Path $tmp 'plugin root'
            $proj = Join-Path $tmp 'my project'
            New-Item -ItemType Directory -Path $root, (Join-Path $proj '.claude') -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $KitRoot 'hooks') -Destination (Join-Path $root 'hooks') -Recurse
            [IO.File]::WriteAllText((Join-Path $root 'version.txt'), "$pluginVer`n")
            $marker = Join-Path $proj '.claude/working-memory-kit.version'
            if ($projectVer) { [IO.File]::WriteAllText($marker, "$projectVer`n") }
            $env:CLAUDE_PROJECT_DIR = $proj
            return @{ Tmp = $tmp; Root = $root; Proj = $proj; Marker = $marker }
        }

        function Invoke-Hook ($f) { return (& (Join-Path $f.Root 'hooks/version-check.ps1') | Out-String).Trim() }
    }

    BeforeEach { $script:SavedProjectDir = $env:CLAUDE_PROJECT_DIR }
    AfterEach {
        $env:CLAUDE_PROJECT_DIR = $script:SavedProjectDir
        if ($script:F) { Remove-TestRepo $script:F.Tmp; $script:F = $null }
    }

    It 'warns when the project is behind, compared as semver (#91)' {
        $script:F = New-HookFixture '0.9.0' '0.10.0'
        Invoke-Hook $script:F | Should -BeExactly $script:Warn
    }

    It 'is silent when the project is newer (#91)' {
        $script:F = New-HookFixture '0.4.0' '0.3.0'
        Invoke-Hook $script:F | Should -BeNullOrEmpty
    }

    It 'is silent with no marker (#91)' {
        $script:F = New-HookFixture '' '0.10.0'
        Invoke-Hook $script:F | Should -BeNullOrEmpty
        Test-Path -LiteralPath $script:F.Marker | Should -BeFalse
    }

    It 'reads a CRLF marker (#91)' {
        $script:F = New-HookFixture '' '0.10.0'
        [IO.File]::WriteAllText($script:F.Marker, "0.9.0`r`n")
        Invoke-Hook $script:F | Should -BeExactly $script:Warn
    }

    It 'runs the hooks.json command under powershell.exe without bash (#91)' -Skip:(-not $script:HasWinPs -or $env:OS -ne 'Windows_NT') {
        $script:F = New-HookFixture '0.9.0' '0.10.0'
        $cmd = (Get-Content -LiteralPath (Join-Path $KitRoot 'hooks/hooks.json') -Raw | ConvertFrom-Json).hooks.SessionStart[0].hooks[0].command
        # A hook that runs through PowerShell gets the placeholder with native backslashes.
        $cmd = $cmd.Replace('${CLAUDE_PLUGIN_ROOT}', $script:F.Root)
        $beforeP = Get-Snapshot $script:F.Proj
        $beforeR = Get-Snapshot $script:F.Root
        $savedPath = $env:PATH
        try {
            # With no Git entry on PATH there's no bash or sh to find, which is the case this command has to cover.
            $env:PATH = (($env:PATH -split ';') | Where-Object { $_ -notmatch 'Git' }) -join ';'
            # -EncodedCommand hands the line over byte for byte; -Command would lose its embedded quotes to 5.1's native argument passing.
            $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
            $out = powershell.exe -NoProfile -EncodedCommand $enc 2>$null
            $LASTEXITCODE | Should -Be 0
        }
        finally { $env:PATH = $savedPath }
        ($out -join "`n").Trim() | Should -BeExactly $script:Warn
        Get-Snapshot $script:F.Proj | Should -Be $beforeP
        Get-Snapshot $script:F.Root | Should -Be $beforeR
    }
}
