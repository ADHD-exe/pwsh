# PSReadLine can fail to load when the host has no real console (redirected
# input/output, CI, the installer's verification child). Never let that break the profile.
if (Get-Module PSReadLine -ErrorAction SilentlyContinue) {
    try {
        Set-PSReadLineKeyHandler -Chord "Ctrl+Shift+z" -Function Undo
        Set-PSReadLineKeyHandler -Chord "Ctrl+Shift+x" -Function KillRegion
    }
    catch { Write-Verbose "keybinds skipped: $($_.Exception.Message)" }
}

# ---------------------------------------------------------
# Rabbit shortcuts: Ctrl+f, Alt+Space, Ctrl+y, Ctrl+Space, Ctrl+h
# (moved here from the main profile; run Test-RabbitKeys to self-check)
# ---------------------------------------------------------
if (Get-Module PSReadLine -ErrorAction SilentlyContinue) {
    # --- shortcut helpers -------------------------------------------------------
    # Each shortcut is registered on its own (Register-RabbitKey) so one failing binding
    # no longer skips the ones after it.
    function Register-RabbitKey {
        param([string]$Chord, [string]$Description, [scriptblock]$ScriptBlock)
        try { Set-PSReadLineKeyHandler -Chord $Chord -BriefDescription $Description -Description $Description -ScriptBlock $ScriptBlock }
        catch { Write-Warning "Key $Chord was skipped: $($_.Exception.Message)" }
    }

    # True when every tool is on PATH; otherwise says what is missing and redraws the prompt.
    function Test-RabbitTools {
        param([string]$Chord, [string[]]$Need)
        $missing = @($Need | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
        if ($missing.Count -eq 0) { return $true }
        Write-Host "`n$Chord needs $($missing -join ' and ') - re-run the installer to add $(if ($missing.Count -gt 1) { 'them' } else { 'it' })." -ForegroundColor Yellow
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        return $false
    }

    # Quote a path for the command line only when it needs it (spaces, ; & ( ) $ ' etc.).
    function ConvertTo-RabbitArgument {
        param([string]$Path)
        if ($Path -match '[\s''"`&;(){}$#,@\[\]|<>]') { return "'" + $Path.Replace("'", "''") + "'" }
        $Path
    }

    # Ctrl+f - fuzzy file search, always in the current directory (fd; honours .gitignore).
    # Tab multi-selects; every pick is quoted if needed and inserted at the cursor.
    Register-RabbitKey Ctrl+f 'Rabbit file search' {
        if (-not (Test-RabbitTools 'Ctrl+f' fzf, fd)) { return }

        $previewCmd = if (Get-Command bat -ErrorAction SilentlyContinue) { 'bat --style=numbers --color=always {}' } else { 'type {}' }
        $oldEnc = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)   # fd/fzf speak UTF-8; keeps accented names intact
            # fd streams straight into fzf, so the list opens at once even in a huge tree.
            $picked = @(fd --type file --hidden --exclude .git | fzf --multi --height 50% --layout reverse --border --border-label ' 🔎 files (Tab = several) ' --header 'Ctrl+G: include git-ignored files · Ctrl+T: back' --bind 'ctrl-g:reload(fd --type file --hidden --no-ignore --exclude .git)' --bind 'ctrl-t:reload(fd --type file --hidden --exclude .git)' --preview $previewCmd (Get-RabbitFzfTheme -Accent Mint))
        }
        finally { [Console]::OutputEncoding = $oldEnc }

        $picked = @($picked | Where-Object { $_ })
        if ($picked.Count -eq 0) { return }   # Esc: leave the line alone

        $text = ($picked | ForEach-Object { ConvertTo-RabbitArgument $_ }) -join ' '

        # `nvim`+Ctrl+F -> `nvim path`, not `nvimpath`
        $line = $null; $cursor = 0
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        if ($cursor -gt 0 -and $line[$cursor - 1] -notmatch '\s') { $text = ' ' + $text }

        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($text)
    }

    # Alt+Space - jump to a directory zoxide knows. What you had typed stays on the line.
    Register-RabbitKey Alt+Spacebar 'Rabbit smart jump' {
        if (-not (Test-RabbitTools 'Alt+Space' zoxide, fzf)) { return }

        $previewCmd = if (Get-Command eza -ErrorAction SilentlyContinue) { 'eza --icons --group-directories-first {}' } else { 'dir {}' }
        $oldEnc = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
            $selected = zoxide query -l | fzf --height 40% --layout reverse --border --border-label ' 🧭 jump ' --preview $previewCmd (Get-RabbitFzfTheme -Accent Purple)
        }
        finally { [Console]::OutputEncoding = $oldEnc }

        if ($selected -and (Test-Path -LiteralPath $selected)) {
            Set-Location -LiteralPath $selected    # zoxide's prompt hook records the visit
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }
    }

    # Ctrl+y - Explore: opens the Yazi file manager and cd's to wherever you leave it. The typed line is kept.
    Register-RabbitKey Ctrl+y 'Rabbit Explore (Yazi)' {
        if (-not (Test-RabbitTools 'Ctrl+y' yazi)) { return }
        yy
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
    }

    # Ctrl+Space - command palette. The typed line is kept.
    Register-RabbitKey Ctrl+Spacebar 'Rabbit command palette' {
        if (-not (Test-RabbitTools 'Ctrl+Space' fzf)) { return }
        if (-not (Get-Command Invoke-CommandPalette -ErrorAction SilentlyContinue)) {
            Write-Host "`nInvoke-CommandPalette is not loaded - re-run the installer or reload the profile." -ForegroundColor Yellow
        }
        else {
            Write-Host ''
            Invoke-CommandPalette
        }
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
    }

    # Ctrl+h - what the shortcuts above do. (Ctrl+h used to be a second Backspace; Backspace itself is unchanged.)
    Register-RabbitKey Ctrl+h 'Rabbit help' {
        if (-not (Get-Command Show-RabbitHelp -ErrorAction SilentlyContinue)) {
            Write-Host "`nShow-RabbitHelp is not loaded - re-run the installer or reload the profile." -ForegroundColor Yellow
        }
        else { Show-RabbitHelp }
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
    }

    # Self-check: is every Rabbit shortcut bound, and is everything it calls available?
    function Test-RabbitKeys {
        $checks = @(
            @{ Chord = 'Ctrl+f';     Tools = 'fzf', 'fd';    Funcs = @() }
            @{ Chord = 'Alt+Space';  Tools = 'zoxide', 'fzf'; Funcs = @() }
            @{ Chord = 'Ctrl+y';     Tools = 'yazi';          Funcs = 'yy' }
            @{ Chord = 'Ctrl+Space'; Tools = 'fzf';           Funcs = 'Invoke-CommandPalette' }
            @{ Chord = 'Ctrl+h';     Tools = @();             Funcs = 'Show-RabbitHelp' }
        )
        $norm  = { param($k) ($k -replace 'spacebar', 'space').ToLowerInvariant() }
        $bound = @(Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Description -like 'Rabbit*' })
        foreach ($c in $checks) {
            $h = $bound | Where-Object { (& $norm $_.Key) -eq (& $norm $c.Chord) }
            $missing = @(@($c.Tools) + @($c.Funcs) | Where-Object { $_ -and -not (Get-Command $_ -ErrorAction SilentlyContinue) })
            $ok = [bool]$h -and $missing.Count -eq 0
            [pscustomobject]@{
                Key     = $c.Chord
                Bound   = [bool]$h
                Missing = if ($missing) { $missing -join ', ' } else { '-' }
                Status  = if ($ok) { 'OK' } else { 'CHECK' }
            }
        }
    }
}
