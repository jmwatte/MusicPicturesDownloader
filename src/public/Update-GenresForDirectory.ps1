function Update-GenresForDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string] $Path,
    [string] $Filter = '*.*',
    [ValidateSet('Smart','PreferAlbumArtist','PreferTrackArtist','PerTrack')] [string] $AlbumArtistPolicy = 'Smart',
        [switch] $Recurse,
        [int] $MaxTags = 3,
        [ValidateSet('lower','camel','title')] [string] $Case = 'lower',
        [string] $Joiner = ';',
        [switch] $Replace,
        [switch] $Merge,
        [switch] $DryRun,
        [string] $ApiKey,
    [string] $CacheFile = (Join-Path -Path $env:TEMP -ChildPath 'MusicPicturesDownloader-lastfm-cache.json'),
    [int] $ThrottleSeconds = 1,
    [string] $LogFile,
    [string] $BackupFolder,
    [switch] $NoOutput,
    [switch] $ConfirmEach
    )

    if (-not (Test-Path -LiteralPath $Path)) { throw "Path not found: $Path" }

    $files = Get-ChildItem -LiteralPath $Path -Filter $Filter -File -ErrorAction Stop
    if ($Recurse) { $files = Get-ChildItem -LiteralPath $Path -Filter $Filter -File -Recurse -ErrorAction Stop }

    # Load cache as a hashtable so arbitrary string keys (with pipes/spaces) can be used
    $cache = @{}
    if (Test-Path -LiteralPath $CacheFile) {
        try {
            $raw = Get-Content -LiteralPath $CacheFile -Raw -ErrorAction Stop
            if ($raw -and $raw.Trim().Length -gt 0) {
                $tmp = $raw | ConvertFrom-Json -ErrorAction Stop
                if ($null -ne $tmp) {
                    foreach ($p in $tmp.PSObject.Properties) { $cache[$p.Name] = $p.Value }
                }
            }
        } catch { Write-Verbose "Failed to read cache: $_"; $cache = @{} }
    }

    $report = @()

    # Helper: detect various/compilation-like albumartist values
    function Test-VariousArtistTag([string]$s) {
        if (-not $s) { return $false }
        $n = ($s -replace '[^\w]', '').ToLowerInvariant()
        return ($n -match '^(various|va|compilation|variousartists)$')
    }

    # Normalize strings for lookup (remove bracketed parts, punctuation, collapse whitespace)
    function ConvertTo-NormalizedLookup([string]$s) {
        if (-not $s) { return $null }
        $t = $s.ToLowerInvariant().Trim()
        # remove parenthetical or bracketed suffixes
        $t = $t -replace '\s*\(.*?\)','' -replace '\s*\[.*?\]',''
        # remove punctuation except apostrophes
        $t = $t -replace "[^\w\s']+", ''
        $t = $t -replace '\s+',' '
        return $t.Trim()
    }

    # Cache of per-directory unique artists to avoid repeated ffprobe calls
    $dirArtistCache = @{}

    # Phase 1: read metadata for every file and decide audio/filter/keys
    $entries = @()
    foreach ($f in $files) {
        Write-Verbose "Collecting metadata: $($f.FullName)"
        try {
            $meta = Get-TrackMetadataFromFile -AudioFilePath $f.FullName
        } catch {
            Write-Warning "Failed to read metadata for $($f.FullName): $_"
            $report += [PSCustomObject]@{ AudioFile=$f.FullName; OldGenres=$null; NewGenres=$null; Written='failed-read' }
            continue
        }

        # determine if this looks like audio
        $isAudio = $false
        if ($meta -and $meta.PSObject.Properties.Match('audioCount')) {
            try { $ac = [int]$meta.audioCount } catch { $ac = 0 }
            if ($ac -gt 0) { $isAudio = $true }
        }
        if (-not $isAudio) {
            $ext = [IO.Path]::GetExtension($f.FullName).ToLowerInvariant()
            $audioExts = '.mp3','.flac','.m4a','.aac','.ogg','.wav','.wma','.alac','.opus'
            if ($audioExts -contains $ext) { $isAudio = $true }
            elseif ($meta.Tags -and ($meta.Tags.ContainsKey('title') -or $meta.Tags.ContainsKey('album') -or $meta.Tags.ContainsKey('track'))) { $isAudio = $true }
        }

        if (-not $isAudio) {
            Write-Verbose "Skipping non-audio file: $($f.FullName)"
            $report += [PSCustomObject]@{ AudioFile=$f.FullName; OldGenres=$null; NewGenres=$null; Written='skipped-non-audio' }
            continue
        }

        # Determine artist according to policy
        $artist = $null
        $albumArtistTag = $null
        if ($meta.Tags -and $meta.Tags.ContainsKey('albumartist')) { $albumArtistTag = $meta.Tags['albumartist'] }
        elseif ($meta.Tags -and $meta.Tags.ContainsKey('TPE2')) { $albumArtistTag = $meta.Tags['TPE2'] }

        switch ($AlbumArtistPolicy) {
            'PerTrack' { $artist = $meta.Artist }
            'PreferAlbumArtist' { if ($albumArtistTag) { $artist = $albumArtistTag } else { $artist = $meta.Artist } }
            'PreferTrackArtist' { $artist = $meta.Artist }
            'Smart' {
                if ($albumArtistTag -and -not (Test-VariousArtistTag $albumArtistTag)) {
                    # get or compute sibling artists for this directory
                    $dirKey = $f.DirectoryName.ToLowerInvariant()
                    if (-not $dirArtistCache.ContainsKey($dirKey)) {
                        $sibs = @()
                        try {
                            $siblings = Get-ChildItem -LiteralPath $f.DirectoryName -File -ErrorAction Stop
                            foreach ($s in $siblings) {
                                try {
                                    $m = Get-TrackMetadataFromFile -AudioFilePath $s.FullName
                                    if ($m -and $m.Artist) { $sibs += $m.Artist }
                                } catch { }
                            }
                        } catch { }
                        $unique = ($sibs | Where-Object { $_ } | Select-Object -Unique)
                        $dirArtistCache[$dirKey] = $unique
                    }
                    $siblingArtists = $dirArtistCache[$dirKey]
                    if (($siblingArtists.Count -le 1) -or ($siblingArtists.Count -eq 0)) {
                        $artist = $albumArtistTag
                    } else {
                        $artist = $meta.Artist
                    }
                } else {
                    $artist = $meta.Artist
                }
            }
        }

    $album = $meta.Album
    $title = $meta.Title
    $artistNorm = ConvertTo-NormalizedLookup($artist)
    $albumNorm = ConvertTo-NormalizedLookup($album)
    $titleNorm = ConvertTo-NormalizedLookup($title)
        if (-not $artist -and -not $title -and -not $album) {
            Write-Verbose "Skipping (no artist/title/album): $($f.FullName)"
            $report += [PSCustomObject]@{ AudioFile=$f.FullName; OldGenres=$null; NewGenres=$null; Written='skipped' }
            continue
        }

    $key = "{0}|{1}|{2}" -f ($artistNorm), ($albumNorm), ($titleNorm)

        $entries += [PSCustomObject]@{
            File = $f
            Meta = $meta
            Artist = $artist
            Album = $album
            Title = $title
            ArtistNormalized = $artistNorm
            AlbumNormalized = $albumNorm
            TitleNormalized = $titleNorm
            Key = $key
            KeyUsed = $key # may be adjusted later to album-level
            IsAudio = $isAudio
        }
    }

    # Auto-upgrade to album-level lookups when multiple files share same artist+album
    # group by normalized artist+album
    $albumGroups = $entries | Where-Object { $_.IsAudio -and $_.AlbumNormalized } | Group-Object -Property @{ E={ $_.ArtistNormalized + '|' + $_.AlbumNormalized } }
    foreach ($g in $albumGroups) {
        if ($g.Count -gt 1) {
            # use album-level key (empty title) for all members
            foreach ($member in $g.Group) {
                $albumKey = "{0}|{1}|{2}" -f (($member.Artist -as [string]).ToLower().Trim()), (($member.Album -as [string]).ToLower().Trim()), ('')
                $member.KeyUsed = $albumKey
            }
        }
    }

    # Phase 2: perform batched Last.fm lookups for unique keys not already in cache
    $lookupResults = @{}
    $uniqueKeys = ($entries | Where-Object { $_.IsAudio -and $_.KeyUsed }) | Select-Object -ExpandProperty KeyUsed -Unique
    foreach ($k in $uniqueKeys) {
        if ($cache.ContainsKey($k)) {
            Write-Verbose "Cache hit for $k"
            $val = $cache[$k]
            # if this is an album-level key (title empty) and cache value is empty, try an artist-level fallback
            $parts = $k -split '\|'
            if (($parts.Count -ge 3) -and -not $parts[2] -and ($null -eq $val -or ($val -is [System.Array] -and $val.Count -eq 0))) {
                # find representative entry to get normalized artist
                $rep = ($entries | Where-Object { $_.KeyUsed -eq $k })[0]
                $artistNorm = $null
                if ($rep -and $rep.ArtistNormalized) { $artistNorm = $rep.ArtistNormalized }
                if ($artistNorm) {
                    $artistOnlyKey = "{0}||" -f $artistNorm
                    if ($cache.ContainsKey($artistOnlyKey) -and $cache[$artistOnlyKey] -and $cache[$artistOnlyKey].Count -gt 0) {
                        Write-Verbose "Using cached artist-level tags for $artistOnlyKey as album-level empty"
                        $lookupResults[$k] = $cache[$artistOnlyKey]
                        continue
                    }
                    # call artist-only lookup
                    try {
                        Start-Sleep -Seconds $ThrottleSeconds
                        $artistTags = Get-LastFmTopTags -ApiKey $ApiKey -Artist $rep.Artist -Album $null -Track $null -MaxTags $MaxTags
                    } catch {
                        Write-Verbose "Artist-level lookup failed for $($rep.Artist): $_"
                        $artistTags = @()
                    }
                    try { $cache[$artistOnlyKey] = $artistTags } catch { Write-Verbose "Failed to write artist fallback to cache: $_" }
                    try { $cache | ConvertTo-Json -Depth 5 | Set-Content -Path $CacheFile -Encoding UTF8 } catch { Write-Verbose "Failed to persist cache: $_" }
                    $lookupResults[$k] = $artistTags
                    continue
                }
            }
            $lookupResults[$k] = $val
            continue
        }

        # find a representative entry to extract artist/album/title for the lookup (match KeyUsed)
        $rep = ($entries | Where-Object { $_.KeyUsed -eq $k })[0]
        if (-not $rep) { continue }
        $artist = $rep.Artist
        $album = $rep.Album
        $title = $rep.Title

        # If this is an album-level key (empty title), make sure we pass $null for Track so Get-LastFmTopTags uses album/artist lookup
        if (($k -split '\|').Count -ge 3) {
            $parts = $k -split '\|'
            if (-not $parts[2]) { $title = $null }
        }

        try {
            Start-Sleep -Seconds $ThrottleSeconds
            $tags = Get-LastFmTopTags -ApiKey $ApiKey -Artist $artist -Album $album -Track $title -MaxTags $MaxTags
        } catch {
            Write-Warning ([string]::Format('Last.fm query failed for {0}: {1}', $k, $_))
            $tags = @()
        }

    # store in both cache (hashtable) and run-local lookup map
    try { $cache[$k] = $tags } catch { Write-Verbose "Failed to write to cache variable for $k : $_" }
    try { $cache | ConvertTo-Json -Depth 5 | Set-Content -Path $CacheFile -Encoding UTF8 } catch { Write-Verbose "Failed to persist cache: $_" }
    $lookupResults[$k] = $tags
    }

    # Diagnostic: when verbose, persist lookupResults to a workspace file for inspection
    if ($VerbosePreference -ne 'SilentlyContinue') {
        try {
            # Prefer writing diagnostics to a writable location to avoid permission errors
            $diagDir = $null
            $candidates = @()
            if ($CacheFile) { $candidates += (Split-Path -Path $CacheFile -Parent) }
            if ($env:TEMP) { $candidates += $env:TEMP }
            foreach ($d in $candidates) {
                if (-not $d) { continue }
                if (-not (Test-Path -LiteralPath $d)) { continue }
                try {
                    # test if we can create and remove a temp file in the directory
                    $testFile = [IO.Path]::Combine($d, [IO.Path]::GetRandomFileName())
                    '' | Out-File -FilePath $testFile -Encoding UTF8 -Force
                    Remove-Item -LiteralPath $testFile -Force
                    $diagDir = $d
                    break
                } catch { }
            }
            if (-not $diagDir) { $diagDir = $env:TEMP }
            if (-not $diagDir) { $diagDir = (Get-Location) }
            $diag = Join-Path -Path $diagDir -ChildPath '.lastfm-diagnostic.json'
            $lookupResults | ConvertTo-Json -Depth 6 | Set-Content -Path $diag -Encoding UTF8
            Write-Verbose "Wrote diagnostic lookupResults to $diag"
        } catch { Write-Verbose "Failed to write diagnostic file: $_" }
    }

    # Phase 3: apply per-file results (merge/replace/dryrun/write)
    foreach ($entry in $entries) {
        $f = $entry.File
        $meta = $entry.Meta
        $key = $entry.Key
        $keyUsed = $entry.KeyUsed

        if (-not $entry.IsAudio) { continue }

        $tags = $null
        # Use the run-local lookup key (may be album-level) when applying results
        if ($lookupResults.ContainsKey($keyUsed)) { $tags = $lookupResults[$keyUsed] }
        if (-not $tags -or $tags.Count -eq 0) {
            Write-Verbose "No tags from Last.fm for $($f.Name) (lookup key: $keyUsed)"
            $report += [PSCustomObject]@{ AudioFile=$f.FullName; OldGenres=($meta.Tags['genre']); NewGenres=@(); Written='no-tags' }
            continue
        }

        $norm = ConvertTo-Genres -Tags $tags -Case $Case -Max $MaxTags -Joiner $Joiner

        # Merge logic: if Merge requested (or not Replace) then combine existing + new
        if ($Merge -or -not $Replace) {
            $existing = @()
            if ($meta.Tags -and $meta.Tags.ContainsKey('genre')) {
                $existing = ($meta.Tags['genre'] -as [string]) -split '[;\s]+' | Where-Object { $_ -ne '' }
            }
            $merged = @()
            foreach ($g in $existing) { if ($g -and -not ($merged -contains $g)) { $merged += $g } }
            foreach ($g in $norm) { if ($g -and -not ($merged -contains $g)) { $merged += $g } }
            $final = $merged | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -ne '' }
        } else {
            $final = $norm
        }

        if ($DryRun) {
            Write-Output "Dry-run: $($f.FullName) -> $($final -join $Joiner)"
            $report += [PSCustomObject]@{ AudioFile=$f.FullName; OldGenres=($meta.Tags['genre']); NewGenres=$final; Written='dry-run' }
            continue
        }

        # Interactive confirmation per-file when requested
        if ($ConfirmEach) {
            $shortName = [IO.Path]::GetFileName($f.FullName)
            $old = $null
            if ($meta.Tags -and $meta.Tags.ContainsKey('genre')) { $old = ($meta.Tags['genre'] -as [string]) }
            $newStr = ($final -join $Joiner)
            Write-Host "Confirm: $shortName  ->  $newStr  (was: $old)" -NoNewline
            Write-Host "  [Enter]=yes, n=skip, q=abort" -ForegroundColor DarkGray
            $key = Read-Host -Prompt 'Choice'
            if ($key -eq 'q') {
                Write-Verbose "Operation aborted by user at $shortName"
                return $report
            }
            if ($key -eq 'n') {
                Write-Verbose "Skipping $shortName per user choice"
                $report += [PSCustomObject]@{ AudioFile=$f.FullName; OldGenres=($meta.Tags['genre']); NewGenres=$final; Written='skipped-by-user' }
                continue
            }
            # else proceed on Enter or any other input
        }

        # optional backup: copy original to backup folder if specified
        if ($BackupFolder) {
            try {
                if (-not (Test-Path -LiteralPath $BackupFolder)) { New-Item -Path $BackupFolder -ItemType Directory -Force | Out-Null }
                Copy-Item -LiteralPath $f.FullName -Destination (Join-Path -Path $BackupFolder -ChildPath $f.Name) -Force
            } catch { Write-Warning ([string]::Format('Failed to backup {0} to {1}: {2}', $f.FullName, $BackupFolder, $_)) }
        }

        # attempt write
        try {
            $writeRes = Set-FileGenresWithFFmpeg -AudioFilePath $f.FullName -Genres $final -Replace:$true
            if ($writeRes -and $writeRes.Ok) {
                Write-Verbose "Wrote genres for $($f.FullName): $($final -join $Joiner)"
                $report += [PSCustomObject]@{ AudioFile=$f.FullName; OldGenres=($writeRes.OldGenres); NewGenres=$final; Written=$f.FullName }
            } else {
                Write-Warning "Failed to write genres for $($f.FullName)"
                $report += [PSCustomObject]@{ AudioFile=$f.FullName; OldGenres=$null; NewGenres=$final; Written='failed-write' }
            }
        } catch {
            Write-Warning "Exception writing genres for $($f.FullName): $_"
            $report += [PSCustomObject]@{ AudioFile=$f.FullName; OldGenres=$null; NewGenres=$final; Written='error' }
        }
    }

    # Final persist cache
    try { $cache | ConvertTo-Json -Depth 5 | Set-Content -Path $CacheFile -Encoding UTF8 } catch { Write-Verbose "Failed to persist cache at end: $_" }

    if ($LogFile) {
        try { $report | ConvertTo-Json -Depth 5 | Set-Content -Path $LogFile -Encoding UTF8 } catch { Write-Verbose "Failed to write log: $_" }
    }

    # If -NoOutput was requested, return the report object silently (do not write-host the table)
    if ($NoOutput) { return $report }

    return $report
}
