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
    funct will download the best match when it meets the -Threshold. Use this switch to
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
		[Parameter(Mandatory = $true, ParameterSetName = 'ByNames')]
		[string]$Track,
		[Parameter(Mandatory = $true, ParameterSetName = 'ByNames')]
		[string]$Artist,
		[Parameter(ParameterSetName = 'ByNames')]
		[string]$Album,
		[Parameter(ParameterSetName = 'ByFile')]
		[string]$AudioFilePath,
		[string]$DestinationFolder,
		[ValidateSet('230', '600', 'max')]
		[string]$Size = '230',
		[switch]$Embed,
		[ValidateSet('Always', 'IfBigger', 'SkipIfExists')]
		[string]$DownloadMode = 'Always',
		[ValidateSet('Cover', 'Track-Artist', 'Artist-Track', 'Custom')]
		[string]$FileNameStyle = 'Cover',
		[string]$CustomFileName,
		[switch]$NoAuto,
		[switch]$ShowRawTags,
		[double]$Threshold = 0.75,
		[int]$MaxCandidates = 10,
		[switch]$GenerateReport,
		[ValidateSet('Track', 'Artist', 'Album')]
		[string[]]$UseTags,
		[switch]$Interactive,
		# New: accept a direct Qobuz URL (album/track page). When supplied, this is used to obtain candidates directly.
		# allow CorrectUrl without forcing an exclusive parameter set so it can be used with -AudioFilePath
		[string]$CorrectUrl
	)

	process {
		try {
			# Determine search fields first (from audio tags or provided params)
			$SearchTrack = $null; $SearchArtist = $null; $SearchAlbum = $null
			if ($PSBoundParameters.ContainsKey('AudioFilePath') -and $AudioFilePath) {
				Write-Verbose "[Save-QTrackCover] Reading metadata from $AudioFilePath"
				$meta = Get-TrackMetadataFromFile -AudioFilePath $AudioFilePath
				Write-Verbose ("[Save-QTrackCover] Metadata: Title={0}, Album={1}, Artist={2}" -f $meta.Title, $meta.Album, $meta.Artist)
				if ($ShowRawTags) {
					Write-Output "RAW_TAGS:"; $meta.Tags.GetEnumerator() | ForEach-Object { Write-Output ("{0} = {1}" -f $_.Key, $_.Value) }
				}

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
				}
				else {
					$SearchTrack = $meta.Title
					$SearchArtist = $meta.Artist
					$SearchAlbum = $meta.Album
				}

				if ((-not $SearchArtist -or -not $SearchTrack) -and $AudioFilePath) {
					$fname = [System.IO.Path]::GetFileNameWithoutExtension($AudioFilePath)
					$fname = $fname -replace '\s+', ' '  # collapse spaces
					$m = [regex]::Match($fname, '^\s*\d+\s*-\s*(.+?)\s*-\s*(.+?)(?:\s*\(|$)')
					if ($m.Success) {
						if (-not $SearchArtist) { $SearchArtist = $m.Groups[1].Value.Trim() }
						if (-not $SearchTrack) { $SearchTrack = $m.Groups[2].Value.Trim() }
						Write-Verbose ("[Save-QTrackCover] Fallback filename parse: Artist='{0}' Title='{1}' from '{2}'" -f $SearchArtist, $SearchTrack, $fname)
					}
				}
			}
			else {
				if ($PSBoundParameters.ContainsKey('Track')) { $SearchTrack = $Track }
				if ($PSBoundParameters.ContainsKey('Artist')) { $SearchArtist = $Artist }
				if ($PSBoundParameters.ContainsKey('Album')) { $SearchAlbum = $Album }
			}

			# If a direct Qobuz URL was supplied, obtain candidates from the page instead of doing a search.
			if ($PSBoundParameters.ContainsKey('CorrectUrl') -and $CorrectUrl) {
				Write-Verbose ("[Save-QTrackCover] CorrectUrl provided; resolving candidates from page: {0}" -f $CorrectUrl)
				# provide the search track so helper can find the matching track title in playerTracks
				$candidates = Get-QobuzPageImageInfo -Url $CorrectUrl -PreferredSize $Size -MatchTrack $SearchTrack
				# if we lack search fields, attempt to populate from candidate metadata
				if (($null -eq $SearchTrack -or $null -eq $SearchArtist) -and $candidates -and $candidates.Count -gt 0) {
					$first = $candidates[0]
					if (-not $SearchTrack -and $first.TitleAttr) { $SearchTrack = $first.TitleAttr }
					if (-not $SearchArtist -and $first.ArtistAttr) { $SearchArtist = $first.ArtistAttr }
				}
			}
			else {
				$url = New-QTrackSearchUrl -Track $SearchTrack -Artist $SearchArtist -Album $SearchAlbum
				Write-Verbose "[Save-QTrackCover] Searching: $url"
				$html = Get-QTrackSearchHtml -Url $url
				Write-Verbose ("[Save-QTrackCover] HTML length: {0}" -f ($html.Length))
				$candidates = ConvertFrom-QTrackSearchResults -Html $html -MaxCandidates $MaxCandidates
				Write-Verbose ("[Save-QTrackCover] Candidates found: {0}" -f ($candidates.Count))
				if ($candidates.Count -gt 0) {
					$i = 0

					foreach ($c in $candidates) {
						# decode HTML entities for readable verbose output
						Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
						$decodedTitle = [System.Web.HttpUtility]::HtmlDecode($c.TitleAttr)
						$decodedArtist = [System.Web.HttpUtility]::HtmlDecode($c.ArtistAttr)
						$decodedAlbum = [System.Web.HttpUtility]::HtmlDecode($c.AlbumAttr)

						Write-Verbose ("[Save-QTrackCover] Candidate[{0}]: Title={1}, Artist={2}, Album={3}, ImageUrl={4}" -f $i, $decodedTitle, $decodedArtist, $decodedAlbum, $c.ImageUrl)
						$i++
					}
				}
			}

			# Use track-specific scorer
			$scored = foreach ($c in $candidates) { Get-MatchQTrackResult -Track $SearchTrack -Artist $SearchArtist -Candidate $c }
			$scored = $scored | Sort-Object -Property Score -Descending
			Write-Verbose ("[Save-QTrackCover] Scored candidates: {0}" -f ($scored.Count))
			if ($scored.Count -gt 0) { Write-Verbose ("[Save-QTrackCover] Top score: {0}" -f ($scored[0].Score)) }

			$report = [System.Collections.Generic.List[object]]::new()
			foreach ($s in $scored) {
				Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
				$entry = [PSCustomObject]@{
					Index         = $s.Candidate.Index
					ImageUrl      = $s.Candidate.ImageUrl
					InputTitle    = if ($meta -and $meta.Title) { [System.Web.HttpUtility]::HtmlDecode([string]$meta.Title) }  else { $SearchTrack }
					Title         = [System.Web.HttpUtility]::HtmlDecode([string]$s.Candidate.TitleAttr)
					InputAlbum    = if ($meta -and $meta.Album) { [System.Web.HttpUtility]::HtmlDecode([string]$meta.Album) }  else { $SearchAlbum }
					ResultAlbum   = [System.Web.HttpUtility]::HtmlDecode([string]$s.Candidate.AlbumAttr)
					InputArtist   = if ($meta -and $meta.Artist) { [System.Web.HttpUtility]::HtmlDecode([string]$meta.Artist) } else { $SearchArtist }
					ResultArtist  = [System.Web.HttpUtility]::HtmlDecode([string]$s.Candidate.ArtistAttr)
					ResultLink    = $s.Candidate.ResultLink
					AlbumScore    = $s.AlbumScore
					ArtistScore   = $s.ArtistScore
					TrackScore    = $s.TrackScore
					Score         = $s.Score
					AudioFilePath = $AudioFilePath
				}
				$report.Add($entry)
			}

			$reportPath = $null
			$local = $null
			$autoDownloaded = $false
			# allow auto-download when score meets threshold OR when user provided a direct page URL (CorrectUrl) and candidates exist
			$allowAutoDownload = (-not $NoAuto) -and ($scored.Count -gt 0) -and ( ($scored[0].Score -ge $Threshold) -or ($PSBoundParameters.ContainsKey('CorrectUrl') -and $CorrectUrl) )
			if ($allowAutoDownload) {
				$best = $scored[0].Candidate
				$imgUrl = $best.ImageUrl
				if ($imgUrl -match '_\d+\.jpg$') {
					$imgUrl = $imgUrl -replace '_\d+\.jpg$', ('_{0}.jpg' -f $Size)
				}
				elseif ($imgUrl -match '_max\.jpg$') {
					$imgUrl = $imgUrl -replace '_max\.jpg$', ('_{0}.jpg' -f $Size)
				}
				Write-Verbose ("[Save-QTrackCover] Auto mode: Downloading best candidate with score {0} and url {1}" -f $scored[0].Score, $imgUrl)
				# If embedding, download to a temporary folder since the file is not needed afterwards
				if ($Embed) {
					$tempDir = Join-Path -Path $env:TEMP -ChildPath (New-Guid).Guid
					New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
					$local = Save-Image -ImageUrl $imgUrl -DestinationFolder $tempDir -DownloadMode $DownloadMode -FileNameStyle $FileNameStyle -CustomFileName $CustomFileName -Album $SearchTrack -Artist $SearchArtist
				}
				else {
					$local = Save-Image -ImageUrl $imgUrl -DestinationFolder $DestinationFolder -DownloadMode $DownloadMode -FileNameStyle $FileNameStyle -CustomFileName $CustomFileName -Album $SearchTrack -Artist $SearchArtist
				}
				$autoDownloaded = $true
			}

			if ($GenerateReport) {
				
				$ts = (Get-Date).ToString('yyyyMMddHHmmss')
				# Determine report status: success when we auto-downloaded, failed when no candidates, otherwise no-download/candidates
				if ($autoDownloaded)   { $status = 'success' }
				elseif ($scored.Count -eq 0) { $status = 'failed' }
				elseif ($scored.Count -gt 0 -and $scored[0].Score -lt $Threshold) { $status = 'no-download' }
				else { $status = 'failed' }

				# Build enriched report object with diagnostics and simplified candidates
				$fileName = ("q_track_search_{0}_{1}.json" -f $status, $ts)
				$reportPath = Join-Path ($DestinationFolder ? $DestinationFolder : $env:TEMP) $fileName
				if (-not (Test-Path -LiteralPath (Split-Path $reportPath -Parent))) {
					New-Item -Path (Split-Path $reportPath -Parent) -ItemType Directory -Force | Out-Null
				}

				# Simplify candidate objects for the JSON report (avoid serializing complex types)
				$simpleCandidates = @()
				foreach ($r in $report) {
					$simpleCandidates += [PSCustomObject]@{
						Index    = $r.Index
						ImageUrl = $r.ImageUrl
						Title    = $r.Title
						Artist   = $r.ResultArtist
						Album    = $r.ResultAlbum
						Score    = $r.Score
						ResultLink = $r.ResultLink
					}
				}

				# Recent error info if present
				$lastErr = $null
				if ($Error.Count -gt 0) { $lastErr = $Error[0] }

				$fullReport = [PSCustomObject]@{
					Status      = $status
					Timestamp   = $ts
					Input       = [PSCustomObject]@{ SearchTrack = $SearchTrack; SearchArtist = $SearchArtist; SearchAlbum = $SearchAlbum; AudioFile = $AudioFilePath }
					Candidates  = $simpleCandidates
					ReportItems = $report
					Diagnostics = [PSCustomObject]@{
						ErrorMessage = if ($lastErr) { $lastErr.Exception.Message } else { $null }
						Exception    = if ($lastErr) { $lastErr.Exception.GetType().FullName } else { $null }
						StackTrace   = if ($lastErr) { $lastErr.ScriptStackTrace } else { $null }
					}
				}
				$fullReport | ConvertTo-Json -Depth 6 | Out-File -FilePath $reportPath -Encoding UTF8
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
						Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
						$resultArtist = if ($best.ArtistAttr -and ($best.ArtistAttr.ToString().Trim() -ne '')) { [System.Web.HttpUtility]::HtmlDecode($best.ArtistAttr) } else { $null }
						$resultAlbum  = if ($best.AlbumAttr  -and ($best.AlbumAttr.ToString().Trim()  -ne '')) { [System.Web.HttpUtility]::HtmlDecode($best.AlbumAttr)  } else { $null }
						$resultTitle  = if ($best.TitleAttr  -and ($best.TitleAttr.ToString().Trim()  -ne '')) { [System.Web.HttpUtility]::HtmlDecode($best.TitleAttr)  } else { $null }

						Write-SummaryLine -InputArtist $SearchArtist -InputAlbum $SearchAlbum -InputTitle $SearchTrack -ResultArtist $resultArtist -ResultAlbum $resultAlbum -ResultTitle $resultTitle -Location ("embedded in $AudioFilePath")
						Write-Output $true
						return
					}
					else {
						# attempt cleanup on failure too
						if ($Embed -and $local -and ($local -like "$env:TEMP*")) {
							try { Remove-Item -Path $local -Force -ErrorAction SilentlyContinue } catch {}
							try { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
						}
						Write-Output $false
						return
					}
				}
				else {
					Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
					$resultArtist = if ($best.ArtistAttr -and ($best.ArtistAttr.ToString().Trim() -ne '')) { [System.Web.HttpUtility]::HtmlDecode($best.ArtistAttr) } else { $null }
					$resultAlbum  = if ($best.AlbumAttr  -and ($best.AlbumAttr.ToString().Trim()  -ne '')) { [System.Web.HttpUtility]::HtmlDecode($best.AlbumAttr)  } else { $null }
					$resultTitle  = if ($best.TitleAttr  -and ($best.TitleAttr.ToString().Trim()  -ne '')) { [System.Web.HttpUtility]::HtmlDecode($best.TitleAttr)  } else { $null }

					Write-SummaryLine -InputArtist $SearchArtist -InputAlbum $SearchAlbum -InputTitle $SearchTrack -ResultArtist $resultArtist -ResultAlbum $resultAlbum -ResultTitle $resultTitle -Location $local
					Write-Output $local
					return
				}
			}
			elseif ($scored.Count -gt 0) {
				Write-Output $scored
				if ($reportPath) { Write-Output $reportPath }
				return
			}
			else {
				Write-Verbose "[Save-QTrackCover] No candidates found or scored."
				Write-Output $null
				if ($reportPath) { Write-Output $reportPath }
				return
			}
		}
		catch {
			# Centralized diagnostics on exception: persist a minimal diagnostics JSON if report generation requested
			$errMsg = $_.Exception.Message
			Write-Verbose ("[Save-QTrackCover] Exception: {0}" -f $errMsg)
			# attempt to persist diagnostics to same report folder
			try {
				$ts = (Get-Date).ToString('yyyyMMddHHmmss')
				$status = 'failed'
				$diagFile = Join-Path -Path ($DestinationFolder ? $DestinationFolder : $env:TEMP) -ChildPath ("q_track_search_failed_{0}.json" -f $ts)
				# prepare simplified candidates if available
				$simpleCandidates = $null
				try {
					if ($candidates) {
						$simpleCandidates = @()
						foreach ($c in $candidates) {
							$simpleCandidates += [PSCustomObject]@{
								ImageUrl = $c.ImageUrl
								Title    = $c.TitleAttr
								Artist   = $c.ArtistAttr
								Album    = $c.AlbumAttr
								ResultLink = $c.ResultLink
							}
						}
					}
				} catch {}

				$diag = [PSCustomObject]@{
					Status = $status
					Timestamp = $ts
					ErrorMessage = $errMsg
					Exception = $_.Exception.GetType().FullName
					StackTrace = $_.ScriptStackTrace
					Input = [PSCustomObject]@{ SearchTrack = $SearchTrack; SearchArtist = $SearchArtist; AudioFile = $AudioFilePath }
					Candidates = $simpleCandidates
				}
				$diag | ConvertTo-Json -Depth 6 | Out-File -FilePath $diagFile -Encoding UTF8
				Write-Verbose ("[Save-QTrackCover] Wrote diagnostics to $diagFile")
			} catch { Write-Verbose ("[Save-QTrackCover] Failed to write diagnostics file: {0}" -f $_) }

			# Return diagnostic object for immediate inspection
			$diagnostic = [PSCustomObject]@{
				ErrorMessage = $errMsg
				Exception    = $_.Exception
				StackTrace   = $_.ScriptStackTrace
				ReportPath   = if ($diagFile) { $diagFile } else { $null }
				Candidates   = if ($simpleCandidates) { $simpleCandidates } else { $null }
				SearchTrack  = $SearchTrack
				SearchArtist = $SearchArtist
				AudioFilePath= $AudioFilePath
			}
			Write-Output $diagnostic
			return $diagnostic
 		}
 	}
 }
