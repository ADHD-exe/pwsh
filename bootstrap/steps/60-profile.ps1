# =============================================================================
# 60-profile.ps1 - install the PowerShell 7 profile stub
#
# The real profile lives in the repo (<InstallDir>\profile). What goes into
# Documents\PowerShell\Microsoft.PowerShell_profile.ps1 is a tiny managed stub
# that dot-sources it, so:
#   * updating the environment is `git pull` - nothing to re-copy;
#   * the stub never needs to know OneDrive/Documents redirection details;
#   * your own additions go in Microsoft.PowerShell_profile.local.ps1 (next to
#     the stub), which the repo profile loads last and the installer never touches.
# =============================================================================

$script:StubBegin = '# >>> pwsh bootstrap (managed - do not edit between these markers) >>>'
$script:StubEnd   = '# <<< pwsh bootstrap (managed) <<<'

function Get-Pwsh7ProfileDirectory {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { $docs = Join-Path $HOME 'Documents' }
    return (Join-Path $docs 'PowerShell')
}

function New-ProfileStub {
    param([Parameter(Mandatory)][string]$InstallDir)

    $quoted = $InstallDir.Replace("'", "''")

    return @"
$script:StubBegin
# Edit machine-specific additions in Microsoft.PowerShell_profile.local.ps1 (same folder).
`$rabbitRoot = '$quoted'
`$rabbitProfile = Join-Path `$rabbitRoot 'profile\Microsoft.PowerShell_profile.ps1'
if (Test-Path -LiteralPath `$rabbitProfile) { . `$rabbitProfile }
else { Write-Warning "pwsh bootstrap profile not found at `$rabbitProfile - re-run the installer." }
$script:StubEnd
"@
}

function Invoke-ProfileStep {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$InstallDir)

    $dir     = Get-Pwsh7ProfileDirectory
    $target  = Join-Path $dir 'Microsoft.PowerShell_profile.ps1'
    $local   = Join-Path $dir 'Microsoft.PowerShell_profile.local.ps1'
    $stub    = (New-ProfileStub -InstallDir $InstallDir).Replace("`r`n", "`n")
    $repoProfile = Join-Path $InstallDir 'profile\Microsoft.PowerShell_profile.ps1'

    if (-not (Test-Path -LiteralPath $repoProfile)) {
        throw "Repo profile missing: $repoProfile"
    }

    $existing = $null
    if (Test-Path -LiteralPath $target) { $existing = (Get-Content -LiteralPath $target -Raw).Replace("`r`n", "`n") }

    # --- already our stub -> refresh the block in place --------------------
    if ($existing -and $existing.Contains($script:StubBegin)) {
        $pattern = '(?s)' + [regex]::Escape($script:StubBegin) + '.*?' + [regex]::Escape($script:StubEnd)
        $new = [regex]::Replace($existing, $pattern, { param($m) $stub.TrimEnd() })

        if ($new.TrimEnd() -eq $existing.TrimEnd()) {
            Write-Ok 'Profile stub already current'
            Add-Result -Step 'profile' -Item 'stub' -Status 'Skipped' -Detail 'already current'
            return
        }

        if ($PSCmdlet.ShouldProcess($target, 'refresh managed block')) {
            [void](Backup-File -Path $target)
            Write-Utf8NoBom -Path $target -Content $new
            Write-Ok 'Profile stub refreshed'
            Add-Result -Step 'profile' -Item 'stub' -Status 'Ok' -Detail 'managed block refreshed'
        }
        return
    }

    if (-not $PSCmdlet.ShouldProcess($target, 'install profile stub')) { return }

    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    # --- somebody else's profile: keep every line of it --------------------
    if ($existing) {
        $backup = Backup-File -Path $target
        Write-Info "Backed up your existing profile -> $backup"

        $isOldRabbit = $existing -match 'Rabbit PowerShell Profile|RABBIT_PROFILE_LOADED'

        if ($isOldRabbit) {
            Write-Info 'It is the previous version of this profile - replaced (the backup is kept).'
        }
        elseif (-not (Test-Path -LiteralPath $local)) {
            # Migration: your old content keeps running, loaded AFTER the repo profile.
            Write-Utf8NoBom -Path $local -Content $existing
            Write-Info "Your old profile content was moved to $(Split-Path $local -Leaf) and still loads."
            Add-Result -Step 'profile' -Item 'migration' -Status 'Warn' -Detail 'old profile content preserved in Microsoft.PowerShell_profile.local.ps1 - review for duplicates'
        }
        else {
            Write-Warn "$(Split-Path $local -Leaf) already exists, so your old profile was only backed up, not merged."
            Add-Result -Step 'profile' -Item 'migration' -Status 'Warn' -Detail "old profile only backed up: $backup"
        }
    }

    Write-Utf8NoBom -Path $target -Content ($stub.TrimEnd() + "`n")

    if (-not (Test-Path -LiteralPath $local)) {
        Write-Utf8NoBom -Path $local -Content "# Machine-local additions. Loaded last by the repo profile; never overwritten by the installer.`n"
    }

    Write-Ok "Profile stub installed -> $target"
    Add-Result -Step 'profile' -Item 'stub' -Status 'Ok' -Detail $target
}
