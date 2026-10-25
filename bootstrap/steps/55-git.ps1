# =============================================================================
# 55-git.ps1 - git identity and GitHub SSH
#
# Two prompts, as designed:
#   1. your GitHub username
#   2. the public key to paste into GitHub (shown, copied to the clipboard, and
#      the "add key" page is opened), then Enter to test it
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
    <# Returns the GitHub login name on success, $null otherwise. Interactive on purpose: a passphrase prompt must be able to appear. #>
    param([string]$Ssh, [string]$KeyPath)

    # ssh writes its greeting to stderr. Under $ErrorActionPreference = 'Stop', Windows PowerShell 5.1 turns
    # `2>&1` on a native command into a terminating error, so relax it for this one call.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & $Ssh -i $KeyPath -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -T git@github.com 2>&1 }
    finally { $ErrorActionPreference = $prevEap }
    $text = ($out | Out-String)
    Write-LogLine 'SSH' $text

    if ($text -match "Hi ([^!]+)! You've successfully authenticated") { return $Matches[1] }
    return $null
}

function Invoke-GitStep {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$GitUser, [switch]$Unattended, [switch]$SkipSsh)

    if (-not (Test-CommandExists 'git')) { throw 'git is not available - the Core package step must run first.' }

    $userEntered = $false   # true only when the name came from -GitUser or the prompt (not from an existing git config)

    # ---- git-lfs filters (the old gitconfig carried these) ------------------
    if (Test-CommandExists 'git-lfs') {
        if ($PSCmdlet.ShouldProcess('global git config', 'git lfs install')) {
            & git lfs install --skip-repo 2>&1 | Out-Null
            Write-Ok 'git-lfs filters configured'
            Add-Result -Step 'git' -Item 'git-lfs' -Status 'Ok' -Detail 'filters configured'
        }
    }

    # ---- identity -----------------------------------------------------------
    $name  = Get-GitGlobal 'user.name'
    $email = Get-GitGlobal 'user.email'

    if (-not $GitUser -and $name -and $email) {
        Write-Ok "git identity already set: $name <$email>"
        $GitUser = $name
    }
    else {
        if (-not $GitUser) {
            if ($Unattended) {
                Add-Result -Step 'git' -Item 'identity' -Status 'Warn' -Detail 'no -GitUser given and -Unattended: identity and SSH not configured'
                Write-Warn 'No Git username supplied (-GitUser) - skipping identity and SSH.'
                return
            }
            Write-Host ''
            $GitUser = (Read-Host 'GitHub username (used for git user.name and for the SSH key comment)').Trim()
        }

        if ($GitUser -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$') {
            Add-Result -Step 'git' -Item 'identity' -Status 'Warn' -Detail "'$GitUser' does not look like a GitHub username - skipped"
            Write-Warn "'$GitUser' is not a valid GitHub username - skipping git identity and SSH."
            return
        }

        $userEntered = $true

        if (-not $name -and $PSCmdlet.ShouldProcess('git config --global user.name', $GitUser)) {
            & git config --global user.name $GitUser
            Write-Ok "git user.name = $GitUser"
        }

        if (-not $email -and $PSCmdlet.ShouldProcess('git config --global user.email', "$GitUser@users.noreply.github.com")) {
            # GitHub's privacy address: commits are attributed to the account without publishing a mailbox.
            & git config --global user.email "$GitUser@users.noreply.github.com"
            Write-Ok "git user.email = $GitUser@users.noreply.github.com  (change it with: git config --global user.email you@example.com)"
        }

        Add-Result -Step 'git' -Item 'identity' -Status 'Ok' -Detail "user $GitUser"
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

    if ($PSCmdlet.ShouldProcess($sshDir, 'create ~/.ssh and pin the GitHub host key')) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        if (-not (Test-Path -LiteralPath $known)) { New-Item -ItemType File -Path $known -Force | Out-Null }
        $hk = Add-GitHubHostKey -KnownHosts $known -SshKeygen $sshKeygen
        Write-Ok "GitHub host key $hk in known_hosts (pinned, $script:GitHubHostFingerprint)"
    }

    if (-not (Test-Path -LiteralPath $key)) {
        if (-not $PSCmdlet.ShouldProcess($key, 'ssh-keygen -t ed25519')) { return }

        Write-Info 'Generating a new ed25519 key. You will be asked for a passphrase - press Enter for none, or choose one.'
        $comment = "$GitUser@$env:COMPUTERNAME (pwsh bootstrap)"

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

    if ($WhatIfPreference) {
        Write-Info 'Dry run: a real run would test the key against GitHub, then (if needed) show it, copy it and open the add-key page.'
        Add-Result -Step 'git' -Item 'ssh activation' -Status 'Skipped' -Detail 'dry run'
        return
    }

    $login = Test-GitHubSsh -Ssh $ssh -KeyPath $key
    if ($login) {
        Write-Ok "SSH to GitHub already works (logged in as $login)"
    }
    else {
        $pubText = (Get-Content -LiteralPath $pub -Raw).Trim()

        Write-Host ''
        Write-Host '  Add this public key to GitHub to activate SSH:' -ForegroundColor Cyan
        Write-Host ''
        Write-Host "  $pubText" -ForegroundColor White
        Write-Host ''
        Write-Host '  GitHub > Settings > SSH and GPG keys > New SSH key  (Key type: Authentication Key)' -ForegroundColor Gray
        Write-Host '  https://github.com/settings/ssh/new' -ForegroundColor Gray

        if ($Unattended) {
            Add-Result -Step 'git' -Item 'ssh activation' -Status 'Warn' -Detail 'public key shown; add it to GitHub then run: install.ps1 -Only Git'
            return
        }

        try { Set-Clipboard -Value $pubText; Write-Ok 'Public key copied to the clipboard' } catch { Write-Dim 'could not use the clipboard - copy the line above' }
        try { Start-Process 'https://github.com/settings/ssh/new' } catch { Write-Dim 'could not open a browser - open the link above' }

        for ($try = 1; $try -le 3 -and -not $login; $try++) {
            [void](Read-Host "`nPress Enter after you have added the key to GitHub (attempt $try of 3)")
            $login = Test-GitHubSsh -Ssh $ssh -KeyPath $key
            if (-not $login) { Write-Warn 'GitHub did not accept the key yet. Check it was pasted as ONE line, then try again.' }
        }
    }

    if (-not $login) {
        Add-Result -Step 'git' -Item 'ssh activation' -Status 'Warn' -Detail 'not verified; add the key then run: install.ps1 -Only Git'
        Write-Warn 'SSH not verified - git keeps using HTTPS. Re-run later with: install.ps1 -Only Git'
        return
    }

    if ($userEntered -and $login -ne $GitUser) {
        Write-Warn "GitHub says you are '$login' but you entered '$GitUser'. Keeping what you entered for user.name."
    }

    if ($PSCmdlet.ShouldProcess('git config --global', 'url.git@github.com:.insteadOf https://github.com/')) {
        & git config --global 'url.git@github.com:.insteadOf' 'https://github.com/'
        Write-Ok 'git now uses SSH for every github.com remote (https://github.com/... is rewritten automatically)'
    }

    Add-Result -Step 'git' -Item 'ssh activation' -Status 'Ok' -Detail "authenticated as $login"
}
