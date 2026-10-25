# =============================================================================
# 80-configs.ps1 - deploy per-application config from settings\
#
# Each entry names its target application, how to tell it is installed, and where
# its config lives. A config is only deployed when its application is present
# (a stray Everything.ini on a machine without Everything is just clutter).
# =============================================================================

function Test-AppInstalled {
    param([string]$Command, [string[]]$Paths)

    if ($Command -and (Test-CommandExists $Command)) { return $true }
    foreach ($p in $Paths) { if ($p -and (Test-Path -LiteralPath (Expand-Vars $p))) { return $true } }
    return $false
}

function Invoke-ConfigStep {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$RepoRoot, [switch]$Force)

    $s = Join-Path $RepoRoot 'settings'
    $h = $HOME

    # ---- Atuin --------------------------------------------------------------
    if (Test-AppInstalled -Command 'atuin') {
        Copy-ConfigFile -Source (Join-Path $s 'atuin\config.toml') -Target (Join-Path $h '.config\atuin\config.toml') -Force:$Force
    }
    else { Add-Result -Step 'configs' -Item 'atuin' -Status 'Skipped' -Detail 'atuin not installed' }

    # ---- fzf / PSFzf: every file except the old self-installer and README ---
    $fzfTarget = Join-Path $h '.config\fzf'
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $s 'fzf') -File | Where-Object { $_.Name -notin 'Install-FzfConfig.ps1', 'README.md' }) {
        Copy-ConfigFile -Source $f.FullName -Target (Join-Path $fzfTarget $f.Name) -Force:$Force
    }

    # ---- git ignore ---------------------------------------------------------
    Copy-ConfigFile -Source (Join-Path $s 'git\ignore') -Target (Join-Path $h '.config\git\ignore') -Force:$Force

    # ---- OpenCode -----------------------------------------------------------
    if (Test-AppInstalled -Command 'opencode' -Paths @('%LOCALAPPDATA%\Microsoft\WinGet\Links\opencode.exe')) {
        $ocDir = Join-Path $h '.config\opencode'

        if (Test-Path -LiteralPath (Join-Path $ocDir 'opencode.json')) {
            Write-Warn 'opencode.json already exists - opencode.jsonc not deployed (it would be ignored or conflict).'
            Add-Result -Step 'configs' -Item 'opencode' -Status 'Skipped' -Detail 'existing opencode.json kept'
        }
        else {
            Copy-ConfigFile -Source (Join-Path $s 'opencode\opencode.jsonc') -Target (Join-Path $ocDir 'opencode.jsonc') -Force:$Force
        }
    }
    else { Add-Result -Step 'configs' -Item 'opencode' -Status 'Skipped' -Detail 'opencode not installed' }

    # ---- Notepad++ (config.xml carries __USERPROFILE__ so it works for any user) ----
    $nppPaths = @('%ProgramFiles%\Notepad++\notepad++.exe', '%ProgramFiles(x86)%\Notepad++\notepad++.exe')
    if (Test-AppInstalled -Command 'notepad++' -Paths $nppPaths) {
        foreach ($f in Get-ChildItem -LiteralPath (Join-Path $s 'notepad++') -Filter *.xml -File) {
            Copy-ConfigFile -Source $f.FullName -Target (Join-Path $env:APPDATA "Notepad++\$($f.Name)") `
                -Tokens @{ '__USERPROFILE__' = $env:USERPROFILE } -SkipIfRunning 'notepad++' -Force:$Force
        }
    }
    else { Add-Result -Step 'configs' -Item 'notepad++' -Status 'Skipped' -Detail 'Notepad++ not installed (Tools tier)' }

    # ---- Everything ---------------------------------------------------------
    if (Test-AppInstalled -Paths @('%ProgramFiles%\Everything\Everything.exe')) {
        Copy-ConfigFile -Source (Join-Path $s 'everything\Everything.ini') -Target (Join-Path $env:APPDATA 'Everything\Everything.ini') -SkipIfRunning 'Everything' -Force:$Force
    }
    else { Add-Result -Step 'configs' -Item 'everything' -Status 'Skipped' -Detail 'Everything not installed (Tools tier)' }

    # ---- AutoHotkey v2: deploy both scripts, autostart ONLY keybinds.ahk -----
    $ahkExe = @('%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe', '%ProgramFiles%\AutoHotkey\v2\AutoHotkey32.exe', '%ProgramFiles%\AutoHotkey\AutoHotkey.exe') |
        ForEach-Object { Expand-Vars $_ } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if ($ahkExe) {
        $ahkDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AutoHotkey'

        foreach ($f in Get-ChildItem -LiteralPath (Join-Path $s 'autohotkey') -Filter *.ahk -File) {
            Copy-ConfigFile -Source $f.FullName -Target (Join-Path $ahkDir $f.Name) -Force:$Force
        }

        # bandlab_ahk.ahk remaps every letter key while it runs, so it is deployed but never autostarted.
        $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'keybinds.ahk.lnk'

        if (-not (Test-Path -LiteralPath $lnk)) {
            if ($PSCmdlet.ShouldProcess($lnk, 'create autostart shortcut')) {
                $sh = New-Object -ComObject WScript.Shell
                $sc = $sh.CreateShortcut($lnk)
                $sc.TargetPath       = $ahkExe
                $sc.Arguments        = '"' + (Join-Path $ahkDir 'keybinds.ahk') + '"'
                $sc.WorkingDirectory = $ahkDir
                $sc.Save()
                Write-Ok "AutoHotkey autostart shortcut created ($lnk)"
                Add-Result -Step 'configs' -Item 'ahk autostart' -Status 'Ok' -Detail 'keybinds.ahk starts at logon'
            }
        }
        else { Add-Result -Step 'configs' -Item 'ahk autostart' -Status 'Skipped' -Detail 'shortcut already exists' }
    }
    else { Add-Result -Step 'configs' -Item 'autohotkey' -Status 'Skipped' -Detail 'AutoHotkey not installed (Tools tier)' }

    Write-Dim 'The Oh My Posh theme is not copied: the profile loads settings\oh-my-rabbit.omp.json straight from the repo.'
}
