# =============================================================================
# Relaunch.ps1 - continue the install in a NEWLY opened terminal
#
# Why: PATH changes (and new fonts / the new profile) are only seen by processes
# started afterwards. A child process inherits its parent's stale environment, so
# the new window also calls Update-SessionPath first (see Install-Environment.ps1,
# -ResumeAfterPath), which rebuilds PATH from the registry.
# =============================================================================

function Start-ResumeInNewTerminal {
    <# Opens a new Windows Terminal window (or a plain pwsh window as a fallback) that runs this
       installer with -ResumeAfterPath. Returns $true when a window was started. #>
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$Arguments
    )

    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwsh) { $pwsh = (Get-Process -Id $PID).Path }

    $pwshArgv = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $Arguments
    $pwshLine = ConvertTo-ArgumentString -Arguments $pwshArgv

    Write-Info 'Opening a new terminal window to finish (so the new PATH takes effect) ...'

    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wt) {
        try {
            Start-Process -FilePath $wt.Source -ArgumentList ("-w new new-tab --title pwsh-setup `"$pwsh`" " + $pwshLine) -ErrorAction Stop
            return $true
        }
        catch { Write-Dim "Windows Terminal would not start ($($_.Exception.Message)); trying a plain window." }
    }

    try {
        Start-Process -FilePath $pwsh -ArgumentList $pwshLine -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warn "Could not open a new terminal: $($_.Exception.Message)"
        return $false
    }
}
