<#
.SYNOPSIS
    Lists and restores the NAME.bak-<timestamp> backups the installer made.

.EXAMPLE
    .\Restore-Backup.ps1                 # list everything that can be restored
.EXAMPLE
    .\Restore-Backup.ps1 -Restore 3      # restore item 3 from the list (the current file is itself backed up first)
.EXAMPLE
    .\Restore-Backup.ps1 -Restore 3 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param([int]$Restore)

$docs = [Environment]::GetFolderPath('MyDocuments')

$roots = @(
    (Join-Path $docs 'PowerShell')
    (Join-Path $docs 'AutoHotkey')
    (Join-Path $HOME '.config')
    (Join-Path $env:APPDATA 'Notepad++')
    (Join-Path $env:APPDATA 'Everything')
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState')
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState')
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal')
) | Where-Object { Test-Path -LiteralPath $_ }

$items = @(
    foreach ($r in $roots) {
        Get-ChildItem -LiteralPath $r -Recurse -File -Filter '*.bak-*' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '\.bak-\d{8}-\d{6}$' }
    }
) | Sort-Object LastWriteTime -Descending

$pathBackups = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'RabbitBootstrap\backups') -File -Filter 'path-*.txt' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending

if (-not $items -and -not $pathBackups) { Write-Host 'No backups found.'; return }

$i = 0
$table = foreach ($f in $items) {
    $i++
    [pscustomobject]@{ '#' = $i; Backup = $f.Name; Original = ($f.FullName -replace '\.bak-\d{8}-\d{6}$', ''); Made = $f.LastWriteTime }
}

if (-not $Restore) {
    $table | Format-Table -AutoSize -Wrap
    if ($pathBackups) {
        Write-Host 'PATH backups (the raw value as it was before the installer changed it):' -ForegroundColor Cyan
        $pathBackups | ForEach-Object { Write-Host "  $($_.FullName)" }
        Write-Host '  To restore one: System Properties > Environment Variables > edit Path, paste the saved line.' -ForegroundColor DarkGray
    }
    Write-Host 'Restore one with:  .\Restore-Backup.ps1 -Restore <#>' -ForegroundColor DarkGray
    return
}

$pick = $table | Where-Object { $_.'#' -eq $Restore }
if (-not $pick) { throw "No backup numbered $Restore. Run without parameters to see the list." }

$src = Join-Path (Split-Path $pick.Original -Parent) $pick.Backup
if ($PSCmdlet.ShouldProcess($pick.Original, "restore from $($pick.Backup)")) {
    if (Test-Path -LiteralPath $pick.Original) {
        $safety = "{0}.bak-{1}" -f $pick.Original, (Get-Date -Format 'yyyyMMdd-HHmmss')
        Copy-Item -LiteralPath $pick.Original -Destination $safety -Force
        Write-Host "Current file saved as $(Split-Path $safety -Leaf)"
    }
    Copy-Item -LiteralPath $src -Destination $pick.Original -Force
    Write-Host "Restored $($pick.Original)" -ForegroundColor Green
}
