# Offline test for the new-terminal handoff command (Relaunch.ps1).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\bootstrap\lib\Common.ps1')
. (Join-Path $PSScriptRoot '..\bootstrap\lib\Relaunch.ps1')

$fail = 0
function Check($name, [bool]$ok, $detail = '') {
    if ($ok) { Write-Host "  pass  $name" }
    else { Write-Host "  FAIL  $name  $detail"; $script:fail++ }
}

Write-Host 'New-ResumeEncodedCommand'

$path   = "C:\Users\O'Brien Jane\.pwsh\bootstrap\Install-Environment.ps1"   # space + apostrophe
$params = @{ ResumeAfterPath = $true; InstallDir = "C:\Users\O'Brien Jane\.pwsh"; Tier = 'Core,Shell' }

$b64  = New-ResumeEncodedCommand -ScriptPath $path -Parameters $params
$text = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($b64))

$errors = $null
$tokens = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)

Check 'generated command parses without errors' ($errors.Count -eq 0) ($errors | Out-String)
Check 'switch becomes $true'                    ($text -match "'ResumeAfterPath' = \`$true")
Check 'apostrophe in path is escaped'           ($text.Contains("O''Brien Jane"))
Check 'script is splatted with a hashtable'     ($text -match '@p')
Check 'base64 has no characters wt would split' ($b64 -notmatch '[;\s"]')

if ($fail) { Write-Host "`n$fail failed"; exit 1 }
Write-Host "`nall passed"
