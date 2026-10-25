# Toast + terminal-bell notification when a command finishes or fails.
# Bell triggers Windows Terminal's bellStyle (audible/window/taskbar) set in settings.json.

# BurntToast is installed by the installer and autoloads on first use of New-BurntToastNotification.
# (This file used to install it at every shell start and mark PSGallery as trusted machine-wide.)

# Commands running at least this long trigger a notification when they finish.
$global:NotifyThresholdSeconds = 8

$global:NotifyIconPath = "$PSScriptRoot\pwsh-icon.png"

function global:Send-TaskNotification {
    param(
        [string]$Title = "Notification",
        [string]$Message = "Task complete"
    )

    [Console]::Out.Write([char]7)

    if (Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue) {
        try {
            if (Test-Path $global:NotifyIconPath) {
                New-BurntToastNotification -Text $Title, $Message -AppLogo $global:NotifyIconPath
            }
            else {
                New-BurntToastNotification -Text $Title, $Message
            }
        }
        catch {}
    }
}

function notify {
    param(
        [Parameter(Position = 0)]
        [string]$Message = "Task complete"
    )

    Send-TaskNotification -Title "Notification" -Message $Message
}

# Capture the prompt this wraps. `reload` re-sources the profile, at which
# point `prompt` is already the wrapper below - capturing that would make the
# wrapper call itself and blow the call stack, so recognise it by its marker
# and keep the prompt it originally wrapped instead.
$script:currentPrompt = if (Test-Path Function:\prompt) { ${function:prompt} } else { $null }

if ($script:currentPrompt -and $script:currentPrompt.ToString() -notmatch '__RabbitNotifyWrapper') {
    $global:__PreNotifyPrompt = $script:currentPrompt
}
elseif (-not $global:__PreNotifyPrompt) {
    $global:__PreNotifyPrompt = { "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) " }
}

function global:prompt {
    # __RabbitNotifyWrapper - do not remove, see the capture logic above.

    $commandSucceeded = $?
    $hist = Get-History -Count 1

    if ($hist -and $hist.Id -ne $global:__LastNotifiedHistoryId) {

        $duration = $hist.EndExecutionTime - $hist.StartExecutionTime
        $failed = -not $commandSucceeded

        if ($failed -or $duration.TotalSeconds -ge $global:NotifyThresholdSeconds) {

            $global:__LastNotifiedHistoryId = $hist.Id

            $cmdText = $hist.CommandLine
            if ($cmdText.Length -gt 60) {
                $cmdText = $cmdText.Substring(0, 57) + "..."
            }

            $title = if ($failed) { "Command failed" } else { "Command finished" }

            Send-TaskNotification -Title $title -Message "$cmdText ($([int]$duration.TotalSeconds)s)"
        }
    }

    & $global:__PreNotifyPrompt
}
