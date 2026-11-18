# #91: the PowerShell twin of version-check.sh, with the same rules and the same output line.
# hooks.json runs one shell-form command on every OS: `exec bash ...version-check.sh; powershell ... -File ...version-check.ps1`.
# Under sh or Git Bash, exec replaces the shell and the second half never runs. On Windows without Git Bash, Claude Code runs the line through PowerShell, where exec is an unknown command, so it errors to stderr and the `;` moves on to this script under Windows PowerShell 5.1, the kit's floor.
# Warn only when the project's marker is a strictly lower X.Y.Z than the plugin's version.txt. Everything else is silent with exit 0, since a hook error would land in the user's session.

function Read-KitVersion ($path) {
    if (-not [IO.File]::Exists($path)) { return $null }
    # Trim drops the CR that a Windows checkout with autocrlf leaves in version.txt and so in the marker.
    $v = [IO.File]::ReadAllText($path).Trim()
    if ($v -match '^[0-9]+\.[0-9]+\.[0-9]+$') { return $v }
    return $null
}

try {
    if (-not $env:CLAUDE_PROJECT_DIR) { exit 0 }
    $proj = Read-KitVersion (Join-Path $env:CLAUDE_PROJECT_DIR '.claude/working-memory-kit.version')
    $kit = Read-KitVersion (Join-Path $PSScriptRoot '../version.txt')
    # [version] compares field by field as integers; as strings 0.9.0 would sort after 0.10.0.
    if ($proj -and $kit -and ([version]$proj -lt [version]$kit)) {
        Write-Output ('{"systemMessage":"working-memory-kit: this project runs kit ' + $proj + ' and the plugin has ' + $kit + '. Run /working-memory-kit:init to upgrade it."}')
    }
}
catch { }
exit 0
