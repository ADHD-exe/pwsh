# =============================================================================
# Packages.ps1 - detect / install / verify winget packages
#
# Detection order (cheapest first), so re-runs do not reinstall anything:
#   1. command on PATH            2. known install path
#   3. appx package (Store apps)  4. this user's winget Links/Packages folders
#   5. `winget list` - ONLY for packages with no command to test, because it
#      also reports installs made under other Windows accounts.
# A package whose command is not usable by this user is (re)installed with --force.
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

function Find-UserWingetCommand {
    <#
        Looks for the package's command in the folders winget uses for THIS user:
          %LOCALAPPDATA%\Microsoft\WinGet\Links      (shims for portable packages)
          %LOCALAPPDATA%\Microsoft\WinGet\Packages   (portable package folders)
        Returns the full path of the exe, or $null.
    #>
    param([Parameter(Mandatory)]$Package)

    if (-not $Package.Command) { return $null }
    $exe = "$($Package.Command).exe"

    $link = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\$exe"
    if (Test-Path -LiteralPath $link) { return $link }

    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $pkgRoot) {
        $dirs = @(Get-ChildItem -LiteralPath $pkgRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($Package.Id)_*" })
        foreach ($d in $dirs) {
            $hit = Get-ChildItem -LiteralPath $d.FullName -Filter $exe -File -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }

    return $null
}

function Add-UserPathForCommand {
    <# A command that exists for this user but is not on PATH: put its folder on this session's PATH and the persistent User PATH. #>
    param([Parameter(Mandatory)][string]$ExePath)

    $dir = Split-Path -Parent $ExePath
    if ($env:PATH -notlike "*$dir*") { $env:PATH = "$env:PATH;$dir" }

    try { [void](Add-PathEntry -Directory $dir -Scope User) }
    catch { Write-LogLine 'PATH' ("could not add {0} to the User PATH: {1}" -f $dir, $_.Exception.Message) }
}

function Test-PackagePresent {
    <#
        "Present" means USABLE BY THE CURRENT USER, not "some user installed it".

        `winget list` can report a package that was installed under another
        Windows account (or in a scope this account cannot run), so it is only
        trusted for packages that ship no command to test. A package with a
        Command must actually resolve for this user: on PATH, at a known path,
        or in this user's winget Links/Packages folders.
    #>
    param([Parameter(Mandatory)]$Package, [switch]$SkipWingetList)

    if ($Package.Command -and (Test-CommandExists $Package.Command)) { return 'command on PATH' }

    foreach ($p in @($Package.Paths)) {
        if ($p -and (Test-Path -LiteralPath (Expand-Vars $p))) { return 'known path' }
    }

    if ($Package.Appx -and (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        if (Get-AppxPackage -Name $Package.Appx -ErrorAction SilentlyContinue) { return 'appx' }
    }

    # This user's own winget folders: installed for this user, merely not on PATH yet.
    $mine = Find-UserWingetCommand -Package $Package
    if ($mine) {
        Add-UserPathForCommand -ExePath $mine
        if (Test-CommandExists $Package.Command) { return 'this user (winget folder, PATH fixed)' }
    }

    # No command to test -> winget's own record is all there is to go on.
    if (-not $Package.Command -and -not $SkipWingetList -and (Test-WingetUsable)) {
        $src = 'winget'
        if ($Package.Source) { $src = $Package.Source }

        & winget list --id $Package.Id --exact --source $src --disable-interactivity --accept-source-agreements 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return 'winget list' }
    }

    return $null
}

function Test-WingetListed {
    <# True when winget's record says the package is installed (for ANY user/scope it can see). #>
    param([Parameter(Mandatory)]$Package)

    if (-not (Test-WingetUsable)) { return $false }

    $src = 'winget'
    if ($Package.Source) { $src = $Package.Source }

    & winget list --id $Package.Id --exact --source $src --disable-interactivity --accept-source-agreements 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Install-WingetPackage {
    <#
        Returns a status string: Present | Installed | Failed | DryRun
        winget exit codes worth knowing:
          0              success
          0x8A150011     no applicable update / already installed  -> treated as success
          0x8A150014     installer requires elevation              -> reported

        Repair path: when winget claims the package is installed but its command
        is NOT usable by this user (typical when it was installed under another
        Windows account), the install is repeated with --force so it is laid
        down for the current user too.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Package)

    $present = Test-PackagePresent -Package $Package
    if ($present) {
        Write-Ok "$($Package.Name) already installed ($present)"
        Add-Result -Step 'packages' -Item $Package.Name -Status 'Skipped' -Detail "already installed ($present)"
        return 'Present'
    }

    $force = $false
    if ($Package.Command -and (Test-WingetListed -Package $Package)) {
        $force = $true
        Write-Warn "$($Package.Name) is registered with winget but '$($Package.Command)' is not usable by this user - reinstalling with --force"
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

    if ($force) { $wingetArgs += '--force' }

    $output = & winget @wingetArgs 2>&1
    $code   = $LASTEXITCODE
    Write-LogLine 'WINGET' ("{0} exit {1}{2}`n{3}" -f $Package.Id, $code, $(if ($force) { ' (--force)' } else { '' }), ($output | Out-String))

    Update-SessionPath

    $verified = Test-PackagePresent -Package $Package -SkipWingetList
    if (-not $verified) { $verified = Test-PackagePresent -Package $Package }

    if ($verified) {
        $how = if ($force) { 'reinstalled for this user (--force)' } else { 'installed' }
        Write-Ok "$($Package.Name) $how"
        Add-Result -Step 'packages' -Item $Package.Name -Status 'Ok' -Detail $how
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
