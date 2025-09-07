<#
.SYNOPSIS
    Simple file-cache for Qobuz artist search results.

.DESCRIPTION
    Cache-QArtistResults provides helper functions to read and write cached
    search results to disk. Caches are stored under $env:TEMP\MusicPicturesDownloader\cache\artists
    with filenames derived from an SHA1 of the query+locale.

.PARAMETER Query
    The artist query string.

.PARAMETER Locale
    Locale string (affects cache key).

.PARAMETER CacheMinutes
    Expiration time in minutes.

.OUTPUTS
    The cached object or $null if no valid cache exists.
#>
function Get-CachedArtistResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string] $Query,
        [Parameter(Mandatory=$false)] [string] $Locale = 'be-nl',
        [int] $CacheMinutes = 60
    )

    process {
    $base = Join-Path -Path $env:TEMP -ChildPath 'MusicPicturesDownloader\cache\artists'
    if (-not (Test-Path -LiteralPath $base)) { New-Item -LiteralPath $base -ItemType Directory -Force | Out-Null }
        $keySource = "$Locale`|$Query"
        $sha = [System.BitConverter]::ToString((New-Object Security.Cryptography.SHA1Managed).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($keySource))).Replace('-','').ToLowerInvariant()
        $file = Join-Path -Path $base -ChildPath "$sha.json"
        if (-not (Test-Path -LiteralPath $file)) { return $null }
        try {
            $fi = Get-Item -LiteralPath $file
            $ageMin = ((Get-Date) - $fi.LastWriteTime).TotalMinutes
            if ($ageMin -gt $CacheMinutes) { return $null }
            $text = Get-Content -LiteralPath $file -Raw
            return ConvertFrom-Json -InputObject $text
        }
        catch {
            Write-Verbose "Failed to read cache file $file : $_"
            return $null
        }
    }
}

function Set-CachedArtistResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string] $Query,
        [Parameter(Mandatory=$true)] [object] $Result,
        [Parameter(Mandatory=$false)] [string] $Locale = 'be-nl'
    )

    process {
        $base = Join-Path -Path $env:TEMP -ChildPath 'MusicPicturesDownloader\cache\artists'
        if (-not (Test-Path -LiteralPath $base)) { New-Item -Path $base -ItemType Directory -Force | Out-Null }
        $keySource = "$Locale`|$Query"
        $sha = [System.BitConverter]::ToString((New-Object Security.Cryptography.SHA1Managed).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($keySource))).Replace('-','').ToLowerInvariant()
        $file = Join-Path -Path $base -ChildPath "$sha.json"
        try {
            $json = $Result | ConvertTo-Json -Depth 5
            # Use Set-Content with -LiteralPath to avoid path parsing issues
            $json | Set-Content -LiteralPath $file -Encoding UTF8
            return $file
        }
        catch {
            Write-Verbose "Failed to write cache file ${file}: ${_}"
            return $null
        }
    }
}
