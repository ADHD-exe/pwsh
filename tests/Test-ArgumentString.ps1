# Offline test for ConvertTo-ArgumentString (used for the elevated PATH relaunch).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\bootstrap\lib\Common.ps1')

$fail = 0
function Check($name, $actual, $expected) {
    if ($actual -ceq $expected) { Write-Host "  pass  $name" }
    else { Write-Host "  FAIL  $name`n        expected: $expected`n        actual:   $actual"; $script:fail++ }
}

Write-Host 'ConvertTo-ArgumentString'
Check 'plain args untouched'          (ConvertTo-ArgumentString -Arguments '-NoProfile','-File','x.ps1') '-NoProfile -File x.ps1'
Check 'path with space is quoted'     (ConvertTo-ArgumentString -Arguments '-File','C:\Users\Jane Doe\.pwsh\a.ps1') '-File "C:\Users\Jane Doe\.pwsh\a.ps1"'
Check 'trailing backslash is doubled' (ConvertTo-ArgumentString -Arguments 'C:\My Dir\') '"C:\My Dir\\"'
Check 'embedded quote is escaped'     (ConvertTo-ArgumentString -Arguments 'say "hi" now') '"say \"hi\" now"'
Check 'empty string kept as ""'       (ConvertTo-ArgumentString -Arguments 'a','','b') 'a "" b'

if ($fail) { Write-Host "`n$fail failed"; exit 1 }
Write-Host "`nall passed"
