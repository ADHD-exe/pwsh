# =========================================================
# 🧭 NAVIGATION
# =========================================================

function ..   { Set-Location .. }
function ...  { Set-Location ../.. }
function .... { Set-Location ../../.. }

function home { Set-Location $HOME }
function docs { Set-Location ([Environment]::GetFolderPath("MyDocuments")) }
function dl   { Set-Location "$HOME\Downloads" }
function desk { Set-Location "$HOME\Desktop" }
function vids { Set-Location ([Environment]::GetFolderPath('MyVideos')) }
function projects { Set-Location (Join-Path $HOME 'Projects') }
function tmp { Set-Location $env:TEMP }

function rc {
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Set-Location "$env:SystemDrive\`$Recycle.Bin\$sid"
}

function mkcd {
    param([string]$Dir)
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    Set-Location $Dir
}

# All four are eza in different view modes. They're functions rather than
# aliases so they can take a path and extra flags: `ls src`, `la -s size`.
function ls { eza --icons --group-directories-first @args }
function ll { eza --icons --group-directories-first --long --git --header @args }
function la { eza --icons --group-directories-first --long --git --header --all @args }
function lt { eza --icons --group-directories-first --tree --level=2 @args }

function nav {
    # Flat command/description pairs: nested @() arrays get flattened in
    # PowerShell, so pairs are stored as alternating elements instead.
    $pairs = @(
        "..",   "Up one directory"
        "...",  "Up two directories"
        "....", "Up three directories"
        "home", "Go to ~"
        "docs", "Go to Documents"
        "dl",   "Go to Downloads"
        "desk", "Go to Desktop"
        "tmp",  "Go to Temp folder"
        "vids", "Go to Videos"
        "projects", "Go to Projects"
        "rc",   "Go to Recycle Bin"
        "mkcd", "Create a directory and cd into it: mkcd newdir"
        "yy",   "Open yazi file manager (cd on exit)"
    )

    Write-Host "Navigation Commands" -ForegroundColor Cyan
    Write-Host "  (qol shows everything else)" -ForegroundColor DarkGray
    for ($i = 0; $i -lt $pairs.Count; $i += 2) {
        Write-Host ("  {0,-9}" -f $pairs[$i]) -ForegroundColor Yellow -NoNewline
        Write-Host $pairs[$i + 1]
    }
}

function qol {
    $sections = [ordered]@{
        "Listing & Files" = @(
            "ls",   "List files with icons (eza)"
            "ll",   "Long list: size, perms, git status"
            "la",   "Long list incl. hidden dotfiles"
            "lt",   "Tree view, 2 levels"
            "touch", "Create file / update timestamp"
            "head",          "First lines (file or pipe)"
            "tail",          "Last lines (file or pipe)"
            "size", "Total size of a folder: size <path>"
            "extract", "Unpack zip / 7z / tar.gz"
            "backup", "Mirror a folder: backup <src> <dst>"
            "which", "Path of a command"
            "unzip", "Unzip (Expand-Archive wrapper)"
        )
        "Processes" = @(
            "pgrep", "Find a process"
            "pkill", "Kill a process"
            "k9",    "Alias for pkill"
        )
        "Clipboard" = @(
            "cbcopy",   "Copy piped input to clipboard"
            "cbpaste",  "Print clipboard"
            "copypath", "Copy path of file (or cwd if none)"
            "copyfile", "Copy file contents to clipboard"
        )
        "System" = @(
            "df",      "Free space per drive"
            "ip",      "Local + public IP"
            "uptime",  "Time since last boot"
            "sysinfo", "OS + CPU summary"
            "weather", "Forecast from wttr.in"
            "Port",    "Find who's using a port: Port 8080"
            "Admin",   "Launch elevated pwsh"
            "rsex",    "Restart Explorer"
            "reboot",  "Reboot machine"
        )
        "Web" = @(
            "search", "Web search (DuckDuckGo)"
            "bing",   "Bing search"
            "ddg",    "DuckDuckGo search"
            "so",     "Stack Overflow search"
            "gh-search", "GitHub search"
            "web",    "Open a URL"
            "firefox", "Launch Firefox Developer Edition: firefox [url]"
            "serve",  "HTTP server in cwd: serve [port]"
        )
        "Winget" = @(
            "ws",  "Search packages"
            "wi",  "Install"
            "wl",  "List installed"
            "wun", "Uninstall"
            "wr",  "Repair"
        )
        "Git (common)" = @(
            "gs",    "git status"
            "gd",    "git diff"
            "gaa",   "git add --all"
            "gcom",  "add . + commit"
            "lazyg", "add . + commit + push"
            "grt",   "cd to repo root"
            "glgga", "Full commit graph"
        )
        "Config" = @(
            "ep / profile", "Edit profile"
            "reload / rl",  "Reload profile"
            "fn",    "Edit functions.ps1"
            "al",    "Edit aliases.ps1"
            "theme", "Edit oh-my-posh theme"
            "forget", "Remove pattern from history"
        )
    }

    foreach ($name in $sections.Keys) {
        Write-Host ""
        Write-Host $name -ForegroundColor Cyan
        $pairs = $sections[$name]
        for ($i = 0; $i -lt $pairs.Count; $i += 2) {
            Write-Host ("  {0,-14}" -f $pairs[$i]) -ForegroundColor Yellow -NoNewline
            Write-Host $pairs[$i + 1]
        }
    }
    Write-Host ""
    Write-Host "  nav shows navigation commands" -ForegroundColor DarkGray
}

# =========================================================
# 📂 FILE / SYSTEM
# =========================================================

function touch {
    param([string]$File)
    if (Test-Path $File) { (Get-Item $File).LastWriteTime = Get-Date }
    else { New-Item $File -ItemType File | Out-Null }
}

function head {
    param(
        [Parameter(Position = 0)][string]$Path,
        [Parameter(ValueFromPipeline = $true)]$InputObject,
        [Parameter(Position = 1)][Alias("n")][int]$Lines = 10
    )
    begin { $count = 0; $sawInput = $false }
    process {
        if ($Path -or $null -eq $InputObject) { return }
        $sawInput = $true
        if ($count -lt $Lines) { $InputObject; $count++ }
    }
    end {
        if ($Path) { Get-Content $Path -Head $Lines }
        elseif (-not $sawInput) { Write-Warning "Usage: head <path> [lines]  or  <pipeline> | head [-n lines]" }
    }
}

function tail {
    param(
        [Parameter(Position = 0)][string]$Path,
        [Parameter(ValueFromPipeline = $true)]$InputObject,
        [Parameter(Position = 1)][Alias("n")][int]$Lines = 10
    )
    begin { $sawInput = $false; $buf = [System.Collections.Generic.List[object]]::new() }
    process {
        if ($Path -or $null -eq $InputObject) { return }
        $sawInput = $true
        $buf.Add($InputObject)
        if ($buf.Count -gt $Lines) { $buf.RemoveAt(0) }
    }
    end {
        if ($Path) { Get-Content $Path -Tail $Lines }
        elseif ($sawInput) { $buf }
        else { Write-Warning "Usage: tail <path> [lines]  or  <pipeline> | tail [-n lines]" }
    }
}

function size {
    param([Parameter(Position = 0)][string]$Path = ".")
    if (-not (Test-Path -LiteralPath $Path)) { Write-Warning "Not found: $Path"; return }
    $total = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
        Measure-Object Length -Sum).Sum
    if ($null -eq $total) { $total = 0 }
    foreach ($unit in "B","KB","MB","GB","TB") {
        if ($total -lt 1024) { break }
        $total /= 1024
    }
    Write-Host ("{0:N2} {1}  ({2})" -f $total, $unit, (Resolve-Path -LiteralPath $Path).Path)
}

function extract {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Path,
        [Parameter(Position = 1)][string]$Destination = "."
    )
    if (-not (Test-Path -LiteralPath $Path)) { Write-Warning "Not found: $Path"; return }

    # Expand-Archive never sets $LASTEXITCODE; reset it so a stale value from an earlier command cannot hide success.
    $global:LASTEXITCODE = 0
    switch -Regex ($Path) {
        '\.(zip)$'         { Expand-Archive -LiteralPath $Path -DestinationPath $Destination -Force; break }
        '\.(7z)$'          { & 7z x $Path "-o$Destination" -y; break }
        '\.(tar\.gz|tgz)$' { & tar -xzf $Path -C $Destination; break }
        '\.(tar)$'         { & tar -xf $Path -C $Destination; break }
        '\.(gz)$'          { & tar -xzf $Path -C $Destination; break }
        default { Write-Warning "Unsupported archive type: $Path"; return }
    }
    if ($LASTEXITCODE -eq 0) { Write-Host "Extracted to $Destination" -ForegroundColor Green }
}

# Takes precedence over the Info-ZIP unzip.exe that ships with Git for Windows
# (functions beat external programs). Extracts to the current directory unless
# a destination is given.
function unzip {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Path,
        [Parameter(Position = 1)][string]$Destination = ".",
        [switch]$Force
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "Archive not found: $Path"
        return
    }

    Expand-Archive -LiteralPath $Path -DestinationPath $Destination -Force:$Force
}

function which {
    param([string]$Name)
    (Get-Command $Name -ErrorAction SilentlyContinue)?.Source
}

function backup {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Source,
        [Parameter(Mandatory, Position = 1)][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $Source)) { Write-Warning "Source not found: $Source"; return }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Write-Host "Mirroring $Source -> $Destination" -ForegroundColor Cyan
    robocopy (Resolve-Path $Source) $Destination /MIR /R:1 /W:1 /MT:16 /NP
    if ($LASTEXITCODE -lt 8) { Write-Host "Done (robocopy code $LASTEXITCODE)" -ForegroundColor Green }
    else { Write-Warning "Robocopy failed with code $LASTEXITCODE" }
}

function pgrep { param([string]$Name) Get-Process $Name -ErrorAction SilentlyContinue }

function pkill {
    param([string]$Name)
    $procs = pgrep $Name
    if ($procs) { $procs | Stop-Process -Force }
}

function k9 { param([string]$Name) pkill $Name }

# =========================================================
# 📋 CLIPBOARD
# =========================================================

# Named cbcopy/cbpaste, not copy/paste: PowerShell resolves aliases before
# functions, and `copy` is a built-in alias for Copy-Item - a function of that
# name can never run.
function cbcopy {
    param([Parameter(ValueFromPipeline=$true)]$InputObject)
    process { $InputObject | Set-Clipboard }
}

function cbpaste { Get-Clipboard }

function Copy-Pwd { (Get-Location).Path | Set-Clipboard }

function Copy-Path {
    param([string]$File)
    if ($File) { (Resolve-Path $File).Path | Set-Clipboard }
    else { (Get-Location).Path | Set-Clipboard }
}

function Copy-FileContent {
    param([Parameter(Mandatory)][string]$File)
    Get-Content -Raw -LiteralPath $File | Set-Clipboard
}

Set-Alias copypath Copy-Path
Set-Alias copyfile Copy-FileContent

# =========================================================
# ⚙️ SYSTEM
# =========================================================

function uptime {
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $elapsed = (Get-Date) - $boot
    Write-Host ("Up {0}d {1}h {2}m {3}s" -f $elapsed.Days,$elapsed.Hours,$elapsed.Minutes,$elapsed.Seconds)
}

function df {
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
        Select-Object @{n="Drive";e={$_.DeviceID}},
            @{n="TotalGB";e={[math]::Round($_.Size/1GB,1)}},
            @{n="FreeGB";e={[math]::Round($_.FreeSpace/1GB,1)}},
            @{n="Free%";e={[math]::Round(100*$_.FreeSpace/$_.Size)}} |
        Format-Table -AutoSize
}

function ip {
    Write-Host "Local:" -ForegroundColor Cyan
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -ne "127.0.0.1" -and $_.PrefixOrigin -ne "WellKnown" } |
        Select-Object IPAddress, InterfaceAlias | Format-Table -AutoSize

    try {
        $public = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5)
        Write-Host "Public: $public" -ForegroundColor Cyan
    }
    catch { Write-Warning "Could not fetch public IP" }
}

function weather {
    param([string]$Location = "")
    $uri = if ($Location) { "https://wttr.in/$($Location -replace ' ','+')" } else { "https://wttr.in" }
    (Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 10).Content -split "`n" |
        Select-Object -First 12
}

function sysinfo {
    $os  = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    Write-Host "OS:  $($os.Caption)"
    Write-Host "CPU: $($cpu.Name)"
    uptime
}

function Admin { Start-Process pwsh -Verb RunAs }

function Port {
    param([int]$Port)
    Get-NetTCPConnection -LocalPort $Port
}

function Restart-Explorer {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer
}

function Restart-System {
    param([switch]$Force)
    if ($Force -or (Read-Host "Reboot this computer now? (y/N)") -eq 'y') {
        Restart-Computer -Force
    }
}

# =========================================================
# 🦊 APPLICATIONS
# =========================================================

function Get-NotepadPlusPlus {
    $candidates = @(
        "$env:ProgramFiles\Notepad++\notepad++.exe"
    )
    if (${env:ProgramFiles(x86)}) {
        $candidates += "${env:ProgramFiles(x86)}\Notepad++\notepad++.exe"
    }

    $candidates |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}

function notepad {
    # Notepad++ when installed (Tools tier); otherwise the real Windows Notepad. This function shadows
    # notepad.exe, so it must never just give up - fn/al/theme/Edit-Profile all go through it.
    $exe = Get-NotepadPlusPlus
    if (-not $exe) { $exe = Join-Path $env:windir 'notepad.exe' }
    & $exe @args
}

function edit { notepad @args }

function web {
    param([string]$Url)
    if ($Url) { Start-Process $Url }
}

function serve {
    param([int]$Port = 8000)
    Write-Host "Serving $(Get-Location) at http://localhost:$Port (Ctrl+C to stop)" -ForegroundColor Green
    python -m http.server $Port
}

function search {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Query)
    $q = [uri]::EscapeDataString(($Query -join ' '))
    web "https://duckduckgo.com/?q=$q"
}

function bing {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Query)
    $q = [uri]::EscapeDataString(($Query -join ' '))
    web "https://www.bing.com/search?q=$q"
}

function ddg {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Query)
    $q = [uri]::EscapeDataString(($Query -join ' '))
    web "https://duckduckgo.com/?q=$q"
}

function gh-search {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Query)
    $q = [uri]::EscapeDataString(($Query -join ' '))
    web "https://github.com/search?q=$q"
}

function so {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Query)
    $q = [uri]::EscapeDataString(($Query -join ' '))
    web "https://stackoverflow.com/search?q=$q"
}

# =========================================================
# 🧬 GIT
# =========================================================

function gpull { git pull }
function gcom { git add .; git commit -m "$args" }
function lazyg { git add .; git commit -m "$args"; git push }

# =========================================================
# 📝 CONFIGURATION
# =========================================================

function Edit-Profile { & $env:EDITOR (Join-Path $global:RabbitRoot 'profile\Microsoft.PowerShell_profile.ps1') }
function Edit-LocalProfile { & $env:EDITOR (Join-Path (Split-Path -Parent $PROFILE) 'Microsoft.PowerShell_profile.local.ps1') }

function Reload-Profile {
    Remove-Variable RABBIT_PROFILE_LOADED -Scope Global -ErrorAction SilentlyContinue

    # oh-my-posh, notify.ps1 and YouShouldUse each wrap the prompt. Reloading
    # without unwinding that chain makes them wrap each other's wrappers, which
    # ends in a call-depth overflow. Deleting the prompt doesn't work either:
    # `. $PROFILE` here dot-sources into this function's scope, so oh-my-posh's
    # re-init never reaches global and the prompt would be lost. So unwind to
    # the original prompt that notify.ps1 saved, then let them re-wrap cleanly.
    if (Get-Command Disable-YouShouldUse -ErrorAction SilentlyContinue) {
        Disable-YouShouldUse -ErrorAction SilentlyContinue
    }

    if ($global:__PreNotifyPrompt) {
        Set-Item -Path Function:global:prompt -Value $global:__PreNotifyPrompt
    }

    . $PROFILE
    Write-Host "󰑐 Profile reloaded" -ForegroundColor Green
}

function fn { notepad "$PSScriptRoot\functions.ps1" }
function al { notepad "$PSScriptRoot\aliases.ps1" }
function theme { notepad (Join-Path $global:RabbitSettings 'oh-my-rabbit.omp.json') }

# =========================================================
# 🔐 HISTORY
# =========================================================

function forget {
    param([Parameter(Mandatory)][string]$Pattern)
    $historyFile = (Get-PSReadLineOption).HistorySavePath
    if (Test-Path $historyFile) {
        (Get-Content $historyFile) |
            Where-Object { $_ -notmatch [regex]::Escape($Pattern) } |
            Set-Content $historyFile
    }
}

Set-Alias help! Get-Help

# `man <command>` -> Get-Help <command> -Full, so the full article is the
# default rather than the summary. PowerShell ships `man` as an alias for
# `help`; aliases outrank functions, so aliases.ps1 removes it first.
function man {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [switch]$Detailed,
        [switch]$Examples,
        [switch]$Online,
        [switch]$ShowWindow,
        [string]$Parameter
    )

    # Get-Help puts each view in its own parameter set, so they're forwarded
    # one at a time rather than splatted - -Full alongside any other view
    # switch makes Get-Help fail to resolve the set.
    if ($Detailed)   { return Get-Help $Name -Detailed }
    if ($Examples)   { return Get-Help $Name -Examples }
    if ($Online)     { return Get-Help $Name -Online }
    if ($ShowWindow) { return Get-Help $Name -ShowWindow }
    if ($Parameter)  { return Get-Help $Name -Parameter $Parameter }

    Get-Help $Name -Full
}

# =========================================================
# COMMAND PALETTE
# =========================================================

function Invoke-CommandPalette {

    $commands = @(
        "⚡ Edit Profile"
        "📦 Reload Profile"
        "🌳 Git Status"
        "🚀 Git Push"
        "📥 Git Pull"
        "🗂️ Yazi"
        "❓ Help (Ctrl+h)"
        "🏠 Home"
        "📁 Downloads"
        "📄 Documents"
        "🖥️ Desktop"
    )

    $theme = if (Get-Command Get-RabbitFzfTheme -ErrorAction SilentlyContinue) { Get-RabbitFzfTheme -Accent Pink } else { '--color=prompt:#ff42a0' }

    $selection = $commands |
        fzf `
            --height 40% `
            --layout reverse `
            --border `
            --border-label " 🚀 palette " `
            --prompt "⚡ Rabbit Command Palette > " `
            --header "Modern PowerShell Toolkit" `
            $theme

    switch ($selection) {

        "⚡ Edit Profile" { Edit-Profile }
        "📦 Reload Profile" { Reload-Profile }
        "🌳 Git Status" { gs }
        "🚀 Git Push" { gp }
        "📥 Git Pull" { gl }
        "🗂️ Yazi" { yy }
        "❓ Help (Ctrl+h)" { Show-RabbitHelp }
        "🏠 Home" { home }
        "📁 Downloads" { dl }
        "📄 Documents" { docs }
        "🖥️ Desktop" { desk }
    }
}

# =========================================================
# RABBIT HELP  (Ctrl+h)  -  what each shortcut does, in plain words
# =========================================================
# Topics live in the list below. Each one is rendered into a small colored text
# file (palette comes from $global:RabbitPalette, i.e. oh-my-rabbit.omp.json) and
# shown in fzf's preview pane, so you can arrow through them without leaving the
# popup. Enter prints the highlighted page into the terminal so you can keep it.

function Get-RabbitHelpTopics {
    # Mini-markup:  "# title"  "## heading"  "- bullet"  [Key]  `code`
    [ordered]@{
        '00 ⚡ Overview - all keys at a glance' = @'
# Rabbit keys at a glance

## At the prompt
- [Ctrl+F]       find a file and drop its path on your command line
- [Alt+Space]    jump to a folder you have used before
- [Ctrl+Y]       open the Yazi file manager (the shell follows you out)
- [Ctrl+Space]   command palette - a short menu of handy actions
- [Ctrl+R] or [Up]   search your whole command history (Atuin)
- [Ctrl+H]       this help

## More fzf keys (PSFzf)
- [Ctrl+T]  insert a path     [Alt+C]  cd somewhere     [Alt+R]  PSReadLine history
- type `fzf?` for the full fzf cheat sheet, `Test-FzfSetup` to check the wiring

## Inside any fuzzy list
- type to filter, [Up]/[Down] to move, [Enter] to pick, [Esc] to cancel
- [Ctrl+/] toggles the preview pane
- [Ctrl+Y] copy path   [Ctrl+O] open   [Ctrl+E] reveal in Explorer
  (those three act on the highlighted file, in lists that show files)

Pick a topic on the left to read about it.
'@
        '01 🔎 Ctrl+F - file search' = @'
# Ctrl+F  -  find a file

## What it does
Opens a fuzzy list of files, with a preview of the highlighted one.
When you pick a file, its PATH is typed onto your command line.
It does not open or run anything - you decide what to do with it.

## Where it looks
- always the folder you are in and everything below it (hidden files included)
- files your .gitignore hides are left out, and so is the .git folder

## Try it
- type `nvim ` then press [Ctrl+F], pick a file, press [Enter]
  your line now reads `nvim path\to\file` - press [Enter] again to run it
- you do not need exact names: `prof ps1` finds `Microsoft.PowerShell_profile.ps1`

## Filtering tricks
- words are ANDed:  `readme md`
- `'word`  must match exactly      `^word`  must start with it
- `word$`  must end with it        `!word`  must NOT contain it

## Good to know
- [Esc] cancels and leaves your line alone
- needs fzf and fd (the installer adds both)
- looking for a file anywhere on C:?  use `ff name` instead
'@
        '02 🧭 Alt+Space - smart jump' = @'
# Alt+Space  -  smart jump

## What it does
Shows the folders you have visited before (ranked by zoxide: recent and
frequent ones first). Pick one and you are already `cd`-ed there.

## How it learns
Every time you move around the shell, zoxide takes note. A brand new
machine has an empty list - it fills up as you work, so give it a day.

## Try it
- press [Alt+Space], type a few letters of any project folder, press [Enter]
- no menu needed: `z proj` jumps straight to the best match for "proj"

## Good to know
- the preview shows what is inside the highlighted folder
- [Esc] cancels and stays where you are
- needs zoxide and fzf (the installer adds both)
- jump to a folder you have NEVER been in:  `cdf name`  (searches all of C:)
'@
        '03 🗂️ Ctrl+Y - Yazi file manager' = @'
# Ctrl+Y  -  Yazi

## What it does
Opens Yazi, a full-screen file manager in the terminal: three columns -
parent folder, current folder, and a preview of what is under the cursor.
When you quit, your shell lands in the folder you were looking at.
(Typing `yy` does the same thing.)

## The five keys to start with
- [h] [j] [k] [l]  or arrows - left (up a folder), down, up, right (open it)
- [Enter]   open the file with its default program
- [q]       quit and cd the shell to this folder
- [Q]       quit WITHOUT changing folder
- [~]       Yazi's own full key list (also [F1])

## Then these
- [Space] mark files    [y] copy    [x] cut    [p] paste
- [d] send to recycle bin    [a] new file (end with `\` for a folder)    [r] rename
- [/] find in this folder    [.] show / hide hidden files

## Good to know
- nothing is moved until you press [p] - marking and copying are safe
- Yazi wears the same oh-my-rabbit colors as the prompt
'@
        '04 🚀 Ctrl+Space - command palette' = @'
# Ctrl+Space  -  command palette

## What it does
A short menu of things you do all the time. Type to filter, press
[Enter] to run the highlighted one. Nothing to remember.

## What is on it
- edit or reload your profile
- git status / push / pull
- open Yazi
- jump to Home, Downloads, Documents, Desktop
- open this help

## Make it yours
The list lives in `Invoke-CommandPalette` (functions.ps1). Add a line to the
list and a matching line to the `switch` below it - that is all it takes.
'@
        '05 📜 Ctrl+R / Up - history (Atuin)' = @'
# Ctrl+R or Up  -  history search

## What it does
Atuin keeps every command you have run - with the folder, time and whether it
worked - and lets you fuzzy-search all of it, not just this window.

## Try it
- press [Ctrl+R], type a few letters of an old command, press [Enter]
- start typing a command, then press [Up]: the search opens with your text

## Good to know
- [Ctrl+Up] / [Ctrl+Down] are the plain PSReadLine history (prefix match)
- [Alt+R] is the fzf version of PSReadLine history
'@
    }
}

function ConvertTo-RabbitHelpText {
    param([Parameter(Mandatory)][string]$Markup)

    $p   = $global:RabbitPalette
    $esc = [char]27
    $rs  = "$esc[0m"
    $fg  = { param($hex, [switch]$Bold)
        $r = [Convert]::ToInt32($hex.Substring(1, 2), 16); $g = [Convert]::ToInt32($hex.Substring(3, 2), 16); $b = [Convert]::ToInt32($hex.Substring(5, 2), 16)
        "$esc[$(if ($Bold) { '1;' })38;2;$r;$g;${b}m" }

    $title  = & $fg $p.Mint   -Bold
    $head   = & $fg $p.Purple -Bold
    $bullet = & $fg $p.Pink
    $key    = & $fg $p.Cream  -Bold
    $code   = & $fg $p.Cyan
    $text   = & $fg $p.Text

    # Colour codes are added only AFTER the markup has been parsed. (Colouring the bullet first and then
    # searching the line for [Key] let the "[" of an ESC[...m code pair with a later "]", which ate the
    # escape sequences and printed fragments like "38;2;255;66;160m" in the help text.)
    $plain = ($global:RabbitThemeEnabled -eq $false)
    $span  = {
        param($text, $keyColor, $codeColor, $textColor)
        [regex]::Replace($text, '\[([^\]]+)\]|`([^`]+)`', {
            param($m)
            if ($m.Groups[1].Success) { "$keyColor$($m.Groups[1].Value)$textColor" } else { "$codeColor$($m.Groups[2].Value)$textColor" }
        })
    }

    $out = foreach ($line in ($Markup -split "\r?\n")) {
        if ($plain) {
            if     ($line -like '# *')  { $line.Substring(2); continue }
            elseif ($line -like '## *') { $line.Substring(3); continue }
            if ($line -like '- *') { $line = '• ' + $line.Substring(2) }
            [regex]::Replace($line, '\[([^\]]+)\]|`([^`]+)`', { param($m) if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value } })
            continue
        }

        if     ($line -like '# *')  { "$title$($line.Substring(2))$rs"; continue }
        elseif ($line -like '## *') { "$head$($line.Substring(3))$rs"; continue }

        if ($line -like '- *') { $body = & $span $line.Substring(2) $key $code $text; "$bullet•$rs$text $body$rs" }
        else                   { $body = & $span $line $key $code $text;             "$text$body$rs" }
    }
    $out -join "`n"
}

function Show-RabbitHelp {
    <#
    .SYNOPSIS
        Ctrl+h help launcher: what Ctrl+F, Alt+Space, Ctrl+Y and Ctrl+Space do.
    .DESCRIPTION
        Opens a themed fzf list of topics with a live preview. Enter prints the
        highlighted page into the terminal. Without fzf, prints every page.
    #>
    [CmdletBinding()]
    param()

    $topics = Get-RabbitHelpTopics
    $dir    = Join-Path ([IO.Path]::GetTempPath()) 'rabbit-help'
    $null   = New-Item -ItemType Directory -Path $dir -Force
    $utf8   = [Text.UTF8Encoding]::new($false)

    $rows  = foreach ($name in $topics.Keys) {
        $file = Join-Path $dir (($name -replace '[^A-Za-z0-9]+', '-').Trim('-') + '.txt')
        [IO.File]::WriteAllText($file, (ConvertTo-RabbitHelpText $topics[$name]) + "`n", $utf8)
        "$name`t$file"
    }

    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        foreach ($row in $rows) { Write-Host (Get-Content -LiteralPath ($row -split "`t")[1] -Raw); Write-Host '' }
        return
    }

    $theme = if (Get-Command Get-RabbitFzfTheme -ErrorAction SilentlyContinue) { Get-RabbitFzfTheme -Accent Cyan } else { '--color=border:#00ffff' }

    $picked = $rows | fzf --delimiter "`t" --with-nth 1 --no-multi `
        --height 85% --layout reverse --border rounded --border-label ' ❓ rabbit keys ' `
        --prompt 'topic > ' --info hidden `
        --header 'arrows move · enter prints the page here · esc closes' `
        --preview 'type {2}' --preview-window 'right,68%,border-left,wrap' `
        --bind 'ctrl-y:ignore,ctrl-o:ignore,ctrl-e:ignore' $theme

    if ($picked) {
        Write-Host ''
        Write-Host (Get-Content -LiteralPath (($picked | Select-Object -First 1) -split "`t")[1] -Raw)
    }
}

Set-Alias keys Show-RabbitHelp
