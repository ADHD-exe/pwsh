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
| 4 | **git** | Asks for your **GitHub username**, sets `user.name`/`user.email`, creates an ed25519 key if you have none, **shows the public key** (copied to the clipboard, add-key page opened), waits for you to paste it into GitHub, tests the login, then turns on `https://github.com/` → SSH rewriting |
| 5 | **packages** | Installs the selected tiers (below) via winget, detecting what is already there |
| 6 | **npm** | Global npm packages the profile's aliases use (`openclaw`, `claude`) |
| 7 | **modules** | Installs PowerShell modules for PowerShell 7 (CurrentUser), then imports each in a clean process to prove they load |
| 8 | **fonts** | Installs the bundled Nerd Fonts for the current user (no admin) |
| 9 | **profile** | Writes a small stub to `Documents\PowerShell\Microsoft.PowerShell_profile.ps1` that loads the repo profile |
| 10 | **terminal** | Merges `settings\settings.json` into Windows Terminal's settings (backup first) |
| 11 | **configs** | Deploys Atuin, fzf, git ignore, OpenCode, and — if installed — Notepad++, Everything, AutoHotkey |
| 12 | **path** | Adds the executable folders from `bootstrap\manifests\path.psd1` to the **system PATH** (one UAC prompt) |
| 13 | **verify** | Checks commands, the theme, fonts, loads the profile in a fresh `pwsh` and times it, validates Terminal's JSON |

The two interactive moments (GitHub username, pasting the SSH key) are early on purpose —
after step 4 you can walk away. The run ends with a summary table and a log path
(`%LOCALAPPDATA%\RabbitBootstrap\logs`). Exit code is non-zero if anything required failed.

### Options

| Option | Meaning |
|---|---|
| `-Tier Core,Shell,Tools,Apps` | Which package tiers. **Default: `Core,Shell`** |
| `-Only Git` | Run just named steps: `prereqs core repo git packages npm modules fonts profile terminal configs path verify` |
| `-PathScope User` | Put PATH entries on the user PATH instead of the system PATH (no UAC) |
| `-GitUser name` | Skip the username prompt |
| `-SkipSsh` | Set up the git identity but not SSH |
| `-Unattended` | No prompts. SSH key is generated without a passphrase and the public key is printed for you to add later |
| `-Elevate` | Approve the system-PATH elevation without asking |
| `-NoAdmin` | Skip packages known to need machine-wide (UAC) installers |
| `-IncludeRisky` | Also install simplewall, Winaero Tweaker, DISMTools, NVCleanstall (in the Apps tier) |
| `-Force` | Deploy configs even if the app is running; replace an unparsable Terminal `settings.json` (backed up) |
| `-VerifyOnly` | Check that every winget id in the manifest exists. Installs nothing |
| `-WhatIf` | Dry run |

---

## What gets installed

**Tiers** (`bootstrap\manifests\packages.psd1` is the source of truth)

| Tier | Contents |
|---|---|
| **Core** | Git, PowerShell 7, Windows Terminal, Node.js LTS |
| **Shell** (default) | Oh My Posh, Atuin, zoxide, fzf, fd, bat, eza, Yazi, ripgrep, git-lfs, OpenCode, Neovim |
| **Tools** (opt-in) | Notepad++, AutoHotkey v2, Everything (+ `es` CLI, EverythingToolbar), CMake, Python 3.14, PeaZip, Autoruns |
| **Apps** (opt-in) | Firefox Dev Edition, Spotify, Equibop, eM Client, Outlook, Paint.NET, GIMP, VLC, OBS, ShareX, qBittorrent, Signal, Telegram, Ollama, Tailscale, Syncthing, … |

**PowerShell modules** (PowerShell Gallery unless noted): Terminal-Icons, PSReadLine (only upgraded if
older than 2.3.6), PSWriteColor, syntax-highlighting, PSEverything, PSFzf, BurntToast, PSCompletions,
and `YouShouldUse` (cloned from `ADHD-exe/pwsh-you-should-use`). Nothing is vendored in this repo.

**Fonts** (`settings\fonts`): Monoid Nerd Font (used by Windows Terminal), FiraCode Nerd Font,
EnvyCodeR Nerd Font.

**Theme:** `settings\oh-my-rabbit.omp.json`, loaded straight from the repo by the profile.

---

## Repository layout

```
install.ps1                       entry point: download → hash → unpack → run installer
bootstrap/
  Install-Environment.ps1         the orchestrator (options above)
  Restore-Backup.ps1              list / restore the NAME.bak-<timestamp> files
  lib/                            Common, Packages, Path, Fonts, Json (reusable functions)
  steps/                          one file per step (10-prereqs … 95-verify)
  manifests/                      packages.psd1, modules.psd1, path.psd1  ← edit these to add things
profile/
  Microsoft.PowerShell_profile.ps1   the real profile (loaded through the stub)
  aliases-functions-keybinds/        aliases, git aliases, functions, mkcmd, keybinds, notify
settings/                         per-application config (see below) + fonts
tests/                            offline tests (any OS with PowerShell 7)
.github/workflows/ci.yml          parse + test + lint on every push
```

To add an application: add a line to `packages.psd1`. To add a module: `modules.psd1`.
To add a config: one block in `bootstrap\steps\80-configs.ps1`.

---

## How the profile works

* `Documents\PowerShell\Microsoft.PowerShell_profile.ps1` is a **managed stub**. It dot-sources
  `~\.pwsh\profile\Microsoft.PowerShell_profile.ps1`, so updating is `git pull`, and OneDrive
  folder redirection doesn't matter.
* Your own additions go in **`Microsoft.PowerShell_profile.local.ps1`** (same folder as the stub).
  It loads last and the installer never touches it. `Edit-LocalProfile` opens it.
* Commands you create with `mkcmd` are saved to `~\.config\pwsh\user-commands.ps1` — outside the
  clone, so `git pull` never conflicts with them.
* The profile **never installs anything**. It initialises each tool only if present
  (zoxide, Atuin, Oh My Posh), then loads the alias/function scripts in a fixed order, then PSFzf's
  config (must come after Atuin/zoxide), then `YouShouldUse` (must come after the prompt is wrapped).
* Non-interactive runs (`pwsh -Command`, `-File`) skip all of that. Set `RABBIT_PROFILE_TRACE=1` to
  see where interactive startup time goes.

Key bindings: `Ctrl+f` file search · `Alt+Space` zoxide jump · `Ctrl+y` Yazi · `Ctrl+Space` command palette ·
`Ctrl+↑/↓` PSReadLine history search (plain arrows belong to Atuin when installed).

---

## How settings are deployed

| `settings\` | Target | How |
|---|---|---|
| `settings.json` | Windows Terminal (stable, Preview, or unpackaged — whichever exist) | **Merged**: your profiles/schemes/keybindings/actions win; profiles Terminal generated (WSL, Azure…) are kept. Backup first, JSON validated before the swap |
| `oh-my-rabbit.omp.json` | Oh My Posh | Read in place by the profile |
| `atuin\config.toml` | `~\.config\atuin\` | Copy (only if Atuin installed) |
| `fzf\*` | `~\.config\fzf\` | Copy |
| `git\ignore` | `~\.config\git\ignore` | Copy; set as `core.excludesfile` |
| `opencode\opencode.jsonc` | `~\.config\opencode\` | Copy, unless an `opencode.json` already exists |
| `notepad++\*.xml` | `%APPDATA%\Notepad++\` | Copy with `__USERPROFILE__` filled in; skipped while Notepad++ runs |
| `everything\Everything.ini` | `%APPDATA%\Everything\` | Copy; skipped while Everything runs |
| `autohotkey\*.ahk` | `Documents\AutoHotkey\` | Copy; **only `keybinds.ahk` autostarts** (`bandlab_ahk.ahk` remaps every letter key while running) |
| `fonts\*` | `%LOCALAPPDATA%\Microsoft\Windows\Fonts` + HKCU | Per-user install |

Identical files are left alone; different ones are backed up as `NAME.bak-yyyyMMdd-HHmmss` first.

**PATH:** `bootstrap\manifests\path.psd1` lists the folders from my original notes. Only folders that exist
and contain an executable, and aren't already on PATH, are added. Existing entries are preserved
byte-for-byte (`%SystemRoot%`-style entries are not flattened), and the old value is saved to
`%LOCALAPPDATA%\RabbitBootstrap\backups\path-machine-<time>.txt`.

---

## Re-running, updating, repairing

```powershell
~\.pwsh\install.ps1                     # repair + update everything (git pull, then every step again)
~\.pwsh\install.ps1 -Only Fonts,Terminal
~\.pwsh\install.ps1 -Tier Core,Shell,Tools
```

Or just `git -C ~\.pwsh pull` for profile/theme/settings changes. If the clone has local edits, the
installer refuses to touch it and tells you.

## Undo / restore

* **Any replaced file:** `~\.pwsh\bootstrap\Restore-Backup.ps1` lists every backup; `-Restore <#>` puts one back
  (and backs up what it overwrites).
* **Profile:** delete the block between the `>>> pwsh bootstrap` markers in
  `Documents\PowerShell\Microsoft.PowerShell_profile.ps1`. If you had a profile before, its content is in
  `Microsoft.PowerShell_profile.local.ps1` and the original is in `…profile.ps1.bak-<time>`.
* **PATH:** paste the line from `%LOCALAPPDATA%\RabbitBootstrap\backups\path-*.txt` into
  *System Properties → Environment Variables → Path*.
* **Git SSH rewrite:** `git config --global --unset url.git@github.com:.insteadOf`.
* **Packages:** `winget uninstall --id <id>` (ids are in `packages.psd1`).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `winget is missing or not working` | Update **App Installer** in the Microsoft Store, sign out/in, retry |
| A package shows `not detected after install` | Open the log (path is printed at the end). Run `.\install.ps1 -VerifyOnly` to find wrong ids |
| `oh-my-posh` / `fzf` etc. "not found" right after install | PATH changes need a **new** terminal window |
| Prompt shows `` boxes | Terminal profile font must be **Monoid Nerd Font**; close *all* Terminal windows once after the first install |
| `SSH not verified` | Make sure the key was pasted as one line under *Settings → SSH and GPG keys*; then `.\install.ps1 -Only Git` |
| Terminal settings skipped: `existing file unparsable` | Fix the JSON or re-run with `-Force` (the old file is backed up) |
| System PATH not changed | You declined UAC. Re-run `-Only Path`, or use `-PathScope User` |
| Notepad++/Everything config skipped | The app was running (it rewrites config on exit). Close it, re-run |
| Startup feels slow | `$env:RABBIT_PROFILE_TRACE=1; pwsh` prints a per-section timeline |

## Known limitations

* **Not yet run on a clean Windows machine.** Everything was statically checked and unit-tested
  (settings merge, profile stub, argument handling, font parsing), but the winget ids, Terminal's
  runtime behaviour and the UAC/PATH round trip need a first run on a VM. Treat the first run as a test.
* `Tools` (Notepad++, AutoHotkey, Everything) is **opt-in**; their configs are deployed only when the
  app is installed. The profile falls back to Neovim/Notepad for `$env:EDITOR` without Notepad++.
* The `https → ssh` rewrite is global to your git config once SSH is verified.
* `-Unattended` creates a passphrase-less key.
* Windows Terminal "Preview" and unpackaged installs are merged if present but only the stable package is
  created when missing.
* Windows 10 without OpenSSH Client needs it enabled (Settings → Optional features) for the SSH step.

## License

See `LICENSE`.
# pwsh
