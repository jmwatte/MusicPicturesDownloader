<#
.SYNOPSIS
    Query Last.fm for top tags for a track, album or artist.
.PARAMETER ApiKey
    Last.fm API key. If omitted reads $env:LASTFM_API_KEY or lastFMKeys.json locally.
.PARAMETER Artist
    Artist name.
.PARAMETER Track
    Track title (optional).
.PARAMETER Album
    Album title (optional).
.PARAMETER MaxTags
    Max number of tags to return.
.OUTPUTS
    Array of tag strings ordered by relevance.
#>
function Get-LastFmTopTags {
    [CmdletBinding()]
    param(
        [string] $ApiKey,
        [string] $Artist,
        [string] $Track,
        [string] $Album,
        [int] $MaxTags = 3
    )

    if (-not $ApiKey) {
        if ($env:LASTFM_API_KEY) { $ApiKey = $env:LASTFM_API_KEY }
        else {
            # Try a few common locations for lastFMKeys.json: script path, current dir, and parents
            $candidates = @()
            # script path based candidate
            try { if ($MyInvocation -and $MyInvocation.MyCommand.Path) { $p = Split-Path -Path $MyInvocation.MyCommand.Path -Parent; $candidates += (Join-Path -Path $p -ChildPath '..\..\lastFMKeys.json') } } catch {}
            # current working dir and parents
            try {
                $dir = Get-Location
                while ($dir -and ($candidates.Count -lt 8)) {
                    $candidates += (Join-Path -Path $dir.Path -ChildPath 'lastFMKeys.json')
                    $parent = Split-Path -Path $dir.Path -Parent
                    if (-not $parent -or $parent -eq $dir.Path) { break }
                    $dir = Get-Item -Path $parent
                }
            } catch {}

            foreach ($cf in $candidates) {
                if ($cf -and (Test-Path $cf)) {
                    try { $j = Get-Content $cf -Raw | ConvertFrom-Json; if ($j.APIKey) { $ApiKey = $j.APIKey; break } } catch {}
                }
            }
        }
    }

    if (-not $ApiKey) { throw 'Last.fm API key not provided. Set $env:LASTFM_API_KEY or create lastFMKeys.json next to the repo root.' }

    $results = @()
    $base = 'http://ws.audioscrobbler.com/2.0/'

    # Try track.getTopTags when track+artist provided
    if ($Track -and $Artist) {
        $q = @{ method='track.gettoptags'; artist=$Artist; track=$Track; api_key=$ApiKey; format='json' }
        $url = $base + '?' + ($q.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" } -join '&')
        try { $resp = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop } catch { $resp = $null }
        if ($resp -and $resp.toptags -and $resp.toptags.tag) {
            $resp.toptags.tag | ForEach-Object { $results += $_.name }
        }
    }

    # If no track tags, try album
    if (($results.Count -eq 0) -and $Album -and $Artist) {
        $q = @{ method='album.gettoptags'; artist=$Artist; album=$Album; api_key=$ApiKey; format='json' }
        $url = $base + '?' + ($q.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" } -join '&')
        try { $resp = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop } catch { $resp = $null }
        if ($resp -and $resp.toptags -and $resp.toptags.tag) { $resp.toptags.tag | ForEach-Object { $results += $_.name } }
    }

    # Fallback: artist.getTopTags
    if ($results.Count -eq 0 -and $Artist) {
        $q = @{ method='artist.gettoptags'; artist=$Artist; api_key=$ApiKey; format='json' }
        $url = $base + '?' + ($q.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" } -join '&')
        try { $resp = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop } catch { $resp = $null }
        if ($resp -and $resp.toptags -and $resp.toptags.tag) { $resp.toptags.tag | ForEach-Object { $results += $_.name } }
    }

    # normalize and return top N
    $out = $results | Where-Object { $_ } | ForEach-Object { $_.ToString().Trim() } | Select-Object -Unique | Select-Object -First $MaxTags
    return ,$out
}
