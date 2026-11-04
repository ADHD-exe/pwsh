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

function Set-JsonConfigProperty {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )

    $config = if (Test-Path -LiteralPath $Path) {
        ConvertTo-PlainJsonObject (Get-Content -LiteralPath $Path -Raw)
    }
    else { [pscustomobject]@{} }

    $config | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    $content = $config | ConvertTo-Json -Depth 32
    if ((Test-Path -LiteralPath $Path) -and ((Get-Content -LiteralPath $Path -Raw).Trim() -eq $content.Trim())) { return }
    if (-not $PSCmdlet.ShouldProcess($Path, "set $Name")) { return }

    if (Test-Path -LiteralPath $Path) { [void](Backup-File -Path $Path) }
    Write-Utf8NoBom -Path $Path -Content $content
    Write-Ok "Set $Name -> $Path"
    Add-Result -Step 'configs' -Item (Split-Path $Path -Leaf) -Status 'Ok' -Detail "$Name set"
}

function Invoke-ConfigStep {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$RepoRoot, [switch]$Force)

    $s = Join-Path $RepoRoot 'settings'
    $h = $HOME
    $themeDir = Join-Path $s 'themes'

    $themes = ($script:InstallThemes -ne $false)   # asked once at the start of the install; no = no theme anywhere
    if (-not $themes) { Write-Dim 'Themes declined: skipping the optional application colour themes.' }

    # ---- Atuin --------------------------------------------------------------
    if (Test-AppInstalled -Command 'atuin') {
        # config.toml selects the 'rabbit' theme by name; without themes that line is dropped.
        $atuinTransform = if ($themes) { $null } else { { param($t) [regex]::Replace($t, '(?m)^name\s*=\s*"rabbit"\s*\r?\n', '') } }
        Copy-ConfigFile -Source (Join-Path $s 'atuin\config.toml') -Target (Join-Path $h '.config\atuin\config.toml') -Transform $atuinTransform -Force:$Force

        # Colour theme(s) - the oh-my-rabbit palette.
        if ($themes) {
            foreach ($f in Get-ChildItem -LiteralPath (Join-Path $s 'atuin\themes') -Filter *.toml -File -ErrorAction SilentlyContinue) {
                Copy-ConfigFile -Source $f.FullName -Target (Join-Path $h ".config\atuin\themes\$($f.Name)") -Force:$Force
            }
        }
    }
    else { Add-Result -Step 'configs' -Item 'atuin' -Status 'Skipped' -Detail 'atuin not installed' }

    # ---- fzf / PSFzf: every file except the old self-installer and README ---
    $fzfTarget = Join-Path $h '.config\fzf'
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $s 'fzf') -File | Where-Object { $_.Name -notin 'Install-FzfConfig.ps1', 'README.md' }) {
        # fzf.conf carries the palette as --color= lines; without themes fzf keeps its default colours.
        $fzfTransform = if ($themes -or $f.Name -ne 'fzf.conf') { $null } else { { param($t) [regex]::Replace($t, '(?m)^--color=.*\r?\n?', '') } }
        Copy-ConfigFile -Source $f.FullName -Target (Join-Path $fzfTarget $f.Name) -Transform $fzfTransform -Force:$Force
    }

    # ---- yazi: oh-my-rabbit colour theme (Windows reads %APPDATA%\yazi\config) ---
    if (-not $themes) { Add-Result -Step 'configs' -Item 'yazi theme' -Status 'Skipped' -Detail 'themes declined' }
    elseif (Test-AppInstalled -Command 'yazi') {
        Copy-ConfigFile -Source (Join-Path $s 'yazi\theme.toml') -Target (Join-Path $env:APPDATA 'yazi\config\theme.toml') -Force:$Force
    }
    else { Add-Result -Step 'configs' -Item 'yazi' -Status 'Skipped' -Detail 'yazi not installed' }

    # ---- git ignore ---------------------------------------------------------
    Copy-ConfigFile -Source (Join-Path $s 'git\ignore') -Target (Join-Path $h '.config\git\ignore') -Force:$Force

    # ---- OpenCode -----------------------------------------------------------
    if (Test-AppInstalled -Command 'opencode' -Paths @('%LOCALAPPDATA%\Microsoft\WinGet\Links\opencode.exe')) {
        $ocDir = Join-Path $h '.config\opencode'

        if ($themes) {
            $ocTheme = Join-Path $ocDir 'themes\adhd.json'
            Copy-ConfigFile -Source (Join-Path $themeDir 'opencode - adhd.json') -Target $ocTheme -Force:$Force
            Set-JsonConfigProperty -Path (Join-Path $ocDir 'tui.json') -Name 'theme' -Value 'adhd'
        }

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
        # Notepad++ rewrites config.xml when it exits, so close it first (gracefully; its session snapshot
        # restores unsaved tabs), replace the files (originals are backed up), then reopen it.
        $nppTokens  = @{ '__USERPROFILE__' = $env:USERPROFILE }
        $nppFiles = @(Get-ChildItem -LiteralPath (Join-Path $s 'notepad++') -Filter *.xml -File |
            Where-Object { $themes -or $_.Name -ne 'stylers.xml' } |
            Where-Object { Test-ConfigWouldChange -Source $_.FullName -Target (Join-Path $env:APPDATA "Notepad++\$($_.Name)") -Tokens $nppTokens })
        if ($themes) {
            $nppThemeFile = Join-Path $themeDir 'notepad++ - Night City.xml'
            if (Test-ConfigWouldChange -Source $nppThemeFile -Target (Join-Path $env:APPDATA 'Notepad++\themes\Night City.xml')) {
                $nppFiles += Get-Item -LiteralPath $nppThemeFile
            }
        }
        $nppChanges = $nppFiles
        $nppApp = if ($WhatIfPreference -or $nppChanges.Count -eq 0) { $null } else { Stop-AppForConfig -ProcessName 'notepad++' }
        try {
            foreach ($f in Get-ChildItem -LiteralPath (Join-Path $s 'notepad++') -Filter *.xml -File | Where-Object { $themes -or $_.Name -ne 'stylers.xml' }) {
                $configTransform = if (-not $themes -and $f.Name -eq 'config.xml') {
                    { param($t) $t.Replace('darkThemeName="Night City.xml"', 'darkThemeName="Deep Black.xml"') }
                }
                else { $null }
                Copy-ConfigFile -Source $f.FullName -Target (Join-Path $env:APPDATA "Notepad++\$($f.Name)") `
                    -Tokens @{ '__USERPROFILE__' = $env:USERPROFILE } -Transform $configTransform -SkipIfRunning 'notepad++' -Force:$Force
            }
            if ($themes) {
                Copy-ConfigFile -Source (Join-Path $themeDir 'notepad++ - Night City.xml') `
                    -Target (Join-Path $env:APPDATA 'Notepad++\themes\Night City.xml') -SkipIfRunning 'notepad++' -Force:$Force
            }
        }
        finally { Start-AppAfterConfig $nppApp }
    }
    else { Add-Result -Step 'configs' -Item 'notepad++' -Status 'Skipped' -Detail 'Notepad++ not installed (Tools tier)' }

    # ---- Standalone application themes -------------------------------------
    if ($themes) {
        $documents = [Environment]::GetFolderPath('MyDocuments')
        foreach ($psTheme in @(
            @{ Name = 'powershell-7.6.9 - Night City.ps1'; Directory = (Join-Path $documents 'PowerShell\Themes') },
            @{ Name = 'powershell-5.1 - Night City.ps1'; Directory = (Join-Path $documents 'WindowsPowerShell\Themes') }
        )) {
            Copy-ConfigFile -Source (Join-Path $themeDir $psTheme.Name) `
                -Target (Join-Path $psTheme.Directory $psTheme.Name) -Force:$Force
        }

        $vscodePaths = @('%LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe', '%ProgramFiles%\Microsoft VS Code\Code.exe')
        if (Test-AppInstalled -Command 'code' -Paths $vscodePaths) {
            $extensionDir = Join-Path $h '.vscode\extensions\adhd-exe.dark-high-contrast-theme-1.0.0'
            Copy-ConfigFile -Source (Join-Path $themeDir 'vscode\package.json') `
                -Target (Join-Path $extensionDir 'package.json') -Force:$Force
            Copy-ConfigFile -Source (Join-Path $themeDir 'vscode - Default High Contrast.json') `
                -Target (Join-Path $extensionDir 'themes\dark-high-contrast.json') -Force:$Force
        }
        else { Add-Result -Step 'configs' -Item 'vscode theme' -Status 'Skipped' -Detail 'Visual Studio Code not installed' }
    }
    else { Add-Result -Step 'configs' -Item 'application themes' -Status 'Skipped' -Detail 'themes declined' }

    # ---- Everything ---------------------------------------------------------
    if (Test-AppInstalled -Paths @('%ProgramFiles%\Everything\Everything.exe')) {
        $evTarget = Join-Path $env:APPDATA 'Everything\Everything.ini'
        $evNeeds  = Test-ConfigWouldChange -Source (Join-Path $s 'everything\Everything.ini') -Target $evTarget
        $evApp = if ($WhatIfPreference -or -not $evNeeds) { $null } else { Stop-AppForConfig -ProcessName 'Everything' -QuitArguments @('-quit') -StartArguments @('-startup') }
        try {
            Copy-ConfigFile -Source (Join-Path $s 'everything\Everything.ini') -Target (Join-Path $env:APPDATA 'Everything\Everything.ini') -SkipIfRunning 'Everything' -Force:$Force
        }
        finally { Start-AppAfterConfig $evApp }
    }
    else { Add-Result -Step 'configs' -Item 'everything' -Status 'Skipped' -Detail 'Everything not installed (Tools tier)' }

    # ---- AutoHotkey v2: the launcher keybinds script (only when the user said yes) -----
    $ahkExe = @('%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe', '%ProgramFiles%\AutoHotkey\v2\AutoHotkey32.exe', '%ProgramFiles%\AutoHotkey\AutoHotkey.exe') |
        ForEach-Object { Expand-Vars $_ } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if ($script:InstallKeybinds -eq $false) {
        Add-Result -Step 'configs' -Item 'autohotkey' -Status 'Skipped' -Detail 'keybinds declined at the prompt'
        Write-Dim 'Keybinds declined: AutoHotkey script not deployed.'
    }
    elseif ($ahkExe) {
        $ahkDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AutoHotkey'

        foreach ($f in Get-ChildItem -LiteralPath (Join-Path $s 'autohotkey') -Filter *.ahk -File) {   # keybinds.ahk
            Copy-ConfigFile -Source $f.FullName -Target (Join-Path $ahkDir $f.Name) -Force:$Force
        }

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
