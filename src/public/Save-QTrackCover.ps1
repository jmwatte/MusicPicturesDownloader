<#
.SYNOPSIS
    Download or embed a track cover image from Qobuz.

.DESCRIPTION
    Searches Qobuz for a track using provided Track/Artist (and optional Album) or by reading tags
    from an audio file. Returns scored candidate matches and can download or embed the selected image.

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
    Folder where images will be saved when not embedding. If omitted a temporary folder under $env:TEMP will be used for report generation.

.PARAMETER Size
    Preferred image size. Allowed values: '230', '600', 'max'. Default: '230'.

.PARAMETER Embed
    When specified, the downloaded image will be embedded into the audio file specified by -AudioFilePath using FFmpeg.

.PARAMETER DownloadMode
    Controls how images are downloaded. Allowed values: 'Always', 'IfBigger', 'SkipIfExists'. Default: 'Always'.

.PARAMETER FileNameStyle
    Controls naming scheme for saved images. Allowed values: 'Cover', 'Track-Artist', 'Artist-Track', 'Custom'. Default: 'Cover'.

.PARAMETER CustomFileName
    When FileNameStyle is 'Custom', this template will be used. Use placeholders like {Track} and {Artist}.

.PARAMETER NoAuto
    When specified, do NOT automatically download the top-scoring candidate; by default the function will download the best match when it meets -Threshold.

.PARAMETER ShowRawTags
    When set, outputs raw tag key/value pairs read from the audio file (for debugging).

.PARAMETER Threshold
    Score threshold (0..1) for automatic download. Default: 0.75.

.PARAMETER MaxCandidates
    Maximum number of candidates to evaluate from the search results. Default: 10.

.PARAMETER GenerateReport
    When set, emits a JSON report with candidate scores and details. The report path is also returned.

.PARAMETER UseTags
    When an audio file is supplied, list which tag fields to use for the search. Allowed values: 'Track', 'Artist', 'Album'.

.PARAMETER Interactive
    When set together with -AudioFilePath, prompts interactively to choose which tags to use for the search.

.PARAMETER CorrectUrl
    Optional direct Qobuz URL (album or track page). When supplied, the function will obtain candidates from that page
    instead of building a search URL.

.EXAMPLE
    Save-QTrackCover -Track 'In The Wee Small Hours' -Artist 'Frank Sinatra' -DestinationFolder 'C:\Covers' -Verbose

.EXAMPLE
    Save-QTrackCover -AudioFilePath 'C:\Music\track.mp3' -UseTags Track,Artist -Embed

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
	[int]$MaxInteractiveAttempts = 3,
		# New: accept a direct Qobuz URL (album/track page). When supplied, this is used to obtain candidates directly.
		# allow CorrectUrl without forcing an exclusive parameter set so it can be used with -AudioFilePath
		[string]$CorrectUrl
	)

	process {
		try {
			# Determine search fields first (from audio tags or provided params)
			$SearchTrack = $null; $SearchArtist = $null; $SearchAlbum = $null
			# search URL used for reporting (CorrectUrl or constructed search URL)
			$searchUrl = $null
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
				# use the provided page URL as the search URL for reporting
				$searchUrl = $CorrectUrl
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
				# record constructed search URL for reporting
				$searchUrl = $url
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
			# sort by score desc, tie-breaker: earlier candidate Index (lower is earlier in search results)
			$scored = $scored | Sort-Object -Property @{
				Expression = { $_.Score }
				Descending = $true
			}, @{
				Expression = { if ($_.Candidate -and $_.Candidate.PSObject.Properties.Match('Index')) { [int]$_.Candidate.Index } else { [int]::MaxValue } }
				Descending = $false
			}
			Write-Verbose ("[Save-QTrackCover] Scored candidates: {0}" -f ($scored.Count))
			if ($scored.Count -gt 0) { Write-Verbose ("[Save-QTrackCover] Top score: {0}" -f ($scored[0].Score)) }

			# If interactive mode requested, verify interactivity is possible and, if so, offer chooser when auto-download not triggered
			$interactivePossible = $true
			if ($Interactive) {
				try {
					if (-not ($Host -and $Host.UI -and $Host.UI.RawUI)) { $interactivePossible = $false }
					if ([System.Console]::IsInputRedirected -or [System.Console]::IsOutputRedirected) { $interactivePossible = $false }
				} catch { $interactivePossible = $false }
				if (-not $interactivePossible) {
					# Return the candidate list and friendly message so caller can decide next steps
					Write-Output ([PSCustomObject]@{ Message = 'Interactive mode requested but not possible in this session (host does not support prompts or stdin/stdout is redirected). Returned candidates for offline inspection.'; Candidates = $scored })
					return
				}
			}

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
			# Ensure we have a usable destination folder when saving images; fall back to TEMP if none provided
			$actualDest = if ($PSBoundParameters.ContainsKey('DestinationFolder') -and $DestinationFolder -and $DestinationFolder.ToString().Trim() -ne '') { $DestinationFolder } else { $env:TEMP }
			# allow auto-download when score meets threshold AND there is track/album evidence, OR when user provided a direct page URL (CorrectUrl) and candidates exist
			# This prevents artist-only / position-only matches from being auto-selected.
			# If user explicitly requested interactive mode, suppress automatic download so the chooser is presented.
			$hasStrongEvidence = $false
			try {
				if ($scored -and $scored.Count -gt 0) {
					$top = $scored[0]
					$topTrack = [double]$top.TrackScore
					$topArtist = [double]$top.ArtistScore
					$topAlbum = [double]$top.AlbumScore
					# Require a moderate track match plus supporting artist or album evidence,
					# or a very strong album match (for compilation titles etc.)
					$hasStrongEvidence = ( ($topTrack -gt 0.2) -and ( ($topArtist -gt 0.2) -or ($topAlbum -gt 0.2) ) ) -or ($topAlbum -gt 0.4)
				}
			} catch { $hasStrongEvidence = $false }

			$allowAutoDownload = (-not $NoAuto) -and ($scored.Count -gt 0) -and ( ( ($scored[0].Score -ge $Threshold) -and $hasStrongEvidence ) -or ($PSBoundParameters.ContainsKey('CorrectUrl') -and $CorrectUrl) ) -and (-not $Interactive)

			# Diagnostic verbose output to explain auto-download decision
			try {
				if ($scored -and $scored.Count -gt 0) {
					$top = $scored[0]
					Write-Verbose ("[Save-QTrackCover] Top candidate scores: Score={0}, Track={1}, Artist={2}, Album={3}, ExactTitleBonus={4}, ExactArtistBonus={5}, PositionBonus={6}" -f $top.Score, $top.TrackScore, $top.ArtistScore, $top.AlbumScore, $top.ExactTitleBonus, $top.ExactArtistBonus, $top.PositionBonus)
					Write-Verbose ("[Save-QTrackCover] hasStrongEvidence={0}; Threshold={1}; NoAuto={2}; CorrectUrlProvided={3}; Interactive={4}; allowAutoDownload={5}" -f $hasStrongEvidence, $Threshold, $NoAuto.IsPresent, ($PSBoundParameters.ContainsKey('CorrectUrl') -and $CorrectUrl), $Interactive.IsPresent, $allowAutoDownload)
				}
			} catch {}
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
					$local = Save-Image -ImageUrl $imgUrl -DestinationFolder $actualDest -DownloadMode $DownloadMode -FileNameStyle $FileNameStyle -CustomFileName $CustomFileName -Album $SearchTrack -Artist $SearchArtist
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
					Input       = [PSCustomObject]@{ SearchTrack = $SearchTrack; SearchArtist = $SearchArtist; SearchAlbum = $SearchAlbum; AudioFile = $AudioFilePath; SearchUrl = $searchUrl }
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
				# If interactive was requested and possible, invoke chooser here before returning
				if ($Interactive) {
					# import helper and invoke
					#. (Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath '..\private\Select-QobuzCandidate.ps1') -ErrorAction SilentlyContinue
					$attempt = 0
					do {
						$choice = Select-QobuzCandidate -Scored $scored -Threshold $Threshold -SearchTrack $SearchTrack -SearchArtist $SearchArtist -SearchAlbum $SearchAlbum -SearchUrl $searchUrl -AllowAutoSelect:(!$Interactive)
						if ($choice.Action -eq 'AutoSelected' -or $choice.Action -eq 'Selected') {
						$best = $choice.SelectedCandidate
						# proceed to download/embed same as autoDownloaded path
						$imgUrl = $best.ImageUrl
						if ($imgUrl -match '_\d+\.jpg$') { $imgUrl = $imgUrl -replace '_\d+\.jpg$', ('_{0}.jpg' -f $Size) }
						elseif ($imgUrl -match '_max\.jpg$') { $imgUrl = $imgUrl -replace '_max\.jpg$', ('_{0}.jpg' -f $Size) }
						if ($Embed) {
							$tempDir = Join-Path -Path $env:TEMP -ChildPath (New-Guid).Guid
							New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
							$local = Save-Image -ImageUrl $imgUrl -DestinationFolder $tempDir -DownloadMode $DownloadMode -FileNameStyle $FileNameStyle -CustomFileName $CustomFileName -Album $SearchTrack -Artist $SearchArtist
						}
						else {
							$local = Save-Image -ImageUrl $imgUrl -DestinationFolder $actualDest -DownloadMode $DownloadMode -FileNameStyle $FileNameStyle -CustomFileName $CustomFileName -Album $SearchTrack -Artist $SearchArtist
						}
						# If embedding requested, write and cleanup similar to autoDownloaded path
						if ($Embed -and $AudioFilePath) {
							$ok = Set-TrackImageWithFFmpeg -AudioFilePath $AudioFilePath -ImagePath $local
							if ($ok) {
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
							break
						}
						elseif ($choice.Action -eq 'ManualSearch' -and $choice.ManualSearchRaw) {
							$attempt++
							if ($attempt -gt $MaxInteractiveAttempts) {
								Write-Output ([PSCustomObject]@{ Message = 'MaxInteractiveAttemptsReached'; ManualSearch = $choice.ManualSearchRaw; Candidates = $scored })
								return
							}
							# parse ManualSearchRaw according to shorthand: Title|Artist|Album
							$raw = $choice.ManualSearchRaw
							# split into up to 3 parts, allow quoted segments using ' or "
							$parts = @()
							$sb = '' ; $inQuote = $false ; $quoteChar = $null
							for ($i = 0; $i -lt $raw.Length; $i++) {
								$ch = $raw[$i]
								if ($inQuote) {
									if ($ch -eq $quoteChar) { $inQuote = $false; continue }
									$sb += $ch
								}
								else {
									if ($ch -eq '"' -or $ch -eq "'") { $inQuote = $true ; $quoteChar = $ch ; continue }
									if ($ch -eq '|') { $parts += $sb ; $sb = ''; continue }
									$sb += $ch
								}
							}
							$parts += $sb
							# pad to 3 with '=' (keep)
							while ($parts.Count -lt 3) { $parts += '=' }
							# apply rules: '=' => keep, '' => wipe, otherwise set (trim)
							$newTitle = $SearchTrack; $newArtist = $SearchArtist; $newAlbum = $SearchAlbum
							$p = $parts[0].Trim(); if ($p -ne '=') { if ($p -eq '') { $newTitle = '' } else { $newTitle = $p } }
							$p = $parts[1].Trim(); if ($p -ne '=') { if ($p -eq '') { $newArtist = '' } else { $newArtist = $p } }
							$p = $parts[2].Trim(); if ($p -ne '=') { if ($p -eq '') { $newAlbum = '' } else { $newAlbum = $p } }
							$SearchTrack = $newTitle; $SearchArtist = $newArtist; $SearchAlbum = $newAlbum
							Write-Verbose ("[Save-QTrackCover] ManualSearch attempt {0}: Title='{1}' Artist='{2}' Album='{3}'" -f $attempt, $SearchTrack, $SearchArtist, $SearchAlbum)
							# rebuild search and candidates
							$searchUrl = New-QTrackSearchUrl -Track $SearchTrack -Artist $SearchArtist -Album $SearchAlbum
							$html = Get-QTrackSearchHtml -Url $searchUrl
							$candidates = ConvertFrom-QTrackSearchResults -Html $html -MaxCandidates $MaxCandidates
							$scored = foreach ($c in $candidates) { Get-MatchQTrackResult -Track $SearchTrack -Artist $SearchArtist -Candidate $c }
							$scored = $scored | Sort-Object -Property @{
								Expression = { $_.Score }
								Descending = $true
							}, @{
								Expression = { if ($_.Candidate -and $_.Candidate.PSObject.Properties.Match('Index')) { [int]$_.Candidate.Index } else { [int]::MaxValue } }
								Descending = $false
							}
							continue
						}
						elseif ($choice.Action -in @('Skip','Abort')) {
							Write-Output ([PSCustomObject]@{ Message = $choice.Message; Candidates = $scored })
							return
						}
						else {
							# fall back to returning candidates for inspection
							Write-Output $scored
							if ($reportPath) { Write-Output $reportPath }
							return
						}
					} while ($true)
					elseif ($choice.Action -in @('Skip','Abort')) {
						Write-Output ([PSCustomObject]@{ Message = $choice.Message; Candidates = $scored })
						return
					}
					else {
						# fall back to returning candidates for inspection
						Write-Output $scored
						if ($reportPath) { Write-Output $reportPath }
						return
					}
				}
				else {
					Write-Output $scored
					if ($reportPath) { Write-Output $reportPath }
					return
				}
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
					Input = [PSCustomObject]@{ SearchTrack = $SearchTrack; SearchArtist = $SearchArtist; AudioFile = $AudioFilePath; SearchUrl = $searchUrl }
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
 
