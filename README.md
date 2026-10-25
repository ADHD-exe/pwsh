# pwsh — one-command Windows terminal environment

Turns a fresh Windows install into a complete working shell: PowerShell 7, Windows Terminal,
the `oh-my-rabbit` Oh My Posh theme, Nerd Fonts, a modular PowerShell profile, a modern
command-line toolset (Atuin, zoxide, fzf, fd, bat, eza, Yazi, ripgrep, Neovim, OpenCode),
GitHub SSH, and — optionally — Notepad++, Firefox Developer Edition, AutoHotkey and Everything with their configs.

Re-running it is safe: it repairs what is missing, updates what changed, and leaves
everything else alone. Anything it replaces is backed up first.

**Contents:** [Install](#install) · [Requirements](#requirements) · [What you should know first](#what-you-should-know-first) ·
[Steps](#what-the-installer-does-in-order) · [Packages](#packages-installed-with-winget) ·
[npm](#npm-packages) · [Modules](#powershell-modules) · [Fonts](#fonts) · [System PATH](#system-path-changes) ·
[Terminal settings](#windows-terminal-settings) · [Configs](#app-configs-it-deploys) ·
[Using the shell](#using-the-shell) · [Options](#installer-options) · [Troubleshooting](#troubleshooting) ·
[Repo layout](#repo-layout)

---

## Install

Open **PowerShell** (the blue "Windows PowerShell" that ships with Windows is fine —
you do **not** need to run it as administrator) and paste:

```powershell
irm https://raw.githubusercontent.com/ADHD-exe/pwsh/main/install.ps1 | iex
```

With options (same one line, extra switches at the end). This example also installs the optional **Apps** tier:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ADHD-exe/pwsh/main/install.ps1))) -Tier Core,Shell,Tools,Apps
```

### Safer: download, read, then run

Piping a web page into `iex` runs whatever that page says at that moment. The first
time, read it instead:

```powershell
irm https://raw.githubusercontent.com/ADHD-exe/pwsh/main/install.ps1 -OutFile install.ps1
notepad install.ps1          # ~140 lines; it only downloads the repo and starts the installer
.\install.ps1 -DownloadOnly  # downloads + unpacks the repo and stops, so you can read bootstrap\ too
.\install.ps1                # run it for real
```

To see what *would* happen without changing anything: `.\install.ps1 -WhatIf`.

To pin an exact version and refuse anything else:

```powershell
.\install.ps1 -Ref v1.0.0 -ExpectedSha256 <hash printed by a previous -DownloadOnly run>
```

> **What gets trusted:** `install.ps1` downloads `github.com/ADHD-exe/pwsh` over HTTPS,
> prints the archive's SHA-256, and runs `bootstrap\Install-Environment.ps1` from it. It
> does not download or run any other script. Packages come from winget, modules from the
> PowerShell Gallery, and the `YouShouldUse` module from
> `github.com/ADHD-exe/pwsh-you-should-use`. It never disables Defender, UAC or the
> execution policy (the nested PowerShell 7 process uses a *process-only* bypass so the
> installer's own files can run; nothing persistent is changed).

---

## Requirements

| | |
|---|---|
| Windows | 10 version 1809 (build 17763) or newer, or Windows 11 |
| winget | Comes with "App Installer". On a brand-new Windows 10 it can take a few minutes after first sign-in to appear; update *App Installer* in the Microsoft Store if `winget --version` fails |
| PowerShell | Starts in Windows PowerShell 5.1; the installer installs PowerShell 7 and continues there |
| Internet | github.com, PowerShell Gallery, winget sources |
| Permissions | A normal user account. UAC prompts appear for machine-wide installers and once for the **system PATH** step |
| GitHub account | Optional, but the installer sets up SSH access to GitHub (see step 4). Type `SKIP` there to continue without it |

---

## What you should know first

Read this before your first run.

- **It changes real settings on your machine.** It installs software, merges Windows Terminal's
  `settings.json`, writes your PowerShell profile stub, installs fonts, edits the **system PATH**,
  and (if present) replaces Notepad++ / Everything config files. Every replaced file is backed up
  next to the original as `NAME.bak-<timestamp>`, and the PATH is backed up before it is changed.
- **Expect prompts.** It asks for your git name/email only if they are missing, asks whether to
  replace an existing `~\.pwsh`, may pause while you add an SSH key on GitHub, and shows a UAC
  prompt for machine-wide installers and once for the PATH step. `-Unattended` suppresses the questions.
- **It opens a second terminal window.** After the PATH step it relaunches itself in a **new
  Windows Terminal window** so the new PATH, fonts and profile are in effect, finishes the
  verification there, and leaves you in your configured shell. You can close the first window.
  Use `-NoRelaunch` to stay in one window.
- **Core, Shell and Tools install by default.** That includes Notepad++, AutoHotkey, Everything (plus its CLI and
  taskbar toolbar), CMake, Python 3.14, PeaZip and Autoruns. Three of these (AutoHotkey, Everything,
  EverythingToolbar) use machine-wide installers and raise their own UAC prompts; `-NoAdmin` skips them.
  Personal apps (Spotify, Discord client, OBS, ...) are the **Apps** tier and are opt-in with
  `-Tier Core,Shell,Tools,Apps`. Firewall/driver/tweaker tools are additionally skipped unless you pass `-IncludeRisky`.
  To install only the minimum, use `-Tier Core,Shell`.
- **Open apps keep the old PATH and fonts.** Restart apps that were already running (for example
  Notepad++) to see new fonts, and open a new terminal to pick up PATH changes.
- **Two optional extras are asked once, near the start.** (1) *Themes*: the `oh-my-rabbit` prompt theme, the
  Windows Terminal colour scheme, and the matching Atuin, Yazi, fzf and Notepad++ colours are installed **all
  together or not at all** - answer no and every theme is skipped. (2) *Keybinds*: whether to install
  AutoHotkey and the program-launcher script. Answers are remembered; `-Themes Yes|No` and `-Keybinds Yes|No`
  answer in advance, and `-Unattended` reuses the remembered answers (yes the first time).
- **There is no uninstaller.** Packages can be removed with `winget uninstall`, modules with
  `Uninstall-Module`, and backups are kept so you can restore replaced files by hand.
- **The `claude` command** (Claude Code) is installed from npm, and `opencode` from winget. They are
  installed, not configured with any account — you sign in to each yourself.

---

## What the installer does, in order

| # | Step | What happens |
|---|---|---|
| 1 | **prereqs** | Checks Windows build, winget, network. Stops early with a clear message if something is missing |
| 2 | **core** | Installs Git, PowerShell 7, Windows Terminal, Node.js LTS, then continues inside PowerShell 7 |
| 3 | **repo** | Clones this repo to `~\.pwsh` (shallow). That is the permanent home; updating = `git pull`. If it already exists, asks whether to remove it and install a fresh copy (`-FreshRepo` answers yes; `-Unattended` updates in place) |
| 4 | **git** | Each part is checked first and skipped if already done. Asks for `user.name` and `user.email` only if missing. If SSH to GitHub already works, nothing else happens; if not, it creates a key if you have none, **shows the public key** (clipboard + add-key page) and **waits until GitHub accepts it** (type `SKIP` to continue without SSH), then turns on `https://github.com/` → SSH rewriting. Also configures git-lfs |
| 5 | **packages** | Installs the selected tiers via winget, detecting what is already there |
| 6 | **npm** | Global npm packages the profile's aliases use (`claude`) |
| 7 | **modules** | Installs PowerShell modules for PowerShell 7 (CurrentUser), then imports each in a clean process to prove they load |
| 8 | **fonts** | Installs the bundled Nerd Fonts for the current user (no admin) |
| 9 | **profile** | Writes a small stub to `Documents\PowerShell\Microsoft.PowerShell_profile.ps1` that loads the repo profile |
| 10 | **terminal** | Merges `settings\settings.json` into Windows Terminal's settings (backup first) |
| 11 | **configs** | Deploys Atuin, fzf, git ignore, OpenCode, and — if installed — Notepad++, Everything, AutoHotkey |
| 12 | **path** | Adds the executable folders listed under [System PATH changes](#system-path-changes) to the **system PATH** (one UAC prompt) |
| 13 | **verify** | Opens a **new terminal window** and finishes there: checks every command, the theme, the font, loads the profile in a fresh `pwsh` and times it, validates Terminal's JSON, then leaves you in your configured shell |

Run only some steps with `-Only`, for example `.\install.ps1 -Only fonts,profile`
(valid steps: `prereqs, core, repo, git, packages, npm, modules, fonts, profile, terminal, configs, path, verify`).

---

## Packages installed with winget

Packages are grouped in **tiers**. Choose tiers with `-Tier`; the default is `Core,Shell,Tools`.
A package that is already installed (command found on PATH or its usual install path exists) is skipped.

### Core — always installed

| Package | winget id | Command | Why |
|---|---|---|---|
| Git | `Git.Git` | `git` | Version control; the repo is a git clone |
| PowerShell 7 | `Microsoft.PowerShell` | `pwsh` | The shell everything targets |
| Windows Terminal | `Microsoft.WindowsTerminal` | `wt` | Terminal host with the bundled settings |
| Node.js LTS | `OpenJS.NodeJS.LTS` | `node` | Needed for the npm package below |

### Shell — default

| Package | winget id | Command | What it is |
|---|---|---|---|
| Oh My Posh | `JanDeDobbeleer.OhMyPosh` | `oh-my-posh` | Prompt engine (theme: `oh-my-rabbit`) |
| Atuin | `Atuinsh.Atuin` | `atuin` | Searchable shell history database |
| zoxide | `ajeetdsouza.zoxide` | `zoxide` | Smarter `cd` that learns your folders |
| fzf | `junegunn.fzf` | `fzf` | Fuzzy finder |
| fd | `sharkdp.fd` | `fd` | Fast file finder (used by fzf) |
| bat | `sharkdp.bat` | `bat` | `cat` with syntax highlighting |
| eza | `eza-community.eza` | `eza` | Modern `ls` (icons, git status, tree) |
| Yazi | `sxyazi.yazi` | `yazi` | Terminal file manager |
| ripgrep | `BurntSushi.ripgrep.MSVC` | `rg` | Fast text search |
| git-lfs | `GitHub.GitLFS` | `git-lfs` | Git large file support |
| OpenCode | `SST.opencode` | `opencode` | AI coding assistant in the terminal |
| Neovim | `Neovim.Neovim` | `nvim` | Editor; `vim`/`v` and `ep` use it |

### Tools — installed by default

| Package | winget id | Command | Notes |
|---|---|---|---|
| Notepad++ | `Notepad++.Notepad++` | `notepad++` | Config deployed from `settings\notepad++` |
| AutoHotkey v2 | `AutoHotkey.AutoHotkey` | — | Runs the launcher keybinds script. Only installed if you say yes to the keybinds prompt. Admin installer |
| Firefox Developer Edition | `Mozilla.Firefox.DeveloperEdition` | `firefox` | Added to the system PATH; the profile defines `firefox` to launch it. Checked first, so an existing install is kept. Admin installer |
| Everything | `voidtools.Everything` | — | Instant file search; config deployed. Admin installer |
| Everything CLI | `voidtools.Everything.Cli` | `es` | Used by PSEverything and the profile |
| EverythingToolbar | `srwi.EverythingToolbar` | — | Taskbar search. Admin installer |
| CMake | `Kitware.CMake` | `cmake` | |
| Python 3.14 | `Python.Python.3.14` | `python` | |
| PeaZip | `Giorgiotani.Peazip` | — | Archive manager |
| Autoruns | `Microsoft.Sysinternals.Autoruns` | `autoruns` | Startup-entry viewer |

### Apps — opt-in (`-Tier Core,Shell,Tools,Apps`)

Personal desktop apps. Nothing here is needed by the shell.

| Package | winget id |
|---|---|
| Starship | `Starship.Starship` (not used by the profile, which uses Oh My Posh) |
| Tailscale (admin) | `Tailscale.Tailscale` |
| Spotify | `Spotify.Spotify` |
| Equibop | `Equicord.Equibop` |
| Outlook for Windows | Microsoft Store `9NRX63209R7B` |
| Paint.NET | `dotPDN.PaintDotNet` |
| GIMP | `GIMP.GIMP` |
| VLC | `VideoLAN.VLC` |
| OBS Studio | `OBSProject.OBSStudio` |
| ShareX | `ShareX.ShareX` |
| qBittorrent | `qBittorrent.qBittorrent` |
| Signal | `OpenWhisperSystems.Signal` |
| Telegram | `Telegram.TelegramDesktop` |
| Proton Authenticator | `Proton.ProtonAuthenticator` |
| Ollama | `Ollama.Ollama` |
| Syncthing | `Syncthing.Syncthing` |
| SyncTrayzor | `GermanCoding.SyncTrayzor` |
| Spicetify | `Spicetify.Spicetify` |
| BetterTrumpet | `xmn.BetterTrumpet` |
| RDCMan | `Microsoft.Sysinternals.RDCMan` |
| Bulk Crap Uninstaller | `Klocman.BulkCrapUninstaller` |

**Risky — skipped unless you also pass `-IncludeRisky`:** simplewall (`Henry++.simplewall`, a host firewall that
blocks traffic until configured), Winaero Tweaker (`winaero.tweaker`), DISMTools
(`CodingWondersSoftware.DISMTools.Stable`) and NVCleanstall (`TechPowerUp.NVCleanstall`, an NVIDIA driver installer).

The full, authoritative list lives in `bootstrap\manifests\packages.psd1`. Check that every id still
exists on your winget source without installing anything: `.\install.ps1 -VerifyOnly`.

---

## npm packages

Installed globally in the Shell tier, only when `node`/`npm` is present:

| Package | Command |
|---|---|
| `@anthropic-ai/claude-code` | `claude` |

---

## PowerShell modules

Installed for **PowerShell 7**, **CurrentUser** scope (no admin). After installing, each module is imported in a
clean process to prove it loads. Defined in `bootstrap\manifests\modules.psd1`.

| Module | Source | Purpose |
|---|---|---|
| Terminal-Icons | PowerShell Gallery | File and folder icons in listings |
| PSReadLine (min 2.3.6) | PowerShell Gallery | Line editing, history, key bindings (upgraded only if the bundled copy is older) |
| PSWriteColor | PowerShell Gallery | Coloured console output (autoloads on first use) |
| syntax-highlighting | PowerShell Gallery | Colours your command as you type |
| PSEverything | PowerShell Gallery | PowerShell interface to Everything (autoloads on first use) |
| PSFzf | PowerShell Gallery | fzf key bindings and commands (`Ctrl+t`, `Alt+r`, `Alt+c`, `Alt+a`, `fkill`, `fgs`, `fh`, `cde`) |
| BurntToast | PowerShell Gallery | Windows toast notifications (autoloads on first use) |
| PSCompletions | PowerShell Gallery | Extra tab completions |
| YouShouldUse | `github.com/ADHD-exe/pwsh-you-should-use` (cloned over HTTPS) | Reminds you when an alias exists for what you typed |

---

## Fonts

39 font files bundled in `settings\fonts`, installed **per user** (no admin) and registered in the user font list.
Three Nerd Font families, each in three width variants (regular, **Mono**, **Propo**):

| Family | Styles bundled |
|---|---|
| **Monoid Nerd Font** (used by Windows Terminal, 13 pt) | Regular, Bold, Italic, Retina |
| **FiraCode Nerd Font** | Regular, Light, Medium, SemiBold, Bold, Retina |
| **EnvyCodeR Nerd Font** | Regular, Bold, Italic |

Licenses are in `settings\fonts\licenses`. **A Nerd Font is required** — without one, the prompt's icons
show as empty boxes. Apps that were already open (Notepad++, editors) need a restart to list new fonts.

---

## System PATH changes

Step 12 adds folders to the **system (Machine) PATH**. It needs administrator rights, so the installer opens a
**one-time elevated window** (one UAC prompt) just for this step. Use `-PathScope User` to change only your user
PATH instead (no prompt). The previous PATH is backed up first.

The installer does not add folders blindly. For each entry it skips it if the folder is missing, holds no
`.exe`/`.cmd`/`.bat`, or is already on the PATH. So tools you did not install are simply reported as skipped.

| Folder | Belongs to |
|---|---|
| `%ProgramFiles%\Notepad++` | Notepad++ (Tools) |
| `%ProgramFiles%\CMake\bin` | CMake (Tools) |
| `%ProgramFiles%\7-Zip` | 7-Zip (not installed by this repo; added only if present) |
| `%ProgramFiles%\AutoHotkey` | AutoHotkey (Tools) |
| `%ProgramFiles%\Autoruns` | Autoruns (Tools) |
| `%ProgramFiles%\Everything` | Everything (Tools) |
| `%ProgramFiles%\EverythingToolbar` | EverythingToolbar (Tools) |
| `%ProgramFiles%\Firefox Developer Edition` | Firefox Developer Edition (Tools) |
| `%ProgramFiles%\Git\cmd` | Git (Core) |
| `%ProgramFiles%\Go\bin` | Go (not installed by this repo; added only if present) |
| `%ProgramFiles%\paint.net` | Paint.NET (Apps) |
| `%ProgramFiles%\PeaZip` | PeaZip (Tools) |
| `%ProgramFiles%\Tailscale` | Tailscale (Apps) |
| `%ProgramFiles%\ShareX` | ShareX (Apps) |
| `%ProgramFiles%\starship\bin` | Starship (Apps) |
| `%ProgramFiles%\simplewall` | simplewall (Apps, risky) |
| `%ProgramFiles%\nodejs` | Node.js (Core) |

Most winget installers add their own PATH entries; these are the folders that do not reliably do so.
Edit the list in `bootstrap\manifests\path.psd1`. Programs that are already open keep the old PATH until restarted.

---

## Windows Terminal settings

`settings\settings.json` is **merged** into Windows Terminal's own `settings.json` (a backup is made first). It sets:

- Font **Monoid Nerd Font**, size 13, and the **Night City** colour scheme as the default.
- Profiles for **Pwsh** (PowerShell 7, the default), Windows PowerShell and Command Prompt.
- About 50 extra colour schemes (Dracula, TokyoNight, catppuccin-mocha, Rose Pine, Synthwave, Retrowave, and more).
- Bell behaviour used by the command-finished notifications.

Windows Terminal reloads `settings.json` on save; close all windows once if the font looks wrong.

---

## App configs it deploys

All copied from `settings\`. If a target differs it is backed up as `NAME.bak-<timestamp>` and replaced.

| What | From | To |
|---|---|---|
| Atuin | `settings\atuin\config.toml` | `~\.config\atuin\config.toml` |
| fzf (options, preview scripts, PSFzf config) | `settings\fzf\` | `~\.config\fzf\` |
| Global git ignore | `settings\git\ignore` | `~\.config\git\ignore` |
| OpenCode | `settings\opencode\opencode.jsonc` | `~\.config\opencode\` |
| Notepad++ (if installed) | `settings\notepad++\*.xml` | `%APPDATA%\Notepad++\` |
| Everything (if installed) | `settings\everything\Everything.ini` | `%APPDATA%\Everything\` |
| AutoHotkey launcher script (if you chose it) | `settings\autohotkey\keybinds.ahk` | `Documents\AutoHotkey\` |
| Oh My Posh theme | **not copied** — the profile loads `settings\oh-my-rabbit.omp.json` straight from the repo | — |

Notepad++ and Everything rewrite their config when they exit, so the installer closes them **gracefully**
(never killed), replaces the files, then reopens them. If an app will not close, the file is still replaced and a
warning tells you it may be overwritten.

Git also gets: SSH rewriting of `https://github.com/` URLs and git-lfs filters (see step 4).

---

## Using the shell

Open a new terminal. The repo profile (`profile\`) loads from `~\.pwsh`; update it any time with `git pull` there.

**Key bindings**

| Keys | Does |
|---|---|
| `Ctrl+f` | Fuzzy file search (git files inside a repo, `fd` elsewhere) |
| `Alt+Space` | Jump to a directory zoxide knows |
| `Ctrl+y` | Yazi file manager; the shell `cd`s to where you leave it |
| `Ctrl+Space` | Command palette |
| `Ctrl+r` / `Up` | Atuin history search |
| `Ctrl+t` | Insert file path(s) with fzf |
| `Alt+r` | Search PSReadLine history with fzf |
| `Alt+c` | Jump to a directory with fzf |
| `Alt+a` | Pull an argument out of history |
| `Ctrl+Up` / `Ctrl+Down` | Prefix history search |
| `Ctrl+Shift+z` / `Ctrl+Shift+x` | Undo / kill region |

**Commands worth knowing**

- `qol` lists everything; `nav` lists navigation shortcuts.
- Listing: `ls`, `ll`, `la`, `lt` (all eza). `cat` is `bat` when installed. `vim` and `v` are Neovim.
- Navigation: `..`, `...`, `home`, `docs`, `dl`, `desk`, `tmp`, `mkcd <dir>`, `z <dir>` (zoxide), `yy`/`y` (Yazi).
- Git: an Oh My Zsh–style set (`gst`, `ga`, `gaa`, `gco`, `gcmsg`, `gp`, `gl`, `glog`, ...).
- winget shortcuts: `ws`, `wi`, `wl`, `wr`, `wun`.
- AI: `oc`/`oco`/`ai` start OpenCode; `claude` starts Claude Code.
- Screenshots: `ss`, `ssw` (window), `ssr` (region), `ssc` (to clipboard).
- Profile: `ep` / `profile` edit it, `reload` / `rl` reload it, `mkcmd` creates your own alias or function.
- Machine-local additions go in `Documents\PowerShell\Microsoft.PowerShell_profile.local.ps1` so `git pull` never overwrites them.
- A **toast notification and terminal bell** fire when a command that ran 8 seconds or longer finishes.

**AutoHotkey shortcuts** (only if you said yes to the keybinds prompt; `settings\autohotkey\keybinds.ahk`):
`Win+Enter` PowerShell 7, `Win+B` Firefox Developer Edition, `Win+N` Notepad++, `Win+F` Explorer, `Win+M` Microsoft Store,
`Win+Q` close window, `Win+PgUp/PgDn` maximise/minimise, plus Mac-style `Win+C/V/X/Z` copy/paste/cut/undo.
A launcher key is only created when its program exists on the PC (Windows' own programs, or the ones this installer
installs), so no key ever points at something missing. Reload the script after installing a program later.

---

## Installer options

| Option | Meaning |
|---|---|
| `-Tier Core,Shell,Tools,Apps` | Which package tiers to install (default `Core,Shell,Tools`) |
| `-Only <steps>` | Run only the named steps |
| `-PathScope Machine\|User` | System PATH (default, one UAC prompt) or your user PATH |
| `-Themes Ask\|Yes\|No` | Install every colour theme together, or none (default: ask once) |
| `-Keybinds Ask\|Yes\|No` | Install AutoHotkey and the launcher keybinds script (default: ask once) |
| `-GitUser`, `-GitEmail` | Git identity to set if missing |
| `-InstallDir` | Where the repo lives (default `~\.pwsh`) |
| `-RepoUrl`, `-Branch` | Use a fork or another branch |
| `-WhatIf` | Dry run: show what would happen |
| `-VerifyOnly` | Only check that every winget id exists |
| `-IncludeRisky` | Also install the Risky Apps (firewall, tweakers, driver installer) |
| `-NoAdmin` | Skip packages known to need a UAC prompt |
| `-Force` | Replace config files even if unchanged-looking |
| `-Unattended` | No questions; update `~\.pwsh` in place |
| `-SkipSsh` | Skip the GitHub SSH step |
| `-FreshRepo` | Answer "yes" to replacing an existing `~\.pwsh` |
| `-NoRelaunch` | Stay in this window instead of opening a new terminal |
| `-DownloadOnly`, `-Ref`, `-ExpectedSha256` | `install.ps1` options: download only / pin a tag / require a hash |

---

## Troubleshooting

- **Logs:** `%LOCALAPPDATA%\RabbitBootstrap\logs\install-<timestamp>.log`. The summary at the end lists
  what needs attention.
- **Icons look like boxes:** the terminal is not using a Nerd Font. Close all Windows Terminal windows and reopen, or
  check that the Terminal profile font is *Monoid Nerd Font*.
- **A command is "not found" right after install:** open a **new** terminal. PATH changes do not reach windows that
  were already open.
- **"Profile produced errors" during verify:** the check runs the profile in a child shell where PSReadLine cannot
  load, so errors that only mention PSReadLine, PSFzf or `YSU_NO_AUTOENABLE` are ignored. Anything else is a real
  error: send the log.
- **Git push says to pull first:** your local `main` is behind GitHub. Commit, then `git pull --rebase origin main`,
  then push. Do not force-push.
- **Re-run any time** to repair or update; it skips what is already done.

---

## Repo layout

```
install.ps1                    entry point (download + run the installer)
bootstrap\
  Install-Environment.ps1      the orchestrator
  steps\                       one file per step (10-prereqs ... 95-verify)
  manifests\                   packages.psd1, modules.psd1, path.psd1
  lib\                         shared helpers (Common, Relaunch, ...)
profile\                       the PowerShell profile + aliases, functions, key bindings, notifications
settings\                      configs and assets it deploys (terminal, fonts, theme, Atuin, fzf, git, OpenCode,
                               Notepad++, Everything, AutoHotkey)
tests\                         parser and merge tests, run in CI
docs\                          audit and planning notes
```
