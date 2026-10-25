# fzf + PSFzf for PowerShell

A config that makes `fzf` search the whole C: drive instantly, with a readable
default layout and a small set of commands that are easy to remember.

Built around what you already run: **atuin** keeps Ctrl+R, **zoxide** drives
Alt+C, and **Everything** (via PSEverything) is what makes C:-wide search
return in milliseconds instead of walking half a million files.

---

## Install

```powershell
.\Install-FzfConfig.ps1
```

Installs fzf / fd / ripgrep / bat / eza via winget (`-PackageManager scoop` if
you prefer scoop, `-SkipTools` for none), installs the PSFzf and PSEverything
modules, copies the config to `~\.config\fzf`, and appends a marked block to
your `$PROFILE`. It backs up your profile first and is safe to re-run — a
second run rewrites its block rather than adding another.

Add `-WhatIf` to see exactly what it would do first.

Then open a new terminal and run:

```powershell
fzf?            # the cheat sheet
Test-FzfSetup   # check every piece is wired up
```

### Manual install

Copy the four files anywhere, then add to the **end** of your `$PROFILE`:

```powershell
. "$env:USERPROFILE\.config\fzf\PSFzf.config.ps1"
```

It has to come after your atuin and zoxide lines.

---

## Commands

Every `ff*` command returns plain paths, so they all pipe:

```powershell
ff -Ext log -Since 30 | Remove-Item
ffb 1GB | Get-Item | Sort-Object LastWriteTime
```

### Finding

| Command | What |
|---|---|
| `ff` | every file on C:, pick one (or several with Tab) |
| `ff config` | …whose name contains "config" |
| `ff -In D:\src` | scope to a directory |
| `ff -Ext ps1,psm1` | by extension |
| `ff -Bigger 500MB` | bigger than |
| `ff -Smaller 4KB` | smaller than |
| `ff -Bigger 100MB -Smaller 1GB` | a size range |
| `ff -Since 7` | modified in the last 7 days |
| `ff -All` | include WinSxS, WindowsApps, node_modules… |
| `ff -First 500` | cap the results |
| `ff -Raw 'ext:iso dm:thisyear'` | raw Everything query syntax |

### Shortcuts for the common cases

| Command | What |
|---|---|
| `ffh` | find **h**ere — current directory instead of C: |
| `ffd` | find **d**irectories, not files |
| `ffe ps1` | find by **e**xtension |
| `ffb` / `ffb 1GB` | **b**iggest files first, with a size column |
| `ffn` / `ffn 30` | **n**ewest files (last N days) |
| `ffr TODO` | search file **c**ontents, live ripgrep |

All of them take `ff`'s parameters too: `ffd -In D:\ -Since 1`,
`ffe log,txt -Bigger 10MB`.

### Acting on the pick

| Command | What |
|---|---|
| `fe` | edit in your editor |
| `fo` | open with the default app |
| `fcp` | copy the path to the clipboard |
| `cdf` | cd to any folder on C: |
| `zf` | jump through the zoxide database, with previews |
| `fkill` | pick a process and kill it |
| `fgs` | pick from `git status` |
| `fh` | PSReadLine history (atuin is still Ctrl+R) |
| `cde` | PSFzf's Everything-backed cd |

---

## Keys

### At the prompt

| Key | What |
|---|---|
| `Ctrl+T` | insert path(s) at the cursor, scoped to what you've typed |
| `Alt+C` | cd — fed by the **zoxide** database |
| `Alt+R` | PSReadLine history |
| `Alt+A` | pull an argument out of history |
| `Ctrl+R` | **atuin** — deliberately untouched |

### Inside the fzf window

| Key | What |
|---|---|
| `Tab` / `Ctrl+A` / `Ctrl+X` | mark one / all / none |
| `Ctrl+Y` | copy the highlighted path to the clipboard |
| `Ctrl+O` | open it |
| `Ctrl+E` | reveal it in Explorer |
| `Ctrl+/` or `Alt+P` | toggle the preview |
| `Alt+W` | move the preview pane (right → bottom → hidden) |
| `Alt+↑` / `Alt+↓` | scroll the preview |
| `Ctrl+S` | toggle sort |
| `Ctrl+U` | clear the query |

---

## Everything query syntax

What `-Raw` accepts, and what the parameters above compile down to:

| | |
|---|---|
| `ext:jpg;png` | extensions, semicolon separated |
| `path:C:\src` | anywhere under a path |
| `size:>100mb` `size:1mb..9mb` | size, and ranges |
| `dm:today` `dm:>2026-01-01` | date modified |
| `file:` `folder:` `empty:` | restrict to a type |
| `!node_modules` | exclude |
| `a\|b` | either |
| `regex:^log.*\.txt$` | regular expression |

---

## Files

| File | What it does |
|---|---|
| `fzf.conf` | fzf's layout, colors, preview and in-window keys. This is `$env:FZF_DEFAULT_OPTS_FILE`. |
| `PSFzf.config.ps1` | env vars, PSFzf wiring, zoxide/Everything integration, all the `ff*` commands. |
| `fzf-preview.cmd` | the preview renderer (batch, not PowerShell — previews have to be instant). |
| `fzf-action.cmd` | the copy / open / reveal actions bound to Ctrl+Y / Ctrl+O / Ctrl+E. |
| `Install-FzfConfig.ps1` | installer. |

### Tuning

Live settings are in `$FzfCfg` — change them at the prompt to try something,
or edit the top of `PSFzf.config.ps1` to keep it:

```powershell
$FzfCfg.Root = 'D:\'                       # search a different drive
$FzfCfg.Excludes += 'C:\Users\me\OneDrive' # hide something
$FzfCfg.Editor = 'nvim'
$FzfCfg.FuzzyTab = $true                   # fuzzy Tab completion (off by default)
```

Layout, colors and in-window keys live in `fzf.conf`.

---

## Design notes

A few choices that are deliberate, in case they look wrong later:

**Ctrl+R is left alone.** PSFzf binds it by default and would shadow atuin.
The module is imported with its chords passed in, so its history search lands
on Alt+R instead.

**`FZF_DEFAULT_COMMAND` is deliberately unset.** Setting it would make PSFzf's
Ctrl+T ignore the path you're typing and scan all of C: every time. The C:
default lives in `fzf.conf`'s `--walker-root`, which only applies to a bare
`fzf` with nothing piped into it — which is exactly the case you want it for.

**Three PSFzf aliases are not enabled.** `-EnableAliasFuzzySetLocation` would
alias `fd` over the real `fd.exe`; `-EnableAliasFuzzyFasd` would alias `ff`
over the one here; `-EnableAliasFuzzyEdit` would take `fe`. `-EnableAliasFuzzyZLocation`
is skipped too, since `zf` covers zoxide.

**Colors in `fzf.conf` are 256-color numbers, not hex.** fzf strips `#`
comments from that file, and a `#rrggbb` value would get eaten.

**Comments in `fzf.conf` need fzf 0.55+.** On anything older the PowerShell
config strips them itself and passes the options in through
`FZF_DEFAULT_OPTS`, so the file stays readable either way. (`--walker` needs
0.48+, the options file 0.47+.)

**Everything is the fast path, not the only path.** If PSEverything or the
Everything service isn't available it falls back to `fd`, and to
`Get-ChildItem` after that. All three honor the same filters, so results don't
change — only the speed does. `Test-FzfSetup` tells you which one is live.
