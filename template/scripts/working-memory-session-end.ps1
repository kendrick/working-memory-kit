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

# --shortstat covers both signals in one git call.
$diffStats = git -C $repoRoot diff --shortstat HEAD 2>$null
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

if ($reason) {
    Write-Output "{`"systemMessage`":`"You changed $reason this session. Consider running /update-working-memory or @working-memory-synchronizer to keep the working memory current.`"}"
}
