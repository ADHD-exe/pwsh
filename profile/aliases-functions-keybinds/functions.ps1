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
function vault { Set-Location "D:\" }
function repo { Set-Location "C:\Repositories" }
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
        "vault", "Go to D:\"
        "repo", "Go to C:\Repositories"
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
        "🏠 Home"
        "📁 Downloads"
        "📄 Documents"
        "🖥️ Desktop"
    )

    $selection = $commands |
        fzf `
            --height 40% `
            --layout reverse `
            --border `
            --prompt "⚡ Rabbit Command Palette > " `
            --header "Modern PowerShell Toolkit"

    switch ($selection) {

        "⚡ Edit Profile" { Edit-Profile }
        "📦 Reload Profile" { Reload-Profile }
        "🌳 Git Status" { gs }
        "🚀 Git Push" { gp }
        "📥 Git Pull" { gl }
        "🗂️ Yazi" { yy }
        "🏠 Home" { home }
        "📁 Downloads" { dl }
        "📄 Documents" { docs }
        "🖥️ Desktop" { desk }
    }
}
