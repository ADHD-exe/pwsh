# =============================================================================
# Common.ps1 - logging, result tracking, backups, small helpers
#
# Dot-sourced by Install-Environment.ps1. Must stay compatible with Windows
# PowerShell 5.1 (the installer starts there before PowerShell 7 exists), so:
# no ??, no ?:, no &&/||, no ternary, no -Parallel.
# =============================================================================

$script:Results   = New-Object System.Collections.Generic.List[object]
$script:LogFile   = $null

function Initialize-Log {
    param([string]$Directory)

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $script:LogFile = Join-Path $Directory ("install-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Add-Content -LiteralPath $script:LogFile -Value ("# {0}  PowerShell {1}  user {2}" -f (Get-Date -Format 's'), $PSVersionTable.PSVersion, $env:USERNAME)
}

function Write-LogLine {
    param([string]$Level, [string]$Message)

    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value ("{0} [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message)
    }
}

function Write-Step { param([string]$Message) Write-Host ""; Write-Host "== $Message ==" -ForegroundColor Cyan;  Write-LogLine 'STEP' $Message }
function Write-Ok   { param([string]$Message) Write-Host "OK   $Message" -ForegroundColor Green;                Write-LogLine 'OK'   $Message }
function Write-Info { param([string]$Message) Write-Host "..   $Message" -ForegroundColor Yellow;              Write-LogLine 'INFO' $Message }
function Write-Warn { param([string]$Message) Write-Host "WARN $Message" -ForegroundColor DarkYellow;          Write-LogLine 'WARN' $Message }
function Write-Bad  { param([string]$Message) Write-Host "FAIL $Message" -ForegroundColor Red;                 Write-LogLine 'FAIL' $Message }
function Write-Dim  { param([string]$Message) Write-Host "     $Message" -ForegroundColor DarkGray;            Write-LogLine 'DETAIL' $Message }

function Add-Result {
    <# Records one outcome for the summary table. Status: Ok | Skipped | Warn | Failed #>
    param(
        [string]$Step,
        [string]$Item,
        [ValidateSet('Ok', 'Skipped', 'Warn', 'Failed')][string]$Status,
        [string]$Detail = ''
    )

    $script:Results.Add([pscustomobject]@{ Step = $Step; Item = $Item; Status = $Status; Detail = $Detail })
}

function Write-Summary {
    $groups = $script:Results | Group-Object Status
    Write-Step 'Summary'

    foreach ($name in 'Ok', 'Skipped', 'Warn', 'Failed') {
        $count = @($script:Results | Where-Object { $_.Status -eq $name }).Count
        $color = switch ($name) { 'Ok' { 'Green' } 'Skipped' { 'Gray' } 'Warn' { 'DarkYellow' } 'Failed' { 'Red' } }
        Write-Host ("  {0,-8} {1}" -f $name, $count) -ForegroundColor $color
    }

    $problems = @($script:Results | Where-Object { $_.Status -in 'Warn', 'Failed' })

    if ($problems.Count -gt 0) {
        Write-Host ""
        Write-Host "  Needs attention:" -ForegroundColor Yellow
        foreach ($p in $problems) {
            Write-Host ("   [{0}] {1} / {2}  {3}" -f $p.Status, $p.Step, $p.Item, $p.Detail) -ForegroundColor Yellow
        }
    }

    if ($script:LogFile) {
        Write-Host ""
        Write-Host "  Log: $script:LogFile" -ForegroundColor DarkGray
    }
}

function Get-FailedCount { return @($script:Results | Where-Object { $_.Status -eq 'Failed' }).Count }

function Invoke-Step {
    <#
        Runs one step, turning any thrown error into a Failed result instead of
        aborting the whole run. -Required steps stop the run when they fail,
        because everything after them depends on them.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        [switch]$Required
    )

    Write-Step $Name

    try {
        & $Action
    }
    catch {
        Write-Bad ("{0}: {1}" -f $Name, $_.Exception.Message)
        Write-LogLine 'TRACE' ($_ | Out-String)
        Add-Result -Step $Name -Item '(step)' -Status 'Failed' -Detail $_.Exception.Message

        if ($Required) {
            throw "Required step '$Name' failed - stopping. See the log for details."
        }
    }
}

# ---------------------------------------------------------------------------
# Environment helpers
# ---------------------------------------------------------------------------

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Test-CommandExists {
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

function Expand-Vars {
    param([string]$Text)
    return [Environment]::ExpandEnvironmentVariables($Text)
}

function Update-SessionPath {
    <# winget drops shims in folders that are not on this process's PATH yet. #>
    $machine = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Get-WindowsInfo {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $build = 0
    if ($os) { [void][int]::TryParse($os.BuildNumber, [ref]$build) }

    [pscustomobject]@{
        Caption   = if ($os) { $os.Caption } else { 'unknown' }
        Build     = $build
        Is64Bit   = [Environment]::Is64BitOperatingSystem
        # Windows 10 1809 (17763) is where winget / App Installer is supported from.
        Supported = ($build -ge 17763)
    }
}

# ---------------------------------------------------------------------------
# Files: hashing, backups, safe writes
# ---------------------------------------------------------------------------

function Get-NormalizedText {
    <# Line-ending-insensitive text, used to compare a repo file to a deployed one. #>
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return ((Get-Content -LiteralPath $Path -Raw) -replace "`r`n", "`n").TrimEnd()
}

function Backup-File {
    <# Copies a file next to itself as NAME.bak-yyyyMMdd-HHmmss and returns the backup path. #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    $backup = "{0}.bak-{1}" -f $Path, (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    return $backup
}

function Write-Utf8NoBom {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)

    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Copy-ConfigFile {
    <#
        Deploys one repo file to its real location.
          * identical content          -> left alone ("already current")
          * different existing content -> backed up first, then replaced
          * -Tokens                    -> {'__USERPROFILE__' = value} replacements
          * -SkipIfRunning <process>   -> app rewrites its config on exit; do not race it
          * -WhatIf / -Confirm are honoured
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [hashtable]$Tokens,
        [string]$SkipIfRunning,
        [string]$Step = 'configs',
        [switch]$Force
    )

    $label = Split-Path $Target -Leaf

    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Bad "Missing from repo: $Source"
        Add-Result -Step $Step -Item $label -Status 'Failed' -Detail 'source file missing from repo'
        return
    }

    if ($SkipIfRunning -and -not $Force -and (Get-Process -Name $SkipIfRunning -ErrorAction SilentlyContinue)) {
        Write-Warn "$SkipIfRunning is running and rewrites $label on exit - skipped. Close it and re-run (or use -Force)."
        Add-Result -Step $Step -Item $label -Status 'Skipped' -Detail "$SkipIfRunning is running"
        return
    }

    $content = (Get-Content -LiteralPath $Source -Raw)

    if ($Tokens) {
        foreach ($key in $Tokens.Keys) { $content = $content.Replace($key, [string]$Tokens[$key]) }
    }

    $existing = $null
    if (Test-Path -LiteralPath $Target) { $existing = Get-Content -LiteralPath $Target -Raw }

    if ($null -ne $existing -and (($existing -replace "`r`n", "`n").TrimEnd() -eq ($content -replace "`r`n", "`n").TrimEnd())) {
        Write-Ok "$label already current"
        Add-Result -Step $Step -Item $label -Status 'Skipped' -Detail 'already current'
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Target, 'Deploy config')) { return }

    if ($null -ne $existing) {
        $backup = Backup-File -Path $Target
        Write-Info "Backed up existing $label -> $(Split-Path $backup -Leaf)"
    }

    Write-Utf8NoBom -Path $Target -Content $content
    Write-Ok "Deployed $label -> $Target"
    Add-Result -Step $Step -Item $label -Status 'Ok' -Detail 'deployed'
}

function Test-JsonFile {
    <# Strict JSON check. Windows Terminal and OpenCode both tolerate comments, so -AllowComments strips // lines first. #>
    param([string]$Path, [switch]$AllowComments)

    try {
        $raw = Get-Content -LiteralPath $Path -Raw
        if ($AllowComments) { $raw = [regex]::Replace($raw, '(?m)^\s*//.*$', '') }
        [void]($raw | ConvertFrom-Json -ErrorAction Stop)
        return $true
    }
    catch {
        return $false
    }
}

function ConvertTo-ArgumentString {
    <#
        Builds ONE command-line string from separate arguments, quoting any that contain
        whitespace or quotes. Start-Process -ArgumentList with an array does NOT quote
        elements, so a path such as C:\Users\Jane Doe\.pwsh\... would be split in two.
    #>
    param([string[]]$Arguments)

    $parts = foreach ($a in $Arguments) {
        if ($null -eq $a -or $a -eq '') { '""'; continue }
        if ($a -notmatch '[\s"]') { $a; continue }

        # double any backslashes that sit right before a quote or the closing quote, escape quotes
        $q = $a -replace '(\\*)"', '$1$1\"'
        $q = $q -replace '(\\+)$', '$1$1'
        '"' + $q + '"'
    }
    return ($parts -join ' ')
}
