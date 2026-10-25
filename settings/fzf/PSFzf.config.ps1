#Requires -Version 5.1
<#
===============================================================================
  PSFzf.config.ps1  -  fzf + PSFzf setup for PowerShell on Windows
===============================================================================

  Dot-source this from your $PROFILE, AFTER atuin and zoxide have initialised:

      . "$env:USERPROFILE\.config\fzf\PSFzf.config.ps1"

  Run  Show-FzfHelp   (alias: fzf?)  for the cheat sheet.
  Run  Test-FzfSetup            to verify everything wired up correctly.

  Design notes
  ------------
  * Ctrl+R is deliberately left to atuin. PSFzf's history search moves to Alt+R.
  * Alt+C is wired to the zoxide database, the same way PSFzf's README wires
    ZLocation. Jumping through it also feeds the jump back to zoxide.
  * File search is backed by Everything (via PSEverything) -- it queries an
    index, so searching all of C:\ returns instantly instead of walking 500k
    files. fd is used as a fallback, and fzf's own walker after that.
  * PSFzf's `fd` and `ff` aliases are NOT enabled: they would shadow the real
    fd.exe and the ff function defined below.
===============================================================================
#>

# =============================================================================
#  1. SETTINGS  -- edit these, everything else keys off them
# =============================================================================

$global:FzfCfg = [ordered]@{

    # Where "search everything" means. Change to 'D:\' or a folder to rescope.
    Root          = 'C:\'

    # Paths never returned unless you pass -All. Full paths for Everything;
    # the last component is what fd/fzf-walker exclude on.
    Excludes      = @(
        'C:\Windows\WinSxS'
        'C:\Windows\servicing'
        'C:\Windows\System32\DriverStore'
        'C:\Program Files\WindowsApps'
        'C:\ProgramData\Package Cache'
        'C:\$Recycle.Bin'
        'C:\System Volume Information'
        'node_modules'
        '.git'
        '\AppData\Local\Temp'
    )

    # Use the Everything index when PSEverything is available.
    UseEverything = $true

    # Editor for `fe`. $null = autodetect ($env:EDITOR, code, nvim, notepad).
    Editor        = $null

    # PSReadLine chords. Ctrl+r is intentionally absent -- that's atuin's.
    Chords        = [ordered]@{
        Provider           = 'Ctrl+t'   # insert path(s) at the cursor
        ReverseHistory     = 'Alt+r'    # PSReadLine history (atuin keeps Ctrl+r)
        SetLocation        = 'Alt+c'    # jump to a directory (zoxide-backed)
        ReverseHistoryArgs = 'Alt+a'    # pull an argument out of history
    }

    # Set $true to let Tab do fuzzy completion. Off by default -- it changes
    # muscle memory for every completion in the shell.
    FuzzyTab      = $false
}

$script:FzfCfgDir = $PSScriptRoot
$script:FzfHint   = 'ctrl-y copy · ctrl-o open · ctrl-e reveal · ctrl-/ preview · tab mark'


# =============================================================================
#  2. PATH + fzf OPTIONS FILE
# =============================================================================

# Put fzf-preview.cmd / fzf-action.cmd on PATH so fzf.conf can name them bare.
if ($script:FzfCfgDir -and ($env:PATH -notlike "*$script:FzfCfgDir*")) {
    $env:PATH = "$script:FzfCfgDir;$env:PATH"
}

$script:FzfExe     = Get-Command fzf.exe -ErrorAction SilentlyContinue
$script:FzfVersion = [version]'0.0.0'
if ($script:FzfExe) {
    # Probe with a clean environment: fzf validates FZF_DEFAULT_OPTS /
    # FZF_DEFAULT_OPTS_FILE even for --version, so a broken inherited value
    # makes the probe error out and the version parse silently fail (0.0.0).
    $probeOpts      = $env:FZF_DEFAULT_OPTS
    $probeOptsFile  = $env:FZF_DEFAULT_OPTS_FILE
    $env:FZF_DEFAULT_OPTS     = $null
    $env:FZF_DEFAULT_OPTS_FILE = $null
    try {
        $raw = (& $script:FzfExe.Source --version 2>$null) -split '\s+' | Select-Object -First 1
        if ($raw -match '^\d+\.\d+\.\d+') { $script:FzfVersion = [version]$Matches[0] }
    }
    finally {
        $env:FZF_DEFAULT_OPTS     = $probeOpts
        $env:FZF_DEFAULT_OPTS_FILE = $probeOptsFile
    }
}

$script:FzfConfFile = Join-Path $script:FzfCfgDir 'fzf.conf'
if (Test-Path -LiteralPath $script:FzfConfFile) {
    if ($script:FzfVersion -ge [version]'0.55.0') {
        # fzf reads the file itself, comments and all. Drop any inherited
        # FZF_DEFAULT_OPTS: fzf applies BOTH sources, and a stale inline
        # string would fight (or break) the options file.
        Remove-Item Env:\FZF_DEFAULT_OPTS -ErrorAction SilentlyContinue
        $env:FZF_DEFAULT_OPTS_FILE = $script:FzfConfFile
    }
    else {
        # Older fzf: strip comments/blank lines here and pass options inline.
        Remove-Item Env:\FZF_DEFAULT_OPTS_FILE -ErrorAction SilentlyContinue
        $opts = Get-Content -LiteralPath $script:FzfConfFile |
            ForEach-Object { ($_ -replace '(^|\s)#.*$', '').Trim() } |
            Where-Object { $_ }
        $env:FZF_DEFAULT_OPTS = ($opts -join ' ')
        if ($script:FzfVersion -lt [version]'0.48.0') {
            Write-Warning "fzf $script:FzfVersion is old: --walker options need 0.48+, the options file needs 0.47+, comments need 0.55+. Run: winget upgrade junegunn.fzf"
        }
    }
}

# Note: $env:FZF_DEFAULT_COMMAND is deliberately left UNSET.
# Setting it would make PSFzf's Ctrl+T ignore the path you're typing and scan
# all of C:\ instead. The C:\ default lives in fzf.conf's --walker-root, which
# only applies to a bare `fzf` with nothing piped in -- which is what you want.


# =============================================================================
#  3. PSFzf  -- imported with atuin-safe chords
# =============================================================================

if (-not (Get-Module -ListAvailable -Name PSFzf)) {
    Write-Warning 'PSFzf is not installed. Run: Install-Module PSFzf -Scope CurrentUser'
}
else {
    Import-Module PSFzf -ArgumentList `
        $FzfCfg.Chords.Provider,
        $FzfCfg.Chords.ReverseHistory,
        $FzfCfg.Chords.SetLocation,
        $FzfCfg.Chords.ReverseHistoryArgs `
        -ErrorAction SilentlyContinue

    $psfzfOpts = @{
        PSReadlineChordProvider           = $FzfCfg.Chords.Provider
        PSReadlineChordReverseHistory     = $FzfCfg.Chords.ReverseHistory
        PSReadlineChordSetLocation        = $FzfCfg.Chords.SetLocation
        PSReadlineChordReverseHistoryArgs = $FzfCfg.Chords.ReverseHistoryArgs

        # Aliases that do NOT collide with anything here:
        EnableAliasFuzzyKillProcess       = $true    # fkill
        EnableAliasFuzzyGitStatus         = $true    # fgs
        EnableAliasFuzzyHistory           = $true    # fh  (PSReadLine history file)
        EnableAliasFuzzySetEverything     = $true    # cde (Everything -> cd)

        # Deliberately NOT enabled:
        #   EnableAliasFuzzySetLocation -> would alias `fd` over fd.exe
        #   EnableAliasFuzzyFasd        -> would alias `ff` over the ff below
        #   EnableAliasFuzzyEdit        -> `fe` below is the C:-aware version
        #   EnableAliasFuzzyZLocation   -> you use zoxide, see `zf` / Alt+C

        GitKeyBindings                    = $true
        TabExpansion                      = [bool]$FzfCfg.FuzzyTab
    }
    if (Get-Command fd.exe -ErrorAction SilentlyContinue) { $psfzfOpts.EnableFd = $true }

    # Only pass parameters this PSFzf build actually understands.
    $known = (Get-Command Set-PsFzfOption -ErrorAction SilentlyContinue).Parameters
    if ($known) {
        $safe = @{}
        foreach ($k in $psfzfOpts.Keys) { if ($known.ContainsKey($k)) { $safe[$k] = $psfzfOpts[$k] } }
        Set-PsFzfOption @safe
    }
}


# =============================================================================
#  4. zoxide  -- the PSFzf/ZLocation integration pattern, for zoxide
# =============================================================================

$script:HasZoxide = [bool](Get-Command zoxide -ErrorAction SilentlyContinue)

if ($script:HasZoxide) {
    # Alt+C: PSFzf Invoke-Expression's this and pipes the result into fzf.
    $env:FZF_ALT_C_COMMAND = 'zoxide query --list'

    # ...and jumping through it feeds the directory back into zoxide's ranking.
    if (Get-Command Set-PsFzfOption -ErrorAction SilentlyContinue) {
        Set-PsFzfOption -AltCCommand {
            param($Location)
            Set-Location -LiteralPath $Location
            zoxide add -- $Location
        }
    }

    # `zi` gets its list as "score  path", which our global preview can't read.
    # Hide the preview there; use `zf` below for a previewing directory jumper.
    $env:_ZO_FZF_OPTS = '--preview-window=hidden --height=45% --layout=reverse --no-sort --exit-0 --select-1'
}


# =============================================================================
#  5. Everything  -- the index that makes C:-wide search instant
# =============================================================================

$script:HasEverything = $false
if ($FzfCfg.UseEverything) {
    if (-not (Get-Command Search-Everything -ErrorAction SilentlyContinue)) {
        Import-Module PSEverything -ErrorAction SilentlyContinue
    }
    $script:HasEverything = [bool](Get-Command Search-Everything -ErrorAction SilentlyContinue)
}
$script:HasFd = [bool](Get-Command fd.exe -ErrorAction SilentlyContinue)


# --- helpers ----------------------------------------------------------------

function script:ConvertTo-EvSize {
    param([object]$Value)
    if ($null -eq $Value -or $Value -eq '') { return $null }
    if ($Value -is [string] -and $Value -notmatch '^\d+$') { return $Value.ToLower() }
    return [string][int64]$Value          # PowerShell's 100MB literal -> bytes
}

function script:ConvertTo-EvDate {
    param([object]$Value)
    if ($null -eq $Value -or $Value -eq '') { return $null }
    if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-dd') }
    $s = [string]$Value
    if ($s -match '^(\d+)\s*$')            { return [datetime]::Today.AddDays(-[int]$Matches[1]).ToString('yyyy-MM-dd') }
    if ($s -match '^(\d+)\s*d(ays?)?$')    { return [datetime]::Today.AddDays(-[int]$Matches[1]).ToString('yyyy-MM-dd') }
    if ($s -match '^(\d+)\s*h(ours?)?$')   { return [datetime]::Now.AddHours(-[int]$Matches[1]).ToString('yyyy-MM-dd') }
    if ($s -match '^(\d+)\s*w(eeks?)?$')   { return [datetime]::Today.AddDays(-7 * [int]$Matches[1]).ToString('yyyy-MM-dd') }
    return $s                              # 'today', 'thisweek', 'lastmonth', ...
}

function script:Normalize-FzfPath {
    # Keep the backslash on a drive root ("C:\"), drop it everywhere else, so
    # Everything's path: filter gets a form it understands in both cases.
    param([string]$Path)
    if ($Path -match '^[A-Za-z]:\\?$') { return $Path.Substring(0, 2) + '\' }
    return $Path.TrimEnd('\')
}

function script:Format-FzfSize {
    param([int64]$Bytes)
    $u = 'B', 'KB', 'MB', 'GB', 'TB'; $i = 0; $n = [double]$Bytes
    while ($n -ge 1024 -and $i -lt 4) { $n /= 1024; $i++ }
    if ($i -eq 0) { '{0} B' -f [int64]$n } else { '{0:N1} {1}' -f $n, $u[$i] }
}

function script:Get-FzfEditor {
    if ($FzfCfg.Editor) { return $FzfCfg.Editor }
    if ($env:EDITOR)    { return $env:EDITOR }
    foreach ($e in 'code', 'nvim', 'vim', 'notepad++', 'notepad') {
        if (Get-Command $e -ErrorAction SilentlyContinue) { return $e }
    }
    return 'notepad'
}


# --- candidate sources ------------------------------------------------------

function script:Get-FzfCandidates {
    <# Builds the query for whichever backend is available and returns paths. #>
    param(
        [string]   $Root,
        [string]   $Text,
        [string[]] $Ext,
        [object]   $Bigger,
        [object]   $Smaller,
        [object]   $Since,
        [string]   $Kind = 'File',
        [string[]] $Excludes = @(),
        [string]   $Raw,
        [int]      $First = 0
    )

    # ---------- Everything (indexed, instant) ----------
    if ($script:HasEverything) {
        $p = New-Object System.Collections.Generic.List[string]
        if ($Raw) { $p.Add($Raw) }
        else {
            switch ($Kind) { 'File' { $p.Add('file:') } 'Folder' { $p.Add('folder:') } }
            $p.Add('path:"{0}"' -f (script:Normalize-FzfPath $Root))
            if ($Ext)     { $p.Add('ext:' + (($Ext | ForEach-Object { $_.TrimStart('.') }) -join ';')) }
            $bg = script:ConvertTo-EvSize $Bigger
            $sm = script:ConvertTo-EvSize $Smaller
            if ($bg -and $sm) { $p.Add("size:$sm..$bg") }
            elseif ($bg)      { $p.Add("size:>$bg") }
            elseif ($sm)      { $p.Add("size:<$sm") }
            $dt = script:ConvertTo-EvDate $Since
            if ($dt) { if ($dt -match '^\d{4}-\d{2}-\d{2}$') { $p.Add("dm:>$dt") } else { $p.Add("dm:$dt") } }
            foreach ($x in $Excludes) { $p.Add('!path:"{0}"' -f $x.TrimEnd('\')) }
            if ($Text) { $p.Add($Text) }
        }
        $filter = ($p -join ' ')
        Write-Verbose "Everything query: $filter"
        try {
            $out = Search-Everything -Filter $filter -Global
            if ($First -gt 0) { $out = $out | Select-Object -First $First }
            return $out
        }
        catch {
            Write-Warning "Everything query failed ($($_.Exception.Message)); falling back to fd."
        }
    }

    # ---------- fd (fast walker) ----------
    if ($script:HasFd) {
        $a = @('--absolute-path', '--hidden', '--no-ignore', '--color', 'never')
        switch ($Kind) { 'File' { $a += '--type', 'file' } 'Folder' { $a += '--type', 'directory' } }
        foreach ($e in $Ext) { $a += '--extension', $e.TrimStart('.') }
        $bg = script:ConvertTo-EvSize $Bigger; if ($bg -match '^\d+$') { $a += '--size', "+${bg}b" }
        $sm = script:ConvertTo-EvSize $Smaller; if ($sm -match '^\d+$') { $a += '--size', "-${sm}b" }
        if ("$Since" -match '^\d+$') { $a += '--changed-within', "${Since}d" }
        foreach ($x in $Excludes) { $a += '--exclude', (Split-Path $x -Leaf) }
        $a += '--search-path', $Root
        if ($Text) { $a += [regex]::Escape($Text) } else { $a += '.' }
        Write-Verbose "fd $($a -join ' ')"
        $out = & fd.exe @a 2>$null
        if ($First -gt 0) { $out = $out | Select-Object -First $First }
        return $out
    }

    # ---------- last resort: Get-ChildItem ----------
    Write-Warning 'Neither Everything (PSEverything) nor fd is available; this will be slow. Install PSEverything or fd.'

    $extSet = @()
    if ($Ext) { $extSet = @($Ext | ForEach-Object { '.' + $_.TrimStart('.') }) }
    $bgB = $null; $smB = $null
    $v = script:ConvertTo-EvSize $Bigger;  if ($v -match '^\d+$') { $bgB = [int64]$v }
    $v = script:ConvertTo-EvSize $Smaller; if ($v -match '^\d+$') { $smB = [int64]$v }
    $sinceDt = $null
    $d = script:ConvertTo-EvDate $Since
    if ($d -match '^\d{4}-\d{2}-\d{2}$') { $sinceDt = [datetime]::ParseExact($d, 'yyyy-MM-dd', $null) }

    $gci = @{ LiteralPath = $Root; Recurse = $true; Force = $true; ErrorAction = 'SilentlyContinue' }
    if ($Kind -eq 'File') { $gci.File = $true } elseif ($Kind -eq 'Folder') { $gci.Directory = $true }

    $out = Get-ChildItem @gci | Where-Object {
        foreach ($x in $Excludes) { if ($_.FullName -like "*$x*") { return $false } }
        if ($Text -and $_.Name -notlike "*$Text*") { return $false }
        if ($extSet -and $extSet -notcontains $_.Extension) { return $false }
        if ($null -ne $bgB -and -not $_.PSIsContainer -and $_.Length -le $bgB) { return $false }
        if ($null -ne $smB -and -not $_.PSIsContainer -and $_.Length -ge $smB) { return $false }
        if ($null -ne $sinceDt -and $_.LastWriteTime -lt $sinceDt) { return $false }
        return $true
    } | Select-Object -ExpandProperty FullName

    if ($First -gt 0) { $out = $out | Select-Object -First $First }
    return $out
}


# =============================================================================
#  6. THE COMMANDS
# =============================================================================

function Find-FzfFile {
    <#
    .SYNOPSIS
        Fuzzy-find files anywhere on C: (or wherever you point it).
    .EXAMPLE
        ff                          # everything on C:, pick one
        ff config                   # ...whose name contains "config"
        ff -In D:\src -Ext ps1,psm1 # PowerShell files under D:\src
        ff -Bigger 500MB            # files over half a gig
        ff -Since 7                 # touched in the last 7 days
        ff -Raw 'ext:log dm:today'  # raw Everything query syntax
        ff -Ext log | Remove-Item   # everything returns paths, so it pipes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string] $Query,
        [Alias('i', 'Path')]     [string] $In,
        [Alias('x')]           [string[]] $Ext,
        [Alias('b')]             [object] $Bigger,
        [Alias('s')]             [object] $Smaller,
        [Alias('n')]             [object] $Since,
        [Alias('r')]             [string] $Raw,
        [ValidateSet('File', 'Folder', 'Any')][string] $Kind = 'File',
        [switch] $All,
        [int]    $First = 0,
        [string] $Prompt,
        [string] $Header,
        [switch] $NoPreview,
        [switch] $Single
    )

    $root = $FzfCfg.Root
    if ($In) {
        $resolved = Resolve-Path -LiteralPath $In -ErrorAction SilentlyContinue
        if (-not $resolved) { Write-Error "-In path not found: $In"; return }
        $root = $resolved.ProviderPath
    }
    $ex = if ($All) { @() } else { $FzfCfg.Excludes }

    $candidates = script:Get-FzfCandidates -Root $root -Text $Query -Ext $Ext -Bigger $Bigger `
        -Smaller $Smaller -Since $Since -Kind $Kind -Excludes $ex -Raw $Raw -First $First

    if (-not $candidates) { Write-Warning 'No matches.'; return }

    if (-not $Prompt) {
        $label = if ($Kind -eq 'Folder') { 'dir' } else { 'file' }
        $Prompt = "$label $(script:Normalize-FzfPath $root)> "
    }
    if (-not $Header) { $Header = $script:FzfHint }

    $fzfArgs = @{ Prompt = $Prompt; Header = $Header }
    if (-not $Single)    { $fzfArgs.Multi = $true }
    if (-not $NoPreview) { $fzfArgs.Preview = 'fzf-preview.cmd {}' }

    $candidates | Invoke-Fzf @fzfArgs
}

# NOTE: the wrappers below forward $args to Find-FzfFile, so they must stay
# simple functions. Adding [CmdletBinding()] would make PowerShell reject any
# parameter they don't declare themselves, and `ffd -Ext ps1` would break.

function Find-FzfFolder {
    <#  Same filters as ff, but returns directories.  #>
    Find-FzfFile -Kind Folder @args
}


function Find-FzfHere {
    <#  ff, scoped to the current directory instead of C:.  #>
    Find-FzfFile -In $PWD.ProviderPath @args
}


function Find-FzfByExt {
    <#
    .EXAMPLE
        ffe ps1              # every .ps1 on C:
        ffe log,txt -Since 1 # logs and text files touched today
    #>
    param([Parameter(Mandatory, Position = 0)][string[]] $Extension)
    Find-FzfFile -Ext $Extension @args
}


function Find-FzfBig {
    <#
    .SYNOPSIS
        Biggest files first, with a size column you can also type into.
    .EXAMPLE
        ffb                  # files over 100 MB on C:, largest first
        ffb 1GB              # over a gig
        ffb 200MB -In D:\    # on another drive
        ffb | Remove-Item -WhatIf
    .NOTES
        The size column is searchable: type "GB" to keep only gigabyte files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][object] $Bigger = 100MB,
        [Alias('i', 'Path')]     [string] $In,
        [Alias('x')]           [string[]] $Ext,
        [int]  $First = 500,
        [switch] $All
    )

    $root = $FzfCfg.Root
    if ($In) {
        $resolved = Resolve-Path -LiteralPath $In -ErrorAction SilentlyContinue
        if (-not $resolved) { Write-Error "-In path not found: $In"; return }
        $root = $resolved.ProviderPath
    }
    $ex = if ($All) { @() } else { $FzfCfg.Excludes }

    $paths = script:Get-FzfCandidates -Root $root -Ext $Ext -Bigger $Bigger -Kind File -Excludes $ex
    if (-not $paths) { Write-Warning 'No matches.'; return }

    $lines = $paths |
        ForEach-Object { try { Get-Item -LiteralPath $_ -Force -ErrorAction Stop } catch { } } |
        Sort-Object Length -Descending |
        Select-Object -First $First |
        ForEach-Object { "{0,10}`t{1}" -f (script:Format-FzfSize $_.Length), $_.FullName }

    $lines | Invoke-Fzf -Multi -NoSort -Delimiter "`t" `
        -Preview 'fzf-preview.cmd {2}' `
        -Prompt 'biggest> ' `
        -Header "sorted by size · type GB/MB to filter · $script:FzfHint" |
        ForEach-Object { ($_ -split "`t", 2)[1].Trim() }
}


function Find-FzfRecent {
    <#
    .EXAMPLE
        ffn          # files touched in the last 7 days
        ffn 1        # ...today
        ffn 30 -Ext psd1
    #>
    param([Parameter(Position = 0)][object] $Days = 7)
    Find-FzfFile -Since $Days -Prompt "modified <${Days}d> " @args
}


function Set-FzfLocation {
    <#  Pick a directory anywhere on C: and cd into it (also tells zoxide).  #>
    [CmdletBinding()]
    param([Parameter(Position = 0)][string] $Query)
    $d = Find-FzfFile -Kind Folder -Query $Query -Single -Prompt 'cd> '
    if ($d) {
        Set-Location -LiteralPath $d
        if ($script:HasZoxide) { zoxide add -- $d }
    }
}


function Invoke-FzfZoxide {
    <#
    .SYNOPSIS
        Fuzzy-jump through the zoxide database, with previews.
    .DESCRIPTION
        The zoxide equivalent of PSFzf's Invoke-FuzzyZLocation. Selecting a
        directory both cd's there and bumps its zoxide score.
    #>
    [CmdletBinding()]
    param([Parameter(Position = 0)][string] $Query)

    if (-not $script:HasZoxide) { Write-Warning 'zoxide is not on PATH.'; return }
    $dirs = @(zoxide query --list)
    if (-not $dirs) { Write-Warning 'zoxide database is empty -- cd around a bit first.'; return }

    $sel = $dirs | Invoke-Fzf -NoSort -Query $Query -Prompt 'jump> ' `
        -Preview 'fzf-preview.cmd {}' `
        -Header "zoxide · most-used first · $script:FzfHint"
    if ($sel) {
        Set-Location -LiteralPath $sel
        zoxide add -- $sel
    }
}


function Edit-FzfFile {
    <#  Pick file(s) with ff's filters and open them in your editor.  #>
    $files = @(Find-FzfFile @args)
    if ($files.Count) { & (script:Get-FzfEditor) @files }
}


function Open-FzfFile {
    <#  Pick file(s) and open with the Windows default application.  #>
    $files = @(Find-FzfFile @args)
    foreach ($f in $files) { Start-Process -FilePath $f }
}


function Copy-FzfPath {
    <#  Pick path(s) and copy them to the clipboard.  #>
    $files = @(Find-FzfFile @args)
    if ($files.Count) {
        ($files -join [Environment]::NewLine) | Set-Clipboard
        Write-Host "Copied $($files.Count) path(s) to the clipboard."
    }
}


function Find-FzfContent {
    <#
    .SYNOPSIS
        Live ripgrep search through file contents, with fzf as the front end.
    .DESCRIPTION
        Wraps PSFzf's Invoke-PsFzfRipgrep. Inside the window, Ctrl+R re-runs
        ripgrep with your typed query and Ctrl+F switches to fuzzy-filtering
        the results you already have.
    .EXAMPLE
        ffr TODO
        ffr 'function .*Fzf' -In C:\src
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string] $Pattern,
        [Alias('i', 'Path')]                [string] $In
    )
    if (-not (Get-Command rg.exe -ErrorAction SilentlyContinue)) {
        Write-Warning 'ripgrep (rg) is not installed. Run: winget install BurntSushi.ripgrep.MSVC'
        return
    }
    if ($In) { Push-Location -LiteralPath $In }
    try { Invoke-PsFzfRipgrep -SearchString $Pattern }
    finally { if ($In) { Pop-Location } }
}


# =============================================================================
#  7. ALIASES
# =============================================================================

Set-Alias ff    Find-FzfFile     -Force -Scope Global
Set-Alias ffd   Find-FzfFolder   -Force -Scope Global
Set-Alias ffh   Find-FzfHere     -Force -Scope Global
Set-Alias ffe   Find-FzfByExt    -Force -Scope Global
Set-Alias ffb   Find-FzfBig      -Force -Scope Global
Set-Alias ffn   Find-FzfRecent   -Force -Scope Global
Set-Alias ffr   Find-FzfContent  -Force -Scope Global
Set-Alias cdf   Set-FzfLocation  -Force -Scope Global
Set-Alias zf    Invoke-FzfZoxide -Force -Scope Global
Set-Alias fe    Edit-FzfFile     -Force -Scope Global
Set-Alias fo    Open-FzfFile     -Force -Scope Global
Set-Alias fcp   Copy-FzfPath     -Force -Scope Global


# =============================================================================
#  8. CHEAT SHEET + SELF-TEST
# =============================================================================

function Show-FzfHelp {
    <#  The whole setup on one screen. Alias: fzf?  #>
    $h = @{ ForegroundColor = 'Cyan' }; $k = @{ ForegroundColor = 'Yellow' }; $d = @{ ForegroundColor = 'Gray' }

    function line($key, $desc) {
        Write-Host ('  {0,-30}' -f $key) -NoNewline @k
        Write-Host $desc @d
    }

    Write-Host ''
    Write-Host '  FIND THINGS' @h
    line 'ff [text]'                  'files on C: (Everything index - instant)'
    line 'ff -In <dir>'               'scope to a directory'
    line 'ff -Ext ps1,psm1'           'by extension'
    line 'ff -Bigger 500MB'           'bigger than'
    line 'ff -Smaller 1KB'            'smaller than'
    line 'ff -Since 7'                'modified in the last N days'
    line 'ff -All'                    'include WinSxS, WindowsApps, node_modules...'
    line 'ff -Raw "<query>"'          'raw Everything syntax, see below'
    line 'ff -First 500'              'cap the result count'
    Write-Host ''
    Write-Host '  SHORTCUTS' @h
    line 'ffh [text]'                 'find here (current directory)'
    line 'ffd [text]'                 'find folders, not files'
    line 'ffe ps1[,psm1]'             'find by extension'
    line 'ffb [100MB]'                'biggest files first, with a size column'
    line 'ffn [7]'                    'newest files (last N days)'
    line 'ffr <pattern>'              'search file CONTENTS (live ripgrep)'
    Write-Host ''
    Write-Host '  DO SOMETHING WITH THE PICK' @h
    line 'fe / fo / fcp'              'edit / open / copy path  (take ff''s filters)'
    line 'cdf [text]'                 'cd to any folder on C:'
    line 'zf [text]'                  'jump through the zoxide database'
    line 'fkill / fgs / fh / cde'     'kill process / git status / history / Everything-cd'
    line 'ff -Ext log | Remove-Item'  'it all returns paths, so it all pipes'
    Write-Host ''
    Write-Host '  KEYS AT THE PROMPT' @h
    line $FzfCfg.Chords.Provider           'insert path(s) at the cursor'
    line $FzfCfg.Chords.SetLocation        'cd via zoxide'
    line $FzfCfg.Chords.ReverseHistory     'PSReadLine history (Ctrl+r stays atuin''s)'
    line $FzfCfg.Chords.ReverseHistoryArgs 'pull an argument out of history'
    Write-Host ''
    Write-Host '  KEYS INSIDE FZF' @h
    line 'tab / ctrl-a / ctrl-x'      'mark one / all / none'
    line 'ctrl-y / ctrl-o / ctrl-e'   'copy path / open / reveal in Explorer'
    line 'ctrl-/ or alt-p'            'toggle preview'
    line 'alt-w'                      'move the preview pane'
    line 'alt-up / alt-down'          'scroll the preview'
    line 'ctrl-s / ctrl-u'            'toggle sort / clear query'
    Write-Host ''
    Write-Host '  EVERYTHING QUERY SYNTAX (for -Raw)' @h
    line 'ext:jpg;png'                'extensions, semicolon separated'
    line 'path:C:\src'                'anywhere under a path'
    line 'size:>100mb   size:1mb..9mb' 'size and ranges'
    line 'dm:today  dm:>2026-01-01'   'date modified'
    line 'file:  folder:  empty:'     'restrict to type'
    line '!node_modules'              'exclude'
    line 'a|b'                        'either'
    line 'regex:^log.*\.txt$'         'regular expression'
    Write-Host ''
    Write-Host '  CONFIG' @h
    line '$FzfCfg'                    'live settings (Root, Excludes, Editor...)'
    line 'notepad <configdir>\fzf.conf' 'fzf layout, colors and keys'
    line 'Test-FzfSetup'              'check that everything is wired up'
    Write-Host ''
}
Set-Alias 'fzf?' Show-FzfHelp -Force -Scope Global


function Test-FzfSetup {
    <#  Verifies versions, the options file, the backends and chord conflicts.  #>
    [CmdletBinding()] param()

    function row($name, $ok, $detail) {
        $mark = if ($ok -eq $true) { '  OK  ' } elseif ($ok -eq $null) { ' WARN ' } else { ' FAIL ' }
        $col = if ($ok -eq $true) { 'Green' } elseif ($ok -eq $null) { 'Yellow' } else { 'Red' }
        Write-Host "[$mark]" -ForegroundColor $col -NoNewline
        Write-Host (' {0,-22}' -f $name) -NoNewline
        Write-Host $detail -ForegroundColor Gray
    }

    Write-Host ''
    row 'fzf' ([bool]$script:FzfExe) $(if ($script:FzfExe) { "v$script:FzfVersion  $($script:FzfExe.Source)" } else { 'not on PATH -- winget install junegunn.fzf' })

    if ($script:FzfExe) {
        $mode = if ($env:FZF_DEFAULT_OPTS_FILE) { "FZF_DEFAULT_OPTS_FILE -> $env:FZF_DEFAULT_OPTS_FILE" }
                elseif ($env:FZF_DEFAULT_OPTS) { 'inlined into FZF_DEFAULT_OPTS (fzf < 0.55)' }
                else { 'NOT LOADED' }
        row 'fzf.conf' ([bool](Test-Path -LiteralPath $script:FzfConfFile)) $mode

        # Actually run fzf so a bad option in fzf.conf shows up here, not later.
        $err = & { 'probe' | & $script:FzfExe.Source --filter=probe } 2>&1 |
            Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }
        row 'fzf options parse' (-not $err) $(if ($err) { "$err" } else { 'no errors' })
    }

    row 'PSFzf' ([bool](Get-Module PSFzf)) $(if (Get-Module PSFzf) { "v$((Get-Module PSFzf).Version)" } else { 'Install-Module PSFzf -Scope CurrentUser' })
    row 'Everything index' $(if ($script:HasEverything) { $true } else { $null }) $(if ($script:HasEverything) { 'PSEverything loaded -- C: search is instant' } else { 'PSEverything not loaded; falling back to fd' })
    row 'fd' $(if ($script:HasFd) { $true } else { $null }) $(if ($script:HasFd) { 'present (fallback + PSFzf Ctrl+T)' } else { 'winget install sharkdp.fd' })
    row 'ripgrep' $(if (Get-Command rg.exe -EA SilentlyContinue) { $true } else { $null }) 'needed by ffr'
    row 'bat' $(if (Get-Command bat.exe -EA SilentlyContinue) { $true } else { $null }) 'syntax-highlighted previews'
    row 'zoxide' $(if ($script:HasZoxide) { $true } else { $null }) $(if ($script:HasZoxide) { "Alt+C -> $env:FZF_ALT_C_COMMAND" } else { 'not on PATH' })
    row 'preview helper' ([bool](Get-Command fzf-preview.cmd -EA SilentlyContinue)) "$script:FzfCfgDir on PATH"

    # Chord conflicts -- the atuin question.
    $bound = Get-PSReadLineKeyHandler -Bound
    $ctrlR = $bound | Where-Object { $_.Key -eq 'Ctrl+r' }
    $atuinOk = $ctrlR -and $ctrlR.Function -notmatch 'Fzf' -and $ctrlR.Description -notmatch 'Fzf'
    $ctrlRDesc = if ($ctrlR) { "bound to: $($ctrlR.Function) $($ctrlR.BriefDescription)".Trim() }
                 else { 'unbound -- is atuin initialised BEFORE this file in your $PROFILE?' }
    row 'Ctrl+R (atuin)' $(if ($atuinOk) { $true } else { $null }) $ctrlRDesc

    foreach ($c in $FzfCfg.Chords.GetEnumerator()) {
        $b = $bound | Where-Object { $_.Key -ieq $c.Value }
        row "$($c.Key)" ([bool]$b) "$($c.Value) -> $(if ($b) { $b.BriefDescription } else { 'NOT BOUND' })"
    }
    Write-Host ''
    Write-Host '  Run  fzf?  for the cheat sheet.' -ForegroundColor DarkGray
    Write-Host ''
}
