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

function Install-FontFile {
    <# Returns Installed | Current | Failed | DryRun #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][System.IO.FileInfo]$Font)

    $fontDir  = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $fontsKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    $dest     = Join-Path $fontDir $Font.Name

    $full = Get-FontFullName -Path $Font.FullName
    if (-not $full) { $full = $Font.BaseName }

    $type      = if ($Font.Extension -ieq '.otf') { 'OpenType' } else { 'TrueType' }
    $valueName = "$full ($type)"

    $fileOk = (Test-Path -LiteralPath $dest) -and ((Get-Item -LiteralPath $dest).Length -eq $Font.Length)
    $regOk  = $false

    if (Test-Path $fontsKey) {
        $prop = Get-ItemProperty -Path $fontsKey -Name $valueName -ErrorAction SilentlyContinue
        if ($prop) { $regOk = ($prop.$valueName -eq $dest) }
    }

    if ($fileOk -and $regOk) { return 'Current' }

    if (-not $PSCmdlet.ShouldProcess($Font.Name, 'Install font')) { return 'DryRun' }

    try {
        New-Item -ItemType Directory -Path $fontDir -Force | Out-Null

        if (-not $fileOk) { Copy-Item -LiteralPath $Font.FullName -Destination $dest -Force }

        if (-not (Test-Path $fontsKey)) { New-Item -Path $fontsKey -Force | Out-Null }

        # Per-user fonts are registered with the FULL PATH as the value (that is
        # what Settings > Personalization > Fonts writes); a bare filename is the
        # machine-wide convention and does not work from the user font folder.
        New-ItemProperty -Path $fontsKey -Name $valueName -Value $dest -PropertyType String -Force | Out-Null
        return 'Installed'
    }
    catch {
        Write-LogLine 'FONT' ("{0}: {1}" -f $Font.Name, $_.Exception.Message)
        return 'Failed'
    }
}
