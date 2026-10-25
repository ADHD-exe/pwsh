#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

; =========================================================
;  Program launchers
; =========================================================
#Enter::Run "pwsh.exe"                                                         ; PowerShell 7
#b::Run A_ProgramFiles "\Firefox Developer Edition\firefox.exe"                ; Firefox Developer Edition
#n::Run A_ProgramFiles "\Notepad++\notepad++.exe"                              ; Notepad++
#s::Run A_AppData "\Spotify\Spotify.exe"                   ; Spotify
#d::Run EnvGet("LOCALAPPDATA") "\Equibop\equibop.exe"  ; Equibop (Discord client)
#f::Run "explorer.exe"                                                          ; File Explorer
#m::Run "ms-windows-store://home"                                               ; Microsoft Store
#e::Run EnvGet("ProgramFiles(x86)") "\eM Client\MailClient.exe"                       ; eM Client

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
;  System panels
; =========================================================
#!n::Run "explorer.exe ms-availablenetworks:"   ; Network pane (available networks flyout)
#!v::OpenClassicVolume()                        ; Classic volume mixer (SndVol)
#!c::RunOpenCam()                               ; OpenCam (phone as webcam)
#y::Run "mblctr.exe"                            ; Windows Mobility Center

; =========================================================
;  Helpers
; =========================================================

; Windows 11 ships SndVol.exe in System32, but some builds only keep a working
; copy in SysWOW64 - try both.

; Launches OpenCam from the venv the bootstrap creates. pythonw keeps the
; console window hidden - OpenCam is a GUI app.
RunOpenCam() {
    dir := A_MyDocuments "\OpenCam"
    exe := dir "\venv\Scripts\pythonw.exe"
    if FileExist(exe) {
        Run '"' exe '"' " main.py", dir
        return
    }
    MsgBox "OpenCam is not installed yet. Run bootstrap.ps1 to set it up.", "OpenCam", 0x30
}

OpenClassicVolume() {
    for path in [A_WinDir "\System32\SndVol.exe", A_WinDir "\SysWOW64\SndVol.exe"] {
        if FileExist(path) {
            Run path
            return
        }
    }
    MsgBox "SndVol.exe not found.", "Classic volume", 0x30
}

; Want the small master-volume slider instead of the full mixer? Swap the
; OpenClassicVolume() call above for this line - the number is a packed screen
; position (x + y * 65536) telling Windows where to draw the slider:
;
;   #!v::Run A_WinDir "\System32\SndVol.exe -f 49825268"
