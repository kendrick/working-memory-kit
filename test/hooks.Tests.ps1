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
            # UTF8: 5.1's default is ANSI, and the hook reads the log as UTF-8, so ANSI bytes would come back mangled.
            Set-Content '_working-memory/decisionLog.md' "## 2026-11-01: $title" -Encoding UTF8
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

    # #4: a root manifest changed since session start suggests a Stack review; a lockfile alone doesn't.
    Context 'stack freshness nudge (#4)' {
        BeforeEach {
            Set-Content .working-memoryrc "NUDGE_FILE_THRESHOLD=50`nNUDGE_LINE_THRESHOLD=5000"
            # Set-Content writes CRLF on Windows, which exercises the hook's CR strip.
            Set-Content '_working-memory/projectOverview.md' "# Project Overview`n`n## Stack`n- Language: JS`n"
            Set-Content package.json '{"name":"x"}'
            Set-Content pnpm-lock.yaml 'lock'
            Set-Content pyproject.toml "[project]`nname = `"x`""
            $start = Join-Path $KitRoot 'template/scripts/working-memory-session-start.ps1'
        }
        # Defined here so the tests compare against the spec text, not the script's own template.
        BeforeAll {
            function Get-StackLine ($names) {
                "working-memory: $names changed this session. If the stack shifted, review the Stack section of _working-memory/projectOverview.md."
            }
            function Get-PromoteLine ($title) {
                "working-memory: new decisionLog entry `"$title`". If it applies beyond this repo: ltm promote _working-memory/decisionLog.md --entry `"$title`""
            }
        }

        It 'a package.json change committed this session suggests a Stack review (#4)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content package.json '{"name":"y"}'
            git commit -q -am work
            (Invoke-SessionEndHook | ConvertFrom-Json).systemMessage | Should -BeExactly (Get-StackLine 'package.json')
        }

        It 'an uncommitted pyproject.toml edit suggests a Stack review (#4)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            Add-Content pyproject.toml 'version = "1"'
            (Invoke-SessionEndHook | ConvertFrom-Json).systemMessage | Should -BeExactly (Get-StackLine 'pyproject.toml')
        }

        It 'a lockfile-only change does not nudge (#4)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content pnpm-lock.yaml 'lock2'
            "$(Invoke-SessionEndHook)".Trim() | Should -BeNullOrEmpty
        }

        It 'several changed names are listed in git order (#4)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content package-lock.json 'lock'
            git add package-lock.json
            Set-Content package.json '{"name":"y"}'
            (Invoke-SessionEndHook | ConvertFrom-Json).systemMessage | Should -BeExactly (Get-StackLine 'package-lock.json, package.json')
        }

        It 'an unrelated, nested, or look-alike file does not nudge (#4)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            New-Item -ItemType Directory -Path src, web -Force | Out-Null
            Set-Content src/app.js 'x'
            Set-Content web/package.json '{}'
            Set-Content package.json.orig '{}'
            git add -A
            "$(Invoke-SessionEndHook)".Trim() | Should -BeNullOrEmpty
        }

        It 'no nudge when projectOverview.md also changed this session (#4)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content package.json '{"name":"y"}'
            Add-Content '_working-memory/projectOverview.md' 'more'
            "$(Invoke-SessionEndHook)".Trim() | Should -BeNullOrEmpty
        }

        It 'an untracked new manifest does not nudge (#4)' {
            git add -A; git commit -q -m base
            git rm -q --cached pyproject.toml
            git commit -q -m untrack
            & $start | Out-Null
            Set-Content pyproject.toml "[project]`nname = `"y`""
            "$(Invoke-SessionEndHook)".Trim() | Should -BeNullOrEmpty
        }

        It 'a manifest change committed before session start does not nudge (#4)' {
            git add -A; git commit -q -m base
            Set-Content package.json '{"name":"y"}'
            git commit -q -am pre
            & $start | Out-Null
            "$(Invoke-SessionEndHook)".Trim() | Should -BeNullOrEmpty
        }

        It 'no nudge without a Stack heading, and a CRLF heading still counts (#4)' {
            Set-Content '_working-memory/projectOverview.md' "# Project Overview`n`n## Tech`n"
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content package.json '{"name":"y"}'
            "$(Invoke-SessionEndHook)".Trim() | Should -BeNullOrEmpty
            [IO.File]::WriteAllText((Join-Path (Get-Location) '_working-memory/projectOverview.md'), "# Project Overview`r`n`r`n## Stack`r`n")
            git commit -q -am crlf
            & $start | Out-Null
            Set-Content package.json '{"name":"z"}'
            (Invoke-SessionEndHook | ConvertFrom-Json).systemMessage | Should -BeExactly (Get-StackLine 'package.json')
        }

        It 'the stack line sits between the size nudge and a promote line (#4)' {
            Set-Content .working-memoryrc "NUDGE_FILE_THRESHOLD=1`nNUDGE_LINE_THRESHOLD=1"
            Set-Content .ltm.yaml 'bank: x'
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content package.json "{`n`"name`":`"y`",`n`"version`":`"1`"`n}"
            Set-Content '_working-memory/decisionLog.md' "## 2026-11-01: Cap retries at three per request`n"
            $lines = @((Invoke-SessionEndHook | ConvertFrom-Json).systemMessage -split "`n")
            $lines.Count | Should -Be 3
            $lines[0] | Should -BeLike 'You changed *'
            $lines[1] | Should -BeExactly (Get-StackLine 'package.json')
            $lines[2] | Should -BeExactly (Get-PromoteLine 'Cap retries at three per request')
        }

        It 'no stack nudge during an in-progress merge (#4)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content package.json '{"name":"y"}'
            New-Item -ItemType File -Path (Join-Path (git rev-parse --absolute-git-dir) 'MERGE_HEAD') | Out-Null
            "$(Invoke-SessionEndHook)".Trim() | Should -BeNullOrEmpty
        }

        It 'no nudge when projectOverview.md is missing (#4)' {
            Remove-Item '_working-memory/projectOverview.md'
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content package.json '{"name":"y"}'
            "$(Invoke-SessionEndHook)".Trim() | Should -BeNullOrEmpty
        }

        It 'a manifest changed with a lockfile fires and lists both (#4)' {
            git add -A; git commit -q -m base
            & $start | Out-Null
            Set-Content package.json '{"name":"y"}'
            Set-Content pnpm-lock.yaml 'lock2'
            (Invoke-SessionEndHook | ConvertFrom-Json).systemMessage | Should -BeExactly (Get-StackLine 'package.json, pnpm-lock.yaml')
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

Describe 'update-working-memory script' {
    It 'does not throw outside a git repo' {
        $plain = Join-Path ([System.IO.Path]::GetTempPath()) ('wmk-ng-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path "$plain/_working-memory" -Force | Out-Null
        Set-Location $plain; [Environment]::CurrentDirectory = $plain
        try {
            { & (Join-Path $KitRoot 'template/scripts/update-working-memory.ps1') 6>$null | Out-Null } | Should -Not -Throw
        } finally { Remove-TestRepo $plain }
    }
}
