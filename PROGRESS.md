# Progress report (checkpoint 14)
Ctrl+F now always lists files in the current directory and below (fd, hidden files included, .gitignore and .git honoured),
including inside git repos; it no longer switches to `git ls-files`. Help page 01 updated. Static edit only, not run.

---
(Previous report follows)

# Progress report (checkpoint 13)

Done (static edits only; no PowerShell in this sandbox, nothing run - please test)
Install log 15:52 reviewed: Failed 0, profile loads cleanly. Two real bugs, both fixed:
1. Notepad++ "--version not found, create it?": 95-verify.ps1 ran `notepad++ --version`; Notepad++ treats that as a file name.
   GUI programs (wt, autoruns, notepad++) are no longer probed for a version.
2. Ctrl+H help showed fragments like "38;2;255;66;160m": ConvertTo-RabbitHelpText coloured the bullet first, then its [Key] regex paired the
   "[" of an ESC[...m colour code with a later "]" and ate the escape sequence. Markup is now parsed first and colours added afterwards
   (functions.ps1). Plain text output when themes are declined.
Requested changes:
3. Removed the `vault` (D:\) and `repo` (C:\Repositories) helpers (functions.ps1 + the `nav` list) and the README note about "personal" shortcuts.
4. Installer asks ONCE (together, before packages): "install the themes?" and "download AutoHotkey + launcher keybinds?".
   -Themes Ask|Yes|No, -Keybinds Ask|Yes|No; answers remembered in %LOCALAPPDATA%\RabbitBootstrap; -Unattended reuses them (yes the first time).
   Themes = No skips ALL of: Oh My Posh prompt theme (profile keeps the default prompt), Windows Terminal colour schemes, Atuin theme (and its
   `name = "rabbit"` line), Yazi theme, fzf --color lines, Notepad++ stylers.xml, themed popup colours / help colours.
   Fonts are not a theme and are still installed. Declining after an earlier "yes" does not delete files already deployed.
   Keybinds = No: AutoHotkey is not installed and keybinds.ahk is not deployed.
5. keybinds.ahk rewritten: a launcher key is created only if its program exists (pwsh/Windows PowerShell, Firefox Dev Edition, Notepad++,
   Explorer, Mobility Center, SndVol; Store and network pane are Windows built-ins). Removed Spotify, Equibop, eM Client, OpenCam.
   settings/autohotkey/bandlab_ahk.ahk deleted (personal). eM Client removed from the Apps list.
6. Firefox Developer Edition moved to the Tools tier (installed by default), presence-checked before install (known paths, then winget list),
   its folder added to the system PATH (path.psd1), and a `firefox` function in aliases.ps1 launches it. Verify reports it.
README updated for all of the above.

Still needs you: git pull --rebase, commit, push, re-run. Please check: the two prompts, `firefox`, Ctrl+H text, no Notepad++ popup,
and a run with -Themes No (prompt stays default, no Terminal colour scheme added).

---
(Previous report follows)

# Progress report (checkpoint 12)

Done (static edits only; nothing run - please test)
- Default package tiers are now Core, Shell AND Tools (bootstrap/Install-Environment.ps1 param default + help text,
  packages.psd1 comment). A plain `irm .../install.ps1 | iex` now also installs Notepad++, AutoHotkey v2, Everything,
  Everything CLI, EverythingToolbar, CMake, Python 3.14, PeaZip and Autoruns. Apps stays opt-in (-Tier Core,Shell,Tools,Apps).
- AutoHotkey, Everything and EverythingToolbar use admin installers, so expect extra UAC prompts (-NoAdmin skips them).
- README.md and the install.ps1 header example updated to match (the options example now adds Apps).

Still needs you: commit + push, re-run the installer, confirm the Tools packages install and verify still passes.
  Quick dry run first: ... -WhatIf should print "tiers: Core, Shell, Tools".

---
(Previous report follows)

# Progress report (checkpoint 11)

Done: README.md rewritten for first-time users (static edit only, nothing run).
- Added: "What you should know first", full package tables by tier (Core/Shell/Tools/Apps/Risky), npm package, all 9 PowerShell modules,
  the 3 bundled font families (39 files), every system PATH folder, Windows Terminal settings, where each config is deployed,
  key bindings and commands, installer options, troubleshooting, repo layout.
- Checkpoint 10 (verify fix) is confirmed working by your 14:34 run: "Profile loads cleanly", Failed 0.
- Known cosmetic issue: about 30 blank lines print once at the end of the installer's final shell (not in normal shells). Not fixed.

Still needs you: commit + push README.md and PROGRESS.md.

---
(Previous report follows)
# Progress report (checkpoint 10)

Done (static edits only; no PowerShell in this sandbox, nothing re-run - please test)
Diagnosis of the 14:26 run (log install-20261025-142602): the zip/checkout you ran still had the checkpoint-9 95-verify.ps1.
Every PROFILEERR:: line was PSReadLine fallout or the YSU probe and was filtered correctly; the verify then fell back to raw stderr,
where PowerShell's multi-line error rendering ("Line |", "~~~~", "Write-Error: ...profile.ps1:5") cannot match the PSReadLine filter.
1. bootstrap/steps/95-verify.ps1: when the child finishes and reports its timing, only the tagged $Error dump is trusted
   (raw stderr is used only if the child never reported). Distinct log lines only (the log held ~7600 duplicate lines).
Still needs you
- Make sure THIS version is in your checkout (git pull --rebase first), commit, push, re-run the installer.
- Expect "Profile loads cleanly in a fresh pwsh".

---
(Previous report follows)

# Progress report (checkpoint 9)

Done in this checkpoint (static edits only; no PowerShell in this sandbox, nothing re-run - please test)
Diagnosis of the last run's "Profile produced errors" (log install-20261025-140223): the verify child shell has redirected I/O, so PSReadLine cannot load there. The 3 reported errors were all side effects of that or harmless noise, not real profile bugs:
1. settings/fzf/PSFzf.config.ps1: PSFzf is imported only when PSReadLine is loaded (it needs it for its chords); FZF_DEFAULT_OPTS / FZF_DEFAULT_OPTS_FILE are removed only if they exist (Remove-Item -ErrorAction SilentlyContinue still logs to $Error).
2. bootstrap/steps/95-verify.ps1: the child-shell error filter now also ignores PSFzf.psm1 import errors and YouShouldUse's own Get-Variable probe for YSU_NO_AUTOENABLE (third-party module code, harmless).
Real interactive shells are unaffected: PSReadLine is already loaded there, so PSFzf still imports.

Still needs you
- Commit + push, then re-run the installer; expect "Profile loads cleanly in a fresh pwsh".
- If a profile error still shows, send the new "Profile produced errors" lines.

---
(Previous report follows)

## Checkpoint 8

Done (static edits only; no PowerShell in this sandbox, nothing re-run - please test)
1. ROOT CAUSE of "Could not fast-forward", missing fonts, missing settings\git\ignore and the failing new terminal:
   30-repo.ps1 updated the shallow clone with `fetch --depth 1` + `merge --ff-only`. A depth-1 fetch drops the new
   commit's parents, so git can never prove the old HEAD is an ancestor: the fast-forward fails whenever the clone is
   behind. ~\.pwsh therefore stayed on an old commit (no fonts, no settings\git\ignore) and the new-terminal handoff
   launched that OLD Install-Environment.ps1, which has no -ResumeAfterPath parameter, so it failed every time.
   Fix: fetch + `reset --hard FETCH_HEAD` (only when the tree is clean, as before). If git still cannot update, the
   freshly downloaded files are copied over the install dir so ~\.pwsh and the download never diverge.
2. New-terminal handoff hardened (Relaunch.ps1): command is passed as -EncodedCommand (no wt.exe quoting / ';' issues),
   parameters are splatted from a hashtable, and any start-up error is printed and the window waits for Enter instead of
   vanishing. Install-Environment.ps1 refuses to launch a copy that lacks -ResumeAfterPath and verifies in-place instead.
3. Notepad++ / Everything configs are no longer skipped while the app runs. Originals are backed up (NAME.bak-<timestamp>)
   and replaced on the first run. Because those apps rewrite their config on exit, the installer first closes them
   GRACEFULLY (never killed; Everything via -quit), replaces the files, then reopens them. Only done when a file would
   actually change. If an app will not close, the file is still replaced and a warning explains it may be overwritten.
4. tests\Test-Relaunch.ps1 added (parses the generated handoff command with the real PowerShell parser) and wired into CI.

Still needs you
- Commit + push (settings\git\ignore and settings\fonts are tracked in this checkout; confirm they are on GitHub main)
- Re-run: irm .../install.ps1 | iex   (first run will update ~\.pwsh, install the fonts, deploy git\ignore)
- Check: the new wt window shows "Continuing in a new terminal"; if not, the red error text now stays on screen - send it to me
- Check Notepad++ / Everything reopen with the new settings

Earlier (checkpoint 7): openclaw removed; git step rewritten (skip what is done, SSH loop); handoff terminal added.
