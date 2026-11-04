<#
.SYNOPSIS
    Removes the old, duplicated pre-installer files from Documents\PowerShell.

.DESCRIPTION
    Since the installer, the profile lives in the clone (~\.pwsh). Documents\PowerShell
    should hold only the small stub profile, the .local.ps1 file and installed modules.
    Anything else there is a dead copy of what the clone already provides.

    Dry run by default: nothing is changed unless -Apply is given. With -Apply every
    item is first zipped into %LOCALAPPDATA%\RabbitBootstrap\legacy-backup-<time>.zip.

.EXAMPLE
    .\Remove-LegacyPowerShell.ps1            # show what would go
    .\Remove-LegacyPowerShell.ps1 -Apply     # back up, then remove
#>
[CmdletBinding()]
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$docs = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell'
if (-not (Test-Path -LiteralPath $docs)) { Write-Host "Nothing to do: $docs not found."; return }

$targets = [System.Collections.Generic.List[string]]::new()
function Add-Target([string]$RelativePath) {
    $p = Join-Path $docs $RelativePath
    if (Test-Path -LiteralPath $p) { $targets.Add($p) }
}

# Dead copies of what the clone already provides, and old drafts
foreach ($name in 'settings', 'aliases-functions-keybinds', 'install.ps1', 'rough-draft-install.ps1',
                  'draft-bootstrap scrip.txt', 'README.md', 'LICENSE', '.gitignore') { Add-Target $name }
Get-ChildItem -LiteralPath $docs -Filter 'Microsoft.PowerShell_profile.ps1.bak-*' -File -ErrorAction SilentlyContinue |
    ForEach-Object { $targets.Add($_.FullName) }

# Modules that are not usable modules: source checkouts and a superseded config folder
$mods = Join-Path $docs 'Modules'
foreach ($name in 'dbatools-development', 'fzf-config') { Add-Target "Modules\$name" }
$psrl = Join-Path $mods 'PSReadLine'
if ((Test-Path -LiteralPath (Join-Path $psrl 'MockPSConsole')) -and
    -not (Get-ChildItem -LiteralPath $psrl -Filter 'PSReadLine.psd1' -File -ErrorAction SilentlyContinue)) {
    $targets.Add($psrl)   # source tree (tests, build tools), not an installed module
}

if (-not $targets.Count) { Write-Host 'Nothing to remove.'; return }

$total = 0
foreach ($t in $targets) {
    $size = (Get-ChildItem -LiteralPath $t -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if (-not $size) { $size = (Get-Item -LiteralPath $t -Force).Length }
    $total += $size
    '{0,8:N1} MB  {1}' -f ($size / 1MB), $t.Substring($docs.Length + 1)
}
'{0,8:N1} MB  total' -f ($total / 1MB)

$mas = Join-Path $mods 'Microsoft-Activation-Scripts-master'
if (Test-Path -LiteralPath $mas) {
    Write-Host "`nLeft alone: Modules\Microsoft-Activation-Scripts-master is not a PowerShell module. Move or delete it yourself." -ForegroundColor Yellow
}

if (-not $Apply) { Write-Host "`nDry run. Re-run with -Apply to back up and remove." -ForegroundColor Cyan; return }

$backupDir = Join-Path $env:LOCALAPPDATA 'RabbitBootstrap'
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$zip = Join-Path $backupDir ("legacy-backup-{0:yyyyMMdd-HHmmss}.zip" -f (Get-Date))
Compress-Archive -LiteralPath $targets -DestinationPath $zip -CompressionLevel Optimal
if (-not (Test-Path -LiteralPath $zip)) { throw 'Backup zip was not created; nothing removed.' }
Write-Host "`nBackup: $zip"

foreach ($t in $targets) { Remove-Item -LiteralPath $t -Recurse -Force }
Write-Host 'Removed. Open a new pwsh window to confirm the profile loads.' -ForegroundColor Green
