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

    process {
        # sanitization helper (normalize, collapse doubled single-quotes, collapse whitespace)
        $safe = {
            param($s)
            if (-not $s) { return '' }
            $str = [string]$s
            $str = Convert-TextNormalized $str
            $str = $str -replace "''+", "'"
            $str = ($str -replace '\s+',' ').Trim()
            return $str
        }

        $artistClean = & $safe $Artist
        $trackClean  = & $safe $Track
        $albumClean  = & $safe $Album

        $parts = @()
        if ($artistClean) { $parts += $artistClean }
        if ($trackClean)  { $parts += $trackClean }
        if ($albumClean)  { $parts += $albumClean }

        $query = ($parts -join ' ').Trim()
        $escaped = [uri]::EscapeDataString($query)
        $url = "https://www.qobuz.com/be-nl/search/tracks/$escaped"
        Write-Output $url
    }
}
