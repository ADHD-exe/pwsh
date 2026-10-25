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
        [string]$Branch,
        [switch]$Fresh,
        [switch]$Unattended
    )

    $installFull = [System.IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
    $sourceFull  = [System.IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')

    if ($installFull -ieq $sourceFull) {
        Write-Ok "Running from the install directory already ($installFull)"
        Add-Result -Step 'repo' -Item $installFull -Status 'Skipped' -Detail 'running in place'
        return $installFull
    }

    $hasGit = Test-CommandExists 'git'

    # ---- an install already exists: offer a clean, up-to-date copy ----------
    if (Test-Path -LiteralPath $installFull) {
        $replace = $false

        if ($Fresh) { $replace = $true }
        elseif (-not $Unattended -and -not $WhatIfPreference -and [Environment]::UserInteractive) {
            Write-Info "An existing copy of the repo was found at $installFull"
            $a = Read-Host 'Remove it and install a fresh, up-to-date copy? [Y/n]'
            $replace = ($a -notmatch '^\s*n')
        }

        if ($replace -and $PSCmdlet.ShouldProcess($installFull, 'remove existing copy for a fresh install')) {
            $isClone = Test-Path -LiteralPath (Join-Path $installFull '.git')
            $dirty   = $false
            if ($isClone -and $hasGit) { $dirty = [bool](& git -C $installFull status --porcelain 2>$null) }

            if ($isClone -and -not $dirty) {
                try {
                    # .git pack files are read-only; clear the attribute so the delete cannot stall on them.
                    Get-ChildItem -LiteralPath $installFull -Recurse -Force -File -ErrorAction SilentlyContinue |
                        ForEach-Object { if ($_.IsReadOnly) { $_.IsReadOnly = $false } }
                    Remove-Item -LiteralPath $installFull -Recurse -Force -ErrorAction Stop
                    Write-Ok "Removed the old copy at $installFull"
                    Add-Result -Step 'repo' -Item 'previous install dir' -Status 'Ok' -Detail 'removed (clean clone)'
                }
                catch {
                    Write-Warn "Could not delete $installFull ($($_.Exception.Message)) - moving it aside instead."
                    $replace = $false
                }
            }

            # Local changes, not a clone, or the delete failed: never destroy it, move it aside (handled below).
            if ($replace -and (Test-Path -LiteralPath $installFull)) {
                $aside = "{0}.bak-{1}" -f $installFull, (Get-Date -Format 'yyyyMMdd-HHmmss')
                try {
                    Move-Item -LiteralPath $installFull -Destination $aside -ErrorAction Stop
                    Write-Info "Old copy had local changes or was not a plain clone - kept at $aside"
                    Add-Result -Step 'repo' -Item 'previous install dir' -Status 'Ok' -Detail "backed up to $aside"
                }
                catch {
                    Write-Warn "Could not move $installFull aside ($($_.Exception.Message)) - updating it in place instead."
                }
            }
        }
        elseif (-not $replace) { Write-Dim 'Keeping the existing copy; it will be updated in place.' }
    }

    # ---- existing clone: fast-forward it ------------------------------------
    if ($hasGit -and (Test-Path -LiteralPath (Join-Path $installFull '.git'))) {

        if (-not $PSCmdlet.ShouldProcess($installFull, 'git pull --ff-only')) { return $installFull }

        $dirty = & git -C $installFull status --porcelain 2>$null
        if ($dirty) {
            Write-Warn "Local changes in $installFull - not touching it (commit or stash them, then re-run to update)."
            Add-Result -Step 'repo' -Item $installFull -Status 'Warn' -Detail 'local changes present, update skipped'
            return $installFull
        }

        # A shallow clone cannot be fast-forwarded: `fetch --depth 1` grafts away the new commit's parents, so
        # git cannot prove the old HEAD is an ancestor and `merge --ff-only` fails whenever the clone is behind.
        # This folder is a deployed mirror (local changes were ruled out above), so move it to the fetched
        # commit with `reset --hard`; `clean` is deliberately not used.
        $fetchOut = & git -C $installFull fetch --depth 1 origin $Branch 2>&1
        $fetchExit = $LASTEXITCODE
        Write-LogLine 'GIT' ($fetchOut | Out-String)

        $synced = $false
        if ($fetchExit -eq 0) {
            $resetOut = & git -C $installFull reset --hard FETCH_HEAD 2>&1
            Write-LogLine 'GIT' ($resetOut | Out-String)
            $synced = ($LASTEXITCODE -eq 0)
        }

        if ($synced) {
            Write-Ok "Repo up to date at $installFull"
            Add-Result -Step 'repo' -Item $installFull -Status 'Ok' -Detail 'updated to latest'
            return $installFull
        }

        # git could not update it (offline, SSH rewrite problem, damaged clone ...). The files this run was
        # started from ARE the latest download, so lay them over the install dir. That keeps ~\.pwsh and the
        # download identical, which the new-terminal handoff and every config deploy depend on.
        Write-Warn 'git could not update the existing clone - copying the freshly downloaded files over it instead.'
        if ($sourceFull -and (Test-Path -LiteralPath (Join-Path $sourceFull 'bootstrap\Install-Environment.ps1'))) {
            Get-ChildItem -LiteralPath $sourceFull -Force | Where-Object { $_.Name -ne '.git' } |
                ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $installFull -Recurse -Force }
            Write-Ok "Copied the latest files into $installFull"
            Add-Result -Step 'repo' -Item $installFull -Status 'Warn' -Detail 'git update failed; latest download copied over it'
        }
        else {
            Write-Warn 'No fresh source to copy either - keeping the files that are there.'
            Add-Result -Step 'repo' -Item $installFull -Status 'Warn' -Detail 'update failed, kept existing copy'
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
