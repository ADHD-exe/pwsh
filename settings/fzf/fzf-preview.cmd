@echo off
rem ============================================================================
rem  fzf-preview.cmd  -  preview helper for fzf on Windows
rem ----------------------------------------------------------------------------
rem  fzf spawns previews through cmd.exe, so this is a batch file on purpose:
rem  starting powershell.exe for every keystroke would add ~300ms of lag.
rem
rem  Usage:  fzf-preview.cmd "<path>"
rem ============================================================================
setlocal EnableExtensions

set "TARGET=%~1"
if "%TARGET%"=="" exit /b 0
if not exist "%TARGET%" (
    echo [not found] %TARGET%
    exit /b 0
)

rem --- directory --------------------------------------------------------------
if exist "%TARGET%\" (
    echo %TARGET%
    echo.
    where /q eza.exe && (
        eza -la --icons --color=always --group-directories-first "%TARGET%"
        exit /b 0
    )
    dir /a /o-d "%TARGET%"
    exit /b 0
)

rem --- known binary / huge file: show metadata instead of garbage --------------
for %%E in (exe dll sys msi zip 7z rar gz tar iso bin obj pdb lib png jpg jpeg gif bmp ico webp mp3 mp4 mkv avi wav flac pdf docx xlsx pptx db sqlite) do (
    if /i "%~x1"==".%%E" goto :meta
)

rem files over ~4 MB: metadata only, previewing them is never useful
if %~z1 GTR 4194304 goto :meta

rem --- text file --------------------------------------------------------------
where /q bat.exe && (
    bat --style=numbers,changes --color=always --paging=never --line-range=:500 "%TARGET%"
    exit /b 0
)
type "%TARGET%" 2>nul
exit /b 0

rem --- metadata view ----------------------------------------------------------
:meta
echo %~nx1
echo.
echo   Folder    %~dp1
echo   Size      %~z1 bytes
echo   Modified  %~t1
echo   Attribs   %~a1
echo.
where /q file.exe && file -b "%TARGET%"
exit /b 0
