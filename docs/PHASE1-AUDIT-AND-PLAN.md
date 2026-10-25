# Phase 1 — Repository Audit & Implementation Plan

Source: `Powershell.zip` (git repo, remote `git@github.com:ADHD-exe/powershell.git`, branch `main`, 12 commits).
Audit was done by reading the files; nothing was run on Windows, so every
Windows-runtime claim below is marked **unverified** where it needs a real machine.

---

## 1. What is actually in the zip

| Path | What it is | State |
|---|---|---|
| `install.ps1` | Entry script: prereqs (git, pwsh, node), copy repo to profile dir, npm globals, hand off | Works in design, **hands off to a file that no longer exists** |
| `rough-draft-install.ps1` | Byte-for-byte `install.ps1` plus 29 junk lines of `]]]]]]` at the top | Dead; delete |
| `I want this to be a bootstrap scrip.txt` | The "draft-bootstrap" notes (winget list, PATH list, module list) | Source of intent, not code |
| `Microsoft.PowerShell_profile.ps1` | Profile | Modified vs git HEAD; points at **deleted folders** |
| `aliases-functions-keybinds/` | `aliases.ps1`, `aliases-git.ps1`, `functions.ps1`, `mkcmd.ps1`, `keybinds.ps1`, `notify.ps1`, `pwsh-icon.png` | New merged folder (replaces 3 old folders) |
| `settings/` | atuin, autohotkey (2), everything, fonts (3 families, 54 ttf), fzf, fzf-config, git, notepad++, opencode, `oh-my-rabbit.omp.json`, `settings.json` | See §3 |
| `Modules/` | 11 bundled module folders (91 MB) | See §4 |
| `README.md` | 17 KB, written for the old layout | Rewrite |
| git HEAD (not in working tree) | `bootstrap-packages/bootstrap.ps1`, `deploy-configs.ps1`, `completions/tailscale-completions.ps1`, `powershell.config.json`, `.gitattributes` | Deleted in working tree; **contain most of the real logic** |

Working-tree vs HEAD: 13 deletions, 2 modifications, 5 untracked. The previous
installer logic (package list, font install, Windows Terminal deploy, app-config
deploy, AHK autostart, Freyja, OpenCam) lives only in git history right now.

---

## 2. Defects found (ordered by how badly they break a fresh install)

### Blocking
1. **`install.ps1` → `bootstrap-packages\bootstrap.ps1` does not exist.** The
   folder was deleted. Both the "already in place" check and the final hand-off
   fail, so the installer throws at step 4 (or treats a fresh clone as not-a-clone).
2. **Profile sources folders that no longer exist.** `aliases-functions`,
   `completions`, `keybinds-scripts`, `bootstrap-packages` → now
   `aliases-functions-keybinds`. Result: no aliases, functions, keybinds or
   notifications load at all.
3. **Theme path typo vs reality.** Profile uses `settings\oh-my-rabbit.omp.json`
   (this file exists); your brief says `oh-my-rabbit.json`. The file on disk is
   `.omp.json`. I'll keep the real name and mention it in the README.
4. **`Modules/` is in `.gitignore` but is also the "bundled modules" source.**
   Anything gitignored will not exist when someone pulls the repo from GitHub, so
   `irm | iex` can never see these bundles. Either un-ignore deliberately or
   download everything online (see §4 recommendation).
5. **Global git config breaks fresh machines.** `deploy-configs.ps1` sets
   `url.git@github.com:.insteadOf = https://github.com/`. On a new PC with no SSH
   key, every later HTTPS clone (module clones, OpenCam, even re-running the
   installer's own clone) fails. This should be opt-in, and the installer should
   never apply it before its own clones are finished.
6. **Windows Terminal "Pwsh" profile hard-codes the MSIX alias path**
   `%USERPROFILE%\AppData\Local\Microsoft\WindowsApps\Microsoft.PowerShell_8wekyb3d8bbwe\pwsh.exe`.
   `winget install Microsoft.PowerShell` installs the MSI by default, which lives
   at `C:\Program Files\PowerShell\7\pwsh.exe`, so the profile would launch nothing.
   **Unverified on a clean machine**, but the path logic is wrong for the default
   install either way. Fix: `commandline: "pwsh.exe"` (resolves via PATH) and
   keep the dynamic `Windows.Terminal.PowershellCore` profile as fallback.

### Serious
7. **`PSReadLine` in `Modules/` is the GitHub source tree**, not a built module
   (no `Microsoft.PowerShell.PSReadLine.dll`). It cannot load. PowerShell 7
   already ships PSReadLine; `Install-Module PSReadLine` gets a newer build.
8. **`dbatools-development` is a dev checkout** (41 MB, tests, CI, 13 MB index)
   with no compiled `bin\*.dll`. It is not usable as a module, nothing in the
   profile uses SQL tooling, and the draft calls `Install-Module dbatools`
   anyway. Recommend dropping it from the bundle.
9. **Triplicated fzf config**: `Modules/fzf-config/` (with its own `.git`),
   `settings/fzf-config/` (with its own `.git`), `settings/fzf/` (newer
   `PSFzf.config.ps1`, 31 710 B vs 30 943 B). Embedded `.git` folders also make
   GitHub treat them as submodule gitlinks. `settings/fzf/` is the newest; the
   other two should go.
10. **Hard-coded username** in `functions.ps1`: `C:\Users\jtjex\Videos` and
    `...\Projects`. Replace with `$HOME`/known-folder lookups.
11. **Reversed `Set-Alias` arguments** in `aliases.ps1`:
    `Set-Alias Get-Process gp` and `Set-Alias Get-Help info` define an alias
    *named* `Get-Process`/`Get-Help` pointing at `gp`/`info`. `Set-Alias` takes
    `name value`. As written they don't do what was intended and can shadow the
    real cmdlets.
12. **Freyja is cloned over SSH** (`git@github.com:ADHD-exe/freyja.git`). On a new
    machine without a key this fails; if the repo is private it can never work
    over anonymous HTTPS. Needs to be opt-in and gated on SSH/auth detection.
13. **Profile auto-installs modules at every shell start** (scans scripts with a
    regex for `Import-Module`, then `Install-Module` anything missing). That is
    slow, network-dependent, hard to reason about, and is why startup does
    filesystem + regex scans. Installation belongs in the installer; the profile
    should only import.
14. **`YouShouldUse` is a nested git clone** (`ADHD-exe/pwsh-you-should-use`) —
    fine to *install* via git, wrong to *vendor* with `.git` inside.

### Cleanup
15. Draft module list has typos/duplicates: `syntac-highlighting`, `PSEverything`
    twice, tab/space mix, `iloader` and `oh-my-posh` module dirs that don't exist.
16. Draft package list duplicates `fzf`, `yazi`, `NodeJS` and mixes
    `OpenJS.NodeJS` with `OpenJS.NodeJS.LTS` (the installer uses LTS).
17. `Microsoft.Terminal` in the draft is not the winget id — the id used in the
    old bootstrap, `Microsoft.WindowsTerminal`, is the correct one.
18. Draft says "downloads my Powershell repo **from winget**" — the repo isn't a
    winget package; I'm treating that as "from GitHub".
19. `keybinds.ps1` in the old layout vs `settings/autohotkey/keybinds.ahk` — two
    different things with the same name; the README must distinguish them.
20. `bandlab_ahk.ahk` intercepts every letter key while running; the old deploy
    correctly did **not** autostart it. Keep that.
21. No secrets found: `oh-my-rabbit.omp.json`, `atuin/config.toml`,
    `Everything.ini`, `settings.json` have no tokens or API keys. `gitconfig`
    already has identity stripped. The Atuin `key`/`session`/`*.db` are
    gitignored, which is correct.
22. Repo size: fonts are ~97 MB. Fine for git, but means a shallow clone is
    ~130 MB. Acceptable; the installer should clone shallow and sparse where possible.

---

## 3. `settings/` — what each file configures

| File(s) | Target app | Destination | Strategy |
|---|---|---|---|
| `settings.json` | Windows Terminal | `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` (also check `...Preview...` and unpackaged `%LOCALAPPDATA%\Microsoft\Windows Terminal\settings.json`) | Locate real path, back up, **merge** (not overwrite), validate JSON |
| `oh-my-rabbit.omp.json` | Oh My Posh | Referenced in place from the profile | No copy; just verify it parses |
| `atuin/config.toml` | Atuin | `~\.config\atuin\config.toml` | Copy with backup |
| `git/gitconfig`, `git/ignore` | Git | merged into global config / `~\.config\git\ignore` | Per-key merge; `insteadOf` becomes opt-in |
| `opencode/opencode.jsonc` | OpenCode | `~\.config\opencode\opencode.jsonc` | Copy unless `opencode.json` exists |
| `notepad++/*.xml` | Notepad++ | `%APPDATA%\Notepad++\` | Tokenised (`__USERPROFILE__`), skip if running |
| `everything/Everything.ini` | Everything | `%APPDATA%\Everything\` | Copy, skip if running |
| `autohotkey/keybinds.ahk` | AutoHotkey v2 | `Documents\AutoHotkey\` + Startup shortcut | Autostart this one only |
| `autohotkey/bandlab_ahk.ahk` | AutoHotkey v2 | `Documents\AutoHotkey\` | Deploy, **don't** autostart |
| `fonts/*.ttf` | System fonts | `%LOCALAPPDATA%\Microsoft\Windows\Fonts` + HKCU registry | Per-user install, no admin needed |
| `fzf/*` | fzf + PSFzf | `~\.config\fzf\` | Copy; profile already dot-sources it from there |

**Fonts actually referenced:** Windows Terminal uses `Monoid Nerd Font`; the
bundled TTFs register that exact family name, so the font and config match.
FiraCode and EnvyCodeR are bundled but unused by the terminal profile — they stay
available.

**Windows Terminal `settings.json`:** strictly valid JSON, 4 profiles, 34
keybindings, 6 actions, custom schemes (e.g. `ADHD`), default profile = the custom
"Pwsh" GUID. Needs the pwsh path fix in §2.6. Because it is a **full replacement**
file, a merge should only take your keys (`profiles.defaults`, your profile entries
by GUID, `schemes`, `keybindings`, `actions`, UI settings) and keep any profile
the machine generated itself (Azure Cloud Shell, WSL distros, VS prompts).

---

## 4. `Modules/` — bundle vs download

| Module | Bundled? | Usable as bundled? | Recommendation |
|---|---|---|---|
| BurntToast 1.1.0 | yes (22 MB) | yes | Download from PSGallery (not unavailable online) |
| PSCompletions 8.0.1 | yes (24 MB, 8 platform binaries) | yes | Download from PSGallery |
| PSEverything 3.3.0 | yes | yes | Download |
| PSFzf 2.7.12 | yes | yes | Download |
| PSWriteColor 1.0.3 | yes | yes | Download |
| Terminal-Icons 0.11.0 | yes | yes | Download |
| syntax-highlighting | yes | yes | Download (PSGallery) — confirm name on a live machine |
| YouShouldUse | yes (nested `.git`) | yes | `git clone` from `ADHD-exe/pwsh-you-should-use` (your own repo) |
| PSReadLine | **source tree** | **no** | Don't bundle; use pwsh built-in or PSGallery |
| dbatools-development | **dev checkout** | **no** | Drop (or PSGallery on request) |
| fzf-config | nested `.git`, duplicate | n/a | Drop; `settings/fzf` is canonical |

**Recommendation (needs your OK):** bundle **nothing** in `Modules/` except what is
genuinely unavailable online. Every module above is on PSGallery or your own
GitHub, so the bundle can shrink from 91 MB to roughly 0 and the installer installs
from the sources. That removes the gitignore contradiction in §2.4. If you'd rather
keep an offline fallback, I'll keep a small `Modules/` of pinned copies and
un-ignore it.

---

## 5. Packages — the install manifest

Source: the draft list, de-duplicated, plus items the old bootstrap installed
that the profile/AHK scripts depend on (git-lfs, eza, bat, es CLI, eM Client,
Equibop, etc.).

> **Every winget ID below is unverified.** I have no winget here. The installer
> will run `winget show --id X --exact` in a `-Verify` mode and report bad IDs
> instead of failing the run.

**Core (the installer depends on these):** Git.Git, Microsoft.PowerShell,
Microsoft.WindowsTerminal, OpenJS.NodeJS.LTS.

**Shell stack (explicit in your brief):** Atuinsh.Atuin, ajeetdsouza.zoxide,
junegunn.fzf, sharkdp.fd, sharkdp.bat, eza-community.eza, sxyazi.yazi,
JanDeDobbeleer.OhMyPosh, BurntSushi.ripgrep.MSVC, SST.opencode.

**Editors / system:** Notepad++.Notepad++, AutoHotkey.AutoHotkey,
voidtools.Everything (+ Cli for `es`), srwi.EverythingToolbar, Kitware.CMake,
Microsoft.Sysinternals.Autoruns / RDCMan.

**Everything else from your list** is kept as an **optional "apps" tier**
(Spotify, Signal, Telegram, VLC, OBS, GIMP, Paint.NET, qBittorrent, Ollama,
Tailscale, Syncthing/SyncTrayzor, ShareX, simplewall, Winaero Tweaker,
BulkCrapUninstaller, DISMTools, BetterTrumpet, NVCleanstall, Firefox Dev Edition,
Proton Authenticator, Peazip, Python 3.14, Starship, Spicetify). Installing a
firewall (simplewall), a driver cleaner (NVCleanstall) and a system tweaker
unattended on every run is risky, so these go behind `-Tier Apps` / interactive
opt-in rather than the default.

**Inconsistencies to resolve:** Starship *and* Oh My Posh are both listed — the
profile only uses Oh My Posh. I'll install Starship only in the apps tier.

---

## 6. PATH policy (from `draft-bootstrap`)

Your list is 16 directories under `C:\Program Files\…`. Most winget installers
already add their own PATH entries, and several list entries are not executable
directories (`Git` needs `Git\cmd`; `Go` and `7-Zip` aren't in your package list at all;
`starship`, `simplewall`, `Paint.NET`, `Everything` contain GUI apps).

Plan: **User PATH, not Machine PATH**, unless you say otherwise — it needs no
admin, can't break other users, and survives winget updates. For each entry:
resolve the real executable folder after install, add only if the directory exists
and contains an `.exe`, de-duplicate case-insensitively, preserve unexpanded
`%VAR%` entries, and broadcast `WM_SETTINGCHANGE`. Anything that isn't a PATH
entry is reported, not silently dropped. **Your list contains no URLs**, so the
"URLs in PATH" case from your brief doesn't occur.

---

## 7. Target repository layout

```
install.ps1                      # thin, auditable entry point (download → verify → run)
bootstrap/
  Install-Environment.ps1        # orchestrator, -WhatIf/-Tier/-SkipX switches
  lib/
    Log.ps1  Elevation.ps1  Packages.ps1  Modules.ps1
    Fonts.ps1  Path.ps1  Backup.ps1  Json.ps1
  steps/
    10-prereqs.ps1  20-packages.ps1  30-modules.ps1  40-fonts.ps1
    50-profile.ps1  60-terminal.ps1  70-app-configs.ps1  80-path.ps1  90-verify.ps1
  manifests/
    packages.psd1  modules.psd1  path.psd1
profile/
  Microsoft.PowerShell_profile.ps1
  aliases-functions-keybinds/    # unchanged files, bugs fixed
settings/                        # unchanged app configs (fzf-config copies removed)
Modules/                         # pinned fallbacks only, if you want them
README.md
```

Design rules: data in `.psd1` manifests, behaviour in functions; every step
returns `Ok / Skipped / Warn / Failed` and the run ends with a summary table;
`-WhatIf` everywhere; a transcript to `%LOCALAPPDATA%\RabbitBootstrap\logs`;
exit code non-zero if anything required failed.

### The `irm | iex` flow, made safer
`irm …/install.ps1 | iex` runs one small script that only: checks PowerShell/Windows,
downloads a **pinned release archive** over HTTPS, verifies its SHA-256 against a
value published in the script, extracts to a temp folder, and runs the real
installer from there. The README gets a "download, read, then run" path as the
primary recommendation and the one-liner as the convenience path.

### Elevation
Default is **non-elevated**: user-scope winget installs, per-user fonts, User
PATH, HKCU. Admin is requested only for the steps that truly need it (any
machine-scope winget package such as Tailscale or simplewall, and Machine PATH if
you opt in). The installer relaunches *only the elevated steps* in a UAC prompt
and says why first, instead of relaunching the whole run.

### Idempotency
Detect before acting (command on PATH → known install path → `winget list --id`);
config deploys compare content hashes and write timestamped `.bak-*` copies;
`-Repair` re-verifies and re-deploys without reinstalling.

---

## 8. Decisions I need from you

These are the only calls that change what I build; I'll proceed with the **bold**
default if you don't say otherwise.

1. **Repo layout / URL.** The git remote is `ADHD-exe/powershell`, branch `main`,
   and the files currently sit at the repo root. Your example URL has
   `…/BRANCH/ADHD_exe/powershell/install.ps1`. I'll use a **placeholder** in the
   README as you asked, built around the **root-level** layout above. Tell me
   which real URL/layout to use.
2. **Bundle vs download modules.** **Download everything online, bundle nothing**
   (§4).
3. **Default tier.** **Core + shell stack by default; the apps tier is opt-in.**
4. **PATH scope.** **User PATH.**
5. **Git `insteadOf` rewrite (https → ssh).** **Off by default**, one flag to enable.
6. **Freyja / OpenCam.** **Both opt-in**; Freyja only when an SSH key is detected.

---

## 9. Build phases (a document copy is saved at each boundary)

| Phase | Deliverable | Status |
|---|---|---|
| 1 | This audit + plan | **done** |
| 2 | `bootstrap/` libs + manifests + `install.ps1` | next |
| 3 | Rebuilt profile + aliases/functions bug fixes | |
| 4 | Windows Terminal merge + app-config deploy + fonts + PATH | |
| 5 | README rewrite | |
| 6 | Static validation (PSScriptAnalyzer, JSON/TOML parse, `-WhatIf` on Linux pwsh) + final zip | |

**Validation limits:** I can parse every script and config and lint with
PSScriptAnalyzer here, but I cannot run winget, install fonts, touch the registry
or launch Windows Terminal. Phase 6 will list exactly what remains for you to
test on a clean Windows VM.
