@echo off
rem ============================================================================
rem  fzf-action.cmd  -  side-effect actions bound to keys inside fzf
rem ----------------------------------------------------------------------------
rem  Usage:  fzf-action.cmd <copy|open|reveal|edit> "<path>"
rem
rem  Bound in fzf.conf as:
rem      ctrl-y -> copy    (path to clipboard)
rem      ctrl-o -> open    (default application)
rem      ctrl-e -> reveal  (Explorer, item selected)
rem ============================================================================
setlocal EnableExtensions

set "VERB=%~1"
set "TARGET=%~2"
if "%TARGET%"=="" exit /b 0

if /i "%VERB%"=="copy" (
    rem <nul set /p avoids the trailing newline that plain `echo` would add
    <nul set /p "=%TARGET%" | clip
    exit /b 0
)

if /i "%VERB%"=="open" (
    start "" "%TARGET%"
    exit /b 0
)

if /i "%VERB%"=="reveal" (
    explorer.exe /select,"%TARGET%"
    exit /b 0
)

if /i "%VERB%"=="edit" (
    if defined EDITOR (
        start "" "%EDITOR%" "%TARGET%"
    ) else (
        where /q code.cmd && ( start "" code "%TARGET%" ) || ( start "" notepad "%TARGET%" )
    )
    exit /b 0
)

exit /b 0
