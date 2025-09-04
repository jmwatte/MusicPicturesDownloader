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
    [switch] $Merge,
    [switch] $DryRun,
    [switch] $ConfirmEach,
    [string] $ApiKey
    )

    if (-not (Test-Path -LiteralPath $AudioFilePath)) { throw "Audio file not found: $AudioFilePath" }

    $meta = Get-TrackMetadataFromFile -AudioFilePath $AudioFilePath
    Write-Verbose ("[Update-TrackGenresFromLastFm] Read tags: Title={0}, Album={1}, Artist={2}" -f $meta.Title, $meta.Album, $meta.Artist)

    $tags = Get-LastFmTopTags -ApiKey $ApiKey -Artist $meta.Artist -Track $meta.Title -Album $meta.Album -MaxTags $MaxTags
    if (-not $tags -or $tags.Count -eq 0) { Write-Verbose "No tags returned from Last.fm"; return $null }

    $norm = ConvertTo-Genres -Tags $tags -Case $Case -Max $MaxTags -Joiner $Joiner
    $genresStr = $norm -join $Joiner

    Write-Output "Found genres: $genresStr"
    if ($DryRun) { Write-Output "Dry-run: not writing tags"; return @{ AudioFile=$AudioFilePath; Genres=$norm; Written='dry-run' } }

    # If Merge requested (or not Replace), combine existing genres and new ones
    if ($Merge -or -not $Replace) {
        # read existing genres from file
        $existing = $null
        try { $existingMeta = Get-TrackMetadataFromFile -AudioFilePath $AudioFilePath -ErrorAction SilentlyContinue } catch { $existingMeta = $null }
        if ($existingMeta -and $existingMeta.Tags -and $existingMeta.Tags.ContainsKey('genre')) {
            $existing = ($existingMeta.Tags['genre'] -as [string]) -split '[;\s]+' | Where-Object { $_ -ne '' }
        } else { $existing = @() }

        # merge preserving order: existing first, then new ones not already present
        $merged = @()
        foreach ($g in $existing) { if ($g -and -not ($merged -contains $g)) { $merged += $g } }
        foreach ($g in $norm) { if ($g -and -not ($merged -contains $g)) { $merged += $g } }

        # normalize and trim merged list
        $final = $merged | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -ne '' }
    } else {
        $final = $norm
    }

    # Interactive per-file confirmation (if requested)
    if ($ConfirmEach) {
        # show existing genres (fresh read to show latest) and the new ones
        $existing = @()
        try { $existingMeta = Get-TrackMetadataFromFile -AudioFilePath $AudioFilePath -ErrorAction SilentlyContinue } catch { $existingMeta = $null }
        if ($existingMeta -and $existingMeta.Tags -and $existingMeta.Tags.ContainsKey('genre')) {
            $existing = ($existingMeta.Tags['genre'] -as [string]) -split '[;\s]+' | Where-Object { $_ -ne '' }
        }
        $oldStr = ($existing -join $Joiner)
        if (-not $oldStr) { $oldStr = '<none>' }
        $newStr = ($final -join $Joiner)
        Write-Output ("About to write genres to file: {0}" -f $AudioFilePath)
        Write-Output ("Existing: {0}" -f $oldStr)
        Write-Output ("New: {0}" -f $newStr)
        $ans = Read-Host -Prompt "Press Enter to write, 'n' to skip, 'q' to abort"
        if ($ans -eq 'q') { Write-Output 'Aborted by user'; return $false }
        if ($ans -eq 'n') { Write-Output @{ AudioFile=$AudioFilePath; Genres=$final; Written='skipped' }; return $true }
    }

    $res = Set-FileGenresWithFFmpeg -AudioFilePath $AudioFilePath -Genres $final -Replace:$true
    if ($res -and $res.Ok) {
        # Provide a concise verbose summary: file: <file> old genre:<old> new genre:<new>
    $old = @()
    if ($res.OldGenres) { $old = $res.OldGenres }
    $old = $old -join $Joiner
        if (-not $old) { $old = '<none>' }
        $new = $norm -join $Joiner
        Write-Verbose ("file: {0} old genre:{1} new genre:{2}" -f $AudioFilePath, $old, $new)
        Write-Output @{ AudioFile=$AudioFilePath; Genres=$norm; Written=$AudioFilePath }
        return $true
    }
    return $false
}
