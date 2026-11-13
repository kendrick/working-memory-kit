# Parity twin of test/installer.bats: the installer invariants on PowerShell.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Common.ps1')

    # Asserts the event stays a JSON array: a PS round trip can collapse one group to an object.
    function Get-HookCount ($eventName, $fragment) {
        $s = Get-Content .claude/settings.json -Raw | ConvertFrom-Json
        $groups = $s.hooks.$eventName
        $groups -is [array] | Should -BeTrue
        return @($groups | ForEach-Object { $_.hooks } | Where-Object { "$($_.command)".Contains($fragment) }).Count
    }
}

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

    It 'fresh install exposes Codex skills, hydrator, and lifecycle hooks' {
        Invoke-Installer | Out-Null
        @(
            '.agents/skills/update-working-memory/SKILL.md',
            '.agents/skills/hydrate-discover/SKILL.md',
            '.agents/skills/hydrate-extract/SKILL.md',
            '.agents/skills/hydrate-draft/SKILL.md',
            '.agents/skills/hydrate-reconcile/SKILL.md',
            '.agents/skills/hydrate-propose/SKILL.md',
            '.codex/agents/hydrator.toml',
            '.codex/hooks.json'
        ) | Should -Exist

        $skillSources = @{
            'update-working-memory' = Join-Path $KitRoot 'template/.claude/skills/update-working-memory/SKILL.md'
            'hydrate-discover'      = Join-Path $KitRoot '.claude/skills/hydrate-discover/SKILL.md'
            'hydrate-extract'       = Join-Path $KitRoot '.claude/skills/hydrate-extract/SKILL.md'
            'hydrate-draft'         = Join-Path $KitRoot '.claude/skills/hydrate-draft/SKILL.md'
            'hydrate-reconcile'     = Join-Path $KitRoot '.claude/skills/hydrate-reconcile/SKILL.md'
            'hydrate-propose'       = Join-Path $KitRoot '.claude/skills/hydrate-propose/SKILL.md'
        }
        foreach ($skill in $skillSources.GetEnumerator()) {
            (Get-FileHash (Join-Path '.agents/skills' "$($skill.Key)/SKILL.md")).Hash | Should -Be (Get-FileHash $skill.Value).Hash
        }

        $hooks = Get-Content .codex/hooks.json -Raw | ConvertFrom-Json
        $hooks.hooks.SessionStart[0].hooks[0].command | Should -Not -BeNullOrEmpty
        $hooks.hooks.SessionStart[0].hooks[0].commandWindows | Should -Not -BeNullOrEmpty
        $hooks.hooks.SessionEnd[0].hooks[0].command | Should -Not -BeNullOrEmpty
        $hooks.hooks.SessionEnd[0].hooks[0].commandWindows | Should -Not -BeNullOrEmpty
        $hooks.hooks.SessionStart[0].hooks[0].command | Should -Match 'working-memory-session-start\.sh'
        $hooks.hooks.SessionStart[0].hooks[0].commandWindows | Should -Match 'working-memory-session-start\.ps1'
        $hooks.hooks.SessionEnd[0].hooks[0].command | Should -Match 'working-memory-session-end\.sh'
        $hooks.hooks.SessionEnd[0].hooks[0].commandWindows | Should -Match 'working-memory-session-end\.ps1'
        $hooks.hooks.SessionEnd[0].hooks[0].timeout | Should -Be 3
    }

    It 'Codex hook machinery writes a sidecar instead of replacing an edit' {
        Invoke-Installer | Out-Null
        Add-Content .codex/hooks.json ''
        Invoke-Installer | Out-Null
        '.codex/hooks.json.kitnew' | Should -Exist
        (Get-Content .codex/hooks.json -Raw).Length | Should -BeGreaterThan (Get-Content .codex/hooks.json.kitnew -Raw).Length
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

    # ---- a custom working-memory dir persists in .working-memoryrc (#43). The
    # prompts are unreachable headless, so these seed the rc to drive the read path. ----

    It 'a seeded WORKING_MEMORY_DIR drives a headless install and re-run (#43)' {
        Set-Content .working-memoryrc 'WORKING_MEMORY_DIR="mem"'
        Invoke-Installer | Out-Null
        'mem/decisionLog.md' | Should -Exist
        '_working-memory' | Should -Not -Exist
        git add -A; git commit -q -m base
        Invoke-Installer | Out-Null
        '_working-memory' | Should -Not -Exist
        Get-ChildItem -Recurse -Force -Filter '*.kitnew' | Should -BeNullOrEmpty
        git status --porcelain | Should -BeNullOrEmpty
    }

    # ---- Set-RcKey must not glue a new key onto an rc whose last line lacks a newline (#50).
    # A headless run can't answer the dir prompt, so --no-coexist drives the append branch. ----

    It 'an appended key lands on its own line in an rc with no trailing newline (#50)' {
        [IO.File]::WriteAllText((Join-Path (Get-Location) '.working-memoryrc'), 'WORKING_MEMORY_DIR="mem"')
        Invoke-Installer --no-coexist | Out-Null
        $rc = Get-Content .working-memoryrc
        $rc | Should -Contain 'WORKING_MEMORY_DIR="mem"'
        $rc | Should -Contain 'external_spec_tooling=false'
        Invoke-Installer | Out-Null
        '_working-memory' | Should -Not -Exist
    }

    It 'an rc that ends in a newline gets no blank line (#50)' {
        [IO.File]::WriteAllText((Join-Path (Get-Location) '.working-memoryrc'), "WORKING_MEMORY_DIR=`"mem`"`n")
        Invoke-Installer --no-coexist | Out-Null
        $rc = Get-Content .working-memoryrc
        $rc | Should -Contain 'external_spec_tooling=false'
        $rc | Should -Not -Contain ''
    }

    It 'an empty rc gets the key with no blank line (#50)' {
        [IO.File]::WriteAllText((Join-Path (Get-Location) '.working-memoryrc'), '')
        Invoke-Installer --no-coexist | Out-Null
        @(Get-Content .working-memoryrc)[0] | Should -Be 'external_spec_tooling=false'
    }

    It 'deleting WORKING_MEMORY_DIR sends a headless re-run to _working-memory (#43)' {
        Set-Content .working-memoryrc 'WORKING_MEMORY_DIR="mem"'
        Invoke-Installer | Out-Null
        'mem/decisionLog.md' | Should -Exist
        Set-Content .working-memoryrc ''
        Invoke-Installer | Out-Null
        '_working-memory' | Should -Exist
    }

    It 'an unrelated rc key change leaves the custom dir alone (#43)' {
        Set-Content .working-memoryrc 'WORKING_MEMORY_DIR="mem"'
        Invoke-Installer | Out-Null
        Add-Content .working-memoryrc 'NUDGE_FILE_THRESHOLD=9'
        Invoke-Installer | Out-Null
        '_working-memory' | Should -Not -Exist
        Get-Content .working-memoryrc | Should -Contain 'WORKING_MEMORY_DIR="mem"'
    }

    It 'a default install writes no .working-memoryrc; an escaping rc dir is refused (#43)' {
        Invoke-Installer | Out-Null
        '.working-memoryrc' | Should -Not -Exist
        Set-Content .working-memoryrc 'WORKING_MEMORY_DIR="../outside"'
        Invoke-Installer | Should -Match 'WORKING_MEMORY_DIR'
        '../outside' | Should -Not -Exist
    }

    It 'a rooted rc dir (leading backslash) is refused and the default is used (#43)' {
        # pwsh resolves a backslash-rooted path from the filesystem root, so point at a
        # writable sibling of the repo, which the installer would create if the refusal failed.
        # Windows repos are drive-qualified, so strip the drive to keep the seed leading with a backslash.
        $outside = "$repo-evil"
        $rooted = ($outside -replace '/', '\') -replace '^[A-Za-z]:', ''
        Set-Content .working-memoryrc ('WORKING_MEMORY_DIR="' + $rooted + '"')
        Invoke-Installer | Should -Match 'ignoring WORKING_MEMORY_DIR='
        '_working-memory/decisionLog.md' | Should -Exist
        $outside | Should -Not -Exist
    }

    It 'a drive-letter rc dir is refused and the default is used (#43)' {
        # Where $repo has a drive, seed a unique sibling so a stray dir on the runner can't fail the
        # no-write assert. Without a drive, C:\evil can't exist, so the assert only bites on Windows.
        $outside = 'C:\evil'
        if ($repo -match '^[A-Za-z]:') { $outside = "$repo-evil2" -replace '/', '\' }
        Set-Content .working-memoryrc ('WORKING_MEMORY_DIR="' + $outside + '"')
        Invoke-Installer | Should -Match 'ignoring WORKING_MEMORY_DIR='
        '_working-memory/decisionLog.md' | Should -Exist
        $outside | Should -Not -Exist
    }

    It 'an rc dir outside the allow-list is refused before it reaches a hook (#49)' {
        foreach ($dir in 'wm$&x', "x'+(New-Item PWNED)+'") {
            Set-Content .working-memoryrc ('WORKING_MEMORY_DIR="' + $dir + '"')
            Invoke-Installer | Should -Match 'using only letters, digits'
            '_working-memory/decisionLog.md' | Should -Exist
            Get-ChildItem -Recurse -Force -Filter PWNED | Should -BeNullOrEmpty
            (Get-Content -Raw scripts/working-memory-session-start.ps1).Contains($dir) | Should -BeFalse
        }
    }

    It 'fresh install writes Claude Code session hooks (#36)' {
        Invoke-Installer | Out-Null
        Get-HookCount 'SessionStart' 'working-memory-session-start.sh' | Should -Be 1
        Get-HookCount 'SessionEnd' 'working-memory-session-end.sh' | Should -Be 1
    }

    It 're-install keeps one copy of each Claude hook and a pre-existing hook (#36)' {
        New-Item -ItemType Directory .claude -Force | Out-Null
        Set-Content .claude/settings.json '{"permissions":{"allow":["Bash(ls)"]},"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"echo mine"}]}]}}'
        Invoke-Installer | Out-Null
        git add -A; git commit -q -m base
        Invoke-Installer | Out-Null
        Get-HookCount 'SessionStart' 'echo mine' | Should -Be 1
        Get-HookCount 'SessionStart' 'working-memory-session-start.sh' | Should -Be 1
        Get-HookCount 'SessionEnd' 'working-memory-session-end.sh' | Should -Be 1
        (Get-Content .claude/settings.json -Raw | ConvertFrom-Json).permissions.allow[0] | Should -Be 'Bash(ls)'
        git status --porcelain | Should -BeNullOrEmpty
    }

    It 'an invalid .claude/settings.json is left alone with a warning (#36)' {
        New-Item -ItemType Directory .claude -Force | Out-Null
        Set-Content .claude/settings.json '{ "hooks": ,'
        $before = (Get-FileHash .claude/settings.json).Hash
        Invoke-Installer | Should -Match ([regex]::Escape(' is not valid JSON (or not the settings shape Claude Code reads); left it as-is. Fix it and re-run to get the working-memory hooks.'))
        (Get-FileHash .claude/settings.json).Hash | Should -Be $before
    }

    It 're-install swaps an old kit entry for the current one and drops its duplicate (#36)' {
        New-Item -ItemType Directory .claude -Force | Out-Null
        Set-Content .claude/settings.json '{"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"echo mine"},{"type":"command","command":"bash scripts/working-memory-session-start.sh","timeout":5}]},{"hooks":[{"type":"command","command":"bash scripts/working-memory-session-start.sh"}]}]}}'
        Invoke-Installer | Out-Null
        Get-HookCount 'SessionStart' 'echo mine' | Should -Be 1
        Get-HookCount 'SessionStart' 'working-memory-session-start.sh' | Should -Be 1
        $groups = @((Get-Content .claude/settings.json -Raw | ConvertFrom-Json).hooks.SessionStart)
        $kit = (Get-Content (Join-Path $KitRoot 'template/.claude/settings.json') -Raw | ConvertFrom-Json).hooks.SessionStart[0].hooks[0]
        $groups.Count | Should -Be 1
        $groups[0].matcher | Should -Be 'startup'
        $groups[0].hooks[1].command | Should -Be $kit.command
        $groups[0].hooks[1].timeout | Should -Be $kit.timeout
    }

    It 're-install keeps a user hook whose script name only ends in the kit''s (#36)' {
        New-Item -ItemType Directory .claude -Force | Out-Null
        Set-Content .claude/settings.json '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash scripts/my-working-memory-session-start.sh"}]}]}}'
        Invoke-Installer | Out-Null
        Get-HookCount 'SessionStart' 'my-working-memory-session-start.sh' | Should -Be 1
        Get-HookCount 'SessionStart' 'CLAUDE_PROJECT_DIR/scripts/working-memory-session-start.sh' | Should -Be 1
    }

    It 'fresh install: no template example reads as a dated log entry (#37)' {
        Invoke-Installer | Out-Null
        Select-String -Path '_working-memory/*.md' -Pattern '^## \d{4}-' | Should -BeNullOrEmpty
        $logs = '_working-memory/decisionLog.md', '_working-memory/antipatterns.md'
        foreach ($log in $logs) {
            Select-String -Path $log -Pattern '^<!-- ## YYYY-MM-DD: ' | Should -Not -BeNullOrEmpty
        }
        # 5.1 reads BOM-less UTF-8 as ANSI, where an em dash isn't [char]0x2014 and this would pass vacuously.
        Get-Content _working-memory/antipatterns.md -Raw -Encoding UTF8 | Should -Not -Match ([char]0x2014)
    }

    It 'fresh install: both log templates show a status line directly under the example heading (#39)' {
        Invoke-Installer | Out-Null
        foreach ($log in '_working-memory/decisionLog.md', '_working-memory/antipatterns.md') {
            $lines = Get-Content $log
            $i = 0..($lines.Count - 1) | Where-Object { $lines[$_] -match '^<!-- ## YYYY-MM-DD: ' } | Select-Object -First 1
            $lines[$i + 1] | Should -Be '<!-- status: accepted -->'
            $lines[$i + 2] | Should -Match '^<!-- *-->$'
            Get-Content $log -Raw | Should -Match 'superseded_by'
        }
        Get-Content AGENTS.md -Raw | Should -Match 'status: superseded'
    }
}

# Windows PowerShell 5.1 reads a BOM-less script as ANSI, so a non-ASCII literal can
# decode to a curly quote that ends a string. Parsing as Windows-1252 catches that on
# any engine, including update-working-memory.ps1, which no other test runs.
Describe 'shipped scripts under 5.1' {
    It '<_> parses when read as Windows-1252' -ForEach @('init.ps1', 'template/scripts/update-working-memory.ps1',
        'template/scripts/working-memory-session-start.ps1', 'template/scripts/working-memory-session-end.ps1') {
        $text = [Text.Encoding]::GetEncoding(1252).GetString([IO.File]::ReadAllBytes((Join-Path $KitRoot $_)))
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }
}
