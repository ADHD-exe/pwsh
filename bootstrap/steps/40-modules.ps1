# =============================================================================
# 40-modules.ps1 - PowerShell 7 modules (CurrentUser scope)
#
# Only ever runs under PowerShell 7: Windows PowerShell 5.1 has a different
# module path, and the profile is a PowerShell 7 profile.
# =============================================================================

function Get-Pwsh7ModuleRoot {
    <# The CurrentUser module folder PowerShell 7 searches (OneDrive-redirected Documents included). #>
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { $docs = Join-Path $HOME 'Documents' }
    return (Join-Path $docs 'PowerShell\Modules')
}

function Install-GalleryModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Module)

    $name = $Module.Name
    $have = Get-Module -ListAvailable -Name $name | Sort-Object Version -Descending | Select-Object -First 1

    if ($have -and (-not $Module.MinimumVersion -or $have.Version -ge [version]$Module.MinimumVersion)) {
        Write-Ok "$name $($have.Version) already available"
        Add-Result -Step 'modules' -Item $name -Status 'Skipped' -Detail "already available ($($have.Version))"
        return
    }

    if (-not $PSCmdlet.ShouldProcess($name, 'Install from PSGallery')) { return }

    Write-Info "Installing $name from PSGallery ..."

    try {
        # PSResourceGet ships with PowerShell 7.4+; -TrustRepository avoids flipping
        # PSGallery to "Trusted" for the whole machine (the old profile did that).
        if (Get-Command Install-PSResource -ErrorAction SilentlyContinue) {
            $p = @{ Name = $name; Scope = 'CurrentUser'; TrustRepository = $true; Quiet = $true; ErrorAction = 'Stop' }
            if ($Module.MinimumVersion) { $p.Version = "[$($Module.MinimumVersion),)" }
            Install-PSResource @p
        }
        else {
            $p = @{ Name = $name; Scope = 'CurrentUser'; Force = $true; AllowClobber = $true; SkipPublisherCheck = $true; ErrorAction = 'Stop' }
            if ($Module.MinimumVersion) { $p.MinimumVersion = $Module.MinimumVersion }
            Install-Module @p
        }

        $have = Get-Module -ListAvailable -Name $name | Sort-Object Version -Descending | Select-Object -First 1

        if ($have) {
            Write-Ok "$name $($have.Version) installed"
            Add-Result -Step 'modules' -Item $name -Status 'Ok' -Detail "installed $($have.Version)"
        }
        else {
            throw 'installed but not discoverable on PSModulePath'
        }
    }
    catch {
        Write-Bad "$name : $($_.Exception.Message)"
        Add-Result -Step 'modules' -Item $name -Status 'Failed' -Detail $_.Exception.Message
    }
}

function Install-GitModule {
    <# Clones one of your own modules into the CurrentUser module folder. Folder name must equal the .psd1 base name. #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Module)

    $name   = $Module.Name
    $target = Join-Path (Get-Pwsh7ModuleRoot) $name

    if (-not (Test-CommandExists 'git')) {
        Add-Result -Step 'modules' -Item $name -Status 'Failed' -Detail 'git not available'
        Write-Bad "$name : git not available"
        return
    }

    if (Test-Path -LiteralPath (Join-Path $target '.git')) {
        if ($PSCmdlet.ShouldProcess($target, 'git pull --ff-only')) {
            & git -C $target pull --ff-only 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Ok "$name up to date"; Add-Result -Step 'modules' -Item $name -Status 'Ok' -Detail 'pulled' }
            else { Write-Warn "$name : pull failed, keeping existing copy"; Add-Result -Step 'modules' -Item $name -Status 'Warn' -Detail 'pull failed' }
        }
        return
    }

    if (Test-Path -LiteralPath $target) {
        # e.g. a copy the OLD layout left behind in the same folder: do not clobber it.
        Write-Warn "$target exists but is not a git clone - left alone."
        Add-Result -Step 'modules' -Item $name -Status 'Skipped' -Detail 'existing non-git folder left alone'
        return
    }

    if (-not $PSCmdlet.ShouldProcess($target, "git clone $($Module.Url)")) { return }

    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    $out = & git clone --depth 1 $Module.Url $target 2>&1
    Write-LogLine 'GIT' ($out | Out-String)

    if ($LASTEXITCODE -ne 0) {
        Write-Bad "$name : clone failed ($($Module.Url))"
        Add-Result -Step 'modules' -Item $name -Status 'Failed' -Detail "clone failed: $($Module.Url)"
        return
    }

    # Cloned files can carry a zone marker and RemoteSigned refuses unsigned marked scripts.
    Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

    Write-Ok "Cloned $name -> $target"
    Add-Result -Step 'modules' -Item $name -Status 'Ok' -Detail 'cloned'
}

function Invoke-ModuleStep {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($PSVersionTable.PSEdition -ne 'Core') {
        if ($WhatIfPreference) { Write-Info 'Dry run under Windows PowerShell: the real run continues in PowerShell 7 and installs the modules there.'; return }
        throw 'The module step must run under PowerShell 7 (pwsh). The installer relaunches itself - if you see this, pwsh is missing.'
    }

    $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:ManifestDir 'modules.psd1')

    foreach ($m in $manifest.Gallery) { Install-GalleryModule -Module $m }
    foreach ($m in $manifest.Git)     { Install-GitModule     -Module $m }

    # One child process imports everything, so a module that breaks on import is
    # caught here rather than at the next shell start. -NoProfile keeps it honest.
    $names = @($manifest.Gallery | ForEach-Object { $_.Name }) + @($manifest.Git | ForEach-Object { $_.Name })
    $names = $names | Where-Object { $_ -ne 'PSReadLine' }   # already loaded by the host; cannot be re-imported meaningfully

    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwsh) { return }

    $probe = '$bad = @(); foreach ($n in $args) { try { Import-Module $n -ErrorAction Stop } catch { $bad += ("{0}: {1}" -f $n, $_.Exception.Message) } }; $bad'
    $failed = @(& $pwsh -NoProfile -NoLogo -Command $probe @names 2>$null)

    if ($failed.Count -eq 0) {
        Write-Ok "All $($names.Count) modules import cleanly in a fresh session"
        Add-Result -Step 'modules' -Item 'import check' -Status 'Ok' -Detail "$($names.Count) modules"
    }
    else {
        foreach ($f in $failed) {
            Write-Bad "import failed - $f"
            Add-Result -Step 'modules' -Item 'import check' -Status 'Failed' -Detail $f
        }
    }
}
