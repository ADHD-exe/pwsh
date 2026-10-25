# =============================================================================
# Relaunch.ps1 - continue the install in a NEWLY opened terminal
#
# Why: PATH changes (and new fonts / the new profile) are only seen by processes
# started afterwards. A child process inherits its parent's stale environment, so
# the new window also calls Update-SessionPath first (see Install-Environment.ps1,
# -ResumeAfterPath), which rebuilds PATH from the registry.
#
# How the command reaches the new window: as -EncodedCommand (base64). That avoids every
# quoting problem with wt.exe (it treats ';' as its own separator and re-parses quotes) and
# lets a small wrapper keep the window open with the error visible if the script cannot start.
# =============================================================================

function ConvertTo-PsLiteral {
    <# Single-quoted PowerShell string literal for any text. #>
    param([string]$Text)
    return "'" + ($Text -replace "'", "''") + "'"
}

function New-ResumeEncodedCommand {
    <# Builds the base64 command for: & <script> @{ ...parameters... } with an error pause around it. #>
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][hashtable]$Parameters
    )

    $pairs = foreach ($k in $Parameters.Keys) {
        $v = $Parameters[$k]
        $lit = if ($v -is [bool] -or $v -is [switch]) { if ($v) { '$true' } else { '$false' } } else { ConvertTo-PsLiteral ([string]$v) }
        "{0} = {1}" -f (ConvertTo-PsLiteral $k), $lit
    }

    $script = @"
`$ErrorActionPreference = 'Continue'
`$p = @{ $($pairs -join '; ') }
try { & $(ConvertTo-PsLiteral $ScriptPath) @p }
catch {
    Write-Host ''
    Write-Host 'The setup window could not continue:' -ForegroundColor Red
    Write-Host `$_.Exception.Message -ForegroundColor Red
    Write-Host ''
    Write-Host 'Run this in any terminal to retry the final check:' -ForegroundColor Yellow
    Write-Host ('  & ' + $(ConvertTo-PsLiteral $ScriptPath) + ' -Only verify -NoRelaunch') -ForegroundColor Yellow
    Read-Host 'Press Enter to close'
}
"@

    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
}

function Start-ResumeInNewTerminal {
    <# Opens a new Windows Terminal window (or a plain pwsh window as a fallback) that runs this
       installer with -ResumeAfterPath. Returns $true when a window was started. #>
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [hashtable]$Parameters = @{}
    )

    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwsh) { $pwsh = (Get-Process -Id $PID).Path }

    $encoded  = New-ResumeEncodedCommand -ScriptPath $ScriptPath -Parameters $Parameters
    $pwshTail = "-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"

    Write-Info 'Opening a new terminal window to finish (so the new PATH takes effect) ...'
    Write-LogLine 'RELAUNCH' "script=$ScriptPath pwsh=$pwsh"

    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wt) {
        try {
            Start-Process -FilePath $wt.Source -ArgumentList ("-w new new-tab --title pwsh-setup `"$pwsh`" " + $pwshTail) -ErrorAction Stop
            return $true
        }
        catch { Write-Dim "Windows Terminal would not start ($($_.Exception.Message)); trying a plain window." }
    }

    try {
        Start-Process -FilePath $pwsh -ArgumentList $pwshTail -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warn "Could not open a new terminal: $($_.Exception.Message)"
        return $false
    }
}
