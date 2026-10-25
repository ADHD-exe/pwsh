# pwsh — one-command Windows terminal environment

Turns a fresh Windows install into my working shell: PowerShell 7, Windows Terminal,
Oh My Posh with the `oh-my-rabbit` theme, Nerd Fonts, Atuin, zoxide, fzf, fd, bat, eza,
Yazi, OpenCode, a modular profile, GitHub SSH — and optionally Notepad++, AutoHotkey
and Everything with their configs.

Re-running it is safe: it repairs what is missing, updates what changed, and leaves
everything else alone. Anything it replaces is backed up first.

---

## Install

Open **PowerShell** (the blue "Windows PowerShell" that ships with Windows is fine —
you do **not** need to run it as administrator) and paste:

```powershell
irm https://raw.githubusercontent.com/ADHD-exe/pwsh/main/install.ps1 | iex
```

With options (same one line, extra switches at the end):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ADHD-exe/pwsh/main/install.ps1))) -Tier Core,Shell,Tools
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
> PowerShell Gallery, and my own `YouShouldUse` module from
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

---

## What the installer does, in order

| # | Step | What happens |
|---|---|---|
| 1 | **prereqs** | Checks Windows build, winget, network. Stops early with a clear message if something is missing |
| 2 | **core** | Installs Git, PowerShell 7, Windows Terminal, Node.js LTS, then continues inside PowerShell 7 |
| 3 | **repo** | Clones this repo to `~\.pwsh` (shallow). That is the permanent home; updating = `git pull` |
| 4 | **git** | Each part is checked first and skipped if already done. Asks for `user.name` and `user.email` only if missing. If SSH to GitHub already works, nothing else happens; if not, it creates a key if you have none, **shows the public key** (clipboard + add-key page) and **waits until GitHub accepts it** (type `SKIP` to continue without SSH), then turns on `https://github.com/` → SSH rewriting |
| 5 | **packages** | Installs the selected tiers (below) via winget, detecting what is already there |
| 6 | **npm** | Global npm packages the profile's aliases use (`claude`) |
| 7 | **modules** | Installs PowerShell modules for PowerShell 7 (CurrentUser), then imports each in a clean process to prove they load |
| 8 | **fonts** | Installs the bundled Nerd Fonts for the current user (no admin) |
| 9 | **profile** | Writes a small stub to `Documents\PowerShell\Microsoft.PowerShell_profile.ps1` that loads the repo profile |
| 10 | **terminal** | Merges `settings\settings.json` into Windows Terminal's settings (backup first) |
| 11 | **configs** | Deploys Atuin, fzf, git ignore, OpenCode, and — if installed — Notepad++, Everything, AutoHotkey |
| 12 | **path** | Adds the executable folders from `bootstrap\manifests\path.psd1` to the **system PATH** (one UAC prompt) |
| 13 | **verify** | After the PATH step the installer opens a **new terminal window** and finishes there (so the new PATH is in effect): checks commands, the theme, fonts, loads the profile in a fresh `pwsh` and times it, validates Terminal's JSON, then leaves you in your configured shell. `-NoRelaunch` keeps everything in the current window. If `~\.pwsh` already exists the installer asks whether to remove it and install a fresh copy (`-FreshRepo` answers yes; `-Unattended` updates in place) |