# =========================================================
# HISTORY
# =========================================================

# `forget` (functions.ps1) removes patterns from the PowerShell history file.
# This wipes everything Atuin and PowerShell have recorded.
function Clear-AllHistory {
    [CmdletBinding()]
    param([switch]$Force)

    if (-not $Force) {
        try {
            $answer = Read-Host 'Clear Atuin and PowerShell history? [y/N]'
        }
        catch {
            Write-Warning 'No console available to confirm; use -Force to clear without prompting.'
            return
        }
        if ($answer -notmatch '^(y|yes)$') { Write-Host 'Cancelled.'; return }
    }

    if (Get-Command atuin -ErrorAction SilentlyContinue) {
        # The daemon (when enabled) keeps the SQLite files open, and Windows
        # will not delete an open file. Stopping it is a no-op when it is off.
        & atuin daemon stop *> $null

        # records.db is the source of truth; history.db is the searchable
        # index built from it. Both must go, or the index is rebuilt from the
        # records. key and meta.db stay so the store keeps its identity.
        $atuinHome = if ($env:ATUIN_HOME) { $env:ATUIN_HOME } else { Join-Path $HOME '.atuin' }
        $dataDir = Join-Path $atuinHome 'data'

        foreach ($name in 'history.db', 'history.db-shm', 'history.db-wal',
                          'records.db', 'records.db-shm', 'records.db-wal') {
            Remove-Item -LiteralPath (Join-Path $dataDir $name) -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Warning 'atuin is not installed; cleared PowerShell history only.'
    }

    if (Get-Command Get-PSReadLineOption -ErrorAction SilentlyContinue) {
        $historyFile = (Get-PSReadLineOption).HistorySavePath
        if (Test-Path -LiteralPath $historyFile) {
            Clear-Content -LiteralPath $historyFile -ErrorAction SilentlyContinue
        }
        try { [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory() } catch {}
    }

    # Session history: what Get-History and the `history` view show.
    Clear-History

    Write-Host 'Atuin and PowerShell history cleared.' -ForegroundColor Green
}

Set-Alias clr-history Clear-AllHistory
