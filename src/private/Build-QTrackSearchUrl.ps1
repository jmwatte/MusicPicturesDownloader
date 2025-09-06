<#
.SYNOPSIS
    Builds a Qobuz search URL for tracks.
.DESCRIPTION
    Constructs the Qobuz search URL for tracks using the provided artist, track, and optional album.
.PARAMETER Track
    The track name.
.PARAMETER Artist
    The artist name.
.PARAMETER Album
    The album name (optional).
#>
function New-QTrackSearchUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Track,
        [Parameter(Mandatory)]
        [string]$Artist,
        [string]$Album
    )
    $parts = @($Artist,$Track)
    if ($Album) { $parts += $Album }
    $query = ($parts -join ' ').Trim()
    $escaped = [uri]::EscapeDataString($query)
    $url = "https://www.qobuz.com/be-nl/search/tracks/$escaped"
    return $url
}
