# =============================================================================
# path.psd1 - PATH entries taken from the old "draft-bootstrap" notes
#
# The installer does NOT add these blindly. For each entry it:
#   * expands %VARS%,
#   * skips it if the directory does not exist (reported as "not installed yet"),
#   * skips it if the directory holds no .exe/.cmd/.bat (a PATH entry that holds
#     nothing executable is just noise),
#   * skips it if it is already on the Machine or User PATH (case-insensitive),
#   * otherwise adds it to the SYSTEM (Machine) PATH. That needs admin, so the
#     installer opens one elevated window (UAC prompt) for just this step.
#     Use  -PathScope User  to add to the user PATH instead (no prompt).
#
# Winget installers usually register their own PATH entries; these are the
# folders from your notes that do not reliably do so.
#
# Changed from the notes (the notes' folder holds no executable on PATH):
#   C:\Program Files\Git        -> C:\Program Files\Git\cmd
#   C:\Program Files\CMake      -> C:\Program Files\CMake\bin
# Not in the notes' package list, so only added if present:
#   Go, 7-Zip
# =============================================================================
@{
    Directories = @(
        '%ProgramFiles%\Notepad++'
        '%ProgramFiles%\CMake\bin'
        '%ProgramFiles%\7-Zip'
        '%ProgramFiles%\AutoHotkey'
        '%ProgramFiles%\Autoruns'
        '%ProgramFiles%\Everything'
        '%ProgramFiles%\EverythingToolbar'
        '%ProgramFiles%\Git\cmd'
        '%ProgramFiles%\Go\bin'
        '%ProgramFiles%\paint.net'
        '%ProgramFiles%\PeaZip'
        '%ProgramFiles%\Tailscale'
        '%ProgramFiles%\ShareX'
        '%ProgramFiles%\starship\bin'
        '%ProgramFiles%\simplewall'
        '%ProgramFiles%\nodejs'
    )
}
