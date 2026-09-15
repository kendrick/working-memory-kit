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

# Styling parity with init.sh: a modern truecolor palette when the terminal can
# render it, plain (ASCII box, no escapes) whenever output is redirected (CI, the
# test suite) or NO_COLOR is set. Only chrome (banner, menu box) is painted; the
# Write-* prefixes above keep their 16-color path so nothing in the body changes.
function Get-ColorMode {
    if ($env:NO_COLOR -or [Console]::IsOutputRedirected) { return 'plain' }
    if ($env:COLORTERM -match 'truecolor|24bit') { return 'truecolor' }
    if ($PSVersionTable.PSVersion.Major -ge 7) { return 'truecolor' }
    return '16'
}
$ColorMode = Get-ColorMode

function Paint ($role, $text) {
    if ($ColorMode -ne 'truecolor') { return $text }
    $rgb = switch ($role) {
        'primary' { '124;124;240' }
        'success' { '74;222;128' }
        'warn'    { '251;191;36' }
        'error'   { '248;113;113' }
        'muted'   { '139;147;167' }
        default   { '' }
    }
    if (-not $rgb) { return $text }
    $esc = [char]27
    return "$esc[38;2;${rgb}m$text$esc[0m"
}

# Rounded box (ASCII when plain) around left-aligned lines, sized to the widest.
function Write-Box ($role, [string[]] $lines) {
    $w = 0; foreach ($l in $lines) { if ($l.Length -gt $w) { $w = $l.Length } }
    if ($ColorMode -eq 'plain') { $tl='+';$tr='+';$bl='+';$br='+';$h='-';$v='|' }
    else { $tl='╭';$tr='╮';$bl='╰';$br='╯';$h='─';$v='│' }
    $rule = $h * ($w + 2)
    Write-Host (Paint $role "$tl$rule$tr")
    foreach ($l in $lines) {
        Write-Host ('{0} {1}{2} {3}' -f (Paint $role $v), $l, (' ' * ($w - $l.Length)), (Paint $role $v))
    }
    Write-Host (Paint $role "$bl$rule$br")
}

# Non-interactive analogue of the bash /dev/tty handling: when stdin is
# redirected (CI, automation, a piped install) skip the prompt and take the
# supplied default, so init.ps1 is drivable without a console instead of
# blocking on Read-Host.
function Read-Prompt ($prompt, $default = '') {
    if ($NonInteractive -or [Console]::IsInputRedirected) { return $default }
    return Read-Host $prompt
}

function Confirm-Prompt ($prompt, $defaultYes = $true) {
    $hint = if ($defaultYes) { '[Y/n]' } else { '[y/N]' }
    $reply = Read-Prompt "$prompt $hint"
    if ([string]::IsNullOrWhiteSpace($reply)) { return $defaultYes }
    return $reply -match '^(y|yes)$'
}

# User-owned content (the working-memory files a human fills in). Create it if
# absent, never touch it once it exists. The upfront Upgrade/Cancel menu, not a
# per-file prompt, governs the run. Parity with copy_if_absent in init.sh.
function Copy-IfAbsent ($src, $dst) {
    if (Test-Path $dst) { return }
    $parent = Split-Path $dst -Parent
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item $src $dst
    Write-Ok "created $dst"
}

# Kit-owned machinery: reconciled toward the shipped version on upgrade without
# clobbering local edits. absent -> create; byte-identical -> silent; diverged ->
# leave the live file, write the incoming version to <file>.kitnew, note it (the
# pacman .pacnew / dpkg .dpkg-dist convention). --overwrite-machinery takes the
# kit version outright. Parity with install_machinery in init.sh.
$script:Diverged = @()
$KitnewSentinel = 'working-memory-kit: a newer version of this file shipped'

# Render src as this install would write it: apply the same WM-dir substitution,
# so the divergence compare doesn't false-positive under a custom dir. Returns a
# path (src itself, or a temp file the caller removes). WriteAllText keeps LF and
# writes UTF8 without a BOM, matching the template bytes.
function Get-RenderedMachinery ($src) {
    if ($WmDir -eq $WmDirDefault) { return $src }
    $tmp = [IO.Path]::GetTempFileName()
    $content = ([IO.File]::ReadAllText($src)) -replace '_working-memory', $WmDir
    [IO.File]::WriteAllText($tmp, $content)
    return $tmp
}

function Install-Machinery ($src, $dst) {
    $rendered = Get-RenderedMachinery $src
    try {
        if (-not (Test-Path $dst)) {
            $parent = Split-Path $dst -Parent
            if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item $rendered $dst
            Write-Ok "created $dst"
        }
        elseif ((Get-FileHash $rendered).Hash -eq (Get-FileHash $dst).Hash) {
            # identical to the shipped version: nothing to reconcile
        }
        elseif ($OverwriteMachinery) {
            Copy-Item $rendered $dst -Force
            Write-Ok "refreshed $dst (took the kit version)"
        }
        else {
            Copy-Item $rendered "$dst.kitnew" -Force
            $rel = $dst.Substring($TargetDir.Length).TrimStart('\', '/')
            $script:Diverged += $rel
            Add-KitnewPointer $dst
            Write-Warn "diverged: kept your $rel; kit version written to $rel.kitnew"
        }
    } finally {
        if ($rendered -ne $src -and (Test-Path $rendered)) { Remove-Item $rendered -Force }
    }
}

# One idempotent pointer noting a .kitnew sidecar. Comment-friendly types only
# (JSON can't carry a comment; the summary covers it). Inserted after a #! shebang
# or a --- frontmatter block so line 1 stays valid. Sentinel-guarded against
# stacking on repeated runs, which byte-stability relies on.
function Add-KitnewPointer ($dst) {
    $base = Split-Path $dst -Leaf
    $raw = [IO.File]::ReadAllText($dst)
    if ($raw.Contains($KitnewSentinel)) { return }
    $open = ''; $close = ''
    if     ($dst -match '\.md(\.example)?$')              { $open = '<!-- '; $close = ' -->' }
    elseif ($dst -match '\.(sh|ps1)$')                    { $open = '# ' }
    elseif ($dst -match '\.working-memoryrc(\.example)?$'){ $open = '# ' }
    else { return }
    $note = "$open$KitnewSentinel. See $base.kitnew, merge what you want, then delete both it and this note.$close"
    $lines = $raw -split "`n"
    $after = 0
    if ($lines[0] -like '#!*') { $after = 1 }
    elseif ($lines[0] -eq '---') {
        for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -eq '---') { $after = $i + 1; break } }
    }
    if ($after -ge $lines.Count) { $new = @($lines) + $note }
    elseif ($after -gt 0)        { $new = @($lines[0..($after - 1)]) + $note + @($lines[$after..($lines.Count - 1)]) }
    else                         { $new = @($note) + @($lines) }
    [IO.File]::WriteAllText($dst, ($new -join "`n"))
}

# w-m-k owns one fenced section in each agent file. A (re)install only reads and
# replaces the text BETWEEN these markers, so a user's surrounding content and
# any neighboring tool's block survive untouched. The span is the kit's to
# refresh on upgrade; don't hand-edit between the markers. Parity with init.sh.
$WmStart = '<!-- working-memory:start -->'
$WmEnd   = '<!-- working-memory:end -->'

# Pull the START..END span (inclusive) out of fenced template content.
function Get-FencedBlock ($content) {
    $pattern = [regex]::Escape($WmStart) + '.*?' + [regex]::Escape($WmEnd)
    return [regex]::Match($content, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
}

# Create / refresh / migrate / inject the kit's fenced section in $dst.
#   freshContent = written verbatim when $dst is absent (whole template, or the block)
#   block        = the fenced START..END span to splice into an existing file
#   position     = 'append' | 'prepend' (only used when $dst has no section yet)
#   sentinel     = end-of-section text that bounds a legacy migration in prepend files
function Set-FencedSection ($dst, $freshContent, $block, $position, $sentinel = '') {
    # We emit the block we own with LF, matching init.sh. On Windows the template
    # checks out with CRLF, so without this the migration path (which rebuilds at
    # LF) and a later re-fence (which splices the block verbatim) would disagree on
    # endings and `git status` would never come clean. Content outside our markers
    # keeps its original endings (see the raw read below), so a re-install never
    # rewrites a user's or neighbor's line endings.
    $freshContent = $freshContent -replace "`r`n", "`n"
    $block = $block -replace "`r`n", "`n"
    if (-not (Test-Path $dst)) {
        $parent = Split-Path $dst -Parent
        if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Set-Content -Path $dst -Value $freshContent -NoNewline
        Write-Ok "created $dst"
        return
    }
    $rawDoc = Get-Content $dst -Raw
    if ($null -eq $rawDoc) { $rawDoc = '' }
    # Normalized copy: used only for detection and the line parsing below. Every
    # write splices into $rawDoc, so text outside our markers keeps its endings.
    $doc = $rawDoc -replace "`r`n", "`n"
    $blk = $block -replace '\s+$', ''

    if ($doc.Contains($WmStart) -and $doc.Contains($WmEnd)) {
        # already fenced: swap our body, leave the markers and everything else
        # (raw, original endings) exactly as the user and any neighbor have it.
        $si = $rawDoc.IndexOf($WmStart)
        $ei = $rawDoc.IndexOf($WmEnd) + $WmEnd.Length
        $doc = $rawDoc.Substring(0, $si) + $blk + $rawDoc.Substring($ei)
    }
    elseif ($doc -match '(?m)^## Working Memory[ \t]*$') {
        # legacy unfenced section: migrate it in place, exactly once.
        # Plain -split already keeps every field, trailing empties included; do
        # NOT append a ', -1' max (Perl's "keep all" idiom). PowerShell reads a
        # negative max as "return one element", which collapses the whole doc to
        # a single line, so the migration finds no heading and wipes user content.
        $lines = $doc -split '\r?\n'
        $si = -1
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^## Working Memory[ \t]*$') { $si = $i; break } }
        $ei = -1
        if ($sentinel) {
            for ($i = $si; $i -lt $lines.Count; $i++) {
                if ($i -gt $si -and $lines[$i] -match '^## ') { break }   # next H2 before the end line: bail
                if ($lines[$i].Contains($sentinel)) { $ei = $i; break }
            }
        } else {
            $ei = $lines.Count - 1
            for ($i = $si + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^## ') { $ei = $i - 1; break } }
            while ($ei -gt $si -and $lines[$ei] -eq '') { $ei-- }   # keep the blank line before the next heading
        }
        if ($ei -lt 0) {
            Write-Warn "$dst has an unfenced Working Memory section I could not bound safely; left it as-is. Fence it by hand or remove it and re-run."
            return
        }
        $pre  = if ($si -gt 0) { $lines[0..($si - 1)] } else { @() }
        $post = if ($ei -lt ($lines.Count - 1)) { $lines[($ei + 1)..($lines.Count - 1)] } else { @() }
        $blkLines = $blk -split '\r?\n'
        $doc = (@($pre) + @($blkLines) + @($post)) -join "`n"
    }
    else {
        # no section yet: splice our block into the raw doc, preserving the user's
        # surrounding endings.
        if ($position -eq 'prepend') { $doc = "$blk`n`n$rawDoc" }
        else { $doc = ($rawDoc -replace '\s+$', '') + "`n`n$blk`n" }
    }
    Set-Content -Path $dst -Value $doc -NoNewline
    Write-Ok "updated working-memory section in $dst"
}

# ---------- neighbor registry (keep in sync with init.sh) ----------

# External spec-driven / memory tooling the kit should coexist with.
#   process  coexist and wire (ownership map + AGENTS cross-ref + conventions deferral)
#   memory   warn only; two durable-memory systems don't divide cleanly
#   note     mention only (overlaps the kit, nothing to wire)
# Triggers are tool-unique top-level paths; a bare specs/ is never a trigger.
$WmkNeighbors = @(
    @{ Name = 'Spec Kit';    Kind = 'process'; Triggers = @('.specify');                Principles = '.specify/memory/constitution.md' }
    @{ Name = 'OpenSpec';    Kind = 'process'; Triggers = @('openspec');                Principles = 'openspec/project.md' }
    @{ Name = 'Kiro';        Kind = 'process'; Triggers = @('.kiro');                   Principles = '.kiro/steering/' }
    @{ Name = 'BMAD';        Kind = 'process'; Triggers = @('bmad-core', '.bmad-core'); Principles = 'bmad-core/data/technical-preferences.md' }
    @{ Name = 'Agent OS';    Kind = 'process'; Triggers = @('.agent-os');               Principles = '.agent-os/standards/' }
    @{ Name = 'Task Master'; Kind = 'process'; Triggers = @('.taskmaster');             Principles = '' }
    @{ Name = 'Memory Bank'; Kind = 'memory';  Triggers = @('memory-bank');             Principles = '' }
    @{ Name = 'ADRs';        Kind = 'note';    Triggers = @('docs/adr', 'docs/decisions'); Principles = '' }
)

# Returns matched neighbors (objects with a resolved Found path) actually present
# in the target. Mirrors detect_neighbors / detect_stack's scan-and-report shape.
function Get-Neighbors ($targetDir) {
    $matched = @()
    foreach ($n in $WmkNeighbors) {
        foreach ($t in $n.Triggers) {
            if (Test-Path (Join-Path $targetDir $t) -PathType Container) {
                $matched += [PSCustomObject]@{ Name = $n.Name; Kind = $n.Kind; Found = $t; Principles = $n.Principles }
                break
            }
        }
    }
    return $matched
}

# Cross-reference paragraph for the fenced AGENTS section, from process neighbors.
# Empty when there are none. The literal _working-memory token is rewritten later
# if the user chose a custom dir.
function Get-ProcessXref ($neighbors) {
    $tools = ($neighbors | Where-Object { $_.Kind -eq 'process' } | ForEach-Object { if ($_.Name) { "$($_.Name) (``$($_.Found)/``)" } else { "``$($_.Found)/``" } }) -join ', '
    if (-not $tools) { return '' }
    return "Spec-driven tooling lives in $tools. Per-feature specs and plans stay there; this Working Memory section is the durable project state. Boundary: see [``_working-memory/README.md``](_working-memory/README.md)."
}

# Prints the who-owns-what map for process/note neighbors and a warning for any
# memory neighbor.
function Write-CoexistenceSummary ($neighbors) {
    $mapped = $neighbors | Where-Object { $_.Kind -eq 'process' -or $_.Kind -eq 'note' }
    if ($mapped) {
        Write-Host ''
        Write-Info 'Coexistence: who owns what now that neighbors are present:'
        foreach ($n in $mapped) {
            if ($n.Kind -eq 'process') {
                $p = if ($n.Principles) { $n.Principles } else { 'its own dir' }
                $label = if ($n.Name) { $n.Name } else { 'external spec tooling' }
                Write-Host "  - $label ($($n.Found)/): principles in $p; per-feature specs stay in the tool."
            } else {
                Write-Host "  - $($n.Name) ($($n.Found)/): overlaps decisionLog.md; left as-is, nothing wired."
            }
        }
        Write-Host '  - working-memory-kit: _working-memory/ and the fenced AGENTS.md section (durable state, decisions, conventions).'
        Write-Host "    Promote cross-cutting decisions up into _working-memory/decisionLog.md. The kit labels these lanes; it doesn't enforce them."
    }
    foreach ($n in ($neighbors | Where-Object { $_.Kind -eq 'memory' })) {
        Write-Warn "Two durable-memory systems detected (working-memory-kit + $($n.Name), in $($n.Found)/). They overlap; pick one as canonical or consolidate. The kit won't auto-merge."
    }
}

# Reads a key from the live .working-memoryrc with the same parser the hooks use,
# so what we persist stays readable.
function Get-RcKey ($key, $default) {
    $file = Join-Path $TargetDir '.working-memoryrc'
    if (-not (Test-Path $file)) { return $default }
    $line = Get-Content $file | Where-Object { $_ -match "^$key=" } | Select-Object -First 1
    if (-not $line) { return $default }
    $val = ($line -split '=', 2)[1].Trim().Trim('"').Trim("'")
    if ($val) { return $val } else { return $default }
}

# Idempotent upsert of one .working-memoryrc key: replace its line or append it,
# leaving every other key alone. Bare key=value, no spaces around =.
function Set-RcKey ($key, $value) {
    $file = Join-Path $TargetDir '.working-memoryrc'
    $newLine = "$key=$value"
    if ((Test-Path $file) -and ((Get-Content $file) -match "^$key=")) {
        $content = Get-Content $file | ForEach-Object { if ($_ -match "^$key=") { $newLine } else { $_ } }
        Set-Content -Path $file -Value $content
    } else {
        Add-Content -Path $file -Value $newLine
    }
}

# ---------- parse args ----------

# --coexist-with <path> registers external spec tooling the registry doesn't know;
# --coexist-principles <file> pairs its principles file; --no-coexist opts out.
# --yes / --non-interactive drives every prompt to its default (CI, automation).
# --overwrite-machinery takes the shipped version of every kit-owned file
# outright, skipping the .kitnew sidecars. Flag-only escape hatch for the Upgrade
# flow (no menu item, no --force alias). Content files are never touched by it.
$CoexistWith = ''
$CoexistPrinciples = ''
$NoCoexist = $false
$NonInteractive = $false
$OverwriteMachinery = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    switch -Regex ($args[$i]) {
        '^--coexist-with=(.+)$'       { $CoexistWith = $Matches[1] }
        '^--coexist-with$'            { if ($i + 1 -lt $args.Count) { $i++; $CoexistWith = $args[$i] } }
        '^--coexist-principles=(.+)$' { $CoexistPrinciples = $Matches[1] }
        '^--coexist-principles$'      { if ($i + 1 -lt $args.Count) { $i++; $CoexistPrinciples = $args[$i] } }
        '^--no-coexist$'              { $NoCoexist = $true }
        '^--overwrite-machinery$'     { $OverwriteMachinery = $true }
        '^--(yes|non-interactive)$'   { $NonInteractive = $true }
        default                       { Write-Warn "ignoring unknown option: $($args[$i])" }
    }
}

# ---------- locate template ----------

# Two install paths: a cloned kit (template/ next to this script) or curl-pipe
# (script alone, fetches the tarball). Local wins so kit devs can iterate
# without round-tripping GitHub.
# Under `iex (irm ...)`, $MyInvocation.MyCommand.Path is empty; keep ScriptDir
# empty in that case so the local-template and dogfood checks both fall through.
$ScriptSource = $MyInvocation.MyCommand.Path
if ($ScriptSource -and (Test-Path $ScriptSource)) {
    $ScriptDir = Split-Path -Parent $ScriptSource
} else {
    $ScriptDir = ''
}
$TargetDir = (Get-Location).Path
$Template  = $null

if ($ScriptDir -and (Test-Path (Join-Path $ScriptDir 'template'))) {
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

# Hydration artifacts live at the kit root's .claude/, not inside template/,
# because they're also used by kit contributors working in the kit repo itself.
# Resolve KitRoot (parent of template/) so the installer can pull them too.
$KitRoot = Split-Path -Parent $Template

# ---------- intro ----------

Write-Host ""
Write-Box 'primary' @('working-memory-kit installer')
Write-Host "Target: $TargetDir"
Write-Host ""

if ($ScriptDir -and ($TargetDir -eq $ScriptDir)) {
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

# ---------- detect neighbor tooling ----------

$Neighbors = Get-Neighbors $TargetDir

# Resolve a user-registered external spec path: a flag this run beats a value
# remembered in .working-memoryrc; --no-coexist (or a remembered opt-out) wins.
$rcTooling = Get-RcKey 'external_spec_tooling' ''
$registeredPath = ''
$registeredPrinciples = ''
if (-not $NoCoexist) {
    if ($CoexistWith) {
        $registeredPath = $CoexistWith.TrimEnd('/')
        $registeredPrinciples = $CoexistPrinciples
    } elseif ($rcTooling -and $rcTooling -ne 'false') {
        $registeredPath = $rcTooling.TrimEnd('/')
        $registeredPrinciples = Get-RcKey 'external_spec_principles' ''
    }
}
if ($registeredPath) {
    $Neighbors = @($Neighbors) + [PSCustomObject]@{ Name = ''; Kind = 'process'; Found = $registeredPath; Principles = $registeredPrinciples }
}

# Persist the answer so re-runs don't need the flag again. Only a flag writes.
if ($NoCoexist) {
    Set-RcKey 'external_spec_tooling' 'false'
    Set-RcKey 'coexistence_asked' 'true'
} elseif ($CoexistWith) {
    Set-RcKey 'external_spec_tooling' "`"$registeredPath`""
    if ($registeredPrinciples) { Set-RcKey 'external_spec_principles' "`"$registeredPrinciples`"" }
    Set-RcKey 'coexistence_asked' 'true'
}

# Nothing known, nothing registered, never asked: point at the escape hatch once.
if ((-not $Neighbors) -and (-not $NoCoexist) -and ((Get-RcKey 'coexistence_asked' '') -ne 'true')) {
    Write-Info 'No spec-driven tooling detected. If this project uses some, re-run with --coexist-with <path> to register it.'
}

# ---------- working-memory directory choice ----------

# Default is _working-memory (underscore prefix keeps it grouped near
# similarly-prefixed tooling directories at the top of file listings).
# Consumer can override at install time; on override, the installer
# substitutes the literal token in copied template files.
$WmDirDefault = '_working-memory'
$WmDir = $WmDirDefault
$reply = Read-Prompt "Install working memory at $WmDirDefault/? [Y/n, or specify alternate path]"
if ($reply -match '^(n|no)$') {
    $custom = Read-Prompt 'Enter alternate path (relative to repo root)'
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

# $Mode drives file handling downstream. A fresh repo installs; an existing kit
# is an upgrade (reconcile machinery, add new content, refresh fenced sections,
# never touch edited content). No console and no flag both resolve to the safe
# upgrade default; an interactive run gets the explicit Upgrade/Cancel choice.
$Mode = 'install'
if ($Existing.Count -gt 0) {
    $Mode = 'upgrade'
    $interactive = -not ($NonInteractive -or [Console]::IsInputRedirected)
    if ($interactive -and -not $OverwriteMachinery) {
        Write-Host ''
        Write-Warn "working-memory-kit is already installed here ($($Existing -join ', '))."
        Write-Host 'Machinery the kit owns (skills, agents, hooks, scripts) reconciles toward the' -ForegroundColor DarkGray
        Write-Host 'latest; if you changed one, the kit version lands beside it as .kitnew instead of' -ForegroundColor DarkGray
        Write-Host 'overwriting. Your working-memory notes are never touched.' -ForegroundColor DarkGray
        $choices = @(
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Upgrade', 'Add anything new, refresh managed sections, keep everything you edited.'),
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Cancel', 'Exit without changes.')
        )
        if ($Host.UI.PromptForChoice('working-memory-kit', 'An install already exists here. What would you like to do?', $choices, 0) -eq 1) {
            $Mode = 'cancel'
        }
    }
    if ($Mode -eq 'cancel') { Write-Host 'cancelled. Nothing changed.'; exit 0 }
}

Write-Host ''
if ($Mode -eq 'upgrade') { Write-Info 'upgrading...' } else { Write-Info 'scaffolding...' }

# ---------- working-memory ----------

if (-not (Test-Path $WmDir)) { New-Item -ItemType Directory -Path $WmDir | Out-Null }
# The kit-authored README and the example are machinery (kit-owned, reconciled).
# The six memory files are the user's content: seeded once, never overwritten.
foreach ($f in @('README.md', 'activeContext.example.md')) {
    Install-Machinery (Join-Path $Template "_working-memory/$f") (Join-Path $TargetDir "$WmDir/$f")
}
foreach ($f in @('projectOverview.md', 'decisionLog.md', 'dataContracts.md', 'conventions.md', 'openQuestions.md', 'antipatterns.md')) {
    Copy-IfAbsent (Join-Path $Template "_working-memory/$f") (Join-Path $TargetDir "$WmDir/$f")
}

if (-not (Test-Path "$WmDir/activeContext.md")) {
    Copy-Item "$WmDir/activeContext.example.md" "$WmDir/activeContext.md"
    Write-Ok "created your local $WmDir/activeContext.md from the template"
}

# Skip pre-population if the placeholder marker is gone: the team has filled
# in their overview by hand and we shouldn't clobber it on re-run. The (?m) is
# load-bearing: against a -Raw whole-file string, ^ anchors to the start of the
# string, not each line (unlike grep), so without it this guard never fires and
# the Stack section silently goes un-prefilled.
if ($Stack.Language -and (Get-Content "$WmDir/projectOverview.md" -Raw) -match '(?m)^_To be filled\._') {
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
    Set-Content -Path "$WmDir/projectOverview.md" -Value $overview
    Write-Ok "pre-populated $WmDir/projectOverview.md with detected stack"
}

# ---------- conventions deferral note (process neighbor with a principles file) ----------

# Point conventions.md at the neighbor's principles file so it stays tactical and
# doesn't restate principles. Marker-guarded so re-runs don't stack it. Uses the
# first process neighbor that actually ships a principles file.
$convFile = Join-Path $TargetDir "$WmDir/conventions.md"
$principlesNeighbor = $Neighbors | Where-Object { $_.Kind -eq 'process' -and $_.Principles } | Select-Object -First 1
if ($principlesNeighbor -and (Test-Path $convFile)) {
    $conv = Get-Content $convFile -Raw
    if ($conv -notmatch 'coexistence:principles') {
        $note = "<!-- coexistence:principles -->`n> Project principles live in ``$($principlesNeighbor.Principles)`` ($($principlesNeighbor.Name)). Keep this file to tactical patterns; don't restate principles."
        $anchor = '<!-- This is the "how we do things here" file. -->'
        $conv = $conv -replace [regex]::Escape($anchor), "$anchor`n`n$note"
        Set-Content -Path $convFile -Value $conv -NoNewline
        Write-Ok "pointed $WmDir/conventions.md at $($principlesNeighbor.Name) principles ($($principlesNeighbor.Principles))"
    }
}

# ---------- .working-memoryrc.example ----------

# We ship the example, not the rc itself. Defaults are baked into the hook
# scripts; the rc is opt-in for teams that want to override line limits or
# nudge thresholds.
Install-Machinery (Join-Path $Template '.working-memoryrc.example') `
                  (Join-Path $TargetDir '.working-memoryrc.example')

# ---------- AGENTS.md ----------

$agentsTemplate = Get-Content (Join-Path $Template 'AGENTS.md') -Raw
# Fold the neighbor cross-reference into the template's fenced section up front,
# so both the fresh-copy and splice paths read the same source and re-installs
# stay idempotent.
$agentsXref = Get-ProcessXref $Neighbors
if ($agentsXref) {
    $agentsTemplate = $agentsTemplate -replace [regex]::Escape($WmEnd), "$agentsXref`n`n$WmEnd"
}
$agentsBlock = Get-FencedBlock $agentsTemplate
Set-FencedSection (Join-Path $TargetDir 'AGENTS.md') $agentsTemplate $agentsBlock 'append'

# Pre-fill the Stack section if (a) we detected a language and (b) the
# placeholder comment is still present. The comment is the idempotency
# marker — once a human fills it in, the placeholder is gone and we
# leave the section alone on re-runs.
if ($Stack.Language) {
    $agentsPath = Join-Path $TargetDir 'AGENTS.md'
    $agentsContent = Get-Content $agentsPath -Raw
    $stackMarker = '<!-- One line per layer. Detected from project. -->'
    if ($agentsContent -like "*$stackMarker*") {
        $stackBlock = "- Language: $($Stack.Language)"
        if ($Stack.Framework) { $stackBlock += "`n- Framework: $($Stack.Framework)" }
        $agentsContent = $agentsContent -replace [regex]::Escape($stackMarker), $stackBlock
        Set-Content -Path $agentsPath -Value $agentsContent -NoNewline
        Write-Ok 'pre-populated AGENTS.md Stack with detected stack'
    }
}

# ---------- Claude Code config ----------

foreach ($d in @('.claude/agents','.claude/skills/update-working-memory')) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
Install-Machinery `
    (Join-Path $Template '.claude/agents/working-memory-synchronizer.md') `
    (Join-Path $TargetDir '.claude/agents/working-memory-synchronizer.md')
Install-Machinery `
    (Join-Path $Template '.claude/skills/update-working-memory/SKILL.md') `
    (Join-Path $TargetDir '.claude/skills/update-working-memory/SKILL.md')

# Hydration surface: composite agent + five phase skills. Sourced from the kit
# root (not template/) since kit contributors use the same files. Optional —
# installs cleanly if the kit version doesn't ship them yet.
$hydratorSrc = Join-Path $KitRoot '.claude/agents/hydrator.md'
if (Test-Path $hydratorSrc) {
    Install-Machinery $hydratorSrc (Join-Path $TargetDir '.claude/agents/hydrator.md')
}
$hydrateSkillsDir = Join-Path $KitRoot '.claude/skills'
if (Test-Path $hydrateSkillsDir) {
    Get-ChildItem -Path $hydrateSkillsDir -Directory -Filter 'hydrate-*' | ForEach-Object {
        $skillFile = Join-Path $_.FullName 'SKILL.md'
        if (Test-Path $skillFile) {
            $dst = Join-Path $TargetDir ".claude/skills/$($_.Name)/SKILL.md"
            Install-Machinery $skillFile $dst
        }
    }
}

# ---------- Codex config ----------

# Codex discovers repository skills from .agents/skills. Install from the
# existing .claude sources so the shared workflow keeps one source of truth.
Install-Machinery `
    (Join-Path $Template '.claude/skills/update-working-memory/SKILL.md') `
    (Join-Path $TargetDir '.agents/skills/update-working-memory/SKILL.md')
if (Test-Path $hydrateSkillsDir) {
    Get-ChildItem -Path $hydrateSkillsDir -Directory -Filter 'hydrate-*' | ForEach-Object {
        $skillFile = Join-Path $_.FullName 'SKILL.md'
        if (Test-Path $skillFile) {
            $dst = Join-Path $TargetDir ".agents/skills/$($_.Name)/SKILL.md"
            Install-Machinery $skillFile $dst
        }
    }
}
Install-Machinery (Join-Path $Template '.codex/agents/hydrator.toml') `
                  (Join-Path $TargetDir '.codex/agents/hydrator.toml')
Install-Machinery (Join-Path $Template '.codex/hooks.json') `
                  (Join-Path $TargetDir '.codex/hooks.json')

$claudeBody = @'
## Working Memory

**AGENT INSTRUCTION:** before deciding what to read, scan the on-demand table under `## Working Memory` in [`AGENTS.md`](AGENTS.md). If your task matches a row, that file is required reading before you proceed.

Always read `_working-memory/activeContext.md` on session start. AGENTS.md is the canonical source for the on-demand table and update rules.
To sync working memory, run `/update-working-memory` or invoke the `working-memory-synchronizer` agent.
'@
$claudeBlock = "$WmStart`n$claudeBody`n$WmEnd"
Set-FencedSection (Join-Path $TargetDir 'CLAUDE.md') $claudeBlock $claudeBlock 'prepend' 'To sync working memory'

# ---------- Copilot config ----------

foreach ($d in @('.github/hooks','.github/instructions')) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

Install-Machinery (Join-Path $Template '.github/hooks/working-memory-hooks.json') `
                  (Join-Path $TargetDir '.github/hooks/working-memory-hooks.json')
# Inert example of a path-scoped Copilot instruction wired to working memory. The
# .example suffix keeps it out of VS Code's active *.instructions.md glob; a
# consumer copies it to working-memory.instructions.md to switch it on.
Install-Machinery (Join-Path $Template '.github/instructions/working-memory.instructions.md.example') `
                  (Join-Path $TargetDir '.github/instructions/working-memory.instructions.md.example')

$copilotTemplate = Get-Content (Join-Path $Template '.github/copilot-instructions.md') -Raw
$copilotBlock = Get-FencedBlock $copilotTemplate
Set-FencedSection (Join-Path $TargetDir '.github/copilot-instructions.md') $copilotTemplate $copilotBlock 'prepend' 'To sync working memory'

# ---------- scripts ----------

if (-not (Test-Path 'scripts')) { New-Item -ItemType Directory -Path 'scripts' | Out-Null }
$scriptFiles = @(
    'working-memory-session-start.sh','working-memory-session-start.ps1',
    'working-memory-session-end.sh','working-memory-session-end.ps1',
    'update-working-memory.sh','update-working-memory.ps1'
)
foreach ($f in $scriptFiles) {
    Install-Machinery (Join-Path $Template "scripts\$f") (Join-Path $TargetDir "scripts\$f")
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

# Machinery files already rendered the token at write time (Install-Machinery),
# so only the fenced files remain: they're spliced in place from the template's
# _working-memory literal and can't be pre-rendered.
if ($WmDir -ne $WmDirDefault) {
    Write-Info "substituting _working-memory -> $WmDir in the fenced sections"
    $filesToSub = @(
        'AGENTS.md',
        'CLAUDE.md',
        '.github/copilot-instructions.md'
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
    '.claude/agents/working-memory-synchronizer.md',
    '.claude/skills/update-working-memory/SKILL.md',
    '.claude/agents/hydrator.md',
    '.claude/skills/hydrate-discover/SKILL.md',
    '.claude/skills/hydrate-extract/SKILL.md',
    '.claude/skills/hydrate-draft/SKILL.md',
    '.claude/skills/hydrate-reconcile/SKILL.md',
    '.claude/skills/hydrate-propose/SKILL.md',
    '.agents/skills/update-working-memory/SKILL.md',
    '.agents/skills/hydrate-discover/SKILL.md',
    '.agents/skills/hydrate-extract/SKILL.md',
    '.agents/skills/hydrate-draft/SKILL.md',
    '.agents/skills/hydrate-reconcile/SKILL.md',
    '.agents/skills/hydrate-propose/SKILL.md',
    '.codex/agents/hydrator.toml',
    '.codex/hooks.json'
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

# Coexistence summary: who owns what, plus any memory-tool overlap warning.
Write-CoexistenceSummary $Neighbors

# Divergence summary: kit files you'd edited, left untouched, with the shipped
# version parked alongside as .kitnew. JSON has no sidecar pointer, so this is
# the only notice it gets.
if ($script:Diverged.Count -gt 0) {
    Write-Host ''
    Write-Warn "$($script:Diverged.Count) kit file(s) diverged from the shipped version and were left as you have them:"
    foreach ($f in $script:Diverged) { Write-Host "    - $f  (kit version: $f.kitnew)" }
    Write-Host '    Diff each against its .kitnew, merge what you want, then delete the .kitnew.'
    Write-Host '    Or re-run with --overwrite-machinery to take every kit version at once.'
}

Write-Host ''
Write-Host 'done.' -ForegroundColor Green
Write-Host ''
Write-Host 'next steps:'
Write-Host '  1. Populate working memory (recommended for existing codebases):'
Write-Host '       Use the hydrator agent in Claude Code, Copilot, or Codex.'
Write-Host '       Or run the hydrate-discover skill to walk the five phases one at a time.'
Write-Host '       This scans your codebase, git history, README, and ADRs to fill'
Write-Host '       projectOverview / decisionLog / dataContracts / conventions.'
Write-Host '       For a brand-new project, skip this step and edit the files by hand.'
Write-Host "  2. Edit $WmDir/activeContext.md to reflect what you're working on."
Write-Host '  3. Teammates: after cloning, run:'
Write-Host "       Copy-Item $WmDir/activeContext.example.md $WmDir/activeContext.md"
Write-Host '  4. Ongoing sync: use the update-working-memory skill, or run:'
Write-Host '     ./scripts/update-working-memory.ps1'
Write-Host '  5. To tune line limits or nudge thresholds:'
Write-Host '       Copy-Item .working-memoryrc.example .working-memoryrc   # then edit'

if (-not $canonicalOk) {
    Write-Host ''
    Write-Warn 'some canonical artifacts are missing. Review the messages above.'
}
