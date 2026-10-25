# =============================================================================
# 50-fonts.ps1 - install the Nerd Fonts bundled in settings\fonts (per user)
# =============================================================================

function Invoke-FontStep {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$RepoRoot)

    $dir = Join-Path $RepoRoot 'settings\fonts'

    if (-not (Test-Path -LiteralPath $dir)) {
        throw "Font folder missing from the repo: $dir"
    }

    $fonts = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Extension -in '.ttf', '.otf' })
    Write-Info "$($fonts.Count) font files in settings\fonts"

    $counts = @{ Installed = 0; Current = 0; Failed = 0; DryRun = 0 }

    foreach ($f in $fonts) {
        $r = Install-FontFile -Font $f
        $counts[$r]++
        if ($r -eq 'Failed') { Write-Bad "font failed: $($f.Name) (see log)"; Add-Result -Step 'fonts' -Item $f.Name -Status 'Failed' -Detail 'copy or registry write failed' }
    }

    Write-Ok ("fonts: {0} installed, {1} already current, {2} failed" -f $counts.Installed, $counts.Current, $counts.Failed)
    Add-Result -Step 'fonts' -Item 'Nerd Fonts' -Status $(if ($counts.Failed) { 'Warn' } else { 'Ok' }) -Detail ("{0} installed / {1} current / {2} failed" -f $counts.Installed, $counts.Current, $counts.Failed)

    # Windows Terminal reads the font list at start-up. Nothing is restarted
    # automatically (that would close the user's tabs); we only say so.
    if ($counts.Installed -gt 0 -and (Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue)) {
        Write-Warn 'Windows Terminal was already running - close ALL its windows once so it can see the new fonts.'
        Add-Result -Step 'fonts' -Item 'Windows Terminal restart' -Status 'Warn' -Detail 'close all Terminal windows once to load new fonts'
    }

    # Per-user fonts do not show up for apps that were already running either.
    Write-Dim 'Apps that were already open (e.g. Notepad++) need a restart to list the new fonts.'
}
