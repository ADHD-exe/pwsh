# =============================================================================
# 55-git.ps1 - git identity and GitHub SSH
#
# Every part is checked first and skipped when it is already done:
#   - git-lfs filters           (skipped when configured)
#   - user.name                 (asked only when missing)
#   - user.email                (asked only when missing)
#   - SSH to GitHub             (tested first; if it already works, nothing else happens)
#   - otherwise: key made if absent, the PUBLIC KEY is shown, and the installer
#     WAITS until GitHub accepts it. It does not move on before that
#     (type SKIP to deliberately continue without SSH).
#
# Nothing is overwritten: an existing user.name / user.email / key is kept.
# The https -> ssh rewrite is only switched on AFTER an SSH login is proven, so a
# half-finished setup can never break `git clone https://...`.
# =============================================================================

# GitHub's published ed25519 host key (docs.github.com ->
# "GitHub's SSH key fingerprints"; SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU).
# Pinned so the first connection is never trust-on-first-use.
$script:GitHubHostKey = 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'
$script:GitHubHostFingerprint = 'SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU'

function Get-GitGlobal {
    param([string]$Key)
    $v = & git config --global --get $Key 2>$null
    if ($LASTEXITCODE -eq 0 -and $v) { return ([string]$v).Trim() }
    return $null
}

function Find-SshTool {
    param([ValidateSet('ssh', 'ssh-keygen')][string]$Name)

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $gitUsr = Join-Path $env:ProgramFiles 'Git\usr\bin'
    $alt = Join-Path $gitUsr "$Name.exe"
    if (Test-Path -LiteralPath $alt) { return $alt }

    return $null
}

function Add-GitHubHostKey {
    <# Adds the pinned key to known_hosts unless github.com is already there. #>
    param([string]$KnownHosts, [string]$SshKeygen)

    $prefix = ''
    if (Test-Path -LiteralPath $KnownHosts) {
        & $SshKeygen -F github.com -f $KnownHosts 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return 'present' }

        # A file whose last line has no newline would swallow the appended key into that line.
        $raw = Get-Content -LiteralPath $KnownHosts -Raw
        if ($raw -and -not $raw.EndsWith("`n")) { $prefix = "`n" }
    }

    Add-Content -LiteralPath $KnownHosts -Value ($prefix + $script:GitHubHostKey) -Encoding ASCII
    return 'added'
}

function Test-GitHubSsh {
    <# Returns the GitHub login name on success, $null otherwise.
       Without -KeyPath, ssh uses whatever its normal config/agent offers (detects an already-working setup).
       -Batch never prompts (used for that silent pre-check); without it a passphrase prompt can appear. #>
    param([string]$Ssh, [string]$KeyPath, [switch]$Batch)

    $sshArgs = @('-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=15')
    if ($Batch)   { $sshArgs += @('-o', 'BatchMode=yes') }
    if ($KeyPath) { $sshArgs += @('-i', $KeyPath, '-o', 'IdentitiesOnly=yes') }
    $sshArgs += @('-T', 'git@github.com')

    # ssh writes its greeting to stderr. Under $ErrorActionPreference = 'Stop', Windows PowerShell 5.1 turns
    # `2>&1` on a native command into a terminating error, so relax it for this one call.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & $Ssh @sshArgs 2>&1 }
    finally { $ErrorActionPreference = $prevEap }
    $text = ($out | Out-String)
    Write-LogLine 'SSH' $text

    if ($text -match "Hi ([^!]+)! You've successfully authenticated") { return $Matches[1] }
    return $null
}

function Read-NonEmpty {
    param([string]$Prompt, [string]$Pattern = '\S')
    for ($i = 0; $i -lt 3; $i++) {
        $v = (Read-Host $Prompt).Trim()
        if ($v -match $Pattern) { return $v }
        Write-Warn 'That does not look right - try again.'
    }
    return $null
}

function Invoke-GitStep {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$GitUser, [string]$GitEmail, [switch]$Unattended, [switch]$SkipSsh)

    if (-not (Test-CommandExists 'git')) { throw 'git is not available - the Core package step must run first.' }

    # ---- git-lfs filters ----------------------------------------------------
    if (Test-CommandExists 'git-lfs') {
        if (Get-GitGlobal 'filter.lfs.clean') {
            Write-Ok 'git-lfs filters already configured'
            Add-Result -Step 'git' -Item 'git-lfs' -Status 'Skipped' -Detail 'already configured'
        }
        elseif ($PSCmdlet.ShouldProcess('global git config', 'git lfs install')) {
            & git lfs install --skip-repo 2>&1 | Out-Null
            Write-Ok 'git-lfs filters configured'
            Add-Result -Step 'git' -Item 'git-lfs' -Status 'Ok' -Detail 'filters configured'
        }
    }

    # ---- identity: ask only for what is missing -----------------------------
    $name  = Get-GitGlobal 'user.name'
    $email = Get-GitGlobal 'user.email'

    if ($name) { Write-Ok "git user.name already set: $name" }
    else {
        if (-not $GitUser -and -not $Unattended) {
            Write-Host ''
            $GitUser = Read-NonEmpty 'Git username (saved as the global git user.name)'
        }
        if ($GitUser) {
            if ($PSCmdlet.ShouldProcess('git config --global user.name', $GitUser)) {
                & git config --global user.name $GitUser
                Write-Ok "git user.name = $GitUser"
                Add-Result -Step 'git' -Item 'user.name' -Status 'Ok' -Detail $GitUser
            }
            $name = $GitUser
        }
        else {
            Add-Result -Step 'git' -Item 'user.name' -Status 'Warn' -Detail 'not set: pass -GitUser or run interactively'
            Write-Warn 'git user.name is not set (no -GitUser given).'
        }
    }

    if ($email) { Write-Ok "git user.email already set: $email" }
    else {
        if (-not $GitEmail -and -not $Unattended) {
            $GitEmail = Read-NonEmpty 'Email for git (saved as the global git user.email)' '^[^@\s]+@[^@\s]+\.[^@\s]+$'
        }
        if ($GitEmail -and $GitEmail -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
            if ($PSCmdlet.ShouldProcess('git config --global user.email', $GitEmail)) {
                & git config --global user.email $GitEmail
                Write-Ok "git user.email = $GitEmail"
                Add-Result -Step 'git' -Item 'user.email' -Status 'Ok' -Detail $GitEmail
            }
            $email = $GitEmail
        }
        else {
            Add-Result -Step 'git' -Item 'user.email' -Status 'Warn' -Detail 'not set: pass -GitEmail or run interactively'
            Write-Warn 'git user.email is not set (no valid -GitEmail given).'
        }
    }

    $exclude = Join-Path $HOME '.config\git\ignore'
    if ((Test-Path -LiteralPath $exclude) -and -not (Get-GitGlobal 'core.excludesfile')) {
        & git config --global core.excludesfile $exclude
    }

    if ($SkipSsh) { Write-Dim 'SSH setup skipped (-SkipSsh)'; return }

    # ---- SSH ----------------------------------------------------------------
    $ssh       = Find-SshTool 'ssh'
    $sshKeygen = Find-SshTool 'ssh-keygen'

    if (-not $ssh -or -not $sshKeygen) {
        Write-Bad 'OpenSSH client not found.'
        Write-Host '     Windows: Settings > System > Optional features > "OpenSSH Client"  (or it ships inside Git for Windows).' -ForegroundColor Yellow
        Add-Result -Step 'git' -Item 'ssh' -Status 'Warn' -Detail 'OpenSSH client missing; install it and re-run: install.ps1 -Only Git'
        return
    }

    $sshDir = Join-Path $HOME '.ssh'
    $key    = Join-Path $sshDir 'id_ed25519'
    $pub    = "$key.pub"
    $known  = Join-Path $sshDir 'known_hosts'

    if ($WhatIfPreference) {
        Write-Info 'Dry run: a real run would pin the GitHub host key, test SSH, and only if it fails create a key, show it and wait for you to add it to GitHub.'
        Add-Result -Step 'git' -Item 'ssh' -Status 'Skipped' -Detail 'dry run'
        return
    }

    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    if (-not (Test-Path -LiteralPath $known)) { New-Item -ItemType File -Path $known -Force | Out-Null }
    $hk = Add-GitHubHostKey -KnownHosts $known -SshKeygen $sshKeygen
    Write-Ok "GitHub host key $hk in known_hosts (pinned, $script:GitHubHostFingerprint)"

    # Silent pre-check: does SSH to GitHub already work with whatever is configured?
    $login = Test-GitHubSsh -Ssh $ssh -Batch
    if ($login) {
        Write-Ok "SSH to GitHub already works (logged in as $login) - no key setup needed"
        Add-Result -Step 'git' -Item 'ssh' -Status 'Skipped' -Detail "already working as $login"
    }
    else {
        # ---- key: reuse or create -------------------------------------------
        if (-not (Test-Path -LiteralPath $key)) {
            Write-Info 'Generating a new ed25519 key. You will be asked for a passphrase - press Enter for none, or choose one.'
            $who     = if ($email) { $email } elseif ($name) { $name } else { $env:USERNAME }
            $comment = "$who@$env:COMPUTERNAME (pwsh bootstrap)"

            if ($Unattended) {
                # An empty passphrase needs a different spelling per PowerShell: 5.1 and 7.0-7.2 drop a bare '' and
                # need the literal "" ; 7.3+ (native argument passing = Windows) passes '' through correctly, and
                # would hand ssh-keygen a two-character passphrase of "" if given '""'.
                $modernArgs = ($PSVersionTable.PSVersion -ge [version]'7.3') -and ($PSNativeCommandArgumentPassing -ne 'Legacy')
                $emptyPass  = if ($modernArgs) { '' } else { '""' }
                & $sshKeygen -q -t ed25519 -C $comment -f $key -N $emptyPass
            }
            else { & $sshKeygen -t ed25519 -C $comment -f $key }

            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $pub)) {
                Write-Bad 'ssh-keygen failed'
                Add-Result -Step 'git' -Item 'ssh key' -Status 'Failed' -Detail 'ssh-keygen failed'
                return
            }
            Add-Result -Step 'git' -Item 'ssh key' -Status 'Ok' -Detail $key
        }
        else {
            Write-Ok "Using your existing key $key (not regenerated)"
            Add-Result -Step 'git' -Item 'ssh key' -Status 'Skipped' -Detail 'existing key reused'
        }

        if (-not (Test-Path -LiteralPath $pub)) {
            & $sshKeygen -y -f $key | Set-Content -LiteralPath $pub -Encoding ASCII
        }

        # The key may already be registered with GitHub (e.g. a passphrase blocked the silent check).
        $login = Test-GitHubSsh -Ssh $ssh -KeyPath $key

        if (-not $login) {
            $pubText = (Get-Content -LiteralPath $pub -Raw).Trim()

            Write-Host ''
            Write-Host '  SSH to GitHub is not working yet. Add this PUBLIC key to your GitHub account:' -ForegroundColor Cyan
            Write-Host ''
            Write-Host "  $pubText" -ForegroundColor White
            Write-Host ''
            Write-Host '  1. Open https://github.com/settings/ssh/new' -ForegroundColor Gray
            Write-Host '  2. Key type: Authentication Key. Paste the whole line above as ONE line. Save.' -ForegroundColor Gray

            if ($Unattended) {
                Add-Result -Step 'git' -Item 'ssh activation' -Status 'Warn' -Detail 'public key shown; add it to GitHub then run: install.ps1 -Only Git'
                return
            }

            try { Set-Clipboard -Value $pubText; Write-Ok 'Public key copied to the clipboard' } catch { Write-Dim 'could not use the clipboard - copy the line above' }
            try { Start-Process 'https://github.com/settings/ssh/new' } catch { Write-Dim 'could not open a browser - open the link above' }

            Write-Host ''
            Write-Host '  *** DO NOT CONTINUE UNTIL THE KEY HAS BEEN ADDED TO GITHUB. ***' -ForegroundColor Yellow
            Write-Host '  The rest of the install depends on SSH working.' -ForegroundColor Yellow

            while (-not $login) {
                $a = Read-Host "`nPress Enter once the key is added and saved on GitHub (or type SKIP to continue without SSH)"
                if ($a -match '^\s*skip\s*$') { break }
                $login = Test-GitHubSsh -Ssh $ssh -KeyPath $key
                if (-not $login) { Write-Warn 'GitHub did not accept the key yet. Check it was pasted as ONE line and saved, then press Enter again.' }
            }
        }
    }

    if (-not $login) {
        Add-Result -Step 'git' -Item 'ssh activation' -Status 'Warn' -Detail 'skipped by you; add the key then run: install.ps1 -Only Git'
        Write-Warn 'SSH not verified - git keeps using HTTPS. Re-run later with: install.ps1 -Only Git'
        return
    }

    $rewrite = Get-GitGlobal 'url.git@github.com:.insteadOf'
    if ($rewrite -eq 'https://github.com/') {
        Write-Ok 'git already rewrites https://github.com/ to SSH'
    }
    elseif ($PSCmdlet.ShouldProcess('git config --global', 'url.git@github.com:.insteadOf https://github.com/')) {
        & git config --global 'url.git@github.com:.insteadOf' 'https://github.com/'
        Write-Ok 'git now uses SSH for every github.com remote (https://github.com/... is rewritten automatically)'
    }

    Add-Result -Step 'git' -Item 'ssh activation' -Status 'Ok' -Detail "authenticated as $login"
}
