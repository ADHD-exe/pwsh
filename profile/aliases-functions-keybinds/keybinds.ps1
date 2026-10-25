# PSReadLine can fail to load when the host has no real console (redirected
# input/output, CI, the installer's verification child). Never let that break the profile.
if (Get-Module PSReadLine -ErrorAction SilentlyContinue) {
    try {
        Set-PSReadLineKeyHandler -Chord "Ctrl+Shift+z" -Function Undo
        Set-PSReadLineKeyHandler -Chord "Ctrl+Shift+x" -Function KillRegion
    }
    catch { Write-Verbose "keybinds skipped: $($_.Exception.Message)" }
}
