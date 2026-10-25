# =============================================================================
# 90-path.ps1 - system (Machine) PATH from manifests\path.psd1
#
# Machine PATH needs admin. When the session is not elevated this step explains
# why, asks, and runs ONLY itself in an elevated child (UAC prompt). The rest of
# the install stays un-elevated, so HKCU/fonts/profile still land on the right
# account even for a standard user who approves UAC with an admin's password.
# =============================================================================

function Invoke-PathStep {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('User', 'Machine')][string]$Scope = 'Machine',
        [string]$BackupDirectory,
        [switch]$Unattended,
        [switch]$Elevate,
        [string[]]$ChildArguments
    )

    $dirs = (Import-PowerShellDataFile -LiteralPath (Join-Path $script:ManifestDir 'path.psd1')).Directories

    if ($Scope -eq 'Machine' -and -not (Test-IsAdmin)) {
        Write-Info 'Adding to the system PATH needs administrator rights.'

        $go = [bool]$Elevate
        if (-not $go -and -not $Unattended) {
            $a = Read-Host 'Open a one-time elevated window (UAC prompt) to update the system PATH? [Y/n]'
            $go = ($a -eq '' -or $a -match '^[Yy]')
        }

        if (-not $go) {
            Add-Result -Step 'path' -Item '(system PATH)' -Status 'Warn' -Detail 'not elevated: run install.ps1 -Only Path from an elevated pwsh, or use -PathScope User'
            Write-Warn 'System PATH not changed.'
            return
        }

        if ($PSCmdlet.ShouldProcess('system PATH', 'relaunch elevated')) {
            $result = Join-Path ([IO.Path]::GetTempPath()) ("rabbit-path-{0}.json" -f [guid]::NewGuid().ToString('N'))
            $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
            if (-not $pwsh) { $pwsh = (Get-Process -Id $PID).Path }

            $childArgv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:OrchestratorPath, '-AdminPathOnly', '-ResultFile', $result) + $ChildArguments
            # Start-Process does not quote array elements: a profile path with a space would break the elevated launch.
            $childArgLine = ConvertTo-ArgumentString -Arguments $childArgv

            Write-Info 'Waiting for the elevated window ...'
            try {
                $p = Start-Process -FilePath $pwsh -ArgumentList $childArgLine -Verb RunAs -Wait -PassThru -ErrorAction Stop
            }
            catch {
                Add-Result -Step 'path' -Item '(system PATH)' -Status 'Warn' -Detail 'UAC was declined or the elevated window failed to start'
                Write-Warn "Elevation did not happen: $($_.Exception.Message)"
                return
            }

            if (Test-Path -LiteralPath $result) {
                foreach ($r in (Get-Content -LiteralPath $result -Raw | ConvertFrom-Json)) {
                    Add-Result -Step $r.Step -Item $r.Item -Status $r.Status -Detail $r.Detail
                    $color = switch ($r.Status) { 'Ok' { 'Green' } 'Failed' { 'Red' } 'Warn' { 'DarkYellow' } default { 'Gray' } }
                    Write-Host ("     [{0}] {1} {2}" -f $r.Status, $r.Item, $r.Detail) -ForegroundColor $color
                }
                Remove-Item -LiteralPath $result -Force -ErrorAction SilentlyContinue
            }
            else {
                Add-Result -Step 'path' -Item '(system PATH)' -Status 'Warn' -Detail "elevated window exited with code $($p.ExitCode) and reported nothing"
            }
        }
        return
    }

    foreach ($d in $dirs) { [void](Add-PathEntry -Directory $d -Scope $Scope -BackupDirectory $BackupDirectory) }

    if ($PSCmdlet.ShouldProcess('running applications', 'broadcast environment change')) { Send-EnvironmentChange }

    Write-Info 'PATH is saved. Programs that are already open keep the old PATH - open a NEW terminal (or sign out/in) to pick it up.'
}
