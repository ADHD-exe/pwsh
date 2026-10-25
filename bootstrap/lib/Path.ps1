# =============================================================================
# Path.ps1 - persistent PATH changes
#
# Why this talks to the registry directly instead of using
# [Environment]::Get/SetEnvironmentVariable:
#   * GetEnvironmentVariable *expands* %SystemRoot% etc., and SetEnvironmentVariable
#     writes the result back as a plain REG_SZ - which permanently flattens every
#     existing "%SystemRoot%\system32" style entry (and on some builds stops
#     Windows expanding them at all). Reading the raw value and writing it back
#     as REG_EXPAND_SZ keeps every existing entry byte-for-byte.
# =============================================================================

function Get-PathRegistryTarget {
    param([ValidateSet('User', 'Machine')][string]$Scope)

    if ($Scope -eq 'Machine') {
        return @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; SubKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment' }
    }
    return @{ Hive = [Microsoft.Win32.Registry]::CurrentUser; SubKey = 'Environment' }
}

function Get-RawPath {
    <# The stored PATH string with %VARS% left unexpanded. #>
    param([ValidateSet('User', 'Machine')][string]$Scope)

    $t = Get-PathRegistryTarget -Scope $Scope
    $key = $t.Hive.OpenSubKey($t.SubKey, $false)
    if (-not $key) { return '' }

    try {
        $v = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $v) { return '' }
        return [string]$v
    }
    finally { $key.Close() }
}

function Set-RawPath {
    param([ValidateSet('User', 'Machine')][string]$Scope, [Parameter(Mandatory)][string]$Value)

    $t = Get-PathRegistryTarget -Scope $Scope
    $key = $t.Hive.OpenSubKey($t.SubKey, $true)
    if (-not $key) { throw "Cannot open the $Scope environment registry key for writing (is this an elevated session?)" }

    try { $key.SetValue('Path', $Value, [Microsoft.Win32.RegistryValueKind]::ExpandString) }
    finally { $key.Close() }
}

function Get-PathEntries {
    param([ValidateSet('User', 'Machine')][string]$Scope)

    $raw = Get-RawPath -Scope $Scope
    if (-not $raw) { return @() }
    return @($raw -split ';' | Where-Object { $_ })
}

function Backup-PathValue {
    <# Saves the raw PATH before the first change so it can be restored by hand. #>
    param([ValidateSet('User', 'Machine')][string]$Scope, [string]$Directory)

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $file = Join-Path $Directory ("path-{0}-{1}.txt" -f $Scope.ToLower(), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Set-Content -LiteralPath $file -Value (Get-RawPath -Scope $Scope) -Encoding UTF8
    return $file
}

function Test-DirectoryHasExecutable {
    param([string]$Directory)

    $hit = Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.exe', '.cmd', '.bat', '.ps1' } |
        Select-Object -First 1

    return [bool]$hit
}

function Add-PathEntry {
    <#
        Adds one directory to the persistent PATH (and this session).
        Returns Added | Present | Missing | NoExecutables | TooLong | Denied | Failed | DryRun
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [ValidateSet('User', 'Machine')][string]$Scope = 'Machine',
        [string]$BackupDirectory
    )

    $dir = (Expand-Vars $Directory).TrimEnd('\')

    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        Add-Result -Step 'path' -Item $Directory -Status 'Skipped' -Detail 'directory does not exist (app not installed)'
        Write-Dim "not installed, skipped: $dir"
        return 'Missing'
    }

    if (-not (Test-DirectoryHasExecutable -Directory $dir)) {
        Add-Result -Step 'path' -Item $Directory -Status 'Skipped' -Detail 'no executables directly inside'
        Write-Dim "no executables in $dir - not added"
        return 'NoExecutables'
    }

    $existing = @(Get-PathEntries -Scope 'Machine') + @(Get-PathEntries -Scope 'User') | ForEach-Object { (Expand-Vars $_).TrimEnd('\') }
    if ($existing | Where-Object { $_ -ieq $dir }) {
        Write-Ok "already on PATH: $dir"
        Add-Result -Step 'path' -Item $Directory -Status 'Skipped' -Detail 'already on PATH'
        return 'Present'
    }

    if ($Scope -eq 'Machine' -and -not (Test-IsAdmin)) {
        Add-Result -Step 'path' -Item $Directory -Status 'Warn' -Detail 'Machine PATH needs an elevated run'
        Write-Warn "Machine PATH needs admin - not added: $dir"
        return 'Denied'
    }

    $current = Get-RawPath -Scope $Scope
    $updated = if ($current) { "$($current.TrimEnd(';'));$dir" } else { $dir }

    if ($updated.Length -gt 32000) {
        Add-Result -Step 'path' -Item $Directory -Status 'Failed' -Detail 'PATH would exceed the Windows size limit'
        Write-Bad "PATH too long to add: $dir"
        return 'TooLong'
    }

    if (-not $PSCmdlet.ShouldProcess("$Scope PATH", "add $dir")) { return 'DryRun' }

    try {
        if ($BackupDirectory -and -not $script:PathBackedUp[$Scope]) {
            $b = Backup-PathValue -Scope $Scope -Directory $BackupDirectory
            Write-Info "Saved the previous $Scope PATH to $b"
            $script:PathBackedUp[$Scope] = $true
        }

        Set-RawPath -Scope $Scope -Value $updated
        $env:PATH = "$env:PATH;$dir"
        Write-Ok "added to $Scope PATH: $dir"
        Add-Result -Step 'path' -Item $Directory -Status 'Ok' -Detail "added to $Scope PATH"
        return 'Added'
    }
    catch {
        Add-Result -Step 'path' -Item $Directory -Status 'Failed' -Detail $_.Exception.Message
        Write-Bad "could not update $Scope PATH: $($_.Exception.Message)"
        return 'Failed'
    }
}

$script:PathBackedUp = @{ User = $false; Machine = $false }

function Send-EnvironmentChange {
    <# Tells running apps (Explorer, new terminals) to re-read the environment. #>
    try {
        if (-not ('Rabbit.NativeMethods' -as [type])) {
            Add-Type -Namespace Rabbit -Name NativeMethods -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@
        }

        $result = [UIntPtr]::Zero
        [void][Rabbit.NativeMethods]::SendMessageTimeout([IntPtr]0xFFFF, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
    }
    catch {
        Write-Dim 'could not broadcast the environment change - sign out and back in to be sure'
    }
}
