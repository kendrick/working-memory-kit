# working-memory-kit installer (Windows / PowerShell)
# Scaffolds a two-tier working memory into the current project, with config
# for both Claude Code and GitHub Copilot.

$ErrorActionPreference = 'Stop'

# Replace $RepoDefault before publishing the kit. Forks and private mirrors
# override at install time via the env vars below.
$RepoDefault = 'kendrick/working-memory-kit'
$Repo   = if ($env:WORKING_MEMORY_KIT_REPO)   { $env:WORKING_MEMORY_KIT_REPO }   else { $RepoDefault }
$Branch = if ($env:WORKING_MEMORY_KIT_BRANCH) { $env:WORKING_MEMORY_KIT_BRANCH } else { 'main' }

# ---------- helpers ----------

function Write-Info ($msg) { Write-Host "[info] $msg" -ForegroundColor Blue }
function Write-Ok   ($msg) { Write-Host "[ok] $msg"   -ForegroundColor Green }
function Write-Warn ($msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }
function Write-Fail ($msg) { Write-Host "[error] $msg" -ForegroundColor Red }

function Confirm-Prompt ($prompt, $defaultYes = $true) {
    $hint = if ($defaultYes) { '[Y/n]' } else { '[y/N]' }
    $reply = Read-Host "$prompt $hint"
    if ([string]::IsNullOrWhiteSpace($reply)) { return $defaultYes }
    return $reply -match '^(y|yes)$'
}

# Always prompts before overwriting. Re-running the installer to pick up
# kit upgrades is expected, and a silent overwrite would clobber local edits.
function Copy-IfAbsent ($src, $dst) {
    if (Test-Path $dst) {
        if (Confirm-Prompt "  $dst already exists. Overwrite?" $false) {
            Copy-Item $src $dst -Force
            Write-Ok "overwrote $dst"
        } else {
            Write-Info "kept existing $dst"
        }
    } else {
        $parent = Split-Path $dst -Parent
        if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item $src $dst
        Write-Ok "created $dst"
    }
}

# Idempotency relies on the marker line. If a user renames the heading the
# detection misses and a duplicate section gets appended on re-run, which is
# easier to spot than a silent skip. That's the trade we want.
function Append-SectionIfMissing ($srcContent, $dst, $marker) {
    if (-not (Test-Path $dst)) {
        $parent = Split-Path $dst -Parent
        if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Set-Content -Path $dst -Value $srcContent
        Write-Ok "created $dst"
        return
    }
    $current = Get-Content $dst -Raw
    if ($current -like "*$marker*") {
        Write-Info "$dst already contains working-memory section, leaving alone"
        return
    }
    Add-Content -Path $dst -Value "`n$srcContent"
    Write-Ok "appended working-memory section to $dst"
}

# ---------- locate template ----------

# Two install paths: a cloned kit (template/ next to this script) or curl-pipe
# (script alone, fetches the tarball). Local wins so kit devs can iterate
# without round-tripping GitHub.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TargetDir = (Get-Location).Path
$Template  = $null

if (Test-Path (Join-Path $ScriptDir 'template')) {
    $Template = Join-Path $ScriptDir 'template'
    Write-Info "using local template at $Template"
} else {
    Write-Info "downloading template from $Repo@$Branch"
    $tmp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "wmk-$([guid]::NewGuid().Guid)")
    $tarUrl = "https://codeload.github.com/$Repo/tar.gz/refs/heads/$Branch"
    $tarPath = Join-Path $tmp.FullName 'kit.tar.gz'
    try {
        Invoke-WebRequest -Uri $tarUrl -OutFile $tarPath -UseBasicParsing
        tar -xzf $tarPath -C $tmp.FullName
    } catch {
        Write-Fail "could not download template from $Repo@$Branch"
        Write-Fail "set WORKING_MEMORY_KIT_REPO and WORKING_MEMORY_KIT_BRANCH if you forked"
        exit 1
    }
    $Template = (Get-ChildItem -Path $tmp.FullName -Recurse -Directory -Filter 'template' | Select-Object -First 1).FullName
    if (-not $Template) {
        Write-Fail "downloaded archive did not contain a template/ directory"
        exit 1
    }
}

# ---------- intro ----------

Write-Host ""
Write-Host "working-memory-kit installer" -ForegroundColor Blue
Write-Host "Target: $TargetDir"
Write-Host ""

if ($TargetDir -eq $ScriptDir) {
    Write-Warn "you're running this from the kit's own repo."
    Write-Warn "this would scaffold the kit into itself (dogfood). Continue only if that's intentional."
    if (-not (Confirm-Prompt "Proceed?" $false)) { Write-Host "aborted."; exit 0 }
}

# ---------- detect stack ----------

function Get-Stack {
    $lang = ''
    $framework = ''
    if (Test-Path 'package.json') {
        $lang = 'JavaScript/TypeScript'
        $pj = Get-Content 'package.json' -Raw
        if     ($pj -match '"next"')   { $framework = 'Next.js' }
        elseif ($pj -match '"react"')  { $framework = 'React' }
        elseif ($pj -match '"vue"')    { $framework = 'Vue' }
        elseif ($pj -match '"svelte"') { $framework = 'Svelte' }
    } elseif (Test-Path 'pyproject.toml') {
        $lang = 'Python'
        $py = Get-Content 'pyproject.toml' -Raw
        if     ($py -match 'django')  { $framework = 'Django' }
        elseif ($py -match 'fastapi') { $framework = 'FastAPI' }
        elseif ($py -match 'flask')   { $framework = 'Flask' }
    } elseif (Test-Path 'Cargo.toml') {
        $lang = 'Rust'
    } elseif (Test-Path 'go.mod') {
        $lang = 'Go'
    } elseif (Test-Path 'Gemfile') {
        $lang = 'Ruby'
        if ((Get-Content 'Gemfile' -Raw) -match 'rails') { $framework = 'Rails' }
    }
    return @{ Language = $lang; Framework = $framework }
}

$Stack = Get-Stack
if ($Stack.Language) {
    $msg = $Stack.Language
    if ($Stack.Framework) { $msg += " ($($Stack.Framework))" }
    Write-Info "detected: $msg"
} else {
    Write-Info "no recognized stack detected"
}

# ---------- working-memory directory choice ----------

# Default is _working-memory (underscore prefix keeps it grouped near
# similarly-prefixed tooling directories at the top of file listings).
# Consumer can override at install time; on override, the installer
# substitutes the literal token in copied template files.
$WmDirDefault = '_working-memory'
$WmDir = $WmDirDefault
$reply = Read-Host "Install working memory at $WmDirDefault/? [Y/n, or specify alternate path]"
if ($reply -match '^(n|no)$') {
    $custom = Read-Host 'Enter alternate path (relative to repo root)'
    if ($custom) { $WmDir = $custom.TrimEnd('/').TrimEnd('\') }
} elseif ($reply -and $reply -notmatch '^(y|yes)$') {
    $WmDir = $reply.TrimEnd('/').TrimEnd('\')
}
Write-Info "working memory will be installed at $WmDir/"

# ---------- check existing structure ----------

$Existing = @()
if (Test-Path $WmDir) { $Existing += "$WmDir/" }
if (Test-Path '.claude')     { $Existing += '.claude/' }
if (Test-Path '.github')     { $Existing += '.github/' }
if (Test-Path 'AGENTS.md')   { $Existing += 'AGENTS.md' }
if (Test-Path 'CLAUDE.md')   { $Existing += 'CLAUDE.md' }

if ($Existing.Count -gt 0) {
    Write-Warn "found existing config: $($Existing -join ', ')"
    Write-Warn "files will be merged where possible. You'll be prompted before overwrites."
    if (-not (Confirm-Prompt 'Continue?' $true)) { Write-Host 'aborted.'; exit 0 }
}

Write-Host ''
Write-Info 'scaffolding...'

# ---------- working-memory ----------

if (-not (Test-Path $WmDir)) { New-Item -ItemType Directory -Path $WmDir | Out-Null }
$wmFiles = @('activeContext.example.md','projectOverview.md','decisionLog.md','dataContracts.md','conventions.md','openQuestions.md')
foreach ($f in $wmFiles) {
    Copy-IfAbsent (Join-Path $Template "_working-memory\$f") (Join-Path $TargetDir "$WmDir\$f")
}

if (-not (Test-Path "$WmDir\activeContext.md")) {
    Copy-Item "$WmDir\activeContext.example.md" "$WmDir\activeContext.md"
    Write-Ok "created your local $WmDir/activeContext.md from the template"
}

# Skip pre-population if the placeholder marker is gone: the team has filled
# in their overview by hand and we shouldn't clobber it on re-run.
if ($Stack.Language -and (Get-Content "$WmDir\projectOverview.md" -Raw) -match '^_To be filled\._') {
    $repoName = Split-Path $TargetDir -Leaf
    $dirs = (Get-ChildItem -Directory | Select-Object -First 20 | ForEach-Object { "- $($_.Name)" }) -join "`n"
    $fwLine = if ($Stack.Framework) { $Stack.Framework } else { '_(none detected)_' }
    $overview = @"
# Project Overview

## What This Is
<!-- One sentence. What does this project do? -->
$repoName — _add a one-sentence description here._

## Stack
- Language: $($Stack.Language)
- Framework: $fwLine
- Styling:
- Data layer:
- Deployment:

## Repository Structure
<!-- Top-level directory map. Update as the layout changes. -->
``````
$dirs
``````

## Key Constraints
<!-- Non-obvious things an agent must know: monorepo rules, legacy code -->
<!-- boundaries, API version requirements, browser support, etc. -->
"@
    Set-Content -Path "$WmDir\projectOverview.md" -Value $overview
    Write-Ok "pre-populated $WmDir/projectOverview.md with detected stack"
}

# ---------- .working-memoryrc.example ----------

# We ship the example, not the rc itself. Defaults are baked into the hook
# scripts; the rc is opt-in for teams that want to override line limits or
# nudge thresholds.
Copy-IfAbsent (Join-Path $Template '.working-memoryrc.example') `
              (Join-Path $TargetDir '.working-memoryrc.example')

# ---------- AGENTS.md ----------

$agentsTemplate = Get-Content (Join-Path $Template 'AGENTS.md') -Raw
Append-SectionIfMissing $agentsTemplate (Join-Path $TargetDir 'AGENTS.md') '## Working Memory'

# ---------- Claude Code config ----------

foreach ($d in @('.claude\agents','.claude\skills\update-working-memory')) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
Copy-IfAbsent `
    (Join-Path $Template '.claude\agents\working-memory-synchronizer.md') `
    (Join-Path $TargetDir '.claude\agents\working-memory-synchronizer.md')
Copy-IfAbsent `
    (Join-Path $Template '.claude\skills\update-working-memory\SKILL.md') `
    (Join-Path $TargetDir '.claude\skills\update-working-memory\SKILL.md')

$claudeSection = @'

## Working Memory

On session start, always read `_working-memory/activeContext.md`.
Read other working memory files as directed by the table in `AGENTS.md`.
After significant work, run the working-memory-synchronizer agent or manually update active context.
'@
Append-SectionIfMissing $claudeSection (Join-Path $TargetDir 'CLAUDE.md') '## Working Memory'

# ---------- Copilot config ----------

foreach ($d in @('.github\hooks','.github\instructions')) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

Copy-IfAbsent (Join-Path $Template '.github\hooks\working-memory-hooks.json') `
              (Join-Path $TargetDir '.github\hooks\working-memory-hooks.json')
Copy-IfAbsent (Join-Path $Template '.github\instructions\data-layer.instructions.md') `
              (Join-Path $TargetDir '.github\instructions\data-layer.instructions.md')

$copilotTemplate = Get-Content (Join-Path $Template '.github\copilot-instructions.md') -Raw
Append-SectionIfMissing $copilotTemplate (Join-Path $TargetDir '.github\copilot-instructions.md') '## Working Memory'

# ---------- scripts ----------

if (-not (Test-Path 'scripts')) { New-Item -ItemType Directory -Path 'scripts' | Out-Null }
$scriptFiles = @(
    'working-memory-session-start.sh','working-memory-session-start.ps1',
    'working-memory-session-end.sh','working-memory-session-end.ps1',
    'update-working-memory.sh','update-working-memory.ps1'
)
foreach ($f in $scriptFiles) {
    Copy-IfAbsent (Join-Path $Template "scripts\$f") (Join-Path $TargetDir "scripts\$f")
}
Write-Info 'shell scripts: PowerShell does not need chmod. On Unix systems, run: chmod +x scripts/*.sh'

# ---------- gitignore ----------

$gitignore = '.gitignore'
$line = "$WmDir/activeContext.md"
if (Test-Path $gitignore) {
    $content = Get-Content $gitignore
    if ($content -contains $line) {
        Write-Info '.gitignore already excludes activeContext.md'
    } else {
        Add-Content $gitignore "`n# Local-only active context (working-memory-kit)`n$line"
        Write-Ok 'added activeContext.md to .gitignore'
    }
} else {
    Set-Content $gitignore "# Local-only active context (working-memory-kit)`n$line"
    Write-Ok 'created .gitignore with activeContext.md entry'
}

# ---------- substitute WmDir token in copied files if user overrode default ----------

if ($WmDir -ne $WmDirDefault) {
    Write-Info "substituting _working-memory -> $WmDir in copied template files"
    $filesToSub = @(
        'AGENTS.md',
        'CLAUDE.md',
        '.claude\agents\working-memory-synchronizer.md',
        '.claude\skills\update-working-memory\SKILL.md',
        '.github\copilot-instructions.md',
        '.github\instructions\data-layer.instructions.md',
        'scripts\working-memory-session-start.sh',
        'scripts\working-memory-session-end.sh',
        'scripts\update-working-memory.sh',
        'scripts\working-memory-session-start.ps1',
        'scripts\working-memory-session-end.ps1',
        'scripts\update-working-memory.ps1'
    )
    foreach ($f in $filesToSub) {
        $full = Join-Path $TargetDir $f
        if (Test-Path $full) {
            $content = Get-Content $full -Raw
            # Single broad pattern catches every form: trailing slash, backslash,
            # closing quote in scripts, end of line. The token "_working-memory"
            # only ever appears as the install path; script filenames, env vars,
            # and .working-memoryrc do not collide.
            $content = $content -replace '_working-memory', $WmDir
            Set-Content -Path $full -Value $content -NoNewline
        }
    }
}

# ---------- parity check ----------

Write-Host ''
Write-Info 'verifying canonical artifacts...'
$canonical = @(
    '.claude\agents\working-memory-synchronizer.md',
    '.claude\skills\update-working-memory\SKILL.md'
)
$canonicalOk = $true
foreach ($f in $canonical) {
    if (Test-Path $f) {
        Write-Ok "present: $f"
    } else {
        Write-Warn "missing: $f"
        $canonicalOk = $false
    }
}

# ---------- done ----------

Write-Host ''
Write-Host 'done.' -ForegroundColor Green
Write-Host ''
Write-Host 'next steps:'
Write-Host "  1. Open $WmDir\projectOverview.md and fill in `"What This Is`"."
Write-Host "  2. Edit $WmDir\activeContext.md to reflect what you're working on."
Write-Host '  3. Teammates: after cloning, run:'
Write-Host "       Copy-Item $WmDir\activeContext.example.md $WmDir\activeContext.md"
Write-Host '  4. To sync working memory: invoke the working-memory-synchronizer agent, or'
Write-Host '     run: .\scripts\update-working-memory.ps1'
Write-Host '  5. To tune line limits or nudge thresholds:'
Write-Host '       Copy-Item .working-memoryrc.example .working-memoryrc   # then edit'

if (-not $canonicalOk) {
    Write-Host ''
    Write-Warn 'some canonical artifacts are missing. Review the messages above.'
}
