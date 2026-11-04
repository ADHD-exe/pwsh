# Verify the bundled PowerShell 7 theme uses valid PSReadLine color names.
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Run this test in PowerShell 7.' }
if (-not (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue)) {
    Import-Module PSReadLine -ErrorAction Stop
}

$root = Split-Path -Parent $PSScriptRoot
$theme = Join-Path $root 'settings\themes\powershell-7.6.9 - Night City.ps1'
$warnings = @(& $theme 3>&1)
$themeWarnings = @($warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] -and $_.Message -like 'Night City:*' })

if ($themeWarnings.Count) {
    $themeWarnings | ForEach-Object { Write-Error $_.Message }
    exit 1
}

Write-Host 'all Night City PSReadLine color names are accepted' -ForegroundColor Green
