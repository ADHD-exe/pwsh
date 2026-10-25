# =============================================================================
# 70-terminal.ps1 - merge settings\settings.json into Windows Terminal
# =============================================================================

function Invoke-TerminalStep {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$RepoRoot, [switch]$Force)

    $templatePath = Join-Path $RepoRoot 'settings\settings.json'

    if ($PSVersionTable.PSEdition -ne 'Core') {
        if ($WhatIfPreference) { Write-Info 'Dry run under Windows PowerShell: the real run merges the Terminal settings in PowerShell 7.'; return }
        throw 'The Terminal merge needs PowerShell 7 (Terminal writes // comments that 5.1 cannot parse).'
    }
    if (-not (Test-JsonFile -Path $templatePath -AllowComments)) { throw "settings\settings.json in the repo is not valid JSON: $templatePath" }

    $template = ConvertTo-PlainJsonObject (Get-Content -LiteralPath $templatePath -Raw)

    $wtInstalled = (Test-CommandExists 'wt') -or [bool](Get-AppxPackage -Name 'Microsoft.WindowsTerminal*' -ErrorAction SilentlyContinue)
    $targets = @(Get-WindowsTerminalTargets | Where-Object { (Test-Path -LiteralPath $_.Directory) -or ($_.CanCreate -and $wtInstalled) })

    if ($targets.Count -eq 0) {
        Write-Warn 'Windows Terminal is not installed (or has never been started), so there is nothing to configure yet.'
        Add-Result -Step 'terminal' -Item 'settings.json' -Status 'Warn' -Detail 'Terminal not installed - re-run after installing it'
        return
    }

    foreach ($t in $targets) {
        $label = "Windows Terminal - $($t.Kind)"

        $machine = $null
        $existingRaw = $null

        if (Test-Path -LiteralPath $t.Settings) {
            $existingRaw = Get-Content -LiteralPath $t.Settings -Raw

            try { $machine = ConvertTo-PlainJsonObject $existingRaw }
            catch {
                Write-Warn "$label : existing settings.json could not be parsed ($($_.Exception.Message))."
                if (-not $Force) {
                    Add-Result -Step 'terminal' -Item $label -Status 'Warn' -Detail 'existing file unparsable - left untouched (use -Force to replace it; a backup is made)'
                    continue
                }
                Write-Info '-Force given: the unreadable file will be backed up and replaced.'
            }
        }

        $merged = if ($machine) { Merge-TerminalSettings -Machine $machine -Template $template } else { $template }

        $problems = @(Test-TerminalSettings -Settings $merged)
        foreach ($p in $problems) { Write-Warn "$label : $p" }

        $mergedJson = $merged | ConvertTo-Json -Depth 32

        if ($machine) {
            $currentCompact = $machine | ConvertTo-Json -Depth 32 -Compress
            $mergedCompact  = $merged  | ConvertTo-Json -Depth 32 -Compress

            if ($currentCompact -eq $mergedCompact) {
                Write-Ok "$label already current"
                Add-Result -Step 'terminal' -Item $label -Status 'Skipped' -Detail 'already current'
                continue
            }
        }

        if (-not $PSCmdlet.ShouldProcess($t.Settings, 'merge Windows Terminal settings')) { continue }

        New-Item -ItemType Directory -Path $t.Directory -Force | Out-Null

        if ($existingRaw) {
            $bak = Backup-File -Path $t.Settings
            Write-Info "Backed up -> $bak"
        }

        # Write beside the target and swap, so a crash cannot leave half a file for Terminal to load.
        $tmp = "$($t.Settings).new"
        Write-Utf8NoBom -Path $tmp -Content $mergedJson

        if (-not (Test-JsonFile -Path $tmp)) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            Write-Bad "$label : merged file failed validation - nothing was changed"
            Add-Result -Step 'terminal' -Item $label -Status 'Failed' -Detail 'merged JSON invalid, original untouched'
            continue
        }

        Move-Item -LiteralPath $tmp -Destination $t.Settings -Force
        Write-Ok "$label merged -> $($t.Settings)"
        Add-Result -Step 'terminal' -Item $label -Status 'Ok' -Detail $(if ($problems.Count) { "merged with $($problems.Count) warning(s)" } else { 'merged' })
    }

    Write-Dim 'Windows Terminal reloads settings.json on save; close all windows once if the font looks wrong.'
}
