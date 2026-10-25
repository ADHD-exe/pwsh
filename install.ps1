<#
    install.ps1 - entry point for the pwsh environment bootstrap.

    Works three ways (all from Windows PowerShell 5.1 or PowerShell 7):

      1. One line (convenient; runs code straight from the internet - see README):
           irm https://raw.githubusercontent.com/ADHD-exe/pwsh/main/install.ps1 | iex

      2. With options (still one line):
           & ([scriptblock]::Create((irm https://raw.githubusercontent.com/ADHD-exe/pwsh/main/install.ps1))) -Tier Core,Shell,Tools,Apps

      3. Download, read, then run (recommended the first time):
           irm https://raw.githubusercontent.com/ADHD-exe/pwsh/main/install.ps1 -OutFile install.ps1
           notepad install.ps1
           .\install.ps1

    What THIS file does - and nothing else:
      * downloads the repository as a zip over HTTPS (no git needed yet),
      * prints its SHA-256 (and checks it against -ExpectedSha256 if you pass one),
      * unpacks it to a temp folder and starts bootstrap\Install-Environment.ps1.
    Everything the installer then does is in that folder, in plain scripts.

    Options handled here (everything else is passed to Install-Environment.ps1):
      -Ref <branch|tag|commit>   what to download            (default: main)
      -ExpectedSha256 <hash>     refuse to run if the zip's hash differs
      -DownloadOnly              download + verify + unpack, print the folder, run nothing

    No param() block on purpose: a param block cannot be used with `irm | iex`.
#>

$ErrorActionPreference = 'Stop'

$script:Owner = 'ADHD-exe'
$script:Repo  = 'pwsh'

function ConvertTo-InstallSplat {
    <# Turns the loose command-line tokens in $args into a hashtable that can be splatted. #>
    param([object[]]$Tokens)

    $h = @{}
    $i = 0
    while ($i -lt $Tokens.Count) {
        $t = $Tokens[$i]

        if ($t -is [string] -and $t -match '^-{1,2}([A-Za-z][A-Za-z0-9]*):?$') {
            $name = $Matches[1]
            $next = if ($i + 1 -lt $Tokens.Count) { $Tokens[$i + 1] } else { $null }
            $nextIsValue = ($i + 1 -lt $Tokens.Count) -and -not (($next -is [string]) -and ($next -match '^-{1,2}[A-Za-z]'))

            if ($nextIsValue) { $h[$name] = $next; $i += 2 }
            else              { $h[$name] = $true; $i += 1 }
        }
        else { throw "Unexpected argument '$t'. Use -Name value pairs, e.g. -Tier Core,Shell" }
    }
    return $h
}

function Invoke-PwshBootstrap {
    param([object[]]$Tokens)

    $opts = ConvertTo-InstallSplat -Tokens $Tokens

    $ref      = if ($opts.ContainsKey('Ref')) { [string]$opts['Ref'] } elseif ($opts.ContainsKey('Branch')) { [string]$opts['Branch'] } else { 'main' }
    $expected = if ($opts.ContainsKey('ExpectedSha256')) { ([string]$opts['ExpectedSha256']).Trim().ToLower() } else { $null }
    $dlOnly   = $opts.ContainsKey('DownloadOnly')

    foreach ($k in 'Ref', 'ExpectedSha256', 'DownloadOnly') { [void]$opts.Remove($k) }
    if (-not $opts.ContainsKey('Branch') -and $ref -match '^[A-Za-z0-9._/-]+$') { $opts['Branch'] = $ref }

    if ($env:OS -ne 'Windows_NT') { throw 'This installer configures Windows. Run it on a Windows machine.' }

    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

    # ---- already inside a checkout? run it in place (this is the "download, review, run" path) ----
    $here = if ($PSScriptRoot) { $PSScriptRoot } else { $null }
    $local = if ($here) { Join-Path $here 'bootstrap\Install-Environment.ps1' } else { $null }

    if ($local -and (Test-Path -LiteralPath $local)) {
        Write-Host "Running from the checkout at $here" -ForegroundColor Cyan
        if ($dlOnly) { Write-Host "Nothing to download; the files are in $here"; return }
        $opts['SourceRoot'] = $here
        & $local @opts
        return
    }

    # ---- otherwise fetch the repo as a zip ---------------------------------
    if ($ref -notmatch '^[A-Za-z0-9._/-]+$') { throw "Refusing odd ref '$ref'." }

    $url  = "https://github.com/$script:Owner/$script:Repo/archive/$ref.zip"
    $work = Join-Path ([IO.Path]::GetTempPath()) ("pwsh-bootstrap-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    $zip  = Join-Path $work 'repo.zip'

    New-Item -ItemType Directory -Path $work -Force | Out-Null

    Write-Host "Downloading $url" -ForegroundColor Cyan
    try { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing }
    catch { throw "Download failed ($($_.Exception.Message)). Check the ref '$ref' exists and that github.com is reachable." }

    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
    Write-Host ("  {0:N1} MB   SHA-256 {1}" -f ((Get-Item -LiteralPath $zip).Length / 1MB), $hash)

    if ($expected) {
        if ($hash -ne $expected) { Remove-Item -LiteralPath $work -Recurse -Force; throw "SHA-256 mismatch. Expected $expected, got $hash. Nothing was run." }
        Write-Host '  hash matches -ExpectedSha256' -ForegroundColor Green
    }
    else {
        Write-Host '  (no -ExpectedSha256 given: the hash is shown for your records, not checked)' -ForegroundColor DarkYellow
    }

    Expand-Archive -LiteralPath $zip -DestinationPath $work -Force
    Remove-Item -LiteralPath $zip -Force

    $root = Get-ChildItem -LiteralPath $work -Directory | Select-Object -First 1
    if (-not $root -or -not (Test-Path -LiteralPath (Join-Path $root.FullName 'bootstrap\Install-Environment.ps1'))) {
        throw 'The downloaded archive does not look like this project (bootstrap\Install-Environment.ps1 missing).'
    }

    # Files that arrive from a browser/zip can carry a "downloaded from the internet" mark that RemoteSigned honours.
    Get-ChildItem -LiteralPath $root.FullName -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

    if ($dlOnly) {
        Write-Host "`nUnpacked to $($root.FullName)" -ForegroundColor Green
        Write-Host ('Read it, then run:  & "{0}"' -f (Join-Path $root.FullName 'install.ps1'))
        return
    }

    $opts['SourceRoot'] = $root.FullName
    $exit = 0

    try {
        & (Join-Path $root.FullName 'bootstrap\Install-Environment.ps1') @opts
        $exit = $LASTEXITCODE
    }
    finally {
        # The installer keeps its own permanent copy (~\.pwsh); this temp unpack is disposable.
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($exit) { Write-Host "Installer finished with problems (exit code $exit) - see the summary above." -ForegroundColor Yellow }
}

Invoke-PwshBootstrap -Tokens $args
