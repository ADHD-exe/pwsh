# Offline tests for the profile's `open` and `keybinds` commands.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'profile\aliases-functions-keybinds\functions.ps1')

$failures = 0
function Assert { param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host "  pass  $Name" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Name" -ForegroundColor Red; $script:failures++ }
}

$ahkPath = Join-Path $root 'settings\autohotkey\keybinds.ahk'
$binds = @(Get-RabbitAhkKeybinds -Path $ahkPath)
Assert ($binds.Count -eq 16) 'all current AutoHotkey shortcuts are parsed'
Assert (@($binds | Where-Object { $_.Key -eq 'Win+Enter' -and $_.Does -eq 'PowerShell 7' }).Count -eq 1) 'launcher key and description parsed'
Assert (@($binds | Where-Object { $_.Key -eq 'Win+Alt+Z' -and $_.Group -eq 'Editing shortcuts' }).Count -eq 1) 'modifier order and section parsed'
Assert (@(keybinds -Path $ahkPath -Raw).Count -eq $binds.Count) 'keybinds -Raw returns parsed objects'

$script:lastStarted = $null
function Start-Process {
    param([string]$FilePath, [string]$ArgumentList)
    $script:lastStarted = [pscustomobject]@{ FilePath = $FilePath; ArgumentList = $ArgumentList }
}

$folder = [IO.Path]::GetTempPath()
Open-Explorer -Path $folder
Assert ($script:lastStarted.FilePath -eq 'explorer.exe') 'open launches File Explorer'
Assert ($script:lastStarted.ArgumentList -eq "`"$([IO.Path]::GetFullPath($folder))`"") 'open passes a folder path'

Open-Explorer -Path $PSCommandPath
Assert ($script:lastStarted.ArgumentList -eq "/select,`"$([IO.Path]::GetFullPath($PSCommandPath))`"") 'open selects a file in its folder'

if ($failures) { Write-Host "`n$failures failure(s)" -ForegroundColor Red; exit 1 }
Write-Host "`nall passed" -ForegroundColor Green
