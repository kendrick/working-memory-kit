# Parity twin of test/plugin.bats test 4 (#82): the PowerShell block in skills/init/SKILL.md must
# leave the same tree as init.ps1 run directly. The block is read out of SKILL.md, so a pass
# can't come from a hand-written copy. Needs powershell.exe (5.1 on Windows), so it skips elsewhere.

BeforeDiscovery { $script:HasWinPs = [bool](Get-Command powershell.exe -ErrorAction SilentlyContinue) }

BeforeAll {
    . (Join-Path $PSScriptRoot 'Common.ps1')

    # relpath|mtime ticks|size for everything under $root; .git excluded since it's not plugin content.
    function Get-Snapshot ($root) {
        $n = $root.TrimEnd('\', '/').Length + 1
        return @(Get-ChildItem -LiteralPath $root -Recurse -Force |
            ForEach-Object { $_.FullName.Substring($n) + '|' + $_.LastWriteTimeUtc.Ticks + '|' + $(if ($_.PSIsContainer) { 0 } else { $_.Length }) } |
            Sort-Object)
    }

    # relpath|SHA256 for every file under $root but .git.
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
