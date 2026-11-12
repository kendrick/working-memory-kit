# Parity twin of test/hooks.bats, exercising the .ps1 session-end hook: the
# nudge fires on real work, stays quiet otherwise, and (the #6 regression) does
# not miscount during an in-progress merge. Thresholds are driven low via a
# fixture .working-memoryrc.

BeforeAll { . (Join-Path $PSScriptRoot 'Common.ps1') }

Describe 'session-end hook' {
    BeforeEach {
        $repo = New-TestRepo
        New-Item -ItemType Directory -Path '_working-memory' -Force | Out-Null
    }
    AfterEach { Remove-TestRepo $repo }

    # git diff HEAD needs a HEAD, so every test commits a base first, then makes
    # the "session's work" on top of it.

    It 'session-end nudges above threshold' {
        Set-Content .working-memoryrc "NUDGE_FILE_THRESHOLD=1`nNUDGE_LINE_THRESHOLD=1"
        git add -A; git commit -q -m base
        Set-Content f1.txt 'a'
        Set-Content f2.txt 'b'
        git add -A
        $out = Invoke-SessionEndHook
        $out | Should -Match 'systemMessage'
        $out | Should -Match 'update-working-memory'
    }

    It 'session-end is silent below threshold' {
        Set-Content .working-memoryrc "NUDGE_FILE_THRESHOLD=50`nNUDGE_LINE_THRESHOLD=5000"
        git add -A; git commit -q -m base
        Set-Content f1.txt 'a'
        git add -A
        $out = Invoke-SessionEndHook
        "$out".Trim() | Should -BeNullOrEmpty
    }

    It 'session-end skips during an in-progress merge (regression for #6)' {
        Set-Content .working-memoryrc "NUDGE_FILE_THRESHOLD=1`nNUDGE_LINE_THRESHOLD=1"
        git add -A; git commit -q -m base
        # a large change that would normally nudge...
        foreach ($i in 1..6) { Set-Content "big$i.txt" 'x' }
        git add -A
        # ...but a merge is in progress, so the diff is polluted by the incoming side
        $gitDir = git rev-parse --absolute-git-dir
        Set-Content (Join-Path $gitDir 'MERGE_HEAD') ''
        $out = Invoke-SessionEndHook
        "$out".Trim() | Should -BeNullOrEmpty
    }

    It 'a broken dataContracts pointer is reported when the nudge fires' {
        Set-Content .working-memoryrc "NUDGE_FILE_THRESHOLD=1`nNUDGE_LINE_THRESHOLD=1"
        Set-Content '_working-memory/dataContracts.md' "# Data Contracts`n`nSee [types](src/missing.ts).`n"
        git add -A; git commit -q -m base
        Set-Content f1.txt 'a'
        Set-Content f2.txt 'b'
        git add -A
        $out = Invoke-SessionEndHook
        $out | Should -Match 'broken pointer'
    }

    # Windows PowerShell 5.1 and pwsh 7 escape differently (5.1 writes ' as
    # \u0027), so decode and compare strings, not raw bytes.
    It 'session-end JSON survives a quote and a backslash in pointers (#41)' {
        Set-Content .working-memoryrc "NUDGE_FILE_THRESHOLD=1`nNUDGE_LINE_THRESHOLD=1"
        Set-Content '_working-memory/dataContracts.md' "# Data Contracts`n`nSee [a](src/`"x`".ts), [b](src\y.ts).`n"
        git add -A; git commit -q -m base
        Set-Content f1.txt 'a'
        Set-Content f2.txt 'b'
        git add -A
        $msg = (Invoke-SessionEndHook | ConvertFrom-Json).systemMessage
        $msg | Should -BeLike '*src/"x".ts*'
        $msg | Should -BeLike '*src\y.ts*'
    }

    # Parity guard: today's start message has no quote or backslash, so this
    # passes before the fix too.
    It 'session-start output parses as JSON (#41)' {
        Set-Content '_working-memory/activeContext.md' 'x'
        $out = & (Join-Path $KitRoot 'template/scripts/working-memory-session-start.ps1') | Out-String
        ($out | ConvertFrom-Json).systemMessage | Should -BeLike "*AGENTS.md's*"
    }

    # #33: nudge toward `ltm promote` when a Bank-connected repo gains a decisionLog entry.
    Context 'ltm promote nudge (#33)' {
        BeforeEach {
            Set-Content .working-memoryrc "NUDGE_FILE_THRESHOLD=50`nNUDGE_LINE_THRESHOLD=5000"
            Set-Content .ltm.yaml 'bank: x'
            $start = Join-Path $KitRoot 'template/scripts/working-memory-session-start.ps1'
        }
        # Defined here so the tests compare against the spec text, not the script's own template.
        BeforeAll {
            function Get-PromoteLine ($title) {
                "working-memory: new decisionLog entry `"$title`". If it applies beyond this repo: ltm promote _working-memory/decisionLog.md --entry `"$title`""
            }
        }

        It 'session-end prints an ltm promote line per new decisionLog entry when .ltm.yaml exists (#33)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content '_working-memory/decisionLog.md' "# Decision Log`n`n## 2026-11-01: Cap retries at three per request`n`nbody`n`n## 2026-11-02: Drop the v1 API`n"
            $msg = (Invoke-SessionEndHook | ConvertFrom-Json).systemMessage
            $msg | Should -BeExactly ((Get-PromoteLine 'Cap retries at three per request') + "`n" + (Get-PromoteLine 'Drop the v1 API'))
        }

        It 'the promote nudge counts an entry committed during the session (#33)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content '_working-memory/decisionLog.md' "## 2026-11-01: Cap retries at three per request`n"
            git add -A; git commit -q -m work
            (Invoke-SessionEndHook | ConvertFrom-Json).systemMessage | Should -BeExactly (Get-PromoteLine 'Cap retries at three per request')
        }

        It 'no .ltm.yaml, no promote line (#33)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content '_working-memory/decisionLog.md' "## 2026-11-01: Cap retries at three per request`n"
            Remove-Item .ltm.yaml -Force -ErrorAction Stop
            "$(Invoke-SessionEndHook)".Trim() | Should -BeNullOrEmpty
        }

        It 'a new heading in conventions.md prints nothing (#33)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content '_working-memory/conventions.md' "## 2026-11-01: Cap retries at three per request`n"
            "$(Invoke-SessionEndHook)".Trim() | Should -BeNullOrEmpty
        }

        It "editing an existing entry's body prints nothing (#33)" {
            Set-Content '_working-memory/decisionLog.md' "## 2026-11-01: Cap retries at three per request`n`nbody`n"
            git add -A; git commit -q -m base
            & $start | Out-Null
            Add-Content '_working-memory/decisionLog.md' 'more body'
            "$(Invoke-SessionEndHook)".Trim() | Should -BeNullOrEmpty
        }

        It 'a heading whose only change is case reads as new (#33)' {
            Set-Content '_working-memory/decisionLog.md' "## 2026-11-01: Cap Retries`n"
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content '_working-memory/decisionLog.md' "## 2026-11-01: cap retries`n"
            (Invoke-SessionEndHook | ConvertFrom-Json).systemMessage | Should -BeExactly (Get-PromoteLine 'cap retries')
        }

        # Passes on pwsh 7 regardless; guards 5.1, where git show is decoded with the OEM code page.
        It 'a non-ASCII heading with a body-only edit prints nothing (#33)' {
            Set-Content '_working-memory/decisionLog.md' "# Decision Log`n`n## 2026-10-01: Caf$([char]0xE9) policy`n`nbody`n" -Encoding UTF8
            git add -A; git commit -q -m base
            & $start | Out-Null
            Add-Content '_working-memory/decisionLog.md' 'more body' -Encoding UTF8
            "$(Invoke-SessionEndHook)".Trim() | Should -BeNullOrEmpty
        }

        It 'the promote line keeps the JSON valid with a quote in the title (#33)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content '_working-memory/decisionLog.md' "## 2026-11-01: Use `"at most once`" delivery`n"
            $msg = (Invoke-SessionEndHook | ConvertFrom-Json).systemMessage
            # --entry is single-quoted because the title holds a double quote.
            $msg | Should -BeExactly 'working-memory: new decisionLog entry "Use "at most once" delivery". If it applies beyond this repo: ltm promote _working-memory/decisionLog.md --entry ''Use "at most once" delivery'''
        }

        It 'a title with shell expansion syntax prints a single-quoted entry (#33)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content '_working-memory/decisionLog.md' '## 2026-11-01: Keep $HOME private'
            $msg = (Invoke-SessionEndHook | ConvertFrom-Json).systemMessage
            $msg | Should -BeExactly 'working-memory: new decisionLog entry "Keep $HOME private". If it applies beyond this repo: ltm promote _working-memory/decisionLog.md --entry ''Keep $HOME private'''
            function ltm { $args[3] }
            Invoke-Expression ($msg -replace '^.*If it applies beyond this repo: ', '') | Should -BeExactly 'Keep $HOME private'
        }

        It 'a title with an apostrophe and a dollar sign round-trips (#33)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content '_working-memory/decisionLog.md' '## 2026-11-01: Don''t expand $HOME'
            $msg = (Invoke-SessionEndHook | ConvertFrom-Json).systemMessage
            $msg | Should -BeExactly 'working-memory: new decisionLog entry "Don''t expand $HOME". If it applies beyond this repo: ltm promote _working-memory/decisionLog.md --entry ''Don''''t expand $HOME'''
            function ltm { $args[3] }
            Invoke-Expression ($msg -replace '^.*If it applies beyond this repo: ', '') | Should -BeExactly 'Don''t expand $HOME'
        }

        It 'a title with curly quotes round-trips (#33)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            # Curly quotes are PowerShell quote delimiters; built from code points to keep this file ASCII.
            $apos = [char]0x2019; $lq = [char]0x201C; $rq = [char]0x201D
            $title = "It${apos}s ${lq}`$x${rq}"
            Set-Content '_working-memory/decisionLog.md' "## 2026-11-01: $title"
            $msg = (Invoke-SessionEndHook | ConvertFrom-Json).systemMessage
            $msg | Should -BeExactly "working-memory: new decisionLog entry `"$title`". If it applies beyond this repo: ltm promote _working-memory/decisionLog.md --entry 'It${apos}${apos}s ${lq}`$x${rq}'"
            function ltm { $args[3] }
            Invoke-Expression ($msg -replace '^.*If it applies beyond this repo: ', '') | Should -BeExactly $title
        }

        It 'the promote line follows the size nudge when both fire (#33)' {
            Set-Content .working-memoryrc "NUDGE_FILE_THRESHOLD=1`nNUDGE_LINE_THRESHOLD=1"
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content '_working-memory/decisionLog.md' "## 2026-11-01: Cap retries at three per request`n"
            Set-Content f1.txt 'a'; Set-Content f2.txt 'b'
            git add -A
            $lines = (Invoke-SessionEndHook | ConvertFrom-Json).systemMessage -split "`n"
            $lines.Count | Should -Be 2
            $lines[0] | Should -BeExactly 'You changed 3 files and 4 lines this session. Use the update-working-memory skill or the supplied update script to keep working memory current.'
            $lines[1] | Should -BeExactly (Get-PromoteLine 'Cap retries at three per request')
        }
    }

    # #35: the nudge counts everything since the commit recorded at session start.
    Context 'base recorded at session start (#35)' {
        BeforeEach {
            Set-Content .working-memoryrc "NUDGE_FILE_THRESHOLD=5`nNUDGE_LINE_THRESHOLD=5000"
            $start = Join-Path $KitRoot 'template/scripts/working-memory-session-start.ps1'
        }

        It 'session-end counts work committed after session start (#35)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            foreach ($i in 1..10) { Set-Content "c$i.txt" 'x' }
            git add -A; git commit -q -m work
            Invoke-SessionEndHook | Should -Match '10 files'
        }

        It 'session-end is silent when the only commit predates session start (#35)' {
            foreach ($i in 1..10) { Set-Content "c$i.txt" 'x' }
            git add -A; git commit -q -m base
            & $start | Out-Null
            "$(Invoke-SessionEndHook)".Trim() | Should -BeNullOrEmpty
        }

        It 'session-end falls back to HEAD when the recorded base is gone (#35)' {
            git add -A; git commit -q -m base
            $gitDir = git rev-parse --absolute-git-dir
            Set-Content (Join-Path $gitDir 'working-memory-session-base') ('deadbeef' * 5)
            foreach ($i in 1..10) { Set-Content "c$i.txt" 'x' }
            git add -A
            Invoke-SessionEndHook | Should -Match '10 files'
        }

        It 'session-end falls back to HEAD when the base file is unreadable (#35)' -Skip:($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop' -or (id -u) -eq '0') {
            git add -A; git commit -q -m base
            $base = Join-Path (git rev-parse --absolute-git-dir) 'working-memory-session-base'
            Set-Content $base 'x'
            chmod 000 $base
            try {
                foreach ($i in 1..10) { Set-Content "c$i.txt" 'x' }
                git add -A
                $out = Invoke-SessionEndHook
            } finally { chmod 600 $base }
            $out | Should -Match '10 files'
        }

        It 'session-end trims a trailing newline in the base (#35)' {
            git add -A; git commit -q -m base
            $gitDir = git rev-parse --absolute-git-dir
            Set-Content (Join-Path $gitDir 'working-memory-session-base') (git rev-parse HEAD)
            foreach ($i in 1..10) { Set-Content "c$i.txt" 'x' }
            git add -A; git commit -q -m work
            Invoke-SessionEndHook | Should -Match '10 files'
        }

        It 'session-end does not throw outside a git repo (#35)' {
            $plain = Join-Path ([System.IO.Path]::GetTempPath()) ('wmk-ng-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Path "$plain/_working-memory" -Force | Out-Null
            Set-Location $plain; [Environment]::CurrentDirectory = $plain
            try {
                { & (Join-Path $KitRoot 'template/scripts/working-memory-session-end.ps1') 2>$null | Out-Null } | Should -Not -Throw
            } finally { Set-Location $repo; [Environment]::CurrentDirectory = $repo; Remove-Item -Recurse -Force $plain }
        }

        It 'session-start writes the full SHA, no newline, and nothing in an empty repo (#35)' {
            & $start | Out-Null
            $gitDir = git rev-parse --absolute-git-dir
            $f = Join-Path $gitDir 'working-memory-session-base'
            Test-Path $f | Should -BeFalse
            git add -A; git commit -q -m base
            & $start | Out-Null
            [System.IO.File]::ReadAllText($f) | Should -BeExactly (git rev-parse HEAD)
        }
    }
}
