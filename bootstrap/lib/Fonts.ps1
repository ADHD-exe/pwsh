# =============================================================================
# Fonts.ps1 - per-user font installation (no admin needed)
#
# Fonts go to %LOCALAPPDATA%\Microsoft\Windows\Fonts and are registered under
# HKCU\...\Fonts. The registry value name must be the font's real full name, so
# it is read from the file's `name` table instead of being guessed from the
# filename (the old script used System.Windows.Media, which can fail in a
# constrained host and returns only the family, not "Family Bold").
# =============================================================================

function Get-FontFullName {
    <# Reads name IDs 4 (full name) from a TrueType/OpenType file. Returns $null on any parse trouble. #>
    param([Parameter(Mandatory)][string]$Path)

    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)

        function Read-U16([byte[]]$b, [int]$o) { return ([int]$b[$o] -shl 8) -bor [int]$b[$o + 1] }
        function Read-U32([byte[]]$b, [int]$o) { return ([int64]$b[$o] -shl 24) -bor ([int64]$b[$o + 1] -shl 16) -bor ([int64]$b[$o + 2] -shl 8) -bor [int64]$b[$o + 3] }

        $numTables = Read-U16 $bytes 4
        $nameOffset = $null

        for ($i = 0; $i -lt $numTables; $i++) {
            $rec = 12 + 16 * $i
            $tag = [System.Text.Encoding]::ASCII.GetString($bytes, $rec, 4)
            if ($tag -eq 'name') { $nameOffset = [int](Read-U32 $bytes ($rec + 8)); break }
        }

        if ($null -eq $nameOffset) { return $null }

        $count         = Read-U16 $bytes ($nameOffset + 2)
        $stringsOffset = $nameOffset + (Read-U16 $bytes ($nameOffset + 4))
        $best = $null

        for ($i = 0; $i -lt $count; $i++) {
            $r        = $nameOffset + 6 + 12 * $i
            $platform = Read-U16 $bytes $r
            $nameId   = Read-U16 $bytes ($r + 6)
            if ($nameId -ne 4) { continue }

            $length = Read-U16 $bytes ($r + 8)
            $offset = Read-U16 $bytes ($r + 10)
            $start  = $stringsOffset + $offset

            if ($platform -eq 3) {
                $best = [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, $start, $length)
                break
            }
            elseif ($platform -eq 1 -and -not $best) {
                $best = [System.Text.Encoding]::ASCII.GetString($bytes, $start, $length)
            }
        }

        return $best
    }
    catch { return $null }
}

function Get-InstalledFontIndex {
    <#
        Everything Windows already knows about, from BOTH registry hives:
          Names  - registered font names ("FiraCode Nerd Font Bold (TrueType)")
          Files  - file names of registered fonts that still exist on disk
        plus the file names sitting in C:\Windows\Fonts.
        Built once per run, so 40 fonts do not mean 40 registry scans.
    #>
    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $files = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    $keys = @('HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts', 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts')
    foreach ($k in $keys) {
        if (-not (Test-Path $k)) { continue }
        $item = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
        if (-not $item) { continue }

        foreach ($prop in $item.PSObject.Properties) {
            if ($prop.Name -like 'PS*') { continue }
            [void]$names.Add([string]$prop.Name)

            $data = [string]$prop.Value
            if (-not $data) { continue }
            $full = if ([System.IO.Path]::IsPathRooted($data)) { $data } else { Join-Path $env:WINDIR "Fonts\$data" }
            if (Test-Path -LiteralPath $full) { [void]$files.Add((Split-Path $full -Leaf)) }
        }
    }

    # System font folder: a file there is installed machine-wide. (The per-user folder is NOT listed:
    # a file sitting there without a registry entry still has to be registered.)
    $sysDir = Join-Path $env:WINDIR 'Fonts'
    if (Test-Path -LiteralPath $sysDir) {
        foreach ($f in (Get-ChildItem -LiteralPath $sysDir -File -ErrorAction SilentlyContinue)) { [void]$files.Add($f.Name) }
    }

    return [pscustomobject]@{ Names = $names; Files = $files }
}

function Install-FontFile {
    <#
        Returns Installed | Current | Failed | DryRun

        A font counts as already installed ("Current") when ANY of these hold,
        checked BEFORE anything is copied or written:
          * its registered name exists in HKCU or HKLM
          * a font file with the same name is registered (either hive) or
            present in C:\Windows\Fonts
        Only a font that is genuinely missing is installed. A file that is
        already in the user font folder but locked by a running app (Windows
        Terminal, Notepad++) is never overwritten - it is just registered.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$Font,
        $Index
    )

    if (-not $Index) { $Index = Get-InstalledFontIndex }

    $fontDir  = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $fontsKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    $dest     = Join-Path $fontDir $Font.Name

    $full = Get-FontFullName -Path $Font.FullName
    if (-not $full) { $full = $Font.BaseName }

    $type      = if ($Font.Extension -ieq '.otf') { 'OpenType' } else { 'TrueType' }
    $valueName = "$full ($type)"

    # ---- already installed anywhere (this user or system-wide)? -> nothing to do ----
    if ($Index.Names.Contains($valueName))  { return 'Current' }
    if ($Index.Files.Contains($Font.Name))  { return 'Current' }

    if (-not $PSCmdlet.ShouldProcess($Font.Name, 'Install font')) { return 'DryRun' }

    $stage = 'copy'
    try {
        New-Item -ItemType Directory -Path $fontDir -Force | Out-Null

        # Copy only when the file is not already there; if it is there but cannot be
        # replaced (in use), keep it and only register it.
        if (-not (Test-Path -LiteralPath $dest)) {
            Copy-Item -LiteralPath $Font.FullName -Destination $dest -Force -ErrorAction Stop
        }

        $stage = 'registry'
        if (-not (Test-Path $fontsKey)) { New-Item -Path $fontsKey -Force | Out-Null }

        # Per-user fonts are registered with the FULL PATH as the value (that is
        # what Settings > Personalization > Fonts writes); a bare filename is the
        # machine-wide convention and does not work from the user font folder.
        New-ItemProperty -Path $fontsKey -Name $valueName -Value $dest -PropertyType String -Force -ErrorAction Stop | Out-Null

        [void]$Index.Names.Add($valueName)
        [void]$Index.Files.Add($Font.Name)
        return 'Installed'
    }
    catch {
        $script:LastFontError = "{0} failed: {1}" -f $stage, $_.Exception.Message
        Write-LogLine 'FONT' ("{0}: {1}" -f $Font.Name, $script:LastFontError)
        return 'Failed'
    }
}
