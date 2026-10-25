#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the fzf + PSFzf PowerShell setup: tools, config files, $PROFILE hook.

.DESCRIPTION
    Idempotent. Run it as many times as you like -- it backs up your $PROFILE,
    writes its changes inside a marked block, and rewrites that block on reruns
    instead of appending a second copy.

    The $PROFILE line is appended at the END of the file on purpose: the config
    has to load after atuin and zoxide so it can see their key bindings and
    leave Ctrl+R alone.

.PARAMETER PackageManager
    auto (default) | winget | scoop | none.  'auto' prefers winget.

.PARAMETER Destination
    Where the config files go. Default: ~\.config\fzf

.PARAMETER SkipTools
    Only copy files and patch $PROFILE. Same as -PackageManager none.

.EXAMPLE
    .\Install-FzfConfig.ps1
.EXAMPLE
    .\Install-FzfConfig.ps1 -PackageManager scoop
.EXAMPLE
    .\Install-FzfConfig.ps1 -SkipTools -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('auto', 'winget', 'scoop', 'none')]
    [string] $PackageManager = 'auto',

    [string] $Destination = (Join-Path $env:USERPROFILE '.config\fzf'),

    [switch] $SkipTools
)

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot

function Say  { param($m) Write-Host "  $m" -ForegroundColor Gray }
function Head { param($m) Write-Host "`n$m" -ForegroundColor Cyan }
function Good { param($m) Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }


# ---------------------------------------------------------------------------
# 1. Command-line tools
# ---------------------------------------------------------------------------
if ($SkipTools) { $PackageManager = 'none' }

if ($PackageManager -eq 'auto') {
    $PackageManager =
        if (Get-Command winget -ErrorAction SilentlyContinue) { 'winget' }
        elseif (Get-Command scoop -ErrorAction SilentlyContinue) { 'scoop' }
        else { 'none' }
}

# name -> @(executable, winget id, scoop package, why you want it)
$tools = [ordered]@{
    fzf     = @('fzf.exe', 'junegunn.fzf',            'fzf',      'required')
    fd      = @('fd.exe',  'sharkdp.fd',              'fd',       'fast fallback walker + PSFzf Ctrl+T')
    ripgrep = @('rg.exe',  'BurntSushi.ripgrep.MSVC', 'ripgrep',  'ffr content search')
    bat     = @('bat.exe', 'sharkdp.bat',             'bat',      'syntax-highlighted previews')
    eza     = @('eza.exe', 'eza-community.eza',       'eza',      'nicer directory previews (optional)')
}

Head 'Command-line tools'
if ($PackageManager -eq 'none') {
    Warn 'Skipping tool installation.'
    foreach ($t in $tools.GetEnumerator()) {
        $have = [bool](Get-Command $t.Value[0] -ErrorAction SilentlyContinue)
        if ($have) { Good "$($t.Key) present" } else { Warn "$($t.Key) missing -- $($t.Value[3])" }
    }
}
else {
    Say "Using $PackageManager."
    foreach ($t in $tools.GetEnumerator()) {
        $name = $t.Key; $exe, $wingetId, $scoopPkg, $why = $t.Value
        if (Get-Command $exe -ErrorAction SilentlyContinue) { Good "$name already installed"; continue }
        if (-not $PSCmdlet.ShouldProcess($name, "install via $PackageManager")) { continue }
        Say "Installing $name ($why)..."
        try {
            if ($PackageManager -eq 'winget') {
                winget install --id $wingetId --exact --silent --accept-source-agreements --accept-package-agreements | Out-Null
            }
            else {
                scoop install $scoopPkg | Out-Null
            }
            Good "$name installed"
        }
        catch { Warn "$name failed to install: $($_.Exception.Message)" }
    }
    Say 'A new terminal may be needed before newly installed tools appear on PATH.'
}


# ---------------------------------------------------------------------------
# 2. PowerShell modules
# ---------------------------------------------------------------------------
Head 'PowerShell modules'
foreach ($m in 'PSFzf', 'PSEverything') {
    if (Get-Module -ListAvailable -Name $m) { Good "$m already installed"; continue }
    if (-not $PSCmdlet.ShouldProcess($m, 'Install-Module')) { continue }
    try {
        Install-Module $m -Scope CurrentUser -Force -AllowClobber
        Good "$m installed"
    }
    catch { Warn "$m failed: $($_.Exception.Message)" }
}

# PSEverything is only useful while the Everything service is actually running.
if (-not (Get-Process -Name 'Everything' -ErrorAction SilentlyContinue)) {
    Warn 'Everything (voidtools) does not appear to be running. PSEverything needs it for instant C: search -- start it, or the config falls back to fd.'
}
else { Good 'Everything is running' }


# ---------------------------------------------------------------------------
# 3. Config files
# ---------------------------------------------------------------------------
Head "Config files -> $Destination"
if (-not (Test-Path -LiteralPath $Destination)) {
    if ($PSCmdlet.ShouldProcess($Destination, 'create directory')) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
}

foreach ($f in 'fzf.conf', 'PSFzf.config.ps1', 'fzf-preview.cmd', 'fzf-action.cmd') {
    $from = Join-Path $src $f
    $to = Join-Path $Destination $f
    if (-not (Test-Path -LiteralPath $from)) { Warn "missing from source: $f"; continue }

    # Never silently clobber a fzf.conf the user has since edited.
    if ($f -eq 'fzf.conf' -and (Test-Path -LiteralPath $to)) {
        if ((Get-FileHash $from).Hash -ne (Get-FileHash $to).Hash) {
            $bak = "$to.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
            if ($PSCmdlet.ShouldProcess($to, "back up to $(Split-Path $bak -Leaf)")) {
                Copy-Item $to $bak
                Warn "your existing fzf.conf was backed up to $(Split-Path $bak -Leaf)"
            }
        }
    }
    if ($PSCmdlet.ShouldProcess($to, 'copy')) {
        Copy-Item -LiteralPath $from -Destination $to -Force
        Good $f
    }
}


# ---------------------------------------------------------------------------
# 4. $PROFILE hook
# ---------------------------------------------------------------------------
Head "PowerShell profile -> $PROFILE"

$begin = '# >>> fzf config >>>'
$end = '# <<< fzf config <<<'
$block = @"
$begin
# Loaded last on purpose: it needs to see atuin's and zoxide's key bindings.
. "$(Join-Path $Destination 'PSFzf.config.ps1')"
$end
"@

$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path -LiteralPath $profileDir)) {
    if ($PSCmdlet.ShouldProcess($profileDir, 'create directory')) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
}

$existing = if (Test-Path -LiteralPath $PROFILE) { Get-Content -LiteralPath $PROFILE -Raw } else { '' }

if ($existing -match [regex]::Escape($begin)) {
    $pattern = '(?s)' + [regex]::Escape($begin) + '.*?' + [regex]::Escape($end)
    $new = [regex]::Replace($existing, $pattern, [System.Text.RegularExpressions.MatchEvaluator] { param($m) $block })
    $action = 'update existing fzf block'
}
else {
    $new = ($existing.TrimEnd() + "`r`n`r`n" + $block + "`r`n").TrimStart()
    $action = 'append fzf block'
}

if ($existing -ne $new) {
    if (Test-Path -LiteralPath $PROFILE) {
        $bak = "$PROFILE.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
        if ($PSCmdlet.ShouldProcess($PROFILE, "back up to $(Split-Path $bak -Leaf)")) { Copy-Item $PROFILE $bak }
    }
    if ($PSCmdlet.ShouldProcess($PROFILE, $action)) {
        Set-Content -LiteralPath $PROFILE -Value $new -Encoding UTF8
        Good $action
    }
}
else { Good 'profile already up to date' }

# Sanity-check ordering: atuin/zoxide must init before our block.
if ($new -match 'atuin' -and ($new.IndexOf('atuin') -gt $new.IndexOf($begin))) {
    Warn 'atuin initialises AFTER the fzf block in your profile. Move the atuin line above it, or atuin will take Ctrl+R back after this config runs (which is fine) -- but Alt+R may be left unbound.'
}
if ($new -notmatch 'atuin')  { Say 'No atuin line found in $PROFILE -- Ctrl+R will stay PSReadLine''s.' }
if ($new -notmatch 'zoxide') { Say 'No zoxide line found in $PROFILE -- Alt+C and `zf` will be inactive.' }


# ---------------------------------------------------------------------------
# 5. Verify
# ---------------------------------------------------------------------------
Head 'Verifying'
if ($WhatIfPreference) {
    Say '-WhatIf: nothing was changed, skipping verification.'
}
else {
    . (Join-Path $Destination 'PSFzf.config.ps1')
    Test-FzfSetup
    Write-Host "Done. Open a new terminal, then run " -NoNewline
    Write-Host "fzf?" -ForegroundColor Yellow -NoNewline
    Write-Host " for the cheat sheet."
}
