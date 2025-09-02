<#
.SYNOPSIS
    Download or embed a track cover image from Qobuz.

.DESCRIPTION
    Searches Qobuz for a track using the provided Track/Artist (and optional Album) or by reading tags
    from an audio file. The function returns scored candidate matches and can automatically download
    the best match or embed the downloaded image into an audio file using FFmpeg.

.PARAMETER Track
    The track title to search for. Required when using the ByNames parameter set.

.PARAMETER Artist
    The artist name to search for. Required when using the ByNames parameter set.

.PARAMETER Album
    Optional album name to narrow the search.

.PARAMETER AudioFilePath
    Path to an existing audio file. When provided you can read tag fields (Title/Artist/Album)
    and use them as search inputs via -UseTags or -Interactive.

.PARAMETER DestinationFolder
    Folder where images will be saved when not embedding. If omitted and an image is written a
    temporary folder under $env:TEMP will be used for report generation.

.PARAMETER Embed
    When specified, the downloaded image will be embedded into the audio file specified by
    -AudioFilePath using FFmpeg. Temporary files are cleaned up after embedding.

.PARAMETER DownloadMode
    Controls how images are downloaded: Always, IfBigger, or SkipIfExists.

.PARAMETER FileNameStyle
    Controls the naming scheme for saved images: Cover, Track-Artist, Artist-Track, or Custom.

.PARAMETER CustomFileName
    When FileNameStyle is Custom, this template will be used. Use placeholders like {Track} and {Artist}.

.PARAMETER NoAuto
    When specified, do NOT automatically download the top-scoring candidate; by default the
    function will download the best match when it meets the -Threshold. Use this switch to
    perform a preview/report-only run.

.PARAMETER Threshold
    Score threshold (0..1) for automatic download when -Auto is used. Default: 0.75

.PARAMETER MaxCandidates
    Maximum number of candidates to evaluate from the search results.

.PARAMETER GenerateReport
    When set, emits a JSON report with candidate scores and details. The report path is also returned.

.PARAMETER UseTags
    When an audio file is supplied, list which tag fields to use for the search. Valid values: Track, Artist, Album.

.PARAMETER Interactive
    When set together with -AudioFilePath, prompts interactively to choose which tags to use for the search.

.EXAMPLE
    # Download the best matching cover for a track and save it to C:\Covers (downloads by default)
    Save-QTrackCover -Track 'In The Wee Small Hours' -Artist 'Frank Sinatra' -DestinationFolder 'C:\Covers' -Verbose

.EXAMPLE
    # Read tags from an mp3 and embed the found image into the file (embed after download)
    Save-QTrackCover -AudioFilePath 'C:\Music\track.mp3' -UseTags Track,Artist -Embed

.EXAMPLE
    # Preview / report-only: do not download, only generate a candidate report
    Save-QTrackCover -Track 'Song Title' -Artist 'Artist Name' -NoAuto -GenerateReport

.NOTES
    - Requires the PowerHTML module for HTML parsing and FFmpeg (ffmpeg.exe) in PATH for embedding.
    - Temporary files used for embedding are removed after the operation.
#>
function Save-QTrackCover {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='ByNames')]
        [string]$Track,
        [Parameter(Mandatory=$true, ParameterSetName='ByNames')]
        [string]$Artist,
        [Parameter(ParameterSetName='ByNames')]
        [string]$Album,
        [Parameter(ParameterSetName='ByFile')]
        [string]$AudioFilePath,
        [string]$DestinationFolder,
        [switch]$Embed,
        [ValidateSet('Always', 'IfBigger', 'SkipIfExists')]
        [string]$DownloadMode = 'Always',
        [ValidateSet('Cover', 'Track-Artist', 'Artist-Track', 'Custom')]
        [string]$FileNameStyle = 'Cover',
        [string]$CustomFileName,
    [switch]$NoAuto,
        [double]$Threshold = 0.75,
        [int]$MaxCandidates = 10,
        [switch]$GenerateReport,
        [ValidateSet('Track','Artist','Album')]
        [string[]]$UseTags,
        [switch]$Interactive
    )

    process {
    try {
        # Determine search fields. If AudioFilePath provided, prefer tags per -UseTags or interactive selection.
        $SearchTrack = $null; $SearchArtist = $null; $SearchAlbum = $null
        if ($PSBoundParameters.ContainsKey('AudioFilePath') -and $AudioFilePath) {
            Write-Verbose "[Save-QTrackCover] Reading metadata from $AudioFilePath"
            $meta = Get-TrackMetadataFromFile -AudioFilePath $AudioFilePath
            Write-Verbose ("[Save-QTrackCover] Metadata: Title={0}, Album={1}, Artist={2}" -f $meta.Title, $meta.Album, $meta.Artist)

            if ($Interactive -and -not $UseTags) {
                $choices = @()
                if ($meta.Title) { $choices += 'Track' }
                if ($meta.Artist) { $choices += 'Artist' }
                if ($meta.Album) { $choices += 'Album' }
                $prompt = "Available tag fields: $([string]::Join(',', $choices)). Enter comma-separated fields to use for search (Track,Artist,Album) or press Enter to use Track,Artist:"
                $resp = Read-Host $prompt
                if ($resp -and $resp.Trim() -ne '') { $UseTags = ($resp -split ',') | ForEach-Object { $_.Trim() } }
            }

            if ($UseTags) {
                if ($UseTags -contains 'Track') { $SearchTrack = $meta.Title }
                if ($UseTags -contains 'Artist') { $SearchArtist = $meta.Artist }
                if ($UseTags -contains 'Album') { $SearchAlbum = $meta.Album }
            } else {
                # default: use Track and Artist if present
                $SearchTrack = $meta.Title
                $SearchArtist = $meta.Artist
                $SearchAlbum = $meta.Album
            }
        } else {
            # Using provided parameters
            if ($PSBoundParameters.ContainsKey('Track')) { $SearchTrack = $Track }
            if ($PSBoundParameters.ContainsKey('Artist')) { $SearchArtist = $Artist }
            if ($PSBoundParameters.ContainsKey('Album')) { $SearchAlbum = $Album }
        }

        if (-not $SearchTrack -or -not $SearchArtist) {
            Write-Verbose "[Save-QTrackCover] Missing search fields: Track='$SearchTrack', Artist='$SearchArtist'"
            throw "Both Track and Artist are required for searching. Provide them as parameters or supply an audio file with tags and use -UseTags to select fields."
        }

        $url = New-QTrackSearchUrl -Track $SearchTrack -Artist $SearchArtist -Album $SearchAlbum
        Write-Verbose "[Save-QTrackCover] Searching: $url"

        $html = Get-QTrackSearchHtml -Url $url
        Write-Verbose ("[Save-QTrackCover] HTML length: {0}" -f ($html.Length))

    $candidates = ConvertFrom-QTrackSearchResults -Html $html -MaxCandidates $MaxCandidates
        Write-Verbose ("[Save-QTrackCover] Candidates found: {0}" -f ($candidates.Count))
        if ($candidates.Count -gt 0) {
            $i = 0
            foreach ($c in $candidates) {
                Write-Verbose ("[Save-QTrackCover] Candidate[{0}]: Title={1}, ImageUrl={2}" -f $i, $c.TitleAttr, $c.ImageUrl)
                $i++
            }
        }

    # Use track-specific scorer
    $scored = foreach ($c in $candidates) { Get-MatchQTrackResult -Track $SearchTrack -Artist $SearchArtist -Candidate $c }
        $scored = $scored | Sort-Object -Property Score -Descending
        Write-Verbose ("[Save-QTrackCover] Scored candidates: {0}" -f ($scored.Count))
        if ($scored.Count -gt 0) { Write-Verbose ("[Save-QTrackCover] Top score: {0}" -f ($scored[0].Score)) }

        $report = [System.Collections.Generic.List[object]]::new()
        foreach ($s in $scored) {
            $entry = [PSCustomObject]@{
                Index = $s.Candidate.Index
                ImageUrl = $s.Candidate.ImageUrl
                Title = $s.Candidate.TitleAttr
                ResultLink = $s.Candidate.ResultLink
                AlbumScore = $s.AlbumScore
                ArtistScore = $s.ArtistScore
                Score = $s.Score
            }
            $report.Add($entry)
        }

        $reportPath = $null
        $local = $null
        $autoDownloaded = $false
    if (-not $NoAuto -and $scored.Count -gt 0 -and $scored[0].Score -ge $Threshold) {
            $best = $scored[0].Candidate
            $imgUrl = $best.ImageUrl
            if ($imgUrl -match '_\d+\.jpg$') {
                $imgUrl = $imgUrl -replace '_\d+\.jpg$', ('_{0}.jpg' -f '230')
            } elseif ($imgUrl -match '_max\.jpg$') {
                $imgUrl = $imgUrl -replace '_max\.jpg$', ('_{0}.jpg' -f '230')
            }
            Write-Verbose ("[Save-QTrackCover] Auto mode: Downloading best candidate with score {0} and url {1}" -f $scored[0].Score, $imgUrl)
            # If embedding, download to a temporary folder since the file is not needed afterwards
            if ($Embed) {
                $tempDir = Join-Path -Path $env:TEMP -ChildPath (New-Guid).Guid
                New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
                $local = Download-Image -ImageUrl $imgUrl -DestinationFolder $tempDir -DownloadMode $DownloadMode -FileNameStyle $FileNameStyle -CustomFileName $CustomFileName -Album $SearchTrack -Artist $SearchArtist
            } else {
                $local = Download-Image -ImageUrl $imgUrl -DestinationFolder $DestinationFolder -DownloadMode $DownloadMode -FileNameStyle $FileNameStyle -CustomFileName $CustomFileName -Album $SearchTrack -Artist $SearchArtist
            }
            $autoDownloaded = $true
        }

        if ($GenerateReport) {
            $ts = (Get-Date).ToString('yyyyMMddHHmmss')
            $reportPath = Join-Path ($DestinationFolder ? $DestinationFolder : $env:TEMP) "q_track_search_report_$ts.json"
            if (-not (Test-Path -Path (Split-Path $reportPath -Parent))) { New-Item -Path (Split-Path $reportPath -Parent) -ItemType Directory -Force | Out-Null }
            $report | ConvertTo-Json -Depth 4 | Out-File -FilePath $reportPath -Encoding UTF8
            Write-Verbose ("[Save-QTrackCover] Report written: {0}" -f $reportPath)
        }

            if ($autoDownloaded) {
            if ($Embed -and $AudioFilePath) {
                $ok = Set-TrackImageWithFFmpeg -AudioFilePath $AudioFilePath -ImagePath $local
                    if ($ok) {
                        # remove temporary download if used
                        if ($Embed -and $local -and ($local -like "$env:TEMP*")) {
                            try { Remove-Item -Path $local -Force -ErrorAction SilentlyContinue } catch {}
                            try { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
                        }
                        Write-Output $true; return
                    } else {
                        # attempt cleanup on failure too
                        if ($Embed -and $local -and ($local -like "$env:TEMP*")) {
                            try { Remove-Item -Path $local -Force -ErrorAction SilentlyContinue } catch {}
                            try { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
                        }
                        Write-Output $false; return
                    }
            } else {
                Write-Output $local
                return
            }
        } elseif ($scored.Count -gt 0) {
            Write-Output $scored
            if ($reportPath) { Write-Output $reportPath }
            return
        } else {
            Write-Verbose "[Save-QTrackCover] No candidates found or scored."
            Write-Output $null
            if ($reportPath) { Write-Output $reportPath }
            return
        }
    } catch {
        Write-Output "Error in Save-QTrackCover: $_"
        return $null
    }
    }
}
