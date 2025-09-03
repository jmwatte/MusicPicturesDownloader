<#
.SYNOPSIS
    Query Last.fm for top tags and write them into an audio file's genre tag.
.DESCRIPTION
    Reads metadata from an audio file, queries Last.fm for top tags (track->album->artist fallback), normalizes
    the tags and writes them into the file using ffmpeg. Supports dry-run and Replace mode.
#>
function Update-TrackGenresFromLastFm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string] $AudioFilePath,
        [int] $MaxTags = 3,
        [ValidateSet('lower','camel','title')] [string] $Case = 'lower',
        [string] $Joiner = ';',
        [switch] $Replace,
        [switch] $DryRun,
        [string] $ApiKey
    )

    if (-not (Test-Path $AudioFilePath)) { throw "Audio file not found: $AudioFilePath" }

    $meta = Get-TrackMetadataFromFile -AudioFilePath $AudioFilePath
    Write-Verbose ("[Update-TrackGenresFromLastFm] Read tags: Title={0}, Album={1}, Artist={2}" -f $meta.Title, $meta.Album, $meta.Artist)

    $tags = Get-LastFmTopTags -ApiKey $ApiKey -Artist $meta.Artist -Track $meta.Title -Album $meta.Album -MaxTags $MaxTags
    if (-not $tags -or $tags.Count -eq 0) { Write-Verbose "No tags returned from Last.fm"; return $null }

    $norm = ConvertTo-Genres -Tags $tags -Case $Case -Max $MaxTags -Joiner $Joiner
    $genresStr = $norm -join $Joiner

    Write-Output "Found genres: $genresStr"
    if ($DryRun) { Write-Output "Dry-run: not writing tags"; return @{ AudioFile=$AudioFilePath; Genres=$norm; Written='dry-run' } }

    $ok = Set-FileGenresWithFFmpeg -AudioFilePath $AudioFilePath -Genres $norm -Replace:$Replace
    if ($ok) {
        Write-Output @{ AudioFile=$AudioFilePath; Genres=$norm; Written=$AudioFilePath }
        return $true
    }
    return $false
}
