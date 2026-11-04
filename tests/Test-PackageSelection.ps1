# Offline tests for tier selection of packages.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'bootstrap\lib\Common.ps1')
$script:ManifestDir = Join-Path $root 'bootstrap\manifests'
. (Join-Path $root 'bootstrap\steps\20-packages.ps1')

$failures = 0
function Assert { param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host "  pass  $Name" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Name" -ForegroundColor Red; $script:failures++ }
}

$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:ManifestDir 'packages.psd1')
$riskyApps = @($manifest.Packages | Where-Object { $_.Tier -eq 'Apps' -and $_.Risky })
$default = @(Get-SelectedPackages -Tier @('Core', 'Shell', 'Tools'))
$withApps = @(Get-SelectedPackages -Tier @('Core', 'Shell', 'Tools', 'Apps'))
$appsOnly = @(Get-SelectedPackages -Tier @('Apps'))

Assert ($riskyApps.Count -eq 4) 'manifest has the four flagged Apps packages'
Assert (@($default | Where-Object Risky).Count -eq 0) 'default tiers do not include Apps'
Assert (@($withApps | Where-Object Risky).Count -eq $riskyApps.Count) 'selecting Apps includes every flagged package'
Assert (@($appsOnly | Where-Object Risky).Count -eq $riskyApps.Count) 'Apps-only selection includes every flagged package'
Assert (@($withApps | Where-Object { $_.Name -in @('simplewall', 'Winaero Tweaker', 'DISMTools', 'NVCleanstall') }).Count -eq 4) 'all four requested apps are selected'

if ($failures) { Write-Host "`n$failures failure(s)" -ForegroundColor Red; exit 1 }
Write-Host "`nall passed" -ForegroundColor Green
