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
        # 1) Prefer environment variable
        if ($env:LASTFM_API_KEY) { $ApiKey = $env:LASTFM_API_KEY }
        else {
            # 2) Walk upward from a sensible starting folder (PSScriptRoot / MyInvocation / cwd)
            $candidates = @()
            $start = $null
            try { if ($PSScriptRoot) { $start = $PSScriptRoot } } catch {}
            if (-not $start) {
                try { if ($MyInvocation -and $MyInvocation.MyCommand.Path) { $start = Split-Path -Path $MyInvocation.MyCommand.Path -Parent } } catch {}
            }
            if (-not $start) { $start = (Get-Location).Path }

            $dir = $start
            while ($dir) {
                $candidates += (Join-Path -Path $dir -ChildPath 'lastFMKeys.json')
                $parent = Split-Path -Path $dir -Parent
                if (-not $parent -or $parent -eq $dir) { break }
                $dir = $parent
            }

            # also ensure we check current working directory explicitly
            $cwd = (Get-Location).Path
            if ($cwd -and -not ($candidates -contains (Join-Path $cwd 'lastFMKeys.json'))) { $candidates += (Join-Path $cwd 'lastFMKeys.json') }

            foreach ($cf in $candidates) {
                if ($cf -and (Test-Path $cf)) {
                    try {
                        $j = Get-Content $cf -Raw | ConvertFrom-Json
                        # accept various property name casings
                        if ($j.APIKey -or $j.ApiKey -or $j.api_key) {
                            $ApiKey = $j.APIKey ? $j.APIKey : ($j.ApiKey ? $j.ApiKey : $j.api_key)
                            break
                        }
                    } catch {}
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
    $pairs = $q.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" }
    $url = $base + '?' + ($pairs -join '&')
    try { $resp = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop } catch { $resp = $null }
        if ($resp -and $resp.toptags -and $resp.toptags.tag) {
            $resp.toptags.tag | ForEach-Object { $results += $_.name }
        }
    }

    # If no track tags, try album
    if (($results.Count -eq 0) -and $Album -and $Artist) {
    $q = @{ method='album.gettoptags'; artist=$Artist; album=$Album; api_key=$ApiKey; format='json' }
    $pairs = $q.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" }
    $url = $base + '?' + ($pairs -join '&')
    try { $resp = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop } catch { $resp = $null }
        if ($resp -and $resp.toptags -and $resp.toptags.tag) { $resp.toptags.tag | ForEach-Object { $results += $_.name } }
    }

    # Fallback: artist.getTopTags
    if ($results.Count -eq 0 -and $Artist) {
    $q = @{ method='artist.gettoptags'; artist=$Artist; api_key=$ApiKey; format='json' }
    $pairs = $q.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" }
    $url = $base + '?' + ($pairs -join '&')
    try { $resp = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop } catch { $resp = $null }
        if ($resp -and $resp.toptags -and $resp.toptags.tag) { $resp.toptags.tag | ForEach-Object { $results += $_.name } }
    }

    # normalize and return top N
    $out = $results | Where-Object { $_ } | ForEach-Object { $_.ToString().Trim() } | Select-Object -Unique | Select-Object -First $MaxTags
    return ,$out
}
