# =========================================================
# 📚 mkcmd — interactive command / alias / function manager
# =========================================================
#   mkcmd                      → interactive hub (arrow-key menu)
#   mkcmd gs "git status"      → one-liner (smart: alias or function)
#   mkcmd np notepad -Alias    → explicit alias
#   mkcmd greet "Write-Host 'Hi'" -Function -Force
#   lscmd [filter] [-Full]     → list / inspect your commands
#   edcmd [name]               → redefine, rename, open in editor, copy
#   rmcmd name [name2 ...]     → remove (tab-completes your command names)
#
# Everything is stored in $global:RabbitUserCommands (falls back to
# user-commands.ps1 next to your profile). The file is parsed with the
# PowerShell AST, so hand-written functions/aliases in it are listed,
# edited and removed correctly too. A .bak copy is kept before each write.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+.
# =========================================================

#region ── helpers: storage ────────────────────────────────

function _mkPath {
    if ([string]::IsNullOrWhiteSpace($global:RabbitUserCommands)) {
        $dir = Split-Path -Parent $PROFILE.CurrentUserAllHosts
        $global:RabbitUserCommands = Join-Path $dir 'user-commands.ps1'
    }
    $p = $global:RabbitUserCommands
    if (-not (Test-Path -LiteralPath $p)) {
        $d = Split-Path -Parent $p
        if ($d -and -not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        New-Item -ItemType File -Path $p -Force | Out-Null
    }
    $p
}

function _mkWidth {
    try { [Math]::Max(40, [Console]::WindowWidth) } catch { 100 }
}

function _mkAstText($Ast) {
    if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return $Ast.Value }
    if ($Ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { return $Ast.Value }
    $Ast.Extent.Text
}

# Parse the commands file into entries (functions + Set-Alias lines).
function _mkEntries {
    param([string]$Path = (_mkPath))

    $text = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }

    $tokens = $null; $errs = $null
    $ast   = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errs)
    $lines = $text -split "\r?\n"
    $out   = New-Object System.Collections.Generic.List[object]

    if ($errs -and $errs.Count) {
        Write-Warning "$(Split-Path $Path -Leaf) has syntax errors; some entries may not be listed."
    }

    foreach ($st in $ast.EndBlock.Statements) {
        $name = $null; $type = $null; $value = $null; $code = $null

        if ($st -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            $name  = $st.Name
            $type  = 'function'
            $code  = $st.Extent.Text
            $b     = $st.Body.Extent.Text
            $value = $b.Substring(1, $b.Length - 2).Trim()
        }
        elseif ($st -is [System.Management.Automation.Language.PipelineAst] -and
                $st.PipelineElements.Count -eq 1 -and
                $st.PipelineElements[0] -is [System.Management.Automation.Language.CommandAst]) {
            $cmd = $st.PipelineElements[0]
            $cn  = $cmd.GetCommandName()
            if ($cn -in 'Set-Alias', 'New-Alias', 'sal', 'nal') {
                $pos = @(); $named = @{}
                $els = $cmd.CommandElements
                for ($k = 1; $k -lt $els.Count; $k++) {
                    $el = $els[$k]
                    if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
                        $pn = $el.ParameterName
                        if ($pn -in 'Force', 'PassThru', 'Confirm', 'WhatIf') { continue }
                        if ($el.Argument) { $named[$pn] = _mkAstText $el.Argument }
                        elseif ($k + 1 -lt $els.Count) { $named[$pn] = _mkAstText $els[$k + 1]; $k++ }
                    }
                    else { $pos += (_mkAstText $el) }
                }
                $name = $named['Name']; $value = $named['Value']
                $pi = 0
                if (-not $name  -and $pos.Count -gt $pi) { $name  = $pos[$pi]; $pi++ }
                if (-not $value -and $pos.Count -gt $pi) { $value = $pos[$pi] }
                $type = 'alias'
            }
        }

        if (-not $name) { continue }

        $sl = $st.Extent.StartLineNumber
        $el = $st.Extent.EndLineNumber
        $desc = ''; $bs = $sl
        if ($sl -ge 2 -and $lines[$sl - 2] -match '^\s*#\s*mkcmd:\s*(.*?)\s*$') { $desc = $Matches[1]; $bs = $sl - 1 }

        $out.Add([pscustomobject]@{
            Name         = $name
            Type         = $type
            Value        = $value
            Code         = $code
            Description  = $desc
            StartLine    = $bs
            EndLine      = $el
            RemovesAlias = [bool]($lines[$sl - 1] -match '^\s*Remove-Item\s+Alias:')
            Text         = ($lines[($bs - 1)..($el - 1)] -join "`n")
        })
    }
    @($out)
}

function _mkDropEntries {
    param([string]$Text, [object[]]$Remove, [string]$NewLine)
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($l in ($Text -split "\r?\n")) { $lines.Add($l) }
    foreach ($e in ($Remove | Sort-Object StartLine -Descending)) {
        $i = $e.StartLine - 1
        $lines.RemoveRange($i, $e.EndLine - $e.StartLine + 1)
        while ($i -lt $lines.Count -and [string]::IsNullOrWhiteSpace($lines[$i]) -and
               ($i -eq 0 -or [string]::IsNullOrWhiteSpace($lines[$i - 1]))) { $lines.RemoveAt($i) }
    }
    ($lines -join $NewLine)
}

function _mkBackup {
    param([string]$Path)
    if ((Test-Path -LiteralPath $Path) -and (Get-Item -LiteralPath $Path).Length -gt 0) {
        Copy-Item -LiteralPath $Path -Destination "$Path.bak" -Force
    }
}

# One read → (remove entries) → (append block) → one write.
function _mkCommit {
    param([string]$Path, [object[]]$Remove, [string]$Append, [switch]$NoBackup)
    $text = [System.IO.File]::ReadAllText($Path)
    $nl   = if ($text -match "`r`n") { "`r`n" } elseif ($text -match "`n") { "`n" } else { "`r`n" }
    if ($Remove) { $text = _mkDropEntries -Text $text -Remove $Remove -NewLine $nl }
    $text = $text.TrimEnd()
    if ($Append) {
        $blk  = $Append -replace "\r?\n", $nl
        $text = if ($text) { "$text$nl$nl$blk" } else { $blk }
    }
    $text += $nl
    if (-not $NoBackup) { _mkBackup $Path }
    [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($true))
}

#endregion

#region ── helpers: building & validating ──────────────────

function _mkQuote {
    param([string]$Value, [switch]$Always)
    if (-not $Always -and $Value -match '^[\w\-\.]+$') { return $Value }
    "'" + ($Value -replace "'", "''") + "'"
}

function _mkNameError {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return 'Name cannot be empty.' }
    if ($Name -match '\s')                    { return 'Name cannot contain spaces.' }
    if ($Name -notmatch '^[A-Za-z_][A-Za-z0-9_\-]*$' -and $Name -notmatch '^\.{2,}$') {
        return 'Use letters, numbers, - and _ only (start with a letter or _).'
    }
    $reserved = 'begin','break','catch','class','clean','continue','data','define','do','dynamicparam','else','elseif',
                'end','enum','exit','filter','finally','for','foreach','from','function','hidden','if','in','param',
                'process','return','switch','throw','trap','try','until','using','var','while'
    if ($Name -in $reserved) { return "'$Name' is a PowerShell keyword." }
    $null
}

function _mkBlock {
    param(
        [string]$Name,
        [ValidateSet('alias', 'function')][string]$Type,
        [string]$Body,
        [string[]]$Params,
        [string]$Description,
        [switch]$OverrideAlias
    )
    $L = New-Object System.Collections.Generic.List[string]
    if ($Description) { $L.Add('# mkcmd: ' + ($Description -replace '\s*[\r\n]+\s*', ' ').Trim()) }

    if ($Type -eq 'alias') {
        $force = if ($OverrideAlias) { ' -Force' } else { '' }
        $L.Add("Set-Alias $Name $(_mkQuote $Body)$force")
    }
    else {
        # An existing alias outranks a function of the same name, so drop it first.
        $pre = if ($OverrideAlias) { "Remove-Item Alias:\$Name -Force -ErrorAction SilentlyContinue; " } else { '' }
        $L.Add("${pre}function $Name {")
        if ($Params -and $Params.Count) { $L.Add('    param(' + (($Params | ForEach-Object { '$' + $_ }) -join ', ') + ')') }
        # Never indent bodies containing here-strings (the terminator must start the line).
        $indent = if ($Body -match '(?m)@[''"]\s*$') { '' } else { '    ' }
        foreach ($l in ($Body -split "\r?\n")) {
            if ($indent) { $L.Add(("$indent$l").TrimEnd()) } else { $L.Add($l) }
        }
        $L.Add('}')
    }
    $L -join "`n"
}

function _mkSyntax {
    param([string]$Text)
    $t = $null; $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$t, [ref]$e)
    @($e | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" })
}

function _mkPreview {
    param($Entry, [int]$Max = 60)
    $s = if ($Entry.Type -eq 'alias') { "→ $($Entry.Value)" }
         else { ($Entry.Value -replace '\s*[\r\n]+\s*', '  ') }
    if ($s.Length -gt $Max) { $s = $s.Substring(0, [Math]::Max(1, $Max - 1)) + '…' }
    $s
}

function _mkShowText {
    param([string]$Text, [string]$Indent = '    ')
    foreach ($l in ($Text -split "\r?\n")) {
        if ($l -match '^\s*#\s*mkcmd:\s*(.*)$') { Write-Host "$Indent# $($Matches[1])" -ForegroundColor DarkGreen; continue }
        Write-Host "$Indent$l" -ForegroundColor Gray
    }
}

# Detect clashes with your own commands and with anything else on this machine.
function _mkResolve {
    param(
        [string]$Name, [string]$Type, [object[]]$Entries,
        [switch]$Force, [switch]$Interactive, [switch]$AssumeOverwrite
    )
    $r = [pscustomobject]@{ Proceed = $true; Existing = $null; OverrideAlias = $false }

    $mine = @($Entries | Where-Object { $_.Name -eq $Name })
    if ($mine.Count) {
        $r.Existing = $mine
        if ($AssumeOverwrite -or $Force) { return $r }
        if ($Interactive) {
            Write-Host "  '$Name' already exists in your commands file:" -ForegroundColor Yellow
            _mkShowText $mine[0].Text
            if (-not (_mkYesNo 'Overwrite it?' $false)) { $r.Proceed = $false }
            return $r
        }
        Write-Warning "'$Name' already exists in your commands file. Use -Force to overwrite."
        $r.Proceed = $false
        return $r
    }

    $c = Get-Command -Name $Name -ErrorAction Ignore | Select-Object -First 1
    if ($c) {
        $what = switch ($c.CommandType) {
            'Application' { "a program ($($c.Source))" }
            'Alias'       { "an alias for $($c.Definition)" }
            'Cmdlet'      { "a cmdlet ($($c.Source))" }
            'Function'    { 'a function' }
            default       { "a $($c.CommandType)" }
        }
        Write-Host "  ! '$Name' is already $what. Yours will take priority in this shell." -ForegroundColor Yellow
        if ($c.CommandType -eq 'Alias') { $r.OverrideAlias = $true }
        if (-not $Force) {
            if ($Interactive) { if (-not (_mkYesNo 'Create it anyway?' $false)) { $r.Proceed = $false } }
            else { Write-Warning 'Use -Force to create it anyway.'; $r.Proceed = $false }
        }
    }
    $r
}

#endregion

#region ── helpers: session state ──────────────────────────

function _mkLoadEntry {
    param($Entry)
    try {
        if ($Entry.Type -eq 'alias') {
            Set-Alias -Name $Entry.Name -Value $Entry.Value -Scope Global -Force -ErrorAction Stop
        }
        else {
            if ($Entry.RemovesAlias) { Remove-Item "Alias:\$($Entry.Name)" -Force -ErrorAction SilentlyContinue }
            $code = ([regex]'(?i)^(function|filter)\s+').Replace($Entry.Code, '$1 global:', 1)
            & ([scriptblock]::Create($code))
        }
        $true
    }
    catch { Write-Warning "Could not load '$($Entry.Name)' into this session: $($_.Exception.Message)"; $false }
}

function _mkUnloadEntry {
    param($Entry)
    if ($Entry.Type -eq 'alias') { Remove-Item "Alias:\$($Entry.Name)" -Force -ErrorAction SilentlyContinue }
    else {
        Remove-Item "Function:\global:$($Entry.Name)" -Force -ErrorAction SilentlyContinue
        Remove-Item "Function:\$($Entry.Name)" -Force -ErrorAction SilentlyContinue
    }
}

function _mkLoadAll {
    $n = 0
    foreach ($e in @(_mkEntries)) { if (_mkLoadEntry $e) { $n++ } }
    Write-Host "  ✅ Loaded $n command(s) into this session." -ForegroundColor Green
}

#endregion

#region ── helpers: prompts & menus ────────────────────────

function _mkGuard {
    param([scriptblock]$Do)
    try { & $Do }
    catch {
        if ($_.Exception.Message -eq 'MKCMD_CANCEL') { Write-Host '  Cancelled.' -ForegroundColor Yellow }
        else { throw }
    }
}

function _mkAsk {
    param([string]$Prompt, [string]$Default, [string]$Hint, [scriptblock]$Validate, [switch]$Optional)
    if ($Hint) { Write-Host "    $Hint" -ForegroundColor DarkGray }
    while ($true) {
        $d = if ($Default) { " [$Default]" } else { '' }
        Write-Host "  ? $Prompt$d › " -NoNewline -ForegroundColor Cyan
        $r = Read-Host
        if ($r -eq ':q') { throw 'MKCMD_CANCEL' }
        $r = $r.Trim()
        if (-not $r) { $r = $Default }
        if (-not $r) {
            if ($Optional) { return '' }
            Write-Host '    ✖ This one is required (":q" cancels).' -ForegroundColor Red
            continue
        }
        if ($Validate) {
            $err = & $Validate $r
            if ($err) { Write-Host "    ✖ $err" -ForegroundColor Red; continue }
        }
        return $r
    }
}

function _mkAskBlock {
    param([string]$Prompt)
    Write-Host "  ? $Prompt" -ForegroundColor Cyan
    Write-Host '    One line per row · empty line to finish · ":q" cancels' -ForegroundColor DarkGray
    $rows = @()
    while ($true) {
        Write-Host '    │ ' -NoNewline -ForegroundColor DarkGray
        $l = Read-Host
        if ($l -eq ':q') { throw 'MKCMD_CANCEL' }
        if ([string]::IsNullOrWhiteSpace($l)) {
            if ($rows.Count) { break }
            Write-Host '    ✖ Type at least one line.' -ForegroundColor Red
            continue
        }
        $rows += $l
    }
    $rows -join "`n"
}

function _mkYesNo {
    param([string]$Prompt, [bool]$Default = $true)
    $hint = if ($Default) { 'Y/n' } else { 'y/N' }
    while ($true) {
        Write-Host "  ? $Prompt ($hint) › " -NoNewline -ForegroundColor Cyan
        $r = (Read-Host).Trim().ToLower()
        if ($r -eq ':q') { throw 'MKCMD_CANCEL' }
        if (-not $r) { return $Default }
        if ($r -in 'y', 'yes') { return $true }
        if ($r -in 'n', 'no')  { return $false }
    }
}

# Arrow-key menu (scrolls for long lists). Returns the index, or -1 on Esc/blank.
# Falls back to a numbered list in hosts without a real console (ISE, redirected, etc).
function _mkMenu {
    param([string]$Title, [string[]]$Items, [int]$Default = 0)
    $n = $Items.Count
    if ($n -eq 0) { return -1 }
    if ($Title) { Write-Host "  $Title" -ForegroundColor Cyan }

    $fancy = $false
    try { $fancy = ($Host.Name -eq 'ConsoleHost') -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected } catch { }

    if (-not $fancy) {
        for ($i = 0; $i -lt $n; $i++) { Write-Host ('   {0,2}) {1}' -f ($i + 1), $Items[$i]) }
        while ($true) {
            Write-Host "  Choose 1-$n (blank = cancel) › " -NoNewline -ForegroundColor Cyan
            $ans = Read-Host
            if ([string]::IsNullOrWhiteSpace($ans)) { return -1 }
            $v = 0
            if ([int]::TryParse($ans, [ref]$v) -and $v -ge 1 -and $v -le $n) { return ($v - 1) }
        }
    }

    $w      = (_mkWidth) - 6
    $page   = [Math]::Max(3, [Math]::Min($n, [Console]::WindowHeight - 6))
    $rows   = $page + 1
    $sel    = [Math]::Min([Math]::Max($Default, 0), $n - 1)
    $off    = 0
    $top    = -1
    $result = -2

    [Console]::CursorVisible = $false
    try {
        for ($i = 0; $i -lt $rows; $i++) { Write-Host '' }
        $top = [Console]::CursorTop - $rows

        while ($result -eq -2) {
            if ($sel -lt $off) { $off = $sel }
            elseif ($sel -ge $off + $page) { $off = $sel - $page + 1 }

            for ($row = 0; $row -lt $page; $row++) {
                $idx = $off + $row
                [Console]::SetCursorPosition(0, $top + $row)
                if ($idx -lt $n) {
                    $label = $Items[$idx]
                    if ($label.Length -gt $w) { $label = $label.Substring(0, $w - 1) + '…' }
                    if ($idx -eq $sel) { Write-Host ('  ❯ ' + $label.PadRight($w)) -NoNewline -ForegroundColor Black -BackgroundColor Cyan }
                    else               { Write-Host ('    ' + $label.PadRight($w)) -NoNewline }
                }
                else { Write-Host (' ' * ($w + 4)) -NoNewline }
            }
            $foot = '  ↑↓ move · Enter select · Esc cancel'
            if ($n -gt $page) { $foot += "   ($($sel + 1)/$n)" }
            [Console]::SetCursorPosition(0, $top + $page)
            Write-Host $foot.PadRight($w + 4) -NoNewline -ForegroundColor DarkGray

            $k = [Console]::ReadKey($true)
            switch ($k.Key) {
                'UpArrow'   { $sel = if ($sel -le 0) { $n - 1 } else { $sel - 1 } }
                'DownArrow' { $sel = if ($sel -ge $n - 1) { 0 } else { $sel + 1 } }
                'PageUp'    { $sel = [Math]::Max(0, $sel - $page) }
                'PageDown'  { $sel = [Math]::Min($n - 1, $sel + $page) }
                'Home'      { $sel = 0 }
                'End'       { $sel = $n - 1 }
                'Enter'     { $result = $sel }
                'Escape'    { $result = -1 }
                default {
                    if ($n -le 9 -and $k.KeyChar -ge '1' -and $k.KeyChar -le '9') {
                        $d = [int][string]$k.KeyChar - 1
                        if ($d -lt $n) { $result = $d }
                    }
                }
            }
        }
    }
    finally {
        [Console]::CursorVisible = $true
        if ($top -ge 0) {
            for ($i = 0; $i -lt $rows; $i++) {
                [Console]::SetCursorPosition(0, $top + $i)
                Write-Host (' ' * ($w + 4)) -NoNewline
            }
            [Console]::SetCursorPosition(0, $top)
        }
    }

    if ($result -ge 0) {
        $echo = $Items[$result]
        if ($echo.Length -gt $w) { $echo = $echo.Substring(0, $w - 1) + '…' }
        Write-Host "  ❯ $echo" -ForegroundColor DarkCyan
    }
    $result
}

function _mkPick {
    param([object[]]$Entries, [string]$Title)
    if (-not $Entries.Count) { Write-Host '  No commands yet — create one first.' -ForegroundColor DarkGray; return $null }
    $sorted = @($Entries | Sort-Object Name)
    $items  = @($sorted | ForEach-Object { '{0,-16} {1,-9} {2}' -f $_.Name, $_.Type, (_mkPreview $_ 40) })
    $i = _mkMenu -Title $Title -Items $items
    if ($i -lt 0) { return $null }
    $sorted[$i]
}

function _mkOpenEditor {
    param([string]$Path, [int]$Line = 1)
    $code = Get-Command code -ErrorAction Ignore | Select-Object -First 1
    if ($code) { & $code.Source -g "${Path}:$Line" }
    else       { Start-Process notepad.exe -ArgumentList "`"$Path`"" }
    Write-Host '  Opened. After saving, run mkcmd → "Reload from file" (or open a new terminal).' -ForegroundColor DarkGray
}

#endregion

#region ── wizard ──────────────────────────────────────────

function _mkWizard {
    param([string]$PresetName, [switch]$Overwrite)

    _mkGuard {
        $path = _mkPath
        Write-Host ''
        if ($PresetName) {
            $bad = _mkNameError $PresetName
            if ($bad) { Write-Warning $bad; return }
        }

        $kinds = @(
            ('{0,-10} {1}' -f 'Alias',    'short name for one command/program        np → notepad'),
            ('{0,-10} {1}' -f 'Shortcut', 'saved command line, extra args pass thru  gs → git status'),
            ('{0,-10} {1}' -f 'Function', 'write your own: multi-line, parameters'),
            ('{0,-10} {1}' -f 'Folder',   'type a name, jump to a folder             proj → C:\code\proj'),
            ('{0,-10} {1}' -f 'Open',     'launch a file, folder, program or URL     docs → https://…')
        )
        $t = _mkMenu -Title 'What are you making?  (":q" cancels any prompt)' -Items $kinds
        if ($t -lt 0) { throw 'MKCMD_CANCEL' }
        $type = if ($t -eq 0) { 'alias' } else { 'function' }

        $name = $PresetName
        if (-not $name) {
            $name = _mkAsk 'Command name' -Hint 'Short and easy to type, e.g. gs, proj, deploy' -Validate { param($v) _mkNameError $v }
        }

        $entries = @(_mkEntries $path)
        $res = _mkResolve -Name $name -Type $type -Entries $entries -Interactive -AssumeOverwrite:$Overwrite
        if (-not $res.Proceed) { Write-Host '  Nothing changed.' -ForegroundColor Yellow; return }

        $params = @(); $body = $null
        while ($true) {
            $params = @()
            if ($t -eq 0) {
                $body = _mkAsk 'Which command or program should it run?' `
                    -Hint 'One command, no arguments. e.g. notepad   or   C:\Tools\fzf.exe' `
                    -Validate { param($v) if ($v -match '\s' -and -not (Test-Path -LiteralPath $v)) { 'Aliases cannot include arguments — pick "Shortcut" instead.' } }
                if (-not (Get-Command $body -ErrorAction Ignore)) {
                    Write-Host "    ! '$body' isn't found right now (fine if it gets installed later)." -ForegroundColor Yellow
                }
            }
            elseif ($t -eq 1) {
                $line   = _mkAsk 'Command line to run' -Hint 'e.g. git status   |   docker compose up -d   |   code .'
                $simple = ($line -notmatch '[|;{}&$()]') -and ($line -notmatch '@args')
                $pass   = _mkYesNo 'Pass extra arguments through (adds @args)?' $simple
                $prefix = if ($line -match '^["'']') { '& ' } else { '' }
                $body   = $prefix + $line + $(if ($pass) { ' @args' } else { '' })
            }
            elseif ($t -eq 2) {
                $p = _mkAsk 'Parameter names (optional)' -Optional `
                    -Hint 'Comma separated, e.g. path, count — leave blank to just use $args' `
                    -Validate { param($v)
                        foreach ($x in ($v -split ',')) {
                            if ($x.Trim().TrimStart('$') -notmatch '^[A-Za-z_]\w*$') { return "'$($x.Trim())' is not a valid parameter name." }
                        }
                    }
                if ($p) { $params = @($p -split ',' | ForEach-Object { $_.Trim().TrimStart('$') } | Where-Object { $_ }) }
                $body = _mkAskBlock 'Function body'
            }
            elseif ($t -eq 3) {
                $folder = _mkAsk 'Folder path' -Hint 'e.g. C:\code\myproject   or   ~\Documents'
                $check  = if ($folder -match '^~') { $folder -replace '^~', $HOME } else { $folder }
                if (-not (Test-Path -LiteralPath $check -PathType Container)) {
                    Write-Host '    ! That folder does not exist (yet).' -ForegroundColor Yellow
                    if (-not (_mkYesNo 'Use it anyway?' $false)) { continue }
                }
                if ($folder -match '^~[\\/]?(.*)$') {
                    $rest = $Matches[1]
                    $body = if ($rest) { "Set-Location -LiteralPath (Join-Path `$HOME $(_mkQuote $rest -Always))" } else { 'Set-Location -LiteralPath $HOME' }
                }
                else { $body = "Set-Location -LiteralPath $(_mkQuote $folder -Always)" }
            }
            else {
                $target = _mkAsk 'What should it open?' -Hint 'A file, folder, program or URL, e.g. https://github.com   or   C:\Notes\todo.md'
                $body = "Start-Process $(_mkQuote $target -Always)"
            }

            $block = _mkBlock -Name $name -Type $type -Body $body -Params $params -OverrideAlias:$res.OverrideAlias
            $errs  = @(_mkSyntax $block)
            if ($errs.Count) {
                Write-Host '  ✖ That has a syntax problem:' -ForegroundColor Red
                $errs | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
                if (_mkYesNo 'Try again?' $true) { continue } else { throw 'MKCMD_CANCEL' }
            }
            break
        }

        $desc  = _mkAsk 'Short description (optional)' -Optional
        $block = _mkBlock -Name $name -Type $type -Body $body -Params $params -Description $desc -OverrideAlias:$res.OverrideAlias

        Write-Host ''
        Write-Host '  Preview' -ForegroundColor White
        _mkShowText $block
        Write-Host ''
        if (-not (_mkYesNo 'Save it?' $true)) { throw 'MKCMD_CANCEL' }

        _mkCommit -Path $path -Remove $res.Existing -Append $block

        $new = @(_mkEntries $path) | Where-Object { $_.Name -eq $name } | Select-Object -Last 1
        if ($new -and (_mkLoadEntry $new)) {
            $verb = if ($res.Existing) { 'Updated' } else { 'Added' }
            Write-Host "  ✅ $verb $type '$name' — ready to use right now." -ForegroundColor Green
        }

        $needsArgs = ($type -eq 'function' -and $t -eq 2 -and $params.Count -gt 0)
        if ($new -and -not $needsArgs -and (_mkYesNo 'Run it now to test?' $false)) {
            $a = _mkAsk 'Arguments (optional)' -Optional
            try { Invoke-Expression "$name $a" } catch { Write-Host "  ✖ $($_.Exception.Message)" -ForegroundColor Red }
        }
    }
}

#endregion

#region ── list / edit / remove / transfer ─────────────────

function _mkList {
    param([object[]]$Entries, [string]$Filter, [switch]$Full)
    if ($Filter) {
        $Entries = @($Entries | Where-Object {
            $_.Name -like "*$Filter*" -or $_.Description -like "*$Filter*" -or $_.Value -like "*$Filter*" })
    }
    if (-not $Entries.Count) { Write-Host '  No commands found.' -ForegroundColor DarkGray; return }

    $max = (_mkWidth) - 40
    Write-Host ''
    foreach ($e in ($Entries | Sort-Object Name)) {
        $loaded = if ($e.Type -eq 'alias') { Test-Path "Alias:\$($e.Name)" } else { Test-Path "Function:\$($e.Name)" }
        if ($loaded) { Write-Host '  ● ' -NoNewline -ForegroundColor Green } else { Write-Host '  ○ ' -NoNewline -ForegroundColor Yellow }
        Write-Host ('{0,-16}' -f $e.Name) -NoNewline -ForegroundColor Cyan
        $tc = if ($e.Type -eq 'alias') { 'Magenta' } else { 'Blue' }
        Write-Host ('{0,-9}' -f $e.Type) -NoNewline -ForegroundColor $tc
        Write-Host (_mkPreview $e $max) -NoNewline -ForegroundColor Gray
        if ($e.Description) { Write-Host "  # $($e.Description)" -NoNewline -ForegroundColor DarkGreen }
        Write-Host ''
        if ($Full) { _mkShowText $e.Text '      '; Write-Host '' }
    }
    Write-Host ''
    Write-Host "  $($Entries.Count) command(s)   ● loaded in this session   ○ not loaded (use Reload)" -ForegroundColor DarkGray
}

function _mkRemoveNames {
    param([string[]]$Names, [switch]$NoReload)
    $path = _mkPath
    $entries = @(_mkEntries $path)
    $hit = @()
    foreach ($n in $Names) {
        $m = @($entries | Where-Object { $_.Name -eq $n })
        if (-not $m.Count) { Write-Warning "'$n' not found in your commands file."; continue }
        $hit += $m
    }
    if (-not $hit.Count) { return }
    _mkCommit -Path $path -Remove $hit
    foreach ($e in $hit) {
        if (-not $NoReload) { _mkUnloadEntry $e }
        Write-Host "🗑️  Removed $($e.Type) '$($e.Name)'." -ForegroundColor Yellow
    }
    Write-Host '   (undo: mkcmd → Restore last backup)' -ForegroundColor DarkGray
}

function _mkRename {
    param($Entry)
    $path = _mkPath
    $new = _mkAsk 'New name' -Validate { param($v) _mkNameError $v }
    $entries = @(_mkEntries $path)
    if ($entries | Where-Object { $_.Name -eq $new }) { Write-Warning "'$new' already exists."; return }

    if ($Entry.Type -eq 'alias') {
        $text = _mkBlock -Name $new -Type alias -Body $Entry.Value -Description $Entry.Description
    }
    else {
        $old  = [regex]::Escape($Entry.Name)
        $text = ([regex]"(?i)(\b(?:function|filter)\s+)$old\b").Replace($Entry.Text, "`${1}$new", 1)
        $text = $text -replace "(?i)(Alias:\\)$old\b", "`${1}$new"
    }
    _mkCommit -Path $path -Remove @($Entry) -Append $text
    _mkUnloadEntry $Entry
    $e2 = @(_mkEntries $path) | Where-Object { $_.Name -eq $new } | Select-Object -Last 1
    if ($e2 -and (_mkLoadEntry $e2)) { Write-Host "  ✅ Renamed '$($Entry.Name)' → '$new'." -ForegroundColor Green }
}

function _mkEditMenu {
    param($Entry)
    Write-Host ''
    _mkShowText $Entry.Text
    Write-Host ''
    $items = @('Redefine (run the wizard again)', 'Rename', 'Edit in editor', 'Copy definition to clipboard', 'Back')
    switch (_mkMenu -Title "Edit '$($Entry.Name)'" -Items $items) {
        0 { _mkWizard -PresetName $Entry.Name -Overwrite }
        1 { _mkRename $Entry }
        2 { _mkOpenEditor (_mkPath) $Entry.StartLine }
        3 { Set-Clipboard -Value $Entry.Text; Write-Host '  📋 Copied.' -ForegroundColor Green }
    }
}

function _mkTransfer {
    $path = _mkPath
    $i = _mkMenu -Title 'Export / Import' -Items @('Export my commands to a file', 'Import commands from a file', 'Back')
    if ($i -eq 0) {
        $dest = _mkAsk 'Save to' -Default (Join-Path ([Environment]::GetFolderPath('Desktop')) 'mkcmd-export.ps1')
        Copy-Item -LiteralPath $path -Destination $dest -Force
        Write-Host "  ✅ Exported to $dest" -ForegroundColor Green
    }
    elseif ($i -eq 1) {
        $src = _mkAsk 'Import from' -Validate { param($v) if (-not (Test-Path -LiteralPath $v -PathType Leaf)) { 'File not found.' } }
        $incoming = @(_mkEntries $src)
        if (-not $incoming.Count) { Write-Host '  Nothing importable in that file.' -ForegroundColor Yellow; return }
        $mine = @(_mkEntries $path)
        $remove = @(); $append = @(); $names = @()
        foreach ($e in $incoming) {
            $dup = @($mine | Where-Object { $_.Name -eq $e.Name })
            if ($dup.Count) {
                if (-not (_mkYesNo "'$($e.Name)' already exists — overwrite?" $false)) { continue }
                $remove += $dup
            }
            $append += $e.Text; $names += $e.Name
        }
        if (-not $names.Count) { Write-Host '  Nothing imported.' -ForegroundColor Yellow; return }
        _mkCommit -Path $path -Remove $remove -Append ($append -join "`n`n")
        foreach ($e in @(_mkEntries $path) | Where-Object { $_.Name -in $names }) { [void](_mkLoadEntry $e) }
        Write-Host "  ✅ Imported $($names.Count) command(s)." -ForegroundColor Green
    }
}

function _mkRestore {
    $path = _mkPath
    $bak  = "$path.bak"
    if (-not (Test-Path -LiteralPath $bak)) { Write-Host '  No backup yet.' -ForegroundColor DarkGray; return }
    $when = (Get-Item -LiteralPath $bak).LastWriteTime
    if (-not (_mkYesNo "Swap in the backup from $when? (current file becomes the new backup)" $true)) { return }
    $cur = [System.IO.File]::ReadAllText($path)
    $old = [System.IO.File]::ReadAllText($bak)
    $enc = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllText($path, $old, $enc)
    [System.IO.File]::WriteAllText($bak, $cur, $enc)
    _mkLoadAll
    Write-Host '  Commands that existed only in the newer file stay loaded until you open a new terminal.' -ForegroundColor DarkGray
}

function _mkHub {
    $path = _mkPath
    while ($true) {
        $entries = @(_mkEntries $path)
        $fns = @($entries | Where-Object Type -eq 'function').Count
        $als = @($entries | Where-Object Type -eq 'alias').Count
        Write-Host ''
        Write-Host '  📚 mkcmd' -NoNewline -ForegroundColor Cyan
        Write-Host "   $fns function(s) · $als alias(es)" -ForegroundColor DarkGray
        Write-Host "     $path" -ForegroundColor DarkGray

        $items = @('Create a command', 'List commands', 'Edit a command', 'Remove a command',
                   'Reload from file', 'Export / Import', 'Restore last backup', 'Open file in editor', 'Quit')
        $i = _mkMenu -Items $items
        switch ($i) {
            0 { _mkWizard }
            1 { _mkList -Entries $entries -Full }
            2 { _mkGuard { $e = _mkPick $entries 'Edit which command?'; if ($e) { _mkEditMenu $e } } }
            3 { _mkGuard {
                    $e = _mkPick $entries 'Remove which command?'
                    if ($e -and (_mkYesNo "Remove $($e.Type) '$($e.Name)'?" $true)) { _mkRemoveNames @($e.Name) }
                } }
            4 { _mkLoadAll }
            5 { _mkGuard { _mkTransfer } }
            6 { _mkGuard { _mkRestore } }
            7 { _mkOpenEditor $path 1 }
            default { return }
        }
    }
}

#endregion

#region ── public commands ─────────────────────────────────

function mkcmd {
<#
.SYNOPSIS
    Create commands, aliases and functions on the fly and persist them.
.DESCRIPTION
    With no arguments, opens an interactive hub (create / list / edit / remove /
    reload / export / import / restore). With a name and value it works as a
    one-liner. Definitions are saved to $global:RabbitUserCommands and loaded into
    the current session immediately.
.PARAMETER Name
    Command name.
.PARAMETER Value
    What it runs. A single command becomes an alias; a command line becomes a
    function that forwards extra arguments (@args).
.PARAMETER Alias
    Force an alias (single command, no arguments).
.PARAMETER Function
    Force a function whose body is exactly Value.
.PARAMETER Force
    Overwrite an existing definition, or shadow an existing command.
.PARAMETER Description
    Optional note stored with the definition and shown by lscmd.
.EXAMPLE
    mkcmd
.EXAMPLE
    mkcmd gs "git status"        # gs -sb  →  git status -sb
.EXAMPLE
    mkcmd np notepad
.EXAMPLE
    mkcmd greet "Write-Host 'Hi'" -Function -Force
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Name,
        [Parameter(Position = 1)][string]$Value,
        [switch]$Alias,
        [switch]$Function,
        [switch]$Force,
        [string]$Description
    )

    if ($Alias -and $Function) { Write-Warning 'Choose either -Alias or -Function, not both.'; return }
    if (-not $Name)  { _mkHub; return }
    if (-not $Value) { _mkWizard -PresetName $Name -Overwrite:$Force; return }

    # ── one-liner mode ──
    $bad = _mkNameError $Name
    if ($bad) { Write-Warning $bad; return }
    $Value = $Value.Trim()
    if (-not $Value) { Write-Warning 'Value cannot be empty.'; return }

    $path    = _mkPath
    $entries = @(_mkEntries $path)
    $single  = $Value -notmatch '\s'
    $body    = $Value
    $note    = $null

    if ($Alias) {
        if (-not $single -and -not (Test-Path -LiteralPath $Value)) {
            Write-Warning "Aliases can't include arguments. Drop -Alias (or use -Function) to make a function."; return
        }
        $type = 'alias'
    }
    elseif ($Function) { $type = 'function' }
    elseif ($single -and $Value -notmatch '[$()|;{}"'']') { $type = 'alias' }
    else {
        $type = 'function'
        if ($Value -notmatch '[|;{}&$()]' -and $Value -notmatch '@args') {
            $prefix = if ($Value -match '^["'']') { '& ' } else { '' }
            $body   = "$prefix$Value @args"
            $note   = 'extra arguments are forwarded via @args'
        }
    }

    $res = _mkResolve -Name $Name -Type $type -Entries $entries -Force:$Force
    if (-not $res.Proceed) { return }

    $block = _mkBlock -Name $Name -Type $type -Body $body -Description $Description -OverrideAlias:$res.OverrideAlias
    $errs  = @(_mkSyntax $block)
    if ($errs.Count) { $errs | ForEach-Object { Write-Warning $_ }; return }

    _mkCommit -Path $path -Remove $res.Existing -Append $block
    $new = @(_mkEntries $path) | Where-Object { $_.Name -eq $Name } | Select-Object -Last 1
    if (-not ($new -and (_mkLoadEntry $new))) { return }

    $verb = if ($res.Existing) { 'Updated' } else { 'Added' }
    Write-Host "✅ $verb $type '$Name'" -ForegroundColor Green
    Write-Host "   Written to $(Split-Path $path -Leaf) as:" -ForegroundColor DarkGray
    _mkShowText $block '   '
    if ($note) { Write-Host "   ($note)" -ForegroundColor DarkGray }
    if ($type -eq 'alias' -and -not (Get-Command $Value -ErrorAction Ignore)) {
        Write-Host "   ! '$Value' isn't found right now — the alias won't work until it is." -ForegroundColor Yellow
    }
}

function rmcmd {
<#
.SYNOPSIS
    Remove commands created with mkcmd (or hand-written in the commands file).
.EXAMPLE
    rmcmd greet
.EXAMPLE
    rmcmd gs np      # several at once
.EXAMPLE
    rmcmd            # pick from a menu
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Name,
        [switch]$NoReload
    )
    if ($Name) { _mkRemoveNames -Names $Name -NoReload:$NoReload; return }
    _mkGuard {
        $e = _mkPick @(_mkEntries) 'Remove which command?'
        if ($e -and (_mkYesNo "Remove $($e.Type) '$($e.Name)'?" $true)) { _mkRemoveNames @($e.Name) }
    }
}

function lscmd {
<#
.SYNOPSIS
    List your mkcmd commands. An exact name (or -Full) shows full definitions.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$Filter, [switch]$Full)
    $entries = @(_mkEntries)
    $exact = $Filter -and @($entries | Where-Object { $_.Name -eq $Filter }).Count -gt 0
    _mkList -Entries $entries -Filter $(if ($exact) { $null } else { $Filter }) -Full:($Full -or $exact) | Out-Null
}

function edcmd {
<#
.SYNOPSIS
    Redefine, rename, open in your editor, or copy one of your commands.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$Name)
    _mkGuard {
        $entries = @(_mkEntries)
        $e = if ($Name) { $entries | Where-Object { $_.Name -eq $Name } | Select-Object -First 1 }
             else { _mkPick $entries 'Edit which command?' }
        if (-not $e) { if ($Name) { Write-Warning "'$Name' not found in your commands file." }; return }
        _mkEditMenu $e
    }
}

#endregion

#region ── tab completion ──────────────────────────────────

$__mkNames = {
    param($commandName, $parameterName, $wordToComplete)
    @(_mkEntries) | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', "$($_.Type): $($_.Name)")
    }
}
Register-ArgumentCompleter -CommandName rmcmd, edcmd -ParameterName Name   -ScriptBlock $__mkNames
Register-ArgumentCompleter -CommandName lscmd         -ParameterName Filter -ScriptBlock $__mkNames
Remove-Variable __mkNames -ErrorAction SilentlyContinue

#endregion
