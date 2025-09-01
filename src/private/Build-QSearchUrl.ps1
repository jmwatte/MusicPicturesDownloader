<#
.SYNOPSIS
Builds a Q search URL for an album.
#>

function Build-QSearchUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Album,
        [Parameter(Mandatory = $true)]
        [string]$Artist,
        [string]$Culture = 'be-nl'
    )

    process {
        # Combine album and artist for search, normalize spaces, then URL-encode
        $search = "$Album $Artist" -replace '\s+', ' '
        $encoded = [System.Uri]::EscapeDataString($search)
        $url = "https://www.qobuz.com/$Culture/search/albums/$encoded"
        Write-Output $url
    }
}

# Export-ModuleMember removed from private helper; public exports are handled in MusicPicturesDownloader.psm1
