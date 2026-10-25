# =============================================================================
# modules.psd1 - PowerShell modules, installed for PowerShell 7 (CurrentUser)
#
# Gallery   : installed from PSGallery with Install-PSResource / Install-Module
# Git       : your own modules that are not on the Gallery, cloned over HTTPS
#
# Nothing is vendored in the repo: every module below is obtainable online, so
# there is no Modules\ folder to keep in sync (the old one held two unusable
# source checkouts - PSReadLine and dbatools - and was gitignored anyway).
#
# MinimumVersion is only enforced when set. PSReadLine ships inside PowerShell 7,
# so it is only upgraded if the shipped copy is older than MinimumVersion.
# =============================================================================
@{
    Gallery = @(
        @{ Name = 'Terminal-Icons' }
        @{ Name = 'PSReadLine';          MinimumVersion = '2.3.6' }
        @{ Name = 'PSWriteColor' }
        @{ Name = 'syntax-highlighting' }
        @{ Name = 'PSEverything' }
        @{ Name = 'PSFzf' }
        @{ Name = 'BurntToast' }
        @{ Name = 'PSCompletions' }
    )

    Git = @(
        @{ Name = 'YouShouldUse'; Url = 'https://github.com/ADHD-exe/pwsh-you-should-use.git' }
    )
}
