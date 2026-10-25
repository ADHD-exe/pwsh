# =============================================================================
# 95-verify.ps1 - prove the result works instead of trusting exit codes
# =============================================================================

function Invoke-VerifyStep {
    param([Parameter(Mandatory)][string]$RepoRoot, [string[]]$Tier)

    Update-SessionPath

    # ---- commands -----------------------------------------------------------
    $pkgs = (Import-PowerShellDataFile -LiteralPath (Join-Path $script:ManifestDir 'packages.psd1')).Packages |
        Where-Object { $Tier -contains $_.Tier -and $_.Command -and -not $_.Risky }

    foreach ($p in $pkgs) {
        if (Test-CommandExists $p.Command) {
            $ver = ''
            # wt and autoruns are GUI launchers: asking them for --version can open a window instead of printing.
            if ($p.Command -notin 'wt', 'autoruns') {
                try { $ver = ((& $p.Command --version 2>$null) | Select-Object -First 1) } catch { }
            }
            Write-Ok ("{0,-12} {1}" -f $p.Command, $ver)
        }
        else {
            Write-Warn "$($p.Command) is not on PATH in this session (a new terminal may be needed)"
            Add-Result -Step 'verify' -Item $p.Command -Status 'Warn' -Detail 'not on PATH yet - open a new terminal and re-check'
        }
    }

    # ---- theme --------------------------------------------------------------
    $theme = Join-Path $RepoRoot 'settings\oh-my-rabbit.omp.json'
    if (Test-JsonFile -Path $theme) {
        Write-Ok 'oh-my-rabbit.omp.json parses'

        if (Test-CommandExists 'oh-my-posh') {
            $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'   # 5.1 + Stop + 2>&1 would throw
            try { $init = & oh-my-posh init pwsh --config $theme 2>&1 } finally { $ErrorActionPreference = $prevEap }
            if ($LASTEXITCODE -eq 0 -and $init) { Write-Ok 'oh-my-posh accepts the theme'; Add-Result -Step 'verify' -Item 'theme' -Status 'Ok' -Detail 'oh-my-posh init succeeded' }
            else { Write-Bad 'oh-my-posh rejected the theme'; Add-Result -Step 'verify' -Item 'theme' -Status 'Failed' -Detail (($init | Out-String).Trim()) }
        }
    }
    else { Write-Bad 'theme JSON invalid'; Add-Result -Step 'verify' -Item 'theme' -Status 'Failed' -Detail 'oh-my-rabbit.omp.json does not parse' }

    # ---- font ---------------------------------------------------------------
    $fontKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    $mono = (Get-ItemProperty -Path $fontKey -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -like 'Monoid Nerd Font*' }
    if ($mono) { Write-Ok "Monoid Nerd Font registered ($(@($mono).Count) styles)" }
    else { Write-Warn 'Monoid Nerd Font is not registered for this user'; Add-Result -Step 'verify' -Item 'font' -Status 'Warn' -Detail 'Monoid Nerd Font not found in HKCU fonts' }

    # ---- profile: load it in a clean child shell and time it ----------------
    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    $stub = Join-Path (Get-Pwsh7ProfileDirectory) 'Microsoft.PowerShell_profile.ps1'
    if ($pwsh -and -not (Test-Path -LiteralPath $stub)) {
        Write-Warn "Profile stub not found: $stub"
        Add-Result -Step 'verify' -Item 'profile' -Status 'Warn' -Detail 'profile stub missing - run: install.ps1 -Only Profile'
    }
    elseif ($pwsh) {
        # `pwsh -Command` does not fill $args from trailing arguments (they are appended to the command text),
        # and a path with spaces would break there anyway - so the stub path travels in an environment variable.
        $cmd = '$sw=[Diagnostics.Stopwatch]::StartNew(); . $env:PWSH_VERIFY_PROFILE; $sw.Stop(); [string][int]$sw.ElapsedMilliseconds'
        $env:PWSH_VERIFY_PROFILE = $stub
        # The profile skips prompts, key bindings and tool hooks whenever pwsh was started with -Command/-File,
        # so without the override this check would only exercise the first few lines of it.
        $env:RABBIT_PROFILE_FORCE = '1'
        try { $out = & $pwsh -NoLogo -NoProfile -Command $cmd 2>&1 }
        finally {
            Remove-Item -LiteralPath Env:\PWSH_VERIFY_PROFILE -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath Env:\RABBIT_PROFILE_FORCE -ErrorAction SilentlyContinue
        }
        $text = ($out | Out-String).Trim()
        $ms   = ($out | Where-Object { $_ -match '^\d+$' } | Select-Object -Last 1)
        $errs = @($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

        if ($errs.Count -eq 0 -and $ms) {
            Write-Ok "Profile loads cleanly in a fresh pwsh ($ms ms)"
            Add-Result -Step 'verify' -Item 'profile' -Status 'Ok' -Detail "$ms ms"
        }
        else {
            Write-Bad 'Profile produced errors in a fresh pwsh:'
            $errs | Select-Object -First 5 | ForEach-Object { Write-Dim $_.ToString() }
            Add-Result -Step 'verify' -Item 'profile' -Status 'Failed' -Detail (($errs | Select-Object -First 1) | Out-String).Trim()
        }
    }

    # ---- Terminal -----------------------------------------------------------
    foreach ($t in Get-WindowsTerminalTargets | Where-Object { Test-Path -LiteralPath $_.Settings }) {
        if (Test-JsonFile -Path $t.Settings -AllowComments) { Write-Ok "Terminal settings valid ($($t.Kind))" }
        else { Write-Bad "Terminal settings invalid ($($t.Kind))"; Add-Result -Step 'verify' -Item 'terminal' -Status 'Failed' -Detail $t.Settings }
    }
}
