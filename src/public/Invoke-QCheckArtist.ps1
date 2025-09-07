<#
.SYNOPSIS
    Inspect audio files, search Qobuz for artist candidates, and propose corrections.

.DESCRIPTION
    Invoke-QCheckArtist reads artist/album metadata from audio files, groups
    by AlbumArtist/Artist to reduce duplicate searches, queries Qobuz artist
    search pages, ranks candidates, and returns suggestions. Modes control
    whether user input is required: Manual, Automatic, Interactive.

.PARAMETER AudioFilePath
    One or more audio file paths to inspect (pipeline input supported).

.PARAMETER Mode
    Matching mode: Manual, Automatic, Interactive.

.PARAMETER Locale
    Locale used to construct Qobuz search URLs (default 'be-nl').

.PARAMETER CacheMinutes
    Minutes to cache search results (default 60).

.PARAMETER ThrottleSeconds
    Seconds to wait between web requests (default 1).

.PARAMETER LogPath
    Path to JSONL log file (default in TEMP).

.PARAMETER DryRun
    If set, do not modify any tags; function only reports suggestions.
#>
function Invoke-QCheckArtist {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)] [string[]] $AudioFilePath,
        [ValidateSet('Manual','Automatic','Interactive')] [string] $Mode = 'Interactive',
        [string] $Locale = 'be-nl',
        [int] $CacheMinutes = 60,
        [int] $ThrottleSeconds = 1,
        [string] $LogPath = (Join-Path -Path $env:TEMP -ChildPath 'MusicPicturesDownloader\qcheck.log'),
        [switch] $DryRun
    )

    begin {
        # Ensure required private helpers are available
        # Get-Command -Name Get-TrackMetadataFromFile -ErrorAction Stop | Out-Null
        # Get-Command -Name Build-QArtistSearchUrl -ErrorAction Stop | Out-Null
        # Get-Command -Name Get-QArtistSearchHtml -ErrorAction Stop | Out-Null
        # Get-Command -Name ConvertFrom-QArtistSearchResults -ErrorAction Stop | Out-Null
        # Get-Command -Name Select-QArtistResults -ErrorAction Stop | Out-Null
        # Get-Command -Name Get-CachedArtistResult -ErrorAction Stop | Out-Null
        # Get-Command -Name Set-CachedArtistResult -ErrorAction Stop | Out-Null
        # Get-Command -Name Write-QCheckLog -ErrorAction Stop | Out-Null

        $runId = [guid]::NewGuid().ToString()
        Write-Verbose "Invoke-QCheckArtist RUNID=${runId} Mode=${Mode} Locale=${Locale}"
        $files = @()
    }

    process {
        foreach ($f in $AudioFilePath) { $files += $f }
    }

    end {
        if ($files.Count -eq 0) { return }

        # Read metadata and build grouping keys
        $metaList = @()
        foreach ($file in $files) {
            try {
                $md = Get-TrackMetadataFromFile -AudioFilePath $file
                $metaList += [PSCustomObject]@{
                    File = $file
                    Artist = $md.Artist
                    Album = $md.Album
                    AlbumArtist = $md.AlbumArtist
                }
            }
            catch {
                Write-Verbose "Failed to read metadata for $file : ${_}"
            }
        }

        # Group by AlbumArtist (if present) else Artist, and by Album if present
        $groups = @{}
        foreach ($m in $metaList) {
            if ($m.AlbumArtist) {
                $groupKey = "albumartist:$($m.AlbumArtist)|album:$($m.Album)"
            }
            else {
                $groupKey = "artist:$($m.Artist)"
            }
            if (-not $groups.ContainsKey($groupKey)) { $groups[$groupKey] = @() }
            $groups[$groupKey] += $m
        }

        $results = @()
        foreach ($key in $groups.Keys) {
            $members = $groups[$key]
            # choose search query: prefer AlbumArtist if present, otherwise Artist
            $sample = $members[0]
            $query = if ($sample.AlbumArtist) { $sample.AlbumArtist } else { $sample.Artist }

            # check cache
            $cached = Get-CachedArtistResult -Query $query -Locale $Locale -CacheMinutes $CacheMinutes
            if ($cached) {
                $candidates = $cached
            }
            else {
                # fetch html and parse
                $html = Get-QArtistSearchHtml -Query $query -Locale $Locale -ThrottleSeconds $ThrottleSeconds
                $candidates = ConvertFrom-QTrackSearchResults -Html $html -MaxCandidates 10
                # attach search url for logging
                $searchUrl = Build-QArtistSearchUrl -Query $query -Locale $Locale
                $candidates | ForEach-Object { $_ | Add-Member -NotePropertyName SearchUrl -NotePropertyValue $searchUrl -Force }
                # Only cache non-empty candidate lists to avoid storing parser failures/empty results
                if ($candidates -and ($candidates.Count -gt 0)) {
                    Set-CachedArtistResult -Query $query -Result $candidates -Locale $Locale | Out-Null
                }
                else {
                    Write-Verbose "Not caching empty candidate list for query '$query'"
                }
            }

            # score candidates
            $scored = Select-QArtistResults -InputArtist $query -Candidates $candidates -AlbumName $sample.Album

            # prepare suggestion object
            $top = $scored | Select-Object -First 1
            $suggest = [PSCustomObject]@{
                RunId = $runId
                Mode = $Mode
                GroupKey = $key
                Query = $query
                TopCandidate = $top
                Candidates = $scored
                Files = ($members | ForEach-Object { $_.File })
            }

            # Log suggestion
            Write-QCheckLog -Record $suggest -LogPath $LogPath

            # Auto-apply high-confidence artist when requested and safe
            if ($Mode -eq 'Automatic' -and $top -and ($top.MatchScore -eq 1.0)) {
                # The top object has a Candidate property (string). Use that rather than $top.Artist which may be empty.
                $candidateStr = $null
                if ($top.PSObject.Properties['Candidate']) { $candidateStr = $top.Candidate }
                if (-not $candidateStr -or $candidateStr -eq '') {
                    Write-Verbose "Auto-apply skipped: top candidate string empty for query $query"
                }
                else {
                    $isAlbumArtistGroup = $key -like 'albumartist:*'
                    foreach ($f in $suggest.Files) {
                        if ($DryRun) {
                            if ($isAlbumArtistGroup) { Write-Verbose ("DryRun: would set albumartist='{0}' on '{1}'" -f $candidateStr, $f) }
                            else { Write-Verbose ("DryRun: would set artist='{0}' on '{1}'" -f $candidateStr, $f) }
                        }
                        else {
                            if ($isAlbumArtistGroup) { Write-Verbose ("Applying albumartist='{0}' on '{1}'" -f $candidateStr, $f) }
                            else { Write-Verbose ("Applying artist='{0}' on '{1}'" -f $candidateStr, $f) }
                            try {
                                if ($isAlbumArtistGroup) {
                                    $res = Set-FileArtistWithFFmpeg -AudioFilePath $f -AlbumArtist $candidateStr -ErrorAction Stop
                                    Write-Information "Updated albumartist for $f (OldAlbumArtist=$($res.OldAlbumArtist))"
                                }
                                else {
                                    $res = Set-FileArtistWithFFmpeg -AudioFilePath $f -Artist $candidateStr -ErrorAction Stop
                                    Write-Information "Updated artist for $f (OldArtist=$($res.OldArtist))"
                                }
                            }
                            catch {
                                Write-Warning "Failed to apply artist on $f : $_"
                            }
                        }
                    }
                }
            }

            # Mode handling (for now we only return suggestions; not applying tags)
            $results += $suggest
        }

        # Output results
        foreach ($r in $results) { Write-Output $r }
    }
}
