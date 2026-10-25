# =========================================================
# Rabbit PowerShell profile  (PowerShell 7)
#
# Loaded through the stub the installer writes to
#   Documents\PowerShell\Microsoft.PowerShell_profile.ps1
# Machine-local additions belong in Microsoft.PowerShell_profile.local.ps1
# next to that stub - this file lives in a git clone and is updated by `git pull`.
#
# Nothing here installs anything: the installer owns installation, the profile
# only wires up what is present and skips what is not.
# =========================================================

if ($global:RABBIT_PROFILE_LOADED) { return }
$global:RABBIT_PROFILE_LOADED = $true

# Repo root = parent of this profile\ folder. Everything below is relative to it,
# never to the current directory.
$global:RabbitRoot     = Split-Path -Parent $PSScriptRoot
$global:RabbitSettings = Join-Path $global:RabbitRoot 'settings'
$global:RabbitScripts  = Join-Path $PSScriptRoot 'aliases-functions-keybinds'

# Non-interactive runs (pwsh -Command / -File, CI, scheduled tasks) do not need
# prompts, key bindings or tool hooks. RABBIT_PROFILE_FORCE=1 overrides.
$RabbitInteractive = [Environment]::UserInteractive -and -not ($env:RABBIT_PROFILE_FORCE -ne '1' -and
    ([Environment]::GetCommandLineArgs() | Where-Object { $_ -match '^-(NonInteractive|ni|Command|c|EncodedCommand|e|ec|File|f)$' }))

# Optional timing: set RABBIT_PROFILE_TRACE=1 and open a shell to see where startup time goes.
$RabbitTrace = $env:RABBIT_PROFILE_TRACE -eq '1'
$RabbitClock = [Diagnostics.Stopwatch]::StartNew()
function Write-RabbitTrace { param([string]$Label) if ($RabbitTrace) { Write-Host ("  [profile] {0,5} ms  {1}" -f $RabbitClock.ElapsedMilliseconds, $Label) -ForegroundColor DarkGray } }

[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$env:XDG_CONFIG_HOME ??= "$HOME\.config"
$env:XDG_DATA_HOME   ??= "$HOME\.local\share"
$env:XDG_STATE_HOME  ??= "$HOME\.local\state"
$env:XDG_CACHE_HOME  ??= "$HOME\.cache"

# Editor: Notepad++ when it is installed (Tools tier), otherwise the best thing that is.
$editor = foreach ($candidate in 'notepad++', 'nvim', 'notepad') {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) { $candidate; break }
}
$env:EDITOR = $env:VISUAL = if ($editor) { $editor } else { 'notepad' }

if (-not $RabbitInteractive) { return }

# ---------------------------------------------------------
# Modules - import only what has to be loaded up front.
# BurntToast, PSEverything and PSWriteColor are left to PowerShell's
# autoloading: they load the first time one of their commands is used.
# ---------------------------------------------------------
foreach ($module in 'Terminal-Icons', 'syntax-highlighting', 'PSCompletions') {
    if (Get-Module -ListAvailable -Name $module) {
        Import-Module $module -ErrorAction SilentlyContinue
    }
    else {
        Write-Verbose "Optional module '$module' is not installed (re-run the installer to add it)."
    }
}
Write-RabbitTrace 'modules'

# ---------------------------------------------------------
# Tool integrations (each one only if the tool exists)
# ---------------------------------------------------------
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { zoxide init --cmd z powershell | Out-String })
}
Write-RabbitTrace 'zoxide'

$global:RabbitAtuinEnabled = $false

if (Get-Command atuin -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { atuin init powershell | Out-String })

    # atuin's init binds UpArrow and Ctrl+r to its own search. The PSReadLine
    # key handlers further down would clobber those, so they check this flag.
    $global:RabbitAtuinEnabled = [bool](Get-Module Atuin)
}
Write-RabbitTrace 'atuin'

$RabbitTheme = Join-Path $global:RabbitSettings 'oh-my-rabbit.omp.json'

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    if (Test-Path -LiteralPath $RabbitTheme) {
        Invoke-Expression (& { oh-my-posh init pwsh --config $RabbitTheme | Out-String })
        $null = & prompt 2>$null
    }
    else {
        Write-Warning "Oh My Posh theme not found: $RabbitTheme"
    }
}
Write-RabbitTrace 'oh-my-posh'

# ---------------------------------------------------------
# PSReadLine
# ---------------------------------------------------------
$RabbitHasReadLine = [bool](Get-Module PSReadLine)

if ($RabbitHasReadLine) {
    try {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin
        Set-PSReadLineOption -PredictionViewStyle InLineView
        Set-PSReadLineOption -HistorySaveStyle SaveIncrementally

        Set-PSReadLineOption -Colors @{
            Command   = '#87CEEB'
            Parameter = '#98FB98'
            Operator  = '#FFB6C1'
            Variable  = '#DDA0DD'
            String    = '#FFDAB9'
            Number    = '#B0E0E6'
            Type      = '#F0E68C'
            Comment   = '#D3D3D3'
            Keyword   = '#8367c7'
            Error     = '#FF6347'
        }

        # UpArrow belongs to atuin when it is running - it opens atuin's search with
        # the current buffer as the query. Only fall back to PSReadLine's own history
        # search when atuin is not installed.
        if (-not $global:RabbitAtuinEnabled) {
            Set-PSReadLineKeyHandler -Key 'UpArrow' -Function HistorySearchBackward
        }

        Set-PSReadLineKeyHandler -Key 'DownArrow' -Function HistorySearchForward

        # Always available as the PSReadLine escape hatch, whether or not atuin owns the plain arrow keys.
        Set-PSReadLineKeyHandler -Chord 'Ctrl+UpArrow'   -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Chord 'Ctrl+DownArrow' -Function HistorySearchForward
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

        # Ctrl+f - fuzzy file search (git ls-files inside a repo, fd elsewhere)
        Set-PSReadLineKeyHandler -Chord Ctrl+f -ScriptBlock {
            if (-not ((Get-Command fzf -ErrorAction SilentlyContinue) -and (Get-Command fd -ErrorAction SilentlyContinue))) {
                Write-Host "`nCtrl+f needs fzf and fd - re-run the installer to add them." -ForegroundColor Yellow
                [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
                return
            }

            $files = if ((Get-Command git -ErrorAction SilentlyContinue) -and (git rev-parse --is-inside-work-tree 2>$null)) {
                git ls-files
            }
            else {
                fd --type file --hidden --exclude .git
            }

            $previewCmd = if (Get-Command bat -ErrorAction SilentlyContinue) { 'bat --style=numbers --color=always {}' } else { 'type {}' }
            $selected = $files | fzf --height 50% --layout reverse --border --preview $previewCmd

            if ($selected) { [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected) }
        }

        # Alt+Space - jump to a directory zoxide knows
        Set-PSReadLineKeyHandler -Chord Alt+Spacebar -ScriptBlock {
            if (-not ((Get-Command zoxide -ErrorAction SilentlyContinue) -and (Get-Command fzf -ErrorAction SilentlyContinue))) {
                Write-Host "`nAlt+Space needs zoxide and fzf - re-run the installer to add them." -ForegroundColor Yellow
                [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
                return
            }

            $previewCmd = if (Get-Command eza -ErrorAction SilentlyContinue) { 'eza --icons --group-directories-first {}' } else { 'dir {}' }
            $selected = zoxide query -l | fzf --height 40% --layout reverse --border --preview $previewCmd

            if ($selected) {
                [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
                Set-Location $selected
                [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
            }
        }

        # Ctrl+y - yazi, and cd to wherever you leave it
        Set-PSReadLineKeyHandler -Chord Ctrl+y -ScriptBlock {
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            yy
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }

        Set-PSReadLineKeyHandler -Key Ctrl+Spacebar -ScriptBlock {
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            Invoke-CommandPalette
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }
    }
    catch {
        Write-Warning "PSReadLine setup was skipped: $($_.Exception.Message)"
    }
}
Write-RabbitTrace 'PSReadLine'

function yy {
    if (-not (Get-Command yazi -ErrorAction SilentlyContinue)) {
        Write-Warning 'yazi is not installed - re-run the installer to add it.'
        return
    }

    $tmp = [System.IO.Path]::GetTempFileName()

    yazi $PWD --cwd-file="$tmp"

    if (Test-Path $tmp) {
        $cwd = Get-Content -Path $tmp -ErrorAction SilentlyContinue

        if ($cwd -and (Test-Path $cwd)) { Set-Location $cwd }

        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------
# Aliases, functions and key bindings - explicit order, then anything else
# ---------------------------------------------------------
# user-commands.ps1 (written by mkcmd) lives OUTSIDE the repo so `git pull` stays clean.
$global:RabbitUserCommands = Join-Path $HOME '.config\pwsh\user-commands.ps1'

$scriptOrder = 'aliases.ps1', 'aliases-git.ps1', 'functions.ps1', 'mkcmd.ps1', 'keybinds.ps1', 'notify.ps1'

if (Test-Path -LiteralPath $global:RabbitScripts) {
    $present = Get-ChildItem -LiteralPath $global:RabbitScripts -Filter *.ps1 -File
    $ordered = @($scriptOrder | ForEach-Object { $n = $_; $present | Where-Object Name -eq $n }) +
               @($present | Where-Object { $scriptOrder -notcontains $_.Name } | Sort-Object Name)

    foreach ($script in $ordered) {
        try { . $script.FullName }
        catch { Write-Warning "$($script.Name) failed to load: $($_.Exception.Message)" }
    }
}
else {
    Write-Warning "Script folder missing: $global:RabbitScripts - re-run the installer."
}

if (Test-Path -LiteralPath $global:RabbitUserCommands) {
    try { . $global:RabbitUserCommands }
    catch { Write-Warning "user-commands.ps1 failed to load: $($_.Exception.Message)" }
}
Write-RabbitTrace 'aliases/functions/keybinds'

# fzf / PSFzf config, deployed to ~\.config\fzf by the installer. It has to load after
# atuin and zoxide: it leaves Ctrl+R to atuin and feeds Alt+C from the zoxide database.
$RabbitFzfConfig = Join-Path $HOME '.config\fzf\PSFzf.config.ps1'
if (Test-Path -LiteralPath $RabbitFzfConfig) {
    try { . $RabbitFzfConfig } catch { Write-Warning "PSFzf config failed: $($_.Exception.Message)" }
}
Write-RabbitTrace 'fzf'

# YouShouldUse hooks the prompt to nag about unused aliases, so it must load after
# oh-my-posh sets the prompt AND after notify.ps1 wraps it.
if (Get-Module -ListAvailable -Name YouShouldUse) {
    Import-Module YouShouldUse -ErrorAction SilentlyContinue

    if (Get-Command Update-YouShouldUseHook -ErrorAction SilentlyContinue) {
        Update-YouShouldUseHook
    }
}
Write-RabbitTrace 'YouShouldUse'

# Machine-local additions - never touched by the installer.
$RabbitLocal = Join-Path (Split-Path -Parent $PROFILE) 'Microsoft.PowerShell_profile.local.ps1'
if (Test-Path -LiteralPath $RabbitLocal) {
    try { . $RabbitLocal } catch { Write-Warning "local profile failed: $($_.Exception.Message)" }
}

Write-Host "⚡ Ctrl+f File Search | Alt+Space Smart Jump | Ctrl+y Yazi | Ctrl+Space Command Palette" -ForegroundColor DarkGray
Write-RabbitTrace 'done'
