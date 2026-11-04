# Night City theme for PowerShell 7.6.9 (PSReadLine 3.x)
# Dot-source from your profile: . "C:\Users\jtjex\Desktop\pwsh\themes\powershell-7.6.9 - Night City.ps1"

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
            ContinuationPrompt    = $fg.brightCyan
            Emphasis              = $fg.brightWhite
            Error                 = $fg.brightRed
            Selection             = $selection
            Comment               = $fg.brightBlack
            Keyword               = $fg.brightPurple
            String                = $fg.brightGreen
            Operator              = $fg.brightBlue
            Variable              = $fg.foreground
            Command               = $fg.brightCyan
            Parameter             = $fg.cyan
            Type                  = $fg.cyan
            Number                = $fg.brightYellow
            Member                = $fg.brightBlue
            DefaultToken          = $fg.foreground
            InlinePrediction      = $fg.brightBlack
            ListPrediction        = $fg.brightBlack
            ListPredictionSelected = $selection
        }
    } catch {
        Write-Warning "Night City: could not apply PSReadLine colors - $($_.Exception.Message)"
    }

    $PSStyle.OutputRendering = 'Host'

    $PSStyle.Formatting.Error = $fg.brightRed
    $PSStyle.Formatting.ErrorAccent = $fg.brightRed
    $PSStyle.Formatting.Warning = $fg.brightYellow
    $PSStyle.Formatting.Verbose = $fg.brightCyan
    $PSStyle.Formatting.Debug = $fg.cyan
    $PSStyle.Formatting.FormatAccent = $fg.brightPurple
    $PSStyle.Formatting.TableHeader = $fg.brightCyan
    $PSStyle.Formatting.CustomTableHeaderLabel = $fg.brightPurple
    $PSStyle.Formatting.FeedbackName = $fg.brightCyan
    $PSStyle.Formatting.FeedbackText = $fg.foreground
    $PSStyle.Formatting.FeedbackAction = $fg.brightYellow

    $PSStyle.FileInfo.Directory = $fg.brightBlue
    $PSStyle.FileInfo.Executable = $fg.brightGreen
    $PSStyle.FileInfo.SymbolicLink = $fg.brightCyan
}
