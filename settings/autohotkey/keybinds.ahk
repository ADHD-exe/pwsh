#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

; =========================================================
;  Program launchers
;
;  A launcher key is only created when its program exists on this PC. Everything
;  here ships with Windows or is installed by the installer (PowerShell 7,
;  Notepad++, Firefox Developer Edition), so no key points at a missing program.
;  Install something later and reload this script (right-click its tray icon > Reload)
;  to pick it up.
; =========================================================

; First existing file from a list of candidates, or "" when none exists.
FirstExisting(paths*) {
    for p in paths {
        if (p != "" && FileExist(p))
            return p
    }
    return ""
}

; Bind a key to an executable, but only if the executable exists.
LaunchFile(key, exe) {
    if (exe = "")
        return
    Hotkey(key, (*) => Run('"' exe '"'))
}

pf   := A_ProgramFiles
pf86 := EnvGet("ProgramFiles(x86)")
lad  := EnvGet("LOCALAPPDATA")

; PowerShell 7 (installed by the script); falls back to the Windows PowerShell that ships with Windows.
LaunchFile("#Enter", FirstExisting(pf "\PowerShell\7\pwsh.exe", lad "\Microsoft\WindowsApps\pwsh.exe", A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"))
; Firefox Developer Edition (installed by the script)
LaunchFile("#b", FirstExisting(pf "\Firefox Developer Edition\firefox.exe", pf86 "\Firefox Developer Edition\firefox.exe"))
; Notepad++ (installed by the script)
LaunchFile("#n", FirstExisting(pf "\Notepad++\notepad++.exe", pf86 "\Notepad++\notepad++.exe"))
; File Explorer (Windows)
LaunchFile("#f", FirstExisting(A_WinDir "\explorer.exe"))
; Windows Mobility Center (Windows; absent on some editions)
LaunchFile("#y", FirstExisting(A_WinDir "\System32\mblctr.exe"))

; Classic volume mixer. Windows 11 ships SndVol.exe in System32, but some builds only keep a
; working copy in SysWOW64 - try both, and bind the key only if one exists.
sndvol := FirstExisting(A_WinDir "\System32\SndVol.exe", A_WinDir "\SysWOW64\SndVol.exe")
LaunchFile("#!v", sndvol)

; Want the small master-volume slider instead of the full mixer? Replace the LaunchFile("#!v", ...)
; line above with this one - the number is a packed screen position (x + y * 65536) telling
; Windows where to draw the slider:
;
;   Hotkey("#!v", (*) => Run(A_WinDir "\System32\SndVol.exe -f 49825268"))

; Microsoft Store (Windows). A missing Store only means nothing opens.
Hotkey("#m", (*) => OpenUri("ms-windows-store://home"))

OpenUri(uri) {
    try Run(uri)
}

; =========================================================
;  Editing shortcuts
; =========================================================
#z::Send "^z"       ; Undo
#!z::Send "^y"      ; Redo
#x::Send "^x"       ; Cut
#c::Send "^c"       ; Copy
#v::Send "^v"       ; Paste
#q::Send "!{F4}"    ; Quit / close active window (same as Alt+F4)

; =========================================================
;  Window management
; =========================================================
#PgDn::WinMinimize "A"    ; Minimize active window
#PgUp::WinMaximize "A"    ; Maximize active window

; =========================================================
;  System panels (all part of Windows; classic volume mixer is bound above)
; =========================================================
#!n::Run "explorer.exe ms-availablenetworks:"   ; Network pane (available networks flyout)
