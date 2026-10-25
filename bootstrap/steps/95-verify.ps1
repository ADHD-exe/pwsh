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
            # GUI programs must never be asked for --version: Windows Terminal and Autoruns open a window, and
            # Notepad++ treats "--version" as a file name and offers to create it.
            if ($p.Command -notin 'wt', 'autoruns', 'notepad++') {
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
    if ($script:InstallThemes -eq $false) { Write-Dim 'Themes declined - theme checks skipped.' }
    elseif (Test-JsonFile -Path $theme) {
        Write-Ok 'oh-my-rabbit.omp.json parses'

        if (Test-CommandExists 'oh-my-posh') {
            $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'   # 5.1 + Stop + 2>&1 would throw
            try { $init = & oh-my-posh init pwsh --config $theme 2>&1 } finally { $ErrorActionPreference = $prevEap }
            if ($LASTEXITCODE -eq 0 -and $init) { Write-Ok 'oh-my-posh accepts the theme'; Add-Result -Step 'verify' -Item 'theme' -Status 'Ok' -Detail 'oh-my-posh init succeeded' }
            else { Write-Bad 'oh-my-posh rejected the theme'; Add-Result -Step 'verify' -Item 'theme' -Status 'Failed' -Detail (($init | Out-String).Trim()) }
        }
    }
    else { Write-Bad 'theme JSON invalid'; Add-Result -Step 'verify' -Item 'theme' -Status 'Failed' -Detail 'oh-my-rabbit.omp.json does not parse' }

    # ---- Firefox Developer Edition (Tools tier): installed, and reachable as `firefox` -----------------------
    if ($Tier -contains 'Tools') {
        $ffExe = @('%ProgramFiles%\Firefox Developer Edition\firefox.exe', '%ProgramFiles(x86)%\Firefox Developer Edition\firefox.exe') |
            ForEach-Object { Expand-Vars $_ } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($ffExe) { Write-Ok "Firefox Developer Edition  $ffExe" }
        else { Write-Warn 'Firefox Developer Edition was not found'; Add-Result -Step 'verify' -Item 'firefox' -Status 'Warn' -Detail 'Firefox Developer Edition not installed' }
    }

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
        # $Error is dumped after the profile runs, so a failure names its real message, file and line
        # instead of just the call site in the stub.
        $cmd = '$ErrorActionPreference = "Continue"; $Error.Clear(); $sw=[Diagnostics.Stopwatch]::StartNew(); . $env:PWSH_VERIFY_PROFILE; $sw.Stop(); ' +
               'foreach ($e in @($Error)) { "PROFILEERR::" + $e.Exception.Message + " @ " + $e.InvocationInfo.ScriptName + ":" + $e.InvocationInfo.ScriptLineNumber + " [" + $e.FullyQualifiedErrorId + "]" }; ' +
               '[string][int]$sw.ElapsedMilliseconds'
        $env:PWSH_VERIFY_PROFILE = $stub
        # The profile skips prompts, key bindings and tool hooks whenever pwsh was started with -Command/-File,
        # so without the override this check would only exercise the first few lines of it.
        $env:RABBIT_PROFILE_FORCE = '1'
        try { $out = & $pwsh -NoLogo -NoProfile -Command $cmd 2>&1 }
        finally {
            Remove-Item -LiteralPath Env:\PWSH_VERIFY_PROFILE -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath Env:\RABBIT_PROFILE_FORCE -ErrorAction SilentlyContinue
        }
        # The child prints PROFILEERR:: lines from $Error, then the elapsed ms. Many modules emit the same error
        # thousands of times (syntax-highlighting), so the log gets each distinct line once.
        Write-LogLine 'PROFILE' ((@($out | ForEach-Object { "$_" } | Select-Object -Unique) -join "`n").Trim())
        $ms = ($out | Where-Object { $_ -is [string] -and $_ -match '^\d+$' } | Select-Object -Last 1)

        # PSReadLine cannot load in a child with redirected I/O; that is a limit of this check, not of the profile.
        # Errors that only follow from that (PSFzf, Atuin, PSCompletions, syntax-highlighting, oh-my-posh init all
        # need it) and YouShouldUse's harmless Get-Variable probe for YSU_NO_AUTOENABLE are filtered for that reason.
        $ignore = 'PSReadLine|PSFzf\.psm1|YSU_NO_AUTOENABLE'
        $tagged = @($out | Where-Object { $_ -is [string] -and $_.StartsWith('PROFILEERR::') } | ForEach-Object { $_.Substring(12) } | Where-Object { $_ -notmatch $ignore } | Select-Object -Unique)
        if ($ms) {
            # The child finished and dumped $Error, so that dump is the complete list. Raw stderr is NOT consulted:
            # PowerShell renders one error over several lines ("Line |", "~~~~"), which no filter can match.
            $errs = $tagged
        }
        elseif ($tagged.Count -gt 0) { $errs = $tagged }
        else {
            # The child never reported its timing (crashed or hung): fall back to its raw stderr.
            $errs = @($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.ToString() -notmatch $ignore } | ForEach-Object { $_.ToString() })
            if ($errs.Count -eq 0) { $errs = @('the child shell did not finish loading the profile') }
        }

        if ($errs.Count -eq 0 -and $ms) {
            Write-Ok "Profile loads cleanly in a fresh pwsh ($ms ms)"
            Add-Result -Step 'verify' -Item 'profile' -Status 'Ok' -Detail "$ms ms"
        }
        else {
            Write-Bad 'Profile produced errors in a fresh pwsh:'
            $errs | Select-Object -First 5 | ForEach-Object { Write-Dim $_ }
            Add-Result -Step 'verify' -Item 'profile' -Status 'Failed' -Detail ([string]($errs | Select-Object -First 1))
        }
    }

    # ---- Terminal -----------------------------------------------------------
    foreach ($t in Get-WindowsTerminalTargets | Where-Object { Test-Path -LiteralPath $_.Settings }) {
        if (Test-JsonFile -Path $t.Settings -AllowComments) { Write-Ok "Terminal settings valid ($($t.Kind))" }
        else { Write-Bad "Terminal settings invalid ($($t.Kind))"; Add-Result -Step 'verify' -Item 'terminal' -Status 'Failed' -Detail $t.Settings }
    }
}
