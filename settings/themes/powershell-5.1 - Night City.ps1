# Night City theme for Windows PowerShell 5.1 (PSReadLine 2.x)
# Dot-source from your profile: . "C:\Users\jtjex\Desktop\pwsh\themes\powershell-5.1 - Night City.ps1"

& {
    $esc = [char]27

    $nightCity = @{
        background     = '#020005'
        foreground     = '#7C90FF'
        black          = '#141C1F'
        red            = '#D636D3'
        green          = '#1AC990'
        yellow         = '#DED326'
        blue           = '#4E03C2'
        purple         = '#7600C4'
        cyan           = '#00A3B5'
        white          = '#6364C4'
        brightBlack    = '#393F59'
        brightRed      = '#F301FF'
        brightGreen    = '#02FFBF'
        brightYellow   = '#FFF77C'
        brightBlue     = '#6829FF'
        brightPurple   = '#9900FF'
        brightCyan     = '#3DD8FF'
        brightWhite    = '#8B97FF'
        cursor         = '#00FFFF'
        selection      = '#4A7AFF'
    }

    function ConvertTo-AnsiFg([string]$hex) {
        $h = $hex.TrimStart('#')
        $r = [Convert]::ToInt32($h.Substring(0, 2), 16)
        $g = [Convert]::ToInt32($h.Substring(2, 2), 16)
        $b = [Convert]::ToInt32($h.Substring(4, 2), 16)
        "$esc[38;2;$r;$g;${b}m"
    }

    function ConvertTo-AnsiBg([string]$hex) {
        $h = $hex.TrimStart('#')
        $r = [Convert]::ToInt32($h.Substring(0, 2), 16)
        $g = [Convert]::ToInt32($h.Substring(2, 2), 16)
        $b = [Convert]::ToInt32($h.Substring(4, 2), 16)
        "$esc[48;2;$r;$g;${b}m"
    }

    $fg = @{}
    foreach ($key in $nightCity.Keys) { $fg[$key] = ConvertTo-AnsiFg $nightCity[$key] }
    $selection = (ConvertTo-AnsiBg $nightCity.selection) + (ConvertTo-AnsiFg $nightCity.background)

    try {
        Set-PSReadLineOption -Colors @{
            ContinuationPrompt = $fg.brightCyan
            Emphasis           = $fg.brightWhite
            Error              = $fg.brightRed
            Selection          = $selection
            Comment            = $fg.brightBlack
            Keyword            = $fg.brightPurple
            String             = $fg.brightGreen
            Operator           = $fg.brightBlue
            Variable           = $fg.foreground
            Command            = $fg.brightCyan
            Parameter          = $fg.cyan
            Type               = $fg.cyan
            Number             = $fg.brightYellow
            Member             = $fg.brightBlue
            Default            = $fg.foreground
        }
    } catch {
        Write-Warning "Night City: could not apply PSReadLine colors - $($_.Exception.Message)"
    }

    $Host.PrivateData.ErrorForegroundColor = 'Magenta'
    $Host.PrivateData.ErrorBackgroundColor = 'Black'
    $Host.PrivateData.WarningForegroundColor = 'Yellow'
    $Host.PrivateData.WarningBackgroundColor = 'Black'
    $Host.PrivateData.VerboseForegroundColor = 'Cyan'
    $Host.PrivateData.VerboseBackgroundColor = 'Black'
    $Host.PrivateData.DebugForegroundColor = 'Cyan'
    $Host.PrivateData.DebugBackgroundColor = 'Black'
    $Host.PrivateData.ProgressForegroundColor = 'Cyan'
    $Host.PrivateData.ProgressBackgroundColor = 'Black'
}
