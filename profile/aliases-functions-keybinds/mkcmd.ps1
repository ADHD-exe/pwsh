# =========================================================
# 📚 Function/Alias Creator & Remover
# =========================================================
function mkcmd {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value,
        [switch]$Alias,
        [switch]$Function,
        [switch]$Force
    )

    $target = $global:RabbitUserCommands
    if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType File -Path $target -Force | Out-Null }

    # --- Validation ---
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Warning "Name cannot be empty."; return
    }
    if ([string]::IsNullOrWhiteSpace($Value)) {
        Write-Warning "Value cannot be empty."; return
    }
    if ($Name -match '\s') {
        Write-Warning "Name cannot contain spaces."; return
    }

    # --- Determine type ---
    # Explicit flags take priority; otherwise guess by presence of spaces
    $makeAlias = $false
    if ($Alias)    { $makeAlias = $true }
    elseif ($Function) { $makeAlias = $false }
    else {
        # Heuristic: no spaces = likely a single command name → alias
        #            spaces    = has args/body → wrap in function
        $makeAlias = ($Value -notmatch ' ')
    }

    # --- Duplicate detection ---
    $profileContent = Get-Content $target -Raw -ErrorAction SilentlyContinue
    $patterns = @("function $Name ", "function $Name{", "Set-Alias $Name ")
    $exists = $patterns | Where-Object { $profileContent -match [regex]::Escape($_) }

    if ($exists -and -not $Force) {
        Write-Warning "'$Name' already exists in your commands file. Use -Force to overwrite."
        return
    }

    # --- Build the block ---
    if ($makeAlias) {
        $block = "Set-Alias $Name $Value"
        $type  = "alias"
    } else {
        $block = @"
function $Name {
    $Value
}
"@
        $type = "function"
    }

    # --- Write to functions file (overwrite if -Force) ---
    if ($exists -and $Force) {
        rmcmd -Name $Name -NoReload
    }

    Add-Content -Path $target -Value "`n$block"

    # --- Define in the current session at global scope ---
    if ($makeAlias) {
        Set-Alias -Name $Name -Value $Value -Scope Global
    }
    else {
        New-Item -Path "Function:global:$Name" -Value $Value -Force | Out-Null
    }

    Write-Host "✅ Added $type '$Name'" -ForegroundColor Green
    Write-Host "   Written to user-commands.ps1 as:" -ForegroundColor DarkGray
    Write-Host "   $($block -replace "`n", " | ")" -ForegroundColor DarkGray
}

# =========================================================

function rmcmd {
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$NoReload   # internal flag used by mkcmd -Force
    )

    $target = $global:RabbitUserCommands
    if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType File -Path $target -Force | Out-Null }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Warning "Name cannot be empty."; return
    }

    $lines   = Get-Content $target
    $output  = [System.Collections.Generic.List[string]]::new()
    $removed = $false
    $skip    = $false
    $braceDepth = 0

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Detect start of the target function block
        if (-not $skip -and $line -match "^\s*function\s+$([regex]::Escape($Name))\s*(\{|$)") {
            $skip = $true
            $removed = $true
            # Count any opening braces on this line
            $braceDepth = ([regex]::Matches($line, '\{')).Count - ([regex]::Matches($line, '\}')).Count
            # A one-line `function x { ... }` is already closed; without this the NEXT line would be eaten too.
            if ($braceDepth -le 0 -and $line -match '\{') { $skip = $false }
            continue
        }

        # Detect target alias line
        if (-not $skip -and $line -match "^\s*Set-Alias\s+$([regex]::Escape($Name))\s+") {
            $removed = $true
            continue
        }

        # If inside a function block, track brace depth to find the end
        if ($skip) {
            $braceDepth += ([regex]::Matches($line, '\{')).Count
            $braceDepth -= ([regex]::Matches($line, '\}')).Count
            if ($braceDepth -le 0) { $skip = $false }
            continue
        }

        $output.Add($line)
    }

    if (-not $removed) {
        Write-Warning "'$Name' not found in your commands file."
        return
    }

    # Trim trailing blank lines
    while ($output.Count -gt 0 -and [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
        $output.RemoveAt($output.Count - 1)
    }

    $output | Set-Content $target

    if (-not $NoReload) {
        Remove-Item "Function:\$Name" -ErrorAction SilentlyContinue
        Remove-Item "Alias:\$Name" -ErrorAction SilentlyContinue
        Write-Host "🗑️  Removed '$Name' from the functions file." -ForegroundColor Yellow
    }
}

# =========================================================
# Usage Examples (shown via Show-Help or read comments)
#
#   mkcmd greet "Write-Host 'Hello!'"     # → function (has spaces)
#   mkcmd np notepad                       # → alias    (no spaces)
#   mkcmd np notepad -Alias                # → explicit alias
#   mkcmd greet "Write-Host 'Hi'" -Force  # → overwrite existing
#   rmcmd greet                            # → remove function/alias by name
# =========================================================
