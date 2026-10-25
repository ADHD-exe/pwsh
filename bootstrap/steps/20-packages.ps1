# =============================================================================
# 20-packages.ps1 - winget packages (by tier) and global npm packages
# =============================================================================

function Get-SelectedPackages {
    param([string[]]$Tier, [switch]$IncludeRisky, [switch]$NoAdmin)

    $all = (Import-PowerShellDataFile -LiteralPath (Join-Path $script:ManifestDir 'packages.psd1')).Packages

    foreach ($p in $all) {
        if ($Tier -notcontains $p.Tier) { continue }

        if ($p.Risky -and -not $IncludeRisky) {
            Add-Result -Step 'packages' -Item $p.Name -Status 'Skipped' -Detail 'risky package - pass -IncludeRisky to install'
            Write-Dim "$($p.Name): skipped (risky, needs -IncludeRisky)"
            continue
        }

        if ($p.Admin -and $NoAdmin) {
            Add-Result -Step 'packages' -Item $p.Name -Status 'Skipped' -Detail 'machine-wide installer, -NoAdmin was given'
            Write-Dim "$($p.Name): skipped (-NoAdmin)"
            continue
        }

        $p
    }
}

function Invoke-PackageStep {
    [CmdletBinding(SupportsShouldProcess)]
    param([string[]]$Tier, [switch]$IncludeRisky, [switch]$NoAdmin, [switch]$VerifyOnly)

    $packages = @(Get-SelectedPackages -Tier $Tier -IncludeRisky:$IncludeRisky -NoAdmin:$NoAdmin)
    Write-Info ("{0} package(s) selected from tier(s): {1}" -f $packages.Count, ($Tier -join ', '))

    $uac = @($packages | Where-Object { $_.Admin -and -not (Test-IsAdmin) })
    if ($uac.Count -gt 0 -and -not $VerifyOnly) {
        Write-Info ("These are machine-wide installers and will ask for UAC approval: {0}" -f (($uac | ForEach-Object { $_.Name }) -join ', '))
    }

    foreach ($pkg in $packages) {

        if ($VerifyOnly) {
            if (Test-WingetId -Package $pkg) {
                Write-Ok "$($pkg.Id) exists in the $(if ($pkg.Source) { $pkg.Source } else { 'winget' }) source"
                Add-Result -Step 'verify-ids' -Item $pkg.Name -Status 'Ok' -Detail $pkg.Id
            }
            else {
                Write-Bad "$($pkg.Id) NOT FOUND - fix the id in bootstrap\manifests\packages.psd1"
                Add-Result -Step 'verify-ids' -Item $pkg.Name -Status 'Failed' -Detail "id not found: $($pkg.Id)"
            }
            continue
        }

        [void](Install-WingetPackage -Package $pkg)
    }
}

function Invoke-NpmGlobalStep {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $npm = (Import-PowerShellDataFile -LiteralPath (Join-Path $script:ManifestDir 'packages.psd1')).NpmGlobals

    if (-not (Test-CommandExists 'npm')) {
        Add-Result -Step 'npm' -Item '(all)' -Status 'Skipped' -Detail 'npm not available - open a new terminal after Node installs and re-run'
        Write-Warn 'npm not found; skipping global npm packages.'
        return
    }

    foreach ($pkg in $npm) {
        if (Test-CommandExists $pkg.Command) {
            Write-Ok "$($pkg.Name) already installed"
            Add-Result -Step 'npm' -Item $pkg.Name -Status 'Skipped' -Detail 'already installed'
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($pkg.Name, 'npm install -g')) { continue }

        Write-Info "npm install -g $($pkg.Name) ..."
        $out = & npm install -g $pkg.Name 2>&1
        Write-LogLine 'NPM' ("{0} exit {1}`n{2}" -f $pkg.Name, $LASTEXITCODE, ($out | Out-String))
        $npmExit = $LASTEXITCODE
        Update-SessionPath
        # npm's global bin folder is often not on PATH in the current session.
        $npmPrefix = (& npm prefix -g 2>$null | Select-Object -First 1)
        if ($npmPrefix -and (Test-Path -LiteralPath $npmPrefix) -and ($env:Path -notlike "*$npmPrefix*")) { $env:Path = "$env:Path;$npmPrefix" }

        if (Test-CommandExists $pkg.Command) {
            Write-Ok "$($pkg.Name) installed"
            Add-Result -Step 'npm' -Item $pkg.Name -Status 'Ok' -Detail 'installed'
        }
        else {
            $why = ($out | Out-String).Trim() -split "`r?`n" | Where-Object { $_ -match 'ERR|error|404|not found' } | Select-Object -First 2
            if ($npmExit -ne 0) { Write-Warn "npm exited $npmExit for $($pkg.Name): $($why -join ' | ')" }
            Write-Bad "$($pkg.Name) not found after install - try: npm install -g $($pkg.Name)"
            Add-Result -Step 'npm' -Item $pkg.Name -Status 'Failed' -Detail "npm install -g $($pkg.Name)"
        }
    }
}
