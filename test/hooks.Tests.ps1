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
}
