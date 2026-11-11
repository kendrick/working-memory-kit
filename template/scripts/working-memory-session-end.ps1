# Reminds the developer to update the working memory if significant work was done.

$ErrorActionPreference = 'Stop'

$repoRoot = (git rev-parse --show-toplevel 2>$null)
if (-not $repoRoot) { $repoRoot = (Get-Location).Path }

# Hooks fire on every session in every project. Skip silently outside
# working-memory consumers.
if (-not (Test-Path (Join-Path $repoRoot '_working-memory'))) { exit 0 }

# Reads a key from .working-memoryrc with a default. Parses key=value instead
# of dot-sourcing, so a malicious rc can't execute arbitrary code.
function Get-Cfg ($key, $default) {
    $file = Join-Path $repoRoot '.working-memoryrc'
    if (-not (Test-Path $file)) { return $default }
    $line = Get-Content $file | Where-Object { $_ -match "^$key=" } | Select-Object -First 1
    if (-not $line) { return $default }
    $val = ($line -split '=', 2)[1].Trim().Trim('"').Trim("'")
    if ($val) { return $val } else { return $default }
}

$fileThreshold = if ($env:WORKING_MEMORY_FILE_THRESHOLD) { [int]$env:WORKING_MEMORY_FILE_THRESHOLD } else { [int](Get-Cfg 'NUDGE_FILE_THRESHOLD' 5) }
$lineThreshold = if ($env:WORKING_MEMORY_LINE_THRESHOLD) { [int]$env:WORKING_MEMORY_LINE_THRESHOLD } else { [int](Get-Cfg 'NUDGE_LINE_THRESHOLD' 200) }

# A merge/rebase in progress (typically a conflicted `git pull`) leaves the
# incoming side staged in the index, so `diff HEAD` counts commits the
# developer never wrote: a one-line edit can read as "7 files changed." Skip
# until it resolves; the next session-end measures cleanly. (Swapping to
# `git diff` with no ref isn't the fix: it silently misses fully staged work.)
$gitDir = git -C $repoRoot rev-parse --absolute-git-dir 2>$null
if ($gitDir -and (
    (Test-Path (Join-Path $gitDir 'MERGE_HEAD')) -or
    (Test-Path (Join-Path $gitDir 'rebase-merge')) -or
    (Test-Path (Join-Path $gitDir 'rebase-apply')))) { exit 0 }

# --shortstat covers both signals in one git call. LC_ALL=C pins the output
# to English so the regexes below stay valid under non-default locales.
$prevLcAll = $env:LC_ALL
$env:LC_ALL = 'C'
try {
    # Diffing against HEAD would see a clean tree after commit-as-you-go (#35).
    # Trim: the bash start hook writes the base with a trailing newline. A
    # missing, empty, or gc'd base falls back to HEAD.
    $base = 'HEAD'
    if ($gitDir -and (Test-Path (Join-Path $gitDir 'working-memory-session-base'))) {
        # An unreadable base (ACL, mode bits) throws under 'Stop'; keep HEAD.
        $recorded = ''
        try { $recorded = ((Get-Content -Raw (Join-Path $gitDir 'working-memory-session-base')) + '').Trim() } catch {}
        if ($recorded) {
            # Windows PowerShell 5.1 turns native stderr into ErrorRecords, and
            # cat-file prints "fatal: Not a valid object name" for a gc'd base.
            # Under 'Stop' that throws, so relax it around this one call.
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                git -C $repoRoot cat-file -e "$recorded^{commit}" 2>$null
                if ($LASTEXITCODE -eq 0) { $base = $recorded }
            } finally { $ErrorActionPreference = $prevEap }
        }
    }
    $diffStats = git -C $repoRoot diff --shortstat $base 2>$null
} finally {
    if ($null -eq $prevLcAll) { Remove-Item Env:LC_ALL -ErrorAction SilentlyContinue }
    else { $env:LC_ALL = $prevLcAll }
}
$changedFiles = 0
$linesChanged = 0
if ($diffStats) {
    if ($diffStats -match '(\d+)\s+files?\s+changed') { $changedFiles = [int]$Matches[1] }
    $insertions = if ($diffStats -match '(\d+)\s+insertions?') { [int]$Matches[1] } else { 0 }
    $deletions  = if ($diffStats -match '(\d+)\s+deletions?')  { [int]$Matches[1] } else { 0 }
    $linesChanged = $insertions + $deletions
}

# Either signal trips the nudge. Surface which one fired so the dev knows
# whether the session was wide (many files) or deep (one big refactor).
$reason = $null
if ($changedFiles -gt $fileThreshold -and $linesChanged -gt $lineThreshold) {
    $reason = "$changedFiles files and $linesChanged lines"
} elseif ($changedFiles -gt $fileThreshold) {
    $reason = "$changedFiles files"
} elseif ($linesChanged -gt $lineThreshold) {
    $reason = "$linesChanged lines"
}

# Only check pointers when the diff threshold already trips the nudge.
# We don't want a separate firing condition for "your dataContracts pointers
# rotted" — that would be a new source of nag. But when the nudge is already
# firing, broken pointers piggyback as extra signal in the same message.
$extra = ''
if ($reason) {
    $dcFile = Join-Path $repoRoot '_working-memory/dataContracts.md'
    if (Test-Path $dcFile) {
        $broken = @()
        $links = Select-String -Path $dcFile -Pattern '\]\(([^)]+)\)' -AllMatches |
            ForEach-Object { $_.Matches } |
            ForEach-Object { $_.Groups[1].Value }
        foreach ($raw in $links) {
            $path = ($raw -split '#', 2)[0]
            if (-not $path) { continue }
            if ($path -match '^(https?://|mailto:)') { continue }
            $rootResolved = Join-Path $repoRoot $path
            $wmResolved   = Join-Path $repoRoot (Join-Path '_working-memory' $path)
            if ((Test-Path $rootResolved -ErrorAction SilentlyContinue) -or (Test-Path $wmResolved -ErrorAction SilentlyContinue)) { continue }
            $broken += $path
        }
        if ($broken.Count -gt 0) {
            $extra = " dataContracts.md has $($broken.Count) broken pointer(s): $($broken -join ', ')."
        }
    }
}

# #33: a Bank-connected repo (.ltm.yaml at the root) that gained a decisionLog
# heading since the session base gets the `ltm promote` command to run. The hook
# only prints it. "New" means the heading line is absent at $base, so an entry
# committed mid-session still counts and body edits never do.
$promote = @()
$logRel = '_working-memory/decisionLog.md'
$logFile = Join-Path $repoRoot $logRel
if ((Test-Path (Join-Path $repoRoot '.ltm.yaml')) -and (Test-Path $logFile)) {
    # Unreadable file (ACL, mode bits) throws under 'Stop'; treat as no entries.
    $now = ''
    try { $now = (Get-Content -Raw -Encoding UTF8 $logFile) + '' } catch {}
    # A base without the file makes git show fail; relax 'Stop' for 5.1's stderr ErrorRecords.
    $then = ''
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # 5.1 decodes native output with the console's OEM code page while $now is
    # UTF-8, so a non-ASCII heading would differ from itself and read as new
    # every session. The set can throw with no console; then keep the default.
    $prevEnc = $null
    try { $prevEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
    try { $then = (@(git -C $repoRoot show "${base}:$logRel" 2>$null) -join "`n") } finally {
        $ErrorActionPreference = $prevEap
        if ($prevEnc) { try { [Console]::OutputEncoding = $prevEnc } catch {} }
    }
    $heading = '^## '
    # Case-sensitive (-c*) to match the bash twin's grep -qxF; PowerShell's
    # default operators ignore case, so a recased heading would go unnoticed.
    $old = @(($then -split "`n") | ForEach-Object { $_ -replace "`r", '' } | Where-Object { $_ -cmatch $heading })
    foreach ($h in (($now -split "`n") | ForEach-Object { $_ -replace "`r", '' } | Where-Object { $_ -cmatch $heading })) {
        if ($old -ccontains $h) { continue }
        $title = if ($h -match '^## \d{4}-\d{2}-\d{2}: (.+)$') { $Matches[1] } else { $h.Substring(3) }
        $promote += "working-memory: new decisionLog entry `"$title`". If it applies beyond this repo: ltm promote $logRel --entry `"$title`""
    }
}

$msg = $null
if ($reason) {
    $msg = "You changed $reason this session.$extra Use the update-working-memory skill or the supplied update script to keep working memory current."
}
if ($promote.Count -gt 0) {
    $msg = (@($msg) + $promote | Where-Object { $_ }) -join "`n"
}
if ($msg) {
    # A quote or backslash in a pointer or title must reach the host escaped, or
    # the host drops the message silently.
    Write-Output ([pscustomobject]@{ systemMessage = $msg } | ConvertTo-Json -Compress)
}
