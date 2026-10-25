# =============================================================================
# Packages.ps1 - detect / install / verify winget packages
#
# Detection order (cheapest first), so re-runs do not reinstall anything:
#   1. command on PATH            2. known install path
#   3. appx package (Store apps)  4. `winget list --id <id> --exact`
# After an install the same checks run again - success is *verified*, never
# assumed from winget's exit code.
# =============================================================================

function Get-WingetExe { return (Get-Command winget -ErrorAction SilentlyContinue) }

function Test-WingetUsable {
    <# `winget --version` can exist as a stub on a fresh Windows 10 until App Installer updates. #>
    $w = Get-WingetExe
    if (-not $w) { return $false }

    try {
        $v = & winget --version 2>$null
        return ($LASTEXITCODE -eq 0 -and $v)
    }
    catch { return $false }
}

function Test-PackagePresent {
    param([Parameter(Mandatory)]$Package, [switch]$SkipWingetList)

    if ($Package.Command -and (Test-CommandExists $Package.Command)) { return 'command on PATH' }

    foreach ($p in @($Package.Paths)) {
        if ($p -and (Test-Path -LiteralPath (Expand-Vars $p))) { return 'known path' }
    }

    if ($Package.Appx -and (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        if (Get-AppxPackage -Name $Package.Appx -ErrorAction SilentlyContinue) { return 'appx' }
    }

    if (-not $SkipWingetList -and (Test-WingetUsable)) {
        $src = 'winget'
        if ($Package.Source) { $src = $Package.Source }

        & winget list --id $Package.Id --exact --source $src --disable-interactivity --accept-source-agreements 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return 'winget list' }
    }

    return $null
}

function Install-WingetPackage {
    <#
        Returns a status string: Present | Installed | Failed | DryRun
        winget exit codes worth knowing:
          0              success
          0x8A150011     no applicable update / already installed  -> treated as success
          0x8A150014     installer requires elevation              -> reported
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Package)

    $present = Test-PackagePresent -Package $Package
    if ($present) {
        Write-Ok "$($Package.Name) already installed ($present)"
        Add-Result -Step 'packages' -Item $Package.Name -Status 'Skipped' -Detail "already installed ($present)"
        return 'Present'
    }

    if (-not $PSCmdlet.ShouldProcess($Package.Name, "winget install $($Package.Id)")) { return 'DryRun' }

    $src = 'winget'
    if ($Package.Source) { $src = $Package.Source }

    Write-Info "Installing $($Package.Name) ($($Package.Id)) ..."

    $wingetArgs = @(
        'install', '--id', $Package.Id, '--source', $src,
        '--exact', '--silent', '--disable-interactivity',
        '--accept-package-agreements', '--accept-source-agreements'
    )

    # msstore ids are not matched with --exact the same way, and the Store source
    # needs no --silent flag to behave.
    if ($src -eq 'msstore') {
        $wingetArgs = @('install', '--id', $Package.Id, '--source', 'msstore', '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements')
    }

    $output = & winget @wingetArgs 2>&1
    $code   = $LASTEXITCODE
    Write-LogLine 'WINGET' ("{0} exit {1}`n{2}" -f $Package.Id, $code, ($output | Out-String))

    Update-SessionPath

    $verified = Test-PackagePresent -Package $Package -SkipWingetList
    if (-not $verified) { $verified = Test-PackagePresent -Package $Package }

    if ($verified) {
        Write-Ok "$($Package.Name) installed"
        Add-Result -Step 'packages' -Item $Package.Name -Status 'Ok' -Detail 'installed'
        return 'Installed'
    }

    $hint = "winget exit 0x{0:X}" -f $code
    if ($code -eq 0x8A150014 -or $code -eq -1978335212) { $hint += ' (needs elevation - re-run from an elevated pwsh)' }

    Write-Bad "$($Package.Name): not detected after install ($hint)"
    Add-Result -Step 'packages' -Item $Package.Name -Status 'Failed' -Detail $hint
    return 'Failed'
}

function Test-WingetId {
    <# -VerifyOnly: confirm an id exists in the source without installing. #>
    param([Parameter(Mandatory)]$Package)

    $src = 'winget'
    if ($Package.Source) { $src = $Package.Source }

    & winget show --id $Package.Id --exact --source $src --disable-interactivity --accept-source-agreements 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}
