<#
.SYNOPSIS
Builds a Q search URL for an album.
#>
function Build-QSearchUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Album,
        [string]$Culture = 'be-nl'
    )

    process {
        # Normalize spaces then URL-encode
        $normalized = $Album -replace '\s+', ' '
        $encoded = [System.Uri]::EscapeDataString($normalized)
        $url = "https://www.qobuz.com/$Culture/search/albums/$encoded"
        Write-Output $url
    }
}

# Export-ModuleMember removed from private helper; public exports are handled in MusicPicturesDownloader.psm1
