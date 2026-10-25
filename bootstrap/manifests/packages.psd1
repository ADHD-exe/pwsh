# =============================================================================
# packages.psd1 - winget package manifest
#
# Tiers (selected with  install.ps1 -Tier Core,Shell,Tools ; the DEFAULT is Core,Shell,Tools):
#   Core  - the installer and profile cannot work without these
#   Shell - the command-line stack the profile integrates with
#   Tools - editors / system utilities / Firefox Developer Edition that the repo's settings\ configure
#   Apps  - everything else from the old draft list; OPT-IN (-Tier Apps)
#
# Fields
#   Name       display name
#   Id         winget id (matched with --exact; ids are case-insensitive)
#   Command    command that proves it is installed ('' when it ships no CLI)
#   Paths      extra "is it installed" probes; %VARS% are expanded at runtime
#   Source     winget (default) | msstore
#   Admin      $true when the installer is known to be machine-wide and will
#              raise a UAC prompt. Used only to warn up front / skip with
#              -NoAdmin. UNVERIFIED hints - correct them after a clean-VM run.
#   Note       free text shown in the log
#
# IMPORTANT: every Id here is UNVERIFIED until run on Windows. Run
#   .\install.ps1 -VerifyOnly
# to check all ids against the winget source without installing anything.
# =============================================================================
@{
    Packages = @(

        # ------------------------------ Core --------------------------------
        @{ Tier = 'Core';  Name = 'Git';              Id = 'Git.Git';                  Command = 'git';  Paths = @('%ProgramFiles%\Git\cmd\git.exe') }
        @{ Tier = 'Core';  Name = 'PowerShell 7';     Id = 'Microsoft.PowerShell';     Command = 'pwsh'; Paths = @('%ProgramFiles%\PowerShell\7\pwsh.exe') }
        @{ Tier = 'Core';  Name = 'Windows Terminal'; Id = 'Microsoft.WindowsTerminal'; Command = 'wt';  Paths = @('%LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe') }
        @{ Tier = 'Core';  Name = 'Node.js LTS';      Id = 'OpenJS.NodeJS.LTS';        Command = 'node'; Paths = @('%ProgramFiles%\nodejs\node.exe') }

        # ------------------------------ Shell -------------------------------
        @{ Tier = 'Shell'; Name = 'Oh My Posh';  Id = 'JanDeDobbeleer.OhMyPosh'; Command = 'oh-my-posh' }
        @{ Tier = 'Shell'; Name = 'Atuin';       Id = 'Atuinsh.Atuin';           Command = 'atuin' }
        @{ Tier = 'Shell'; Name = 'zoxide';      Id = 'ajeetdsouza.zoxide';      Command = 'zoxide' }
        @{ Tier = 'Shell'; Name = 'fzf';         Id = 'junegunn.fzf';            Command = 'fzf' }
        @{ Tier = 'Shell'; Name = 'fd';          Id = 'sharkdp.fd';              Command = 'fd' }
        @{ Tier = 'Shell'; Name = 'bat';         Id = 'sharkdp.bat';             Command = 'bat' }
        @{ Tier = 'Shell'; Name = 'eza';         Id = 'eza-community.eza';       Command = 'eza' }
        @{ Tier = 'Shell'; Name = 'Yazi';        Id = 'sxyazi.yazi';             Command = 'yazi' }
        @{ Tier = 'Shell'; Name = 'ripgrep';     Id = 'BurntSushi.ripgrep.MSVC'; Command = 'rg' }
        @{ Tier = 'Shell'; Name = 'git-lfs';     Id = 'GitHub.GitLFS';           Command = 'git-lfs' }
        @{ Tier = 'Shell'; Name = 'OpenCode';    Id = 'SST.opencode';            Command = 'opencode'; Paths = @('%LOCALAPPDATA%\Microsoft\WinGet\Links\opencode.exe') }
        @{ Tier = 'Shell'; Name = 'Neovim';      Id = 'Neovim.Neovim';           Command = 'nvim';     Paths = @('%ProgramFiles%\Neovim\bin\nvim.exe'); Note = 'aliases vim/v and Edit-Profile call nvim' }

        # ------------------------------ Tools -------------------------------
        @{ Tier = 'Tools'; Name = 'Notepad++';   Id = 'Notepad++.Notepad++';     Command = 'notepad++'; Paths = @('%ProgramFiles%\Notepad++\notepad++.exe', '%ProgramFiles(x86)%\Notepad++\notepad++.exe') }
        @{ Tier = 'Tools'; Name = 'AutoHotkey v2'; Id = 'AutoHotkey.AutoHotkey'; Command = '';          Paths = @('%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe', '%ProgramFiles%\AutoHotkey\AutoHotkey.exe'); Admin = $true }
        @{ Tier = 'Tools'; Name = 'Everything';  Id = 'voidtools.Everything';   Command = '';          Paths = @('%ProgramFiles%\Everything\Everything.exe'); Admin = $true }
        @{ Tier = 'Tools'; Name = 'Everything CLI (es)'; Id = 'voidtools.Everything.Cli'; Command = 'es'; Paths = @('%ProgramFiles%\Everything\es.exe', '%LOCALAPPDATA%\Microsoft\WinGet\Links\es.exe'); Note = 'PSEverything and the profile use es' }
        @{ Tier = 'Tools'; Name = 'EverythingToolbar'; Id = 'srwi.EverythingToolbar'; Command = '';    Paths = @('%ProgramFiles%\EverythingToolbar'); Admin = $true; Note = 'draft listed .Launcher and .Deskband; verify which id exists' }
        @{ Tier = 'Tools'; Name = 'CMake';       Id = 'Kitware.CMake';           Command = 'cmake';  Paths = @('%ProgramFiles%\CMake\bin\cmake.exe') }
        @{ Tier = 'Tools'; Name = 'Python 3.14'; Id = 'Python.Python.3.14';      Command = 'python'; Paths = @('%LOCALAPPDATA%\Programs\Python\Python314\python.exe', '%LOCALAPPDATA%\Programs\Python\Launcher\py.exe') }
        # Command stays empty on purpose: a regular Firefox on PATH must not count as "Developer Edition is installed".
        @{ Tier = 'Tools'; Name = 'Firefox Developer Edition'; Id = 'Mozilla.Firefox.DeveloperEdition'; Command = ''; Paths = @('%ProgramFiles%\Firefox Developer Edition\firefox.exe', '%ProgramFiles(x86)%\Firefox Developer Edition\firefox.exe'); Admin = $true; Note = 'on the system PATH; the profile adds a `firefox` command; Win+B in keybinds.ahk' }
        @{ Tier = 'Tools'; Name = 'PeaZip';      Id = 'Giorgiotani.Peazip';      Command = '';       Paths = @('%ProgramFiles%\PeaZip\peazip.exe') }
        @{ Tier = 'Tools'; Name = 'Autoruns';    Id = 'Microsoft.Sysinternals.Autoruns'; Command = 'autoruns'; Paths = @('%ProgramFiles%\Autoruns') }

        # ------------------------------ Apps (opt-in) -----------------------
        @{ Tier = 'Apps';  Name = 'Starship';    Id = 'Starship.Starship';       Command = 'starship'; Note = 'profile uses Oh My Posh; Starship is only here because the draft listed it' }
        @{ Tier = 'Apps';  Name = 'Tailscale';   Id = 'Tailscale.Tailscale';     Command = 'tailscale'; Paths = @('%ProgramFiles%\Tailscale\tailscale.exe'); Admin = $true }
        @{ Tier = 'Apps';  Name = 'Spotify';     Id = 'Spotify.Spotify';         Command = '';       Paths = @('%APPDATA%\Spotify\Spotify.exe') }
        @{ Tier = 'Apps';  Name = 'Equibop';     Id = 'Equicord.Equibop';        Command = '';       Paths = @('%LOCALAPPDATA%\Equibop\equibop.exe') }
        @{ Tier = 'Apps';  Name = 'Outlook for Windows'; Id = '9NRX63209R7B';    Command = '';       Source = 'msstore'; Appx = 'Microsoft.OutlookForWindows' }
        @{ Tier = 'Apps';  Name = 'Paint.NET';   Id = 'dotPDN.PaintDotNet';      Command = '';       Paths = @('%ProgramFiles%\paint.net\paintdotnet.exe') }
        @{ Tier = 'Apps';  Name = 'GIMP';        Id = 'GIMP.GIMP';               Command = '' }
        @{ Tier = 'Apps';  Name = 'VLC';         Id = 'VideoLAN.VLC';            Command = '';       Paths = @('%ProgramFiles%\VideoLAN\VLC\vlc.exe') }
        @{ Tier = 'Apps';  Name = 'OBS Studio';  Id = 'OBSProject.OBSStudio';    Command = '' }
        @{ Tier = 'Apps';  Name = 'ShareX';      Id = 'ShareX.ShareX';           Command = '';       Paths = @('%ProgramFiles%\ShareX\ShareX.exe') }
        @{ Tier = 'Apps';  Name = 'qBittorrent'; Id = 'qBittorrent.qBittorrent'; Command = '' }
        @{ Tier = 'Apps';  Name = 'Signal';      Id = 'OpenWhisperSystems.Signal'; Command = '' }
        @{ Tier = 'Apps';  Name = 'Telegram';    Id = 'Telegram.TelegramDesktop'; Command = '' }
        @{ Tier = 'Apps';  Name = 'Proton Authenticator'; Id = 'Proton.ProtonAuthenticator'; Command = '' }
        @{ Tier = 'Apps';  Name = 'Ollama';      Id = 'Ollama.Ollama';           Command = 'ollama' }
        @{ Tier = 'Apps';  Name = 'Syncthing';   Id = 'Syncthing.Syncthing';     Command = 'syncthing' }
        @{ Tier = 'Apps';  Name = 'SyncTrayzor'; Id = 'GermanCoding.SyncTrayzor'; Command = '' }
        @{ Tier = 'Apps';  Name = 'Spicetify';   Id = 'Spicetify.Spicetify';     Command = 'spicetify' }
        @{ Tier = 'Apps';  Name = 'BetterTrumpet'; Id = 'xmn.BetterTrumpet';     Command = '' }
        @{ Tier = 'Apps';  Name = 'RDCMan';      Id = 'Microsoft.Sysinternals.RDCMan'; Command = '' }
        @{ Tier = 'Apps';  Name = 'Bulk Crap Uninstaller'; Id = 'Klocman.BulkCrapUninstaller'; Command = '' }

        # Risky to apply unattended: kept in Apps, flagged Admin, and skipped
        # entirely unless you also pass -IncludeRisky.
        @{ Tier = 'Apps';  Name = 'simplewall';  Id = 'Henry++.simplewall';      Command = '';       Paths = @('%ProgramFiles%\simplewall\simplewall.exe'); Admin = $true; Risky = $true; Note = 'host firewall - will block traffic until configured' }
        @{ Tier = 'Apps';  Name = 'Winaero Tweaker'; Id = 'winaero.tweaker';     Command = '';       Paths = @('%ProgramFiles%\Winaero Tweaker\WinaeroTweaker.exe'); Risky = $true }
        @{ Tier = 'Apps';  Name = 'DISMTools';   Id = 'CodingWondersSoftware.DISMTools.Stable'; Command = ''; Admin = $true; Risky = $true }
        @{ Tier = 'Apps';  Name = 'NVCleanstall'; Id = 'TechPowerUp.NVCleanstall'; Command = '';     Admin = $true; Risky = $true; Note = 'NVIDIA driver installer' }
    )

    # Global npm packages the profile's aliases (claude) point at.
    # Installed in the Shell tier, only when node/npm is present.
    NpmGlobals = @(
        @{ Name = '@anthropic-ai/claude-code'; Command = 'claude' }
    )
}
