# Ensures activeContext.md exists at session start.
# If missing, copies from the example template.

$ErrorActionPreference = 'Stop'

$repoRoot = (git rev-parse --show-toplevel 2>$null)
if (-not $repoRoot) { $repoRoot = (Get-Location).Path }

$wmDir = Join-Path $repoRoot '_working-memory'

# Hooks fire on every session in every project, not just working-memory
# consumers. Bail quietly so unrelated repos don't see noise.
if (-not (Test-Path $wmDir)) { exit 0 }

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

$maxLines = if ($env:WORKING_MEMORY_MAX_LINES) { [int]$env:WORKING_MEMORY_MAX_LINES } else { [int](Get-Cfg 'MAX_ACTIVE_CONTEXT_LINES' 20) }

$activeContext = Join-Path $wmDir 'activeContext.md'
$exampleFile = Join-Path $wmDir 'activeContext.example.md'

# {"systemMessage":"..."} on stdout is the hook protocol — the host surfaces
# it to the user. Plain Write-Host calls get ignored.
if (-not (Test-Path $activeContext)) {
    if (Test-Path $exampleFile) {
        Copy-Item $exampleFile $activeContext
        Write-Output '{"systemMessage":"Created _working-memory/activeContext.md from template. Update it with your current focus."}'
    } else {
        Write-Output '{"systemMessage":"No activeContext.example.md found. Working memory may not be initialized."}'
    }
} else {
    # The default limit (20) comes from activeContext.example.md. Past that,
    # the file has stopped being a queue and started being an archive.
    $lineCount = (Get-Content $activeContext | Where-Object { $_.Trim() -ne '' }).Count
    if ($lineCount -gt $maxLines) {
        Write-Output "{`"systemMessage`":`"Warning: activeContext.md has $lineCount non-empty lines (limit is $maxLines). Run /update-working-memory to prune it.`"}"
    }
}
