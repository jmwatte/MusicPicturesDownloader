## Album-artist vs track-artist: recommended policy and quick filtering scripts

This short guide explains a recommended policy and practical PowerShell recipes for deciding when to use `albumartist` (the album-level artist) vs the per-track `artist` (performing/contributing artist) when calling `Update-GenresForDirectory` or other batch metadata workflows.

Why pre-filter? In many libraries the album artist is the correct choice for album-level metadata (genres, artist-level lookups). But compilations and "various artists" albums should usually be treated per-track. Automatic heuristics are convenient, but a user's library often has exceptions; for highest accuracy it's best to pre-filter your album folders and run the batch tool on the sets you want.

Recommended high-level policy

- Default recommendation: let the user decide by pre-filtering albums into two sets:
  - "Album-level" folders where the album artist applies consistently (use `-PreferAlbumArtist` when running `Update-GenresForDirectory`).
  - "Per-track" folders (compilations / various artists) where each track should be processed individually.
- Rationale: automated heuristics can be wrong for guest-heavy albums, collaborative projects, or mislabeled tags. A short filtering step is fast and deterministic.

Heuristics you can use to detect compilations

1. Tag-based signals (fast)
- `albumartist` equals something like "Various Artists", "VA", "Compilation", or similar.
- Presence of explicit flags such as `compilation` or `is_compilation` in tags.

2. Folder-scan signal (robust)
- If the folder contains audio files with more than one distinct `artist` tag value, it's likely a compilation.

3. Hybrid: prefer albumartist if present and folder is homogeneous; otherwise treat as per-track.

PowerShell recipes (examples)

Prerequisites
- These snippets assume you have the module imported so `Get-TrackMetadataFromFile` is available. If you don't, you can use `ffprobe` directly in a similar fashion.

1) Find album folders that look like single-artist albums

```powershell
# Finds directories that contain audio files where all tracks share the same artist tag.
$root = 'C:\Music'            # change to your music root
$extensions = '*.mp3','*.flac','*.m4a','*.ogg','*.wav' # common extensions to include (optional)

$albumDirs = Get-ChildItem -Path $root -Directory -Recurse | ForEach-Object {
    $dir = $_
    $files = Get-ChildItem -Path $dir.FullName -File -Include $extensions -ErrorAction SilentlyContinue
    if (-not $files -or $files.Count -eq 0) { return }

    $artists = @()
    foreach ($f in $files) {
        try {
            $meta = Get-TrackMetadataFromFile -AudioFilePath $f.FullName
            if ($meta -and $meta.Artist) { $artists += $meta.Artist }
        } catch { }
    }

    $unique = $artists | Where-Object { $_ } | Select-Object -Unique
    if ($unique.Count -eq 1) { [PSCustomObject]@{ Directory=$dir.FullName; Artist=$unique[0] } }
}

# $albumDirs now lists likely single-artist album folders
$albumDirs | Format-Table -AutoSize
```

2) Detect likely compilations (multiple distinct artists or an albumartist of "Various")

```powershell
function Is-VariousArtistTag($s) {
    if (-not $s) { return $false }
    $n = ($s -replace '[^\w]', '').ToLowerInvariant()
    return $n -match '^(various|va|compilation|variousartists)$'
}

$root = 'C:\Music'
$extensions = '*.mp3','*.flac','*.m4a','*.ogg'

$compilations = Get-ChildItem -Path $root -Directory -Recurse | ForEach-Object {
    $dir = $_
    $files = Get-ChildItem -Path $dir.FullName -File -Include $extensions -ErrorAction SilentlyContinue
    if (-not $files -or $files.Count -eq 0) { return }

    $albumArtistTag = $null
    $artists = @()
    foreach ($f in $files) {
        try {
            $meta = Get-TrackMetadataFromFile -AudioFilePath $f.FullName
            if ($meta -and $meta.Tags -and $meta.Tags.ContainsKey('albumartist')) { $albumArtistTag = $meta.Tags['albumartist'] }
            if ($meta -and $meta.Artist) { $artists += $meta.Artist }
        } catch { }
    }

    $unique = $artists | Where-Object { $_ } | Select-Object -Unique
    $isVarious = $false
    if ($albumArtistTag -and (Is-VariousArtistTag $albumArtistTag)) { $isVarious = $true }
    if ($unique.Count -gt 1) { $isVarious = $true }

    if ($isVarious) { [PSCustomObject]@{ Directory=$dir.FullName; AlbumArtist=$albumArtistTag; Artists=$unique } }
}

$compilations | Format-Table -AutoSize
```

3) Run `Update-GenresForDirectory` only for album-folders identified as single-artist

```powershell
# After collecting $albumDirs from recipe #1, run the genre updater per folder using albumartist preference
foreach ($a in $albumDirs) {
    Write-Output "Processing album: $($a.Directory) (artist: $($a.Artist))"
    Update-GenresForDirectory -Path $a.Directory -PreferAlbumArtist -ThrottleSeconds 1 -DryRun
}
```

Notes and operational tips

- Dry runs first: always use `-DryRun` on `Update-GenresForDirectory` so you can inspect the genre proposals before writing tags.
- Use caching: `Update-GenresForDirectory` supports a cache file (default in `%TEMP%`). Preserve that cache between runs to avoid repeated Last.fm calls.
- Backups: supply `-BackupFolder` if you plan to write tags; the recipe above uses directory-based scans, but your workflow can copy originals elsewhere.
- Performance: folder scans invoke `Get-TrackMetadataFromFile` (ffprobe). For large libraries, run scans once and persist an index (or run them overnight).

When to prefer albumartist vs per-track

- Prefer `albumartist` when:
  - The folder is homogeneous (all tracks share the same `artist`).
  - `albumartist` is present and not obviously a "Various" tag.
  - You want a single genre set for the whole album.

- Prefer per-track `artist` when:
  - The folder contains multiple distinct artists.
  - `albumartist` is absent or equal to a compilation marker like "Various Artists".
  - You want maximum accuracy per-track (recommended for compilations or soundtracks).

Advanced:
- If you want fully automatic decisions beyond simple heuristics, consider enriching detection with external lookups (Last.fm album.getInfo or MusicBrainz album lookup). That requires more API calls and error handling but can improve accuracy.

Summary

- Best practice for accuracy: pre-filter your library into "album-level" and "per-track" sets using the simple scripts above, then run `Update-GenresForDirectory` with `-PreferAlbumArtist` on the album-level set and without it on compilations.
- This approach avoids accidental mis-tagging of compilations and gives you deterministic control.

Confidence: 8/10 — the heuristics cover common library layouts; edge cases (mislabeled tags, guest-heavy albums) may still need manual review.
