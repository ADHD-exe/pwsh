<#
.SYNOPSIS
    Installs and configures the PowerShell / terminal environment in this repo.

.DESCRIPTION
    Normally started by ..\install.ps1. Every step is idempotent: re-running
    repairs what is missing and leaves what is already right alone. Existing
    configuration is backed up (NAME.bak-yyyyMMdd-HHmmss) before it is replaced.

    Steps, in order:  prereqs, core, repo, git, packages, npm, modules, fonts,
                      profile, terminal, configs, path, verify

.PARAMETER Tier
    Package tiers to install. Default: Core, Shell.  Tools = Notepad++, AutoHotkey,
    Everything, CMake, Python ...  Apps = the optional desktop apps.

.PARAMETER Only
    Run only the named steps (e.g. -Only Git, or -Only Path).

.PARAMETER PathScope
    Machine (default, system PATH, needs a one-time UAC prompt) or User.

.PARAMETER GitUser
    GitHub username. If omitted you are asked once.

.PARAMETER VerifyOnly
    Check every winget id in the manifest exists; install nothing.

.EXAMPLE
    .\Install-Environment.ps1 -WhatIf
.EXAMPLE
    .\Install-Environment.ps1 -Tier Core,Shell,Tools
.EXAMPLE
    .\Install-Environment.ps1 -Only Git
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Validated below instead of with ValidateSet: `pwsh -File x.ps1 -Tier Core,Shell`
    # delivers "Core,Shell" as ONE string, which ValidateSet would reject.
    [string[]]$Tier = @('Core', 'Shell'),
    [string[]]$Only,

    [ValidateSet('Machine', 'User')]
    [string]$PathScope = 'Machine',

    [string]$GitUser,
    [string]$InstallDir = (Join-Path $HOME '.pwsh'),
    [string]$RepoUrl    = 'https://github.com/ADHD-exe/pwsh.git',
    [string]$Branch     = 'main',
    [string]$SourceRoot,

    [switch]$VerifyOnly,
    [switch]$IncludeRisky,
    [switch]$NoAdmin,
    [switch]$Force,
    [switch]$Unattended,
    [switch]$SkipSsh,
    [switch]$Elevate,

    # internal -------------------------------------------------------------
    [switch]$Relaunched,
    [switch]$AdminPathOnly,
    [string]$ResultFile
)

$ErrorActionPreference = 'Stop'

$validTiers = 'Core', 'Shell', 'Tools', 'Apps'
$validSteps = 'prereqs', 'core', 'repo', 'git', 'packages', 'npm', 'modules', 'fonts', 'profile', 'terminal', 'configs', 'path', 'verify'

$Tier = @($Tier | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })
if ($Only) { $Only = @($Only | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ } | ForEach-Object { $_.ToLower() }) }

foreach ($t in $Tier) { if ($validTiers -notcontains $t) { throw "Unknown tier '$t'. Valid tiers: $($validTiers -join ', ')" } }
foreach ($o in @($Only)) { if ($o -and ($validSteps -notcontains $o)) { throw "Unknown step '$o'. Valid steps: $($validSteps -join ', ')" } }

$script:OrchestratorPath = $PSCommandPath
$script:BootstrapDir     = $PSScriptRoot
$script:ManifestDir      = Join-Path $PSScriptRoot 'manifests'
if (-not $SourceRoot) { $SourceRoot = Split-Path -Parent $PSScriptRoot }

foreach ($f in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'lib') -Filter *.ps1 | Sort-Object Name) { . $f.FullName }
foreach ($f in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'steps') -Filter *.ps1 | Sort-Object Name) { . $f.FullName }

$stateDir = Join-Path $env:LOCALAPPDATA 'RabbitBootstrap'
Initialize-Log -Directory (Join-Path $stateDir 'logs')

function Test-RunStep { param([string]$Key) return (-not $Only) -or ($Only -contains $Key) }

# --------------------------------------------------------------------------
# Elevated child: system PATH only, results handed back through a JSON file.
# --------------------------------------------------------------------------
if ($AdminPathOnly) {
    try {
        if (-not (Test-IsAdmin)) { throw 'The elevated window is not elevated.' }
        Write-Host 'Updating the system PATH ...' -ForegroundColor Cyan
        Invoke-PathStep -Scope $PathScope -BackupDirectory (Join-Path $stateDir 'backups') -Unattended
    }
    catch { Add-Result -Step 'path' -Item '(system PATH)' -Status 'Failed' -Detail $_.Exception.Message }

    if ($ResultFile) { $script:Results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ResultFile -Encoding UTF8 }
    Start-Sleep -Seconds 2
    exit $(if (Get-FailedCount) { 1 } else { 0 })
}

# --------------------------------------------------------------------------
# Main run
# --------------------------------------------------------------------------
Write-Host ''
Write-Host 'pwsh environment installer' -ForegroundColor Cyan
Write-Host ("  tiers: {0}   path scope: {1}   {2}" -f ($Tier -join ', '), $PathScope, $(if ($WhatIfPreference) { '(dry run: nothing will change)' } else { '' }))

$tiersWithCore = @('Core') + @($Tier | Where-Object { $_ -ne 'Core' })

try {
    if (Test-RunStep 'prereqs') { Invoke-Step -Name 'Prerequisites' -Required -Action { Invoke-PrereqStep } }

    if ($VerifyOnly) {
        Invoke-Step -Name 'Verify winget ids' -Action { Invoke-PackageStep -Tier $tiersWithCore -IncludeRisky:$IncludeRisky -VerifyOnly }
        Write-Summary
        exit $(if (Get-FailedCount) { 1 } else { 0 })
    }

    if (Test-RunStep 'core') {
        Invoke-Step -Name 'Core packages (git, PowerShell 7, Windows Terminal, Node)' -Required -Action {
            Invoke-PackageStep -Tier @('Core') -IncludeRisky:$IncludeRisky -NoAdmin:$NoAdmin
        }
    }

    # ---- hand over to PowerShell 7 -----------------------------------------
    if ($PSVersionTable.PSEdition -ne 'Core' -and -not $Relaunched -and -not $WhatIfPreference) {
        Update-SessionPath
        $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $pwsh) { $pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe' }

        if (-not (Test-Path -LiteralPath $pwsh)) { throw 'PowerShell 7 was installed but cannot be found yet. Open a new terminal and run the installer again.' }

        Write-Step 'Continuing in PowerShell 7'
        $childArgs = New-Object System.Collections.Generic.List[string]
        foreach ($k in $PSBoundParameters.Keys) {
            if ($k -in 'SourceRoot', 'Relaunched') { continue }
            $v = $PSBoundParameters[$k]
            if ($v -is [switch]) { if ($v.IsPresent) { $childArgs.Add("-$k") } }
            elseif ($v -is [array]) { $childArgs.Add("-$k"); $childArgs.Add(($v -join ',')) }
            else { $childArgs.Add("-$k"); $childArgs.Add([string]$v) }
        }
        $childArgs.Add('-SourceRoot'); $childArgs.Add($SourceRoot)
        $childArgs.Add('-Relaunched')

        & $pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @childArgs
        exit $LASTEXITCODE
    }

    # ---- repo gets its permanent home before anything is deployed from it ---
    $script:RepoRoot = $SourceRoot

    if (Test-RunStep 'repo') {
        Invoke-Step -Name "Repository -> $InstallDir" -Required -Action {
            $r = @(Invoke-RepoStep -InstallDir $InstallDir -SourceRoot $SourceRoot -RepoUrl $RepoUrl -Branch $Branch)
            $script:RepoRoot = [string]$r[-1]
        }
    }
    elseif (Test-Path -LiteralPath (Join-Path $InstallDir 'profile')) { $script:RepoRoot = $InstallDir }

    # ---- interactive part first, so the long installs can run unattended ----
    if (Test-RunStep 'git') { Invoke-Step -Name 'Git identity and GitHub SSH' -Action { Invoke-GitStep -GitUser $GitUser -Unattended:$Unattended -SkipSsh:$SkipSsh } }

    if (Test-RunStep 'packages') {
        $rest = @($Tier | Where-Object { $_ -ne 'Core' })
        if ($rest.Count -gt 0) {
            Invoke-Step -Name ("Packages ({0})" -f ($rest -join ', ')) -Action { Invoke-PackageStep -Tier $rest -IncludeRisky:$IncludeRisky -NoAdmin:$NoAdmin }
        }
    }

    if ((Test-RunStep 'npm') -and ($Tier -contains 'Shell')) { Invoke-Step -Name 'Global npm packages' -Action { Invoke-NpmGlobalStep } }

    if (Test-RunStep 'modules')  { Invoke-Step -Name 'PowerShell modules'            -Action { Invoke-ModuleStep } }
    if (Test-RunStep 'fonts')    { Invoke-Step -Name 'Fonts'                         -Action { Invoke-FontStep -RepoRoot $script:RepoRoot } }
    if (Test-RunStep 'profile')  { Invoke-Step -Name 'PowerShell profile'            -Action { Invoke-ProfileStep -InstallDir $script:RepoRoot } }
    if (Test-RunStep 'terminal') { Invoke-Step -Name 'Windows Terminal settings'     -Action { Invoke-TerminalStep -RepoRoot $script:RepoRoot -Force:$Force } }
    if (Test-RunStep 'configs')  { Invoke-Step -Name 'Application configs'          -Action { Invoke-ConfigStep -RepoRoot $script:RepoRoot -Force:$Force } }

    if (Test-RunStep 'path') {
        Invoke-Step -Name "PATH ($PathScope)" -Action {
            Invoke-PathStep -Scope $PathScope -BackupDirectory (Join-Path $stateDir 'backups') -Unattended:$Unattended -Elevate:$Elevate -ChildArguments @('-PathScope', $PathScope)
        }
    }

    if (Test-RunStep 'verify') { Invoke-Step -Name 'Verification' -Action { Invoke-VerifyStep -RepoRoot $script:RepoRoot -Tier $tiersWithCore } }
}
catch {
    Write-Bad $_.Exception.Message
    Add-Result -Step 'installer' -Item '(run)' -Status 'Failed' -Detail $_.Exception.Message
}

Write-Summary

Write-Host ''
Write-Host 'Next: open a NEW Windows Terminal window (PATH, fonts and the profile are picked up on start).' -ForegroundColor Cyan
Write-Host "Re-run any time to repair or update. Backups sit next to each replaced file as NAME.bak-<timestamp>." -ForegroundColor DarkGray

exit $(if (Get-FailedCount) { 1 } else { 0 })
