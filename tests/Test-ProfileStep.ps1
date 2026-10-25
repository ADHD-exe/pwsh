# Offline test for bootstrap/steps/60-profile.ps1 (any OS, PowerShell 7).
#   pwsh -NoProfile -File tests/Test-ProfileStep.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'bootstrap/lib/Common.ps1')
. (Join-Path $root 'bootstrap/steps/60-profile.ps1')

$failures = 0
function Assert { param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host "  pass  $Name" -ForegroundColor Green } else { Write-Host "  FAIL  $Name" -ForegroundColor Red; $script:failures++ }
}

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("profiletest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $sandbox | Out-Null
$env:HOME = $sandbox; $env:USERPROFILE = $sandbox
Set-Variable -Name HOME -Value $sandbox -Force -Scope Global -ErrorAction SilentlyContinue

# fake install dir containing the repo profile
$installDir = Join-Path $sandbox '.pwsh'
New-Item -ItemType Directory -Path (Join-Path $installDir 'profile') -Force | Out-Null
Copy-Item (Join-Path $root 'profile/Microsoft.PowerShell_profile.ps1') (Join-Path $installDir 'profile')

$profDir = Get-Pwsh7ProfileDirectory
$target  = Join-Path $profDir 'Microsoft.PowerShell_profile.ps1'
$local   = Join-Path $profDir 'Microsoft.PowerShell_profile.local.ps1'
Write-Host "profile dir: $profDir"

Write-Host "`n1. fresh machine"
Invoke-ProfileStep -InstallDir $installDir
Assert (Test-Path $target) 'stub written'
Assert ((Get-Content $target -Raw) -match [regex]::Escape($installDir)) 'stub points at the install dir'
Assert (Test-Path $local) 'local extension file created'

Write-Host "`n2. rerun is idempotent"
$before = Get-Content $target -Raw
Invoke-ProfileStep -InstallDir $installDir
Assert ((Get-Content $target -Raw) -eq $before) 'stub unchanged'
Assert (@(Get-ChildItem $profDir -Filter '*.bak-*').Count -eq 0) 'no spurious backup'

Write-Host "`n3. install dir moves -> managed block refreshed, user text outside it kept"
Add-Content $target "`n# my own line"
$moved = Join-Path $sandbox 'elsewhere'
New-Item -ItemType Directory -Path (Join-Path $moved 'profile') -Force | Out-Null
Copy-Item (Join-Path $root 'profile/Microsoft.PowerShell_profile.ps1') (Join-Path $moved 'profile')
Invoke-ProfileStep -InstallDir $moved
$after = Get-Content $target -Raw
Assert ($after -match 'elsewhere') 'block now points at the new dir'
Assert ($after -match '# my own line') 'text outside the markers survived'
Assert (@(Get-ChildItem $profDir -Filter '*.bak-*').Count -ge 1) 'backup made before editing'

Write-Host "`n4. someone else's profile is preserved"
Remove-Item $profDir -Recurse -Force
New-Item -ItemType Directory -Path $profDir | Out-Null
Set-Content $target "Set-Alias gs git-status-custom`n# precious"
Invoke-ProfileStep -InstallDir $installDir
Assert ((Get-Content $local -Raw) -match 'precious') 'old content moved into the .local file'
Assert ((Get-Content $target -Raw) -match 'pwsh bootstrap') 'stub installed over it'
Assert (@(Get-ChildItem $profDir -Filter '*.bak-*').Count -eq 1) 'original backed up'

Write-Host "`n5. the previous Rabbit profile is replaced, not migrated"
Remove-Item $profDir -Recurse -Force
New-Item -ItemType Directory -Path $profDir | Out-Null
Set-Content $target "# Rabbit PowerShell Profile`nif (`$global:RABBIT_PROFILE_LOADED) { return }"
Invoke-ProfileStep -InstallDir $installDir
Assert (-not ((Get-Content $local -Raw) -match 'RABBIT_PROFILE_LOADED')) 'old Rabbit profile NOT copied into .local (would double-load)'
Assert (@(Get-ChildItem $profDir -Filter '*.bak-*').Count -eq 1) 'old Rabbit profile backed up'

Write-Host "`n6. -WhatIf changes nothing"
Remove-Item $profDir -Recurse -Force
Invoke-ProfileStep -InstallDir $installDir -WhatIf
Assert (-not (Test-Path $target)) 'nothing written in a dry run'

Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
if ($failures) { Write-Host "`n$failures failure(s)" -ForegroundColor Red; exit 1 }
Write-Host "`nall passed" -ForegroundColor Green
