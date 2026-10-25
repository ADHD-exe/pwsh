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
          * -SkipIfRunning <process>   -> app rewrites its config on exit. NOT skipped any more: the file is backed up
                                          and replaced anyway (the config step closes the app first and reopens it)
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

    # An app that is still running when we get here (it would not close) may overwrite the new file on exit.
    # The original is backed up and the replacement goes in regardless; just say so.
    $stillRunning = $SkipIfRunning -and (Get-Process -Name $SkipIfRunning -ErrorAction SilentlyContinue)

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
    if ($stillRunning) {
        Write-Warn "$SkipIfRunning is still running and may rewrite $label when it exits - close it, then re-run if the settings revert."
        Add-Result -Step $Step -Item $label -Status 'Warn' -Detail "deployed while $SkipIfRunning was running (may be overwritten on exit)"
    }
    else { Add-Result -Step $Step -Item $label -Status 'Ok' -Detail 'deployed' }
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

function Stop-AppForConfig {
    <#
        Closes an app that rewrites its config on exit so the replacement file is not overwritten by it.
        Graceful only (CloseMainWindow / Everything -quit): nothing is ever killed, so no unsaved work is lost.
        Returns a record for Start-AppAfterConfig, or $null when the app was not running or would not close.
    #>
    param(
        [Parameter(Mandatory)][string]$ProcessName,
        [string[]]$QuitArguments,
        [string[]]$StartArguments,
        [int]$TimeoutSeconds = 15
    )

    $procs = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return $null }

    $exe = ($procs | Where-Object { $_.Path } | Select-Object -First 1).Path
    if (-not $exe) { return $null }

    Write-Info "$ProcessName is running - closing it so its config can be replaced (it is reopened afterwards)."

    try {
        if ($QuitArguments) { Start-Process -FilePath $exe -ArgumentList $QuitArguments -ErrorAction Stop | Out-Null }
        else { foreach ($p in $procs) { [void]$p.CloseMainWindow() } }

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline -and (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 300 }
    }
    catch { Write-Dim "Could not ask $ProcessName to close: $($_.Exception.Message)" }

    if (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) {
        Write-Warn "$ProcessName did not close (a save prompt may be open). Its config is replaced anyway; close it to apply."
        return $null
    }

    return [pscustomobject]@{ Exe = $exe; StartArguments = $StartArguments; Name = $ProcessName }
}

function Start-AppAfterConfig {
    param($Record)

    if (-not $Record) { return }

    try {
        if ($Record.StartArguments) { Start-Process -FilePath $Record.Exe -ArgumentList $Record.StartArguments -ErrorAction Stop | Out-Null }
        else { Start-Process -FilePath $Record.Exe -ErrorAction Stop | Out-Null }
        Write-Ok "$($Record.Name) reopened"
    }
    catch { Write-Warn "Could not reopen $($Record.Name): $($_.Exception.Message)" }
}

function Test-ConfigWouldChange {
    <# $true when deploying Source to Target (after token replacement) would change the target file. #>
    param([string]$Source, [string]$Target, [hashtable]$Tokens)

    if (-not (Test-Path -LiteralPath $Source)) { return $false }
    if (-not (Test-Path -LiteralPath $Target)) { return $true }

    $want = Get-Content -LiteralPath $Source -Raw
    if ($Tokens) { foreach ($key in $Tokens.Keys) { $want = $want.Replace($key, [string]$Tokens[$key]) } }
    $have = Get-Content -LiteralPath $Target -Raw

    return (($have -replace "`r`n", "`n").TrimEnd() -ne ($want -replace "`r`n", "`n").TrimEnd())
}
