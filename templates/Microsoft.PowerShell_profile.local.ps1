# Machine-local additions. Copy this file to Documents\PowerShell\Microsoft.PowerShell_profile.local.ps1
# The repo profile loads it last and the installer never overwrites it.

# Personal folder shortcuts (kept out of the shared repo on purpose)
function pics   { Set-Location "$HOME\Photos" }
function github { Set-Location "$HOME\Github" }
function music  { Set-Location "$HOME\Music" }
function vault  { Set-Location 'D:\' }
