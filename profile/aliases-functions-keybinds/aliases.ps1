# =========================================================
# Rabbit Aliases
# =========================================================
Set-Alias ss Take-Screenshot
Set-Alias ssw Take-WindowScreenshot
Set-Alias ssr Take-RegionScreenshot
Set-Alias info Get-Help
Set-Alias ep Edit-Profile
Set-Alias omp oh-my-posh
 
function oc { opencode @args }

# Firefox Developer Edition (installed by the installer's Tools tier). A function, so `firefox` works even
# in a session that started before the install folder reached PATH.
function firefox {
    $exe = @("$env:ProgramFiles\Firefox Developer Edition\firefox.exe", "${env:ProgramFiles(x86)}\Firefox Developer Edition\firefox.exe") |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $exe) { Write-Warning 'Firefox Developer Edition is not installed - re-run the installer (Tools tier).'; return }
    if ($args.Count -gt 0) { Start-Process -FilePath $exe -ArgumentList $args } else { Start-Process -FilePath $exe }
}
Set-Alias oco opencode
Set-Alias c clear
Set-Alias cls clear
Set-Alias vim nvim
Set-Alias v nvim

Set-Alias y yy

Set-Alias reload Reload-Profile
Set-Alias rl Reload-Profile
Set-Alias profile Edit-Profile

Set-Alias rsex Restart-Explorer
Set-Alias reboot Restart-System


Set-Alias grep Select-String
Set-Alias ai opencode

if (Get-Command bat -ErrorAction SilentlyContinue) {
    Set-Alias cat bat
}


function ctt {
    irm "christitus.com/win" | iex
}

function ws { winget search @args }
function wi { winget install @args }
function wl { winget list @args }
function wr { winget repair @args }
function wun { winget uninstall @args }


function ssc { Take-Screenshot -Clipboard -NoFile @args }


# ls / ll / la / lt are eza functions in functions.ps1. PowerShell ships `ls`
# as a built-in alias for Get-ChildItem, and aliases outrank functions, so the
# alias has to go or the function can never run.
Remove-Alias ls -Force -ErrorAction SilentlyContinue

# Same reason: `man` ships as an alias for `help`, which would shadow the man
# function in functions.ps1 that defaults to Get-Help -Full.
Remove-Alias man -Force -ErrorAction SilentlyContinue



# =========================================================
# Screenshots
# =========================================================

$script:ScreenshotDir = Join-Path $HOME "Pictures\Screenshots"

# Loaded on first use: compiling this at every shell start cost hundreds of milliseconds.
function Initialize-ScreenshotTypes {
    if ($script:ScreenshotTypesLoaded) { return }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    if (-not ("ScreenshotHelper.Win32" -as [type])) {
        Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    namespace ScreenshotHelper {
        public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
        public class Win32 {
            [DllImport("user32.dll")]
            public static extern IntPtr GetForegroundWindow();
            [DllImport("user32.dll")]
            public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
        }
    }
"@
    }
    $script:ScreenshotTypesLoaded = $true
}

function New-ScreenshotPath {
    param([string]$Prefix = "Screenshot")
    if (-not (Test-Path $script:ScreenshotDir)) {
        New-Item -ItemType Directory -Path $script:ScreenshotDir -Force | Out-Null
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    return Join-Path $script:ScreenshotDir "$Prefix`_$timestamp.png"
}

function Save-ScreenshotBitmap {
    param(
        $Bitmap,
        [string]$Path,
        [switch]$Clipboard,
        [switch]$NoFile
    )
    Initialize-ScreenshotTypes
    if ($Clipboard) {
        [System.Windows.Forms.Clipboard]::SetImage($Bitmap)
    }
    if (-not $NoFile) {
        $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        return $Path
    }
}

function Take-Screenshot {
    # Full screen (all monitors) screenshot.
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$Clipboard,
        [switch]$NoFile,
        [switch]$Open,
        [int]$Delay = 0
    )
    Initialize-ScreenshotTypes
    if ($Delay -gt 0) { Start-Sleep -Seconds $Delay }

    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)

    if (-not $Path) { $Path = New-ScreenshotPath -Prefix "Full" }
    $saved = Save-ScreenshotBitmap -Bitmap $bitmap -Path $Path -Clipboard:$Clipboard -NoFile:$NoFile

    $graphics.Dispose()
    $bitmap.Dispose()

    if ($saved) {
        Write-Host "Screenshot saved: $saved" -ForegroundColor Green
        if ($Open) { Invoke-Item $saved }
        return $saved
    } elseif ($Clipboard) {
        Write-Host "Screenshot copied to clipboard" -ForegroundColor Green
    }
}

function Take-WindowScreenshot {
    # Screenshot of the current foreground (active) window.
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$Clipboard,
        [switch]$NoFile,
        [switch]$Open,
        [int]$Delay = 0
    )
    Initialize-ScreenshotTypes
    if ($Delay -gt 0) { Start-Sleep -Seconds $Delay }

    $hwnd = [ScreenshotHelper.Win32]::GetForegroundWindow()
    $rect = New-Object ScreenshotHelper.RECT
    [ScreenshotHelper.Win32]::GetWindowRect($hwnd, [ref]$rect) | Out-Null

    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top

    if ($width -le 0 -or $height -le 0) {
        Write-Warning "Could not determine window bounds."
        return
    }

    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $width, $height))

    if (-not $Path) { $Path = New-ScreenshotPath -Prefix "Window" }
    $saved = Save-ScreenshotBitmap -Bitmap $bitmap -Path $Path -Clipboard:$Clipboard -NoFile:$NoFile

    $graphics.Dispose()
    $bitmap.Dispose()

    if ($saved) {
        Write-Host "Window screenshot saved: $saved" -ForegroundColor Green
        if ($Open) { Invoke-Item $saved }
        return $saved
    } elseif ($Clipboard) {
        Write-Host "Window screenshot copied to clipboard" -ForegroundColor Green
    }
}

function Take-RegionScreenshot {
    # Interactive rectangle/freeform/window snip via the built-in Snip & Sketch overlay.
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$NoFile,
        [switch]$Open,
        [int]$TimeoutSeconds = 30
    )
    Initialize-ScreenshotTypes
    try { [System.Windows.Forms.Clipboard]::Clear() } catch {}

    Start-Process "ms-screenclip:"
    Write-Host "Select a region to capture (Esc to cancel)..." -ForegroundColor Yellow

    $elapsedMs = 0
    $found = $false
    while ($elapsedMs -lt ($TimeoutSeconds * 1000)) {
        Start-Sleep -Milliseconds 500
        $elapsedMs += 500
        if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
            $found = $true
            break
        }
    }

    if (-not $found) {
        Write-Warning "No screenshot captured (timed out or cancelled)."
        return
    }

    if ($NoFile) {
        Write-Host "Region screenshot copied to clipboard" -ForegroundColor Green
        return
    }

    $image = [System.Windows.Forms.Clipboard]::GetImage()
    if (-not $Path) { $Path = New-ScreenshotPath -Prefix "Region" }
    $image.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "Region screenshot saved: $Path" -ForegroundColor Green
    if ($Open) { Invoke-Item $Path }
    return $Path
}

