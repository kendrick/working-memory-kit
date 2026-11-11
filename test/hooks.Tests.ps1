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

        It 'session-end trims a trailing newline in the base (#35)' {
            git add -A; git commit -q -m base
            $gitDir = git rev-parse --absolute-git-dir
            Set-Content (Join-Path $gitDir 'working-memory-session-base') (git rev-parse HEAD)
            foreach ($i in 1..10) { Set-Content "c$i.txt" 'x' }
            git add -A; git commit -q -m work
            Invoke-SessionEndHook | Should -Match '10 files'
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
