# =============================================================================
# Json.ps1 - Windows Terminal settings merge
#
# Merge rules (the repo template is "yours", the machine file is "theirs"):
#   scalars / objects      template value wins, machine-only keys are kept
#   profiles.defaults      deep-merged, template wins per key
#   profiles.list          matched by guid; template entries replace same-guid
#                          machine entries, machine-only entries (WSL distros,
#                          Azure Cloud Shell, VS prompts...) are kept
#   schemes / themes       matched by name, same rule
#   actions                matched by id, same rule
#   keybindings            matched by keys, same rule
#   any other array        template replaces machine
#
# Requires PowerShell 7: Windows Terminal's own generated settings.json contains
# // comments, which Windows PowerShell 5.1's ConvertFrom-Json rejects.
# =============================================================================

function Get-WindowsTerminalTargets {
    <# Every settings.json location that exists (or, for the stable package, may be created). #>
    $local = $env:LOCALAPPDATA

    $candidates = @(
        @{ Kind = 'Stable (packaged)';  Dir = Join-Path $local 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState';        Create = $true  }
        @{ Kind = 'Preview (packaged)'; Dir = Join-Path $local 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState'; Create = $false }
        @{ Kind = 'Unpackaged';         Dir = Join-Path $local 'Microsoft\Windows Terminal';                                          Create = $false }
    )

    # A package family name can differ from the stable id on unusual builds - ask Windows when possible.
    if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
        $pkg = Get-AppxPackage -Name 'Microsoft.WindowsTerminal' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pkg) {
            $candidates[0].Dir = Join-Path $local ("Packages\{0}\LocalState" -f $pkg.PackageFamilyName)
        }
    }

    foreach ($c in $candidates) {
        if ((Test-Path -LiteralPath $c.Dir) -or $c.Create) {
            [pscustomobject]@{ Kind = $c.Kind; Directory = $c.Dir; Settings = (Join-Path $c.Dir 'settings.json'); CanCreate = $c.Create }
        }
    }
}

function ConvertTo-PlainJsonObject {
    <# Parses JSON(C) text into PSCustomObjects. PS7's parser accepts // comments. #>
    param([Parameter(Mandatory)][string]$Text)
    return ($Text | ConvertFrom-Json -ErrorAction Stop)
}

function Merge-ObjectByKey {
    <# Merges two arrays of objects on a key property. Template entries replace same-key machine entries; order = machine first, then new template entries. #>
    param($Machine, $Template, [Parameter(Mandatory)][string]$KeyScript)

    $keyOf = [scriptblock]::Create($KeyScript)
    $result = New-Object System.Collections.Generic.List[object]
    $index  = @{}

    foreach ($m in @($Machine)) {
        if ($null -eq $m) { continue }
        $k = [string](& $keyOf $m)
        $index[$k] = $result.Count
        $result.Add($m)
    }

    foreach ($t in @($Template)) {
        if ($null -eq $t) { continue }
        $k = [string](& $keyOf $t)

        if ($index.ContainsKey($k)) { $result[$index[$k]] = $t }
        else { $index[$k] = $result.Count; $result.Add($t) }
    }

    return , $result.ToArray()
}

function Merge-PlainObject {
    <# Deep-merges two PSCustomObjects; $Template wins on conflicts, machine-only keys survive. #>
    param($Machine, $Template)

    # The unary comma stops PowerShell from unrolling a one-element array into a
    # bare object on return - Windows Terminal needs newTabMenu etc. to stay arrays.
    if ($null -eq $Machine) { if ($Template -is [array]) { return , $Template } else { return $Template } }
    if ($null -eq $Template) { if ($Machine -is [array]) { return , $Machine } else { return $Machine } }

    $isObj = { param($o) $o -is [System.Management.Automation.PSCustomObject] }

    if (-not ((& $isObj $Machine) -and (& $isObj $Template))) {
        if ($Template -is [array]) { return , $Template } else { return $Template }
    }

    $out = [ordered]@{}
    foreach ($p in $Machine.PSObject.Properties)  { $out[$p.Name] = $p.Value }
    foreach ($p in $Template.PSObject.Properties) {
        if ($out.Contains($p.Name)) { $out[$p.Name] = Merge-PlainObject -Machine $out[$p.Name] -Template $p.Value }
        else { $out[$p.Name] = $p.Value }
    }

    return [pscustomobject]$out
}

function Merge-TerminalSettings {
    <# Returns the merged settings as a PSCustomObject. Throws on unparsable input. #>
    param([Parameter(Mandatory)]$Machine, [Parameter(Mandatory)]$Template)

    $arrayRules = @{
        'schemes'     = '$_.name'
        'themes'      = '$_.name'
        'actions'     = 'if ($_.id) { $_.id } else { ($_ | ConvertTo-Json -Depth 10 -Compress) }'
        'keybindings' = '$_.keys'
    }

    $out = [ordered]@{}
    foreach ($p in $Machine.PSObject.Properties) { $out[$p.Name] = $p.Value }

    foreach ($p in $Template.PSObject.Properties) {
        $name = $p.Name

        if ($name -eq 'profiles') {
            $mp = $Machine.profiles
            $tp = $p.Value

            if ($null -eq $mp -or $mp -isnot [System.Management.Automation.PSCustomObject]) {
                $out['profiles'] = $tp
                continue
            }

            $merged = [ordered]@{}
            foreach ($q in $mp.PSObject.Properties) { $merged[$q.Name] = $q.Value }

            $merged['defaults'] = Merge-PlainObject -Machine $mp.defaults -Template $tp.defaults

            $merged['list'] = Merge-ObjectByKey -Machine $mp.list -Template $tp.list -KeyScript '$_ = $args[0]; $_.guid'
            $out['profiles'] = [pscustomobject]$merged
            continue
        }

        if ($arrayRules.ContainsKey($name)) {
            $out[$name] = Merge-ObjectByKey -Machine $Machine.$name -Template $p.Value -KeyScript ('$_ = $args[0]; ' + $arrayRules[$name])
            continue
        }

        if ($out.Contains($name)) { $out[$name] = Merge-PlainObject -Machine $out[$name] -Template $p.Value }
        else { $out[$name] = $p.Value }
    }

    return [pscustomobject]$out
}

function Test-TerminalSettings {
    <# Sanity checks on a merged settings object. Returns a list of problem strings (empty = fine). #>
    param([Parameter(Mandatory)]$Settings)

    $problems = New-Object System.Collections.Generic.List[string]

    $guids = @($Settings.profiles.list | ForEach-Object { $_.guid })

    if ($Settings.defaultProfile -and ($guids -notcontains $Settings.defaultProfile)) {
        # The generated PowerShell profile is created from a *source*, so a guid for a dynamic profile is legal even if absent.
        $problems.Add("defaultProfile $($Settings.defaultProfile) is not in profiles.list")
    }

    $dupes = $guids | Group-Object | Where-Object { $_.Count -gt 1 }
    foreach ($d in $dupes) { $problems.Add("duplicate profile guid $($d.Name)") }

    $actionIds = @($Settings.actions | Where-Object { $_.id } | ForEach-Object { $_.id })
    foreach ($kb in @($Settings.keybindings)) {
        if ($kb.id -and ($kb.id -notlike 'Terminal.*') -and ($actionIds -notcontains $kb.id)) {
            $problems.Add("keybinding $($kb.keys) references unknown action id $($kb.id)")
        }
    }

    foreach ($p in @($Settings.profiles.list)) {
        $scheme = $p.colorScheme
        if ($scheme -and (@($Settings.schemes | ForEach-Object { $_.name }) -notcontains $scheme) -and ($scheme -notmatch '^(Campbell|Campbell Powershell|One Half Dark|One Half Light|Solarized Dark|Solarized Light|Tango Dark|Tango Light|Vintage|Ubuntu-.*)$')) {
            $problems.Add("profile '$($p.name)' uses unknown colorScheme '$scheme'")
        }
    }

    return $problems
}
