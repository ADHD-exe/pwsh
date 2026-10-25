# =============================================================================
# 30-repo.ps1 - give the repo a permanent home: ~\.pwsh
#
# Why not clone into Documents\PowerShell like the old installer?
#   * that folder is owned by PowerShell (Modules, Help, Scripts, profile files)
#     and is redirected by OneDrive Known Folder Move - a 100 MB repo with fonts
#     and a .git folder does not belong in a synced folder;
#   * a stable home means the profile stub can point at one path on every machine
#     and "update" is just `git pull`.
# =============================================================================

function Invoke-RepoStep {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$InstallDir,
        [Parameter(Mandatory)][string]$SourceRoot,
        [string]$RepoUrl,
        [string]$Branch
    )

    $installFull = [System.IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
    $sourceFull  = [System.IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')

    if ($installFull -ieq $sourceFull) {
        Write-Ok "Running from the install directory already ($installFull)"
        Add-Result -Step 'repo' -Item $installFull -Status 'Skipped' -Detail 'running in place'
        return $installFull
    }

    $hasGit = Test-CommandExists 'git'

    # ---- existing clone: fast-forward it ------------------------------------
    if ($hasGit -and (Test-Path -LiteralPath (Join-Path $installFull '.git'))) {

        if (-not $PSCmdlet.ShouldProcess($installFull, 'git pull --ff-only')) { return $installFull }

        $dirty = & git -C $installFull status --porcelain 2>$null
        if ($dirty) {
            Write-Warn "Local changes in $installFull - not touching it (commit or stash them, then re-run to update)."
            Add-Result -Step 'repo' -Item $installFull -Status 'Warn' -Detail 'local changes present, update skipped'
            return $installFull
        }

        & git -C $installFull fetch --depth 1 origin $Branch 2>&1 | Out-Null
        & git -C $installFull merge --ff-only FETCH_HEAD 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Repo up to date at $installFull"
            Add-Result -Step 'repo' -Item $installFull -Status 'Ok' -Detail 'fast-forwarded'
        }
        else {
            Write-Warn 'Could not fast-forward the existing clone; keeping the files that are there.'
            Add-Result -Step 'repo' -Item $installFull -Status 'Warn' -Detail 'fast-forward failed, kept existing copy'
        }
        return $installFull
    }

    # ---- something is in the way that is not our clone: move it aside -------
    if (Test-Path -LiteralPath $installFull) {
        $aside = "{0}.bak-{1}" -f $installFull, (Get-Date -Format 'yyyyMMdd-HHmmss')

        if ($PSCmdlet.ShouldProcess($installFull, "move aside to $aside")) {
            Move-Item -LiteralPath $installFull -Destination $aside
            Write-Info "Existing $installFull was not a git clone - moved to $aside"
            Add-Result -Step 'repo' -Item 'previous install dir' -Status 'Ok' -Detail "backed up to $aside"
        }
    }

    # ---- fresh clone (shallow) ----------------------------------------------
    if ($hasGit) {
        if (-not $PSCmdlet.ShouldProcess($installFull, "git clone $RepoUrl")) { return $installFull }

        Write-Info "Cloning $RepoUrl ($Branch) -> $installFull"
        $out = & git clone --depth 1 --branch $Branch $RepoUrl $installFull 2>&1
        Write-LogLine 'GIT' ($out | Out-String)

        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Cloned to $installFull"
            Add-Result -Step 'repo' -Item $installFull -Status 'Ok' -Detail 'cloned'
            return $installFull
        }

        Write-Warn 'git clone failed - falling back to copying the files this run was started from.'
    }

    # ---- fallback: copy the already-downloaded source -----------------------
    if (-not $PSCmdlet.ShouldProcess($installFull, "copy files from $sourceFull")) { return $installFull }

    New-Item -ItemType Directory -Path $installFull -Force | Out-Null
    Get-ChildItem -LiteralPath $sourceFull -Force | Where-Object { $_.Name -ne '.git' } |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $installFull -Recurse -Force }

    Write-Ok "Copied files to $installFull (not a git clone - run the installer again later to convert it)"
    Add-Result -Step 'repo' -Item $installFull -Status 'Warn' -Detail 'copied, not cloned: updates need a re-run'
    return $installFull
}
