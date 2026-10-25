# Phases 2–4 — build notes (installer, profile, settings deployment, README)

Status: **built and statically validated; not yet run on Windows.**

## Decisions applied (yours)

| Decision | Result |
|---|---|
| Repo | `https://github.com/ADHD-exe/pwsh.git`, branch `main`; raw URL in README |
| Default tier | **Core + Shell only.** Tools (Notepad++, AutoHotkey, Everything…) and Apps are opt-in via `-Tier` |
| PATH scope | **System (Machine) PATH.** One-time UAC prompt for just that step; `-PathScope User` avoids it |
| Git / SSH | Prompt 1: GitHub username. Prompt 2: public key shown + copied + add-key page opened, Enter to test. `https→ssh` rewrite enabled **only after** SSH login is proven |
| Freyja / OpenCam | Not part of the project. Removed the `phonecam` function that launched OpenCam |

## Deviations from the Phase 1 plan (and why)

1. **Repo lives at `~\.pwsh`; the profile is a stub.** Cloning 100 MB + `.git` into `Documents\PowerShell` (owned by PowerShell, redirected by OneDrive) was a bad home. Update = `git pull`.
2. **`mkcmd` now writes to `~\.config\pwsh\user-commands.ps1`** instead of appending to `functions.ps1` inside the clone — otherwise every `mkcmd` would dirty the repo and block updates.
3. **Machine PATH is written as REG_EXPAND_SZ from the raw registry value** — `[Environment]::SetEnvironmentVariable` would flatten `%SystemRoot%` entries.
4. **Git identity prompt uses the GitHub noreply address** for `user.email` (no second prompt); change it with one command.
5. `-Tier` / `-Only` are validated manually: `pwsh -File x.ps1 -Tier Core,Shell` delivers one string, which `ValidateSet` rejects (reproduced and fixed).

## Bugs fixed in the carried-over scripts

* `aliases.ps1`: `Set-Alias Get-Process gp` / `Get-Help info` had reversed arguments. `info → Get-Help` fixed; the `gp` line **removed** (`gp` is a read-only built-in alias for Get-ItemProperty, and `ps` already covers Get-Process).
* `aliases.ps1`: compiled C# and loaded WinForms/Drawing at **every shell start** → now lazy (`Initialize-ScreenshotTypes`, called by the screenshot functions). On the test box the aliases/functions section dropped from ~810 ms to ~340 ms.
* `functions.ps1`: hard-coded `C:\Users\jtjex\…` (vids, projects); `theme` pointed at the wrong folder after the restructure; stale `bootstrap-packages` message.
* `notify.ps1`: installed BurntToast and marked PSGallery **Trusted machine-wide** at every shell start → removed (the installer owns installation).
* Old profile: scanned scripts with a regex and `Install-Module`'d at startup; sourced four folders that no longer exist; `$env:EDITOR = notepad++` even when absent → rebuilt.
* Windows Terminal `Pwsh` profile launched a hard-coded MSIX path → `pwsh.exe`.

## Tests that exist and pass (Linux, PowerShell 7.5.4)

* `tests/Test-TerminalMerge.ps1` — 15 assertions: template wins, machine-only profiles/schemes/keybindings kept, no duplicates, idempotent, single-element arrays stay arrays (caught a real bug), validation clean.
* `tests/Test-ProfileStep.ps1` — fresh, idempotent rerun, moved install dir, foreign profile migrated, old Rabbit profile replaced not migrated, `-WhatIf` writes nothing.
* Font-name parser checked against fontTools output for 4 bundled fonts; config deploy idempotency/backup/token replacement checked.
* All `.ps1`/`.psd1` parse; JSON/TOML/XML configs valid; manifests load; 52 packages, 0 duplicate ids.
* `install.ps1` argument forwarding checked for file, `iex`, and `& ([scriptblock]::Create(...))` styles.

## NOT verified (needs a clean Windows VM)

winget ids (use `-VerifyOnly`), actual installs, UAC/PATH round trip, per-user font registration visible to Terminal, Terminal reload, `ssh-keygen`/`ssh -T` interaction with a passphrase prompt, `git clone` fallback, relaunch from Windows PowerShell 5.1 into pwsh 7, PSScriptAnalyzer (runs in CI).

## Next (Phase 6)

Push to `ADHD-exe/pwsh` (public — the raw URL needs it), let CI run on `windows-latest`, then do one run on a throwaway VM with `-WhatIf` first.

## Checkpoint 2 review notes
* CI's Windows PowerShell 5.1 parse check now covers every file under `bootstrap\` plus `install.ps1`. Before, it skipped `lib\Json.ps1` and steps 40/50/60/70/80/95, although the orchestrator dot-sources all of them while still running in 5.1.
* AST scan: no PS7-only syntax (`??`, `?.`, ternary, `&&`/`||`) in `bootstrap\` or `install.ps1`. Only `profile\` uses `??=`, which always runs in PowerShell 7.
* Sandbox (Linux, pwsh 7.5.4): all 33 scripts parse; `Test-TerminalMerge` and `Test-ProfileStep` pass.
* **Bug fixed (90-path):** the elevated PATH relaunch passed `Start-Process -ArgumentList` an array, which PowerShell does not quote. Any profile/temp path containing a space (`C:\Users\Jane Doe\...`) would have split the `-File` path and the elevated window would have failed. Now built with `ConvertTo-ArgumentString` (in `lib\Common.ps1`, 5.1-safe) and covered by `tests/Test-ArgumentString.ps1`, which CI runs.

## Checkpoint 4 review notes (steps 55-git, 70-terminal, 80-configs, 95-verify)
Static review only - **not run** (no PowerShell in the review sandbox this session; re-run the three tests in CI).
* **55-git, fixed:** `-Unattended` key generation passed `-N '""'`. On PowerShell 7.3+ that sets the passphrase to the two characters `""`; now spelled per-version (`''` on 7.3+, `'""'` on 5.1/7.0-7.2).
* **55-git, fixed:** `-WhatIf` with an existing key could still prompt, copy to the clipboard and open the browser; it now stops before the GitHub test and logs a dry-run line.
* **55-git, fixed:** `ssh -T ... 2>&1` throws under `$ErrorActionPreference='Stop'` in Windows PowerShell 5.1 (the `-WhatIf` path stays in 5.1); relaxed locally.
* **55-git, fixed:** appended GitHub host key could merge into the last line of a `known_hosts` that lacks a trailing newline.
* **55-git, fixed:** the "GitHub says you are X but you entered Y" warning fired when an existing git `user.name` (e.g. a full name) was reused; now only when a username was supplied or typed.
* **95-verify, fixed:** profile timing used `pwsh -Command $cmd $stub` and read `$args[0]`; `-Command` appends trailing arguments to the command text instead of filling `$args`, so the check would have failed. The stub path now travels in `$env:PWSH_VERIFY_PROFILE`. Also warns if the stub is missing.
* **95-verify, fixed:** no `--version` call for `wt`/`autoruns` (GUI launchers); `oh-my-posh init ... 2>&1` relaxed under 5.1.
* **70-terminal, 80-configs:** no defects found (merge/skip/backup/WhatIf paths and per-app detection read correctly). Open question for the VM run: Everything may install to `Everything 1.5a` for some ids - config deploy would then skip.
* Still to review: `profile\` (Microsoft.PowerShell_profile.ps1, functions.ps1, aliases*.ps1, notify.ps1, mkcmd.ps1).

## Checkpoint 5 review notes (profile\)
Static review only - not run.
* **95-verify, fixed (my checkpoint-4 fix was incomplete):** the profile exits early whenever pwsh was started with `-Command`/`-File`, so the "loads cleanly" check only ran the first ~40 lines. The child now gets `RABBIT_PROFILE_FORCE=1`.
* **functions.ps1, fixed:** `notepad` shadowed notepad.exe and only printed an install hint when Notepad++ was missing - so `fn`, `al`, `theme`, `Edit-Profile`, `edit` were all dead on the default Core+Shell install. It now falls back to `%windir%\notepad.exe`.
* **functions.ps1, fixed:** `extract` could miss its success message after .zip because `$LASTEXITCODE` was stale.
* **mkcmd.ps1 (`rmcmd`), fixed:** removing a one-line `function x { ... }` also deleted the line after it.
* **aliases.ps1, fixed:** duplicate `ws` function removed.
* Checked, no change: main profile load order, interactive detection, atuin/zoxide/oh-my-posh hooks, `gp`/`gl` alias removal in aliases-git.ps1, notify.ps1 reload guard.
* **Known caveat for the VM run:** notify.ps1's `prompt` wrapper calls `Get-History` before the wrapped prompt, so oh-my-posh sees `$?` = true; failed-command indication in the prompt may always look successful. Not changed (needs a real console to test).
* Not reviewed in depth: `aliases-git.ps1` (471 lines of git helpers; parses, `gp`/`gl` aliases are removed there).
