# =============================================================================
# 10-prereqs.ps1 - is this machine able to run the installer at all?
# Hard requirements throw (the step is -Required); soft ones warn.
# =============================================================================

function Invoke-PrereqStep {
    $os = Get-WindowsInfo
    Write-Info ("{0} (build {1}), PowerShell {2} {3}" -f $os.Caption, $os.Build, $PSVersionTable.PSEdition, $PSVersionTable.PSVersion)

    if ($env:OS -ne 'Windows_NT') { throw 'This installer configures Windows. Run it on a Windows machine.' }

    if (-not $os.Supported) {
        throw ("Windows build {0} is older than 10 1809 (17763), which winget needs." -f $os.Build)
    }

    if (-not $os.Is64Bit) {
        Add-Result -Step 'prereqs' -Item 'architecture' -Status 'Warn' -Detail '32-bit Windows: several packages in the manifest have no 32-bit build'
        Write-Warn '32-bit Windows detected - some packages will not install.'
    }

    if (Test-IsAdmin) {
        Write-Info 'Running elevated. User-scope work (fonts, HKCU, User PATH) will apply to THIS account, so only keep it elevated if it is your own.'
    }
    else {
        Write-Ok 'Running as a normal user (recommended). Machine-wide installers will raise their own UAC prompts.'
    }

    # Network: fail early and clearly rather than 40 packages deep.
    try {
        $r = Invoke-WebRequest -Uri 'https://github.com' -Method Head -UseBasicParsing -TimeoutSec 15
        Write-Ok ("github.com reachable (HTTP {0})" -f [int]$r.StatusCode)
    }
    catch {
        Add-Result -Step 'prereqs' -Item 'network' -Status 'Warn' -Detail 'github.com unreachable - clone/download steps will fail'
        Write-Warn "Could not reach github.com: $($_.Exception.Message)"
    }

    if (-not (Test-WingetUsable)) {
        Write-Bad 'winget is missing or not working.'
        Write-Host '     Install or update "App Installer" from the Microsoft Store, then re-run:' -ForegroundColor Yellow
        Write-Host '     ms-windows-store://pdp/?productid=9NBLGGH4NNS1' -ForegroundColor Yellow
        Write-Host '     (On a brand-new Windows 10, winget can take a few minutes to register after first sign-in.)' -ForegroundColor Yellow
        throw 'winget is required to install packages.'
    }

    Write-Ok ("winget {0}" -f ((& winget --version) -join ''))
    Add-Result -Step 'prereqs' -Item 'environment' -Status 'Ok' -Detail "$($os.Caption) build $($os.Build)"
}
