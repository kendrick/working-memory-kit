# Shared helpers for the PowerShell test suite (Pester 5). The parity twin of
# test/helpers.bash: each test gets a throwaway git repo, the installer runs
# headless into it, and output is captured so tests can assert on it.

$KitRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function New-TestRepo {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('wmk-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Location $dir
    # Set-Location moves PowerShell's provider location but not the process CWD,
    # and native children (the hook's `git rev-parse`) inherit the process CWD.
    # Sync both so cmdlets and git agree on where "the repo" is, the way they do
    # in production where the hook fires with CWD already at the repo root.
    [Environment]::CurrentDirectory = $dir
    git init -q 2>$null
    git config user.email test@example.com
    git config user.name test
    git config commit.gpgsign false
    # Pin line endings so idempotency assertions test the installer, not git's
    # CRLF conversion. On windows-latest autocrlf defaults to true, which would
    # rewrite endings under the test and make `git status` non-deterministic.
    git config core.autocrlf false
    return $dir
}

function Remove-TestRepo ($dir) {
    $tmp = [System.IO.Path]::GetTempPath()
    Set-Location $tmp
    [Environment]::CurrentDirectory = $tmp
    if ($dir -and (Test-Path $dir)) { Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue }
}

# Run the installer headless into the current dir; return all output as one
# string so tests can assert on the printed map/warnings/hint. --yes forces
# every prompt to its default.
function Invoke-Installer {
    param([Parameter(ValueFromRemainingArguments)] [string[]] $InstallerArgs)
    return (& (Join-Path $KitRoot 'init.ps1') @InstallerArgs --yes *>&1 | Out-String)
}

# Run the session-end hook; return its stdout (the nudge JSON, or empty).
function Invoke-SessionEndHook {
    return (& (Join-Path $KitRoot 'template/scripts/working-memory-session-end.ps1') 2>$null | Out-String)
}

# Count lines in a file matching a pattern (the grep -c equivalent).
function Get-MatchCount ($path, $pattern) {
    if (-not (Test-Path $path)) { return 0 }
    return @(Select-String -Path $path -Pattern $pattern).Count
}

# The slice of a file from the first line matching $marker through EOF, joined
# back into one string (the sed "/marker/,$p" equivalent). Used to assert that
# user content lands *after* the closing fence, not inside it.
function Get-FromMarker ($path, $marker) {
    $lines = Get-Content $path
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $marker) { return ($lines[$i..($lines.Count - 1)] -join "`n") }
    }
    return ''
}

# Is the cross-reference inside the working-memory fence in AGENTS.md?
function Test-XrefInsideFence {
    $inside = $false; $seenStart = $false
    foreach ($line in (Get-Content AGENTS.md)) {
        if ($line -match 'working-memory:start') { $seenStart = $true }
        elseif ($line -match 'working-memory:end') { $seenStart = $false }
        elseif ($seenStart -and $line -match 'Spec-driven tooling lives') { $inside = $true }
    }
    return $inside
}
