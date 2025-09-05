function Get-QobuzPageImageInfo {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Url,

		[ValidateSet('230', '600', 'max')]
		[string]$PreferredSize = '230',

		# Optional: if provided, try to find a matching track title in the playerTracks list
		[string]$MatchTrack
	)

	process {
		# Ensure PowerHTML is available
		$convertCmd = Get-Command -Name ConvertFrom-Html -Module PowerHTML -ErrorAction SilentlyContinue
		if (-not $convertCmd) {
			throw "Parsing requires the PowerHTML module. Install it from PSGallery: Install-Module -Name PowerHTML -Scope CurrentUser"
		}

		try {
			$headers = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'; 'Accept-Language' = 'en-US,en;q=0.9' }
			$response = Invoke-WebRequest -Uri $Url -Headers $headers -UseBasicParsing -ErrorAction Stop
			$html = $response.Content
		}
		catch {
			throw "Failed to fetch URL $Url : $($_.Exception.Message)"
		}

		try {
			$doc = ConvertFrom-Html -Content $html
		}
		catch {
			throw "ConvertFrom-Html failed for $Url : $($_.Exception.Message)"
		}

		$results = [System.Collections.Generic.List[object]]::new()
		$index = 0

		try {
			# Use the specific XPath for the single album image
			$imgNode = $doc.SelectSingleNode('//*[@id="album"]/section[1]/div[1]/div[1]/img')
			if (-not $imgNode) {
				# no image found, return empty list
				Write-Verbose ("[Get-QobuzPageImageInfo] No image node found at expected XPath for {0}" -f $Url)
				Write-Output $results
				return
			}

			# prefer title/data-src/src attributes
			$imgVal = $null
			$imgTitle = $null
			if ($imgNode.Attributes['title']) { $imgTitle = $imgNode.Attributes['title'].Value }
			foreach ($attr in @('data-src', 'data-srcset', 'srcset', 'src')) {
				try { if ($imgNode.Attributes[$attr]) { $imgVal = $imgNode.Attributes[$attr].Value; break } } catch {}
			}
			if (-not $imgVal) {
				try { $imgVal = $imgNode.GetAttributeValue('data-src', $null) } catch {}
				if (-not $imgVal) { try { $imgVal = $imgNode.GetAttributeValue('src', $null) } catch {} }
			}

			if (-not $imgVal -or $imgVal.Trim() -eq '') {
				Write-Verbose ("[Get-QobuzPageImageInfo] Image attribute empty for {0}" -f $Url)
				Write-Output $results
				return
			}

			$imgUrl = [string]$imgVal.Trim()

			# Make absolute if protocol-relative or root-relative
			if ($imgUrl.StartsWith('//')) { $imgUrl = 'https:' + $imgUrl }
			elseif ($imgUrl.StartsWith('/')) {
				$baseUri = [uri]$Url
				$imgUrl = ($baseUri.Scheme + '://' + $baseUri.Host + $imgUrl)
			}

			# Normalize known size tokens to preferred size
			if ($imgUrl -match '_\d+\.jpg$') {
				$imgUrl = $imgUrl -replace '_\d+\.jpg$', ('_{0}.jpg' -f $PreferredSize)
			}
			elseif ($imgUrl -match '_max\.jpg$') {
				$imgUrl = $imgUrl -replace '_max\.jpg$', ('_{0}.jpg' -f $PreferredSize)
			}
			elseif ($imgUrl -match '/covers/[^/]+/') {
				$imgUrl = $imgUrl -replace '/covers/[^/]+/', "/covers/$PreferredSize/"
			}

			# Normalize helper: decode HTML, remove parenthetical, strip diacritics/punctuation, lower and collapse spaces
			Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
			function Normalize-ForMatch {
				param([string]$s)
				if (-not $s) { return $null }
				$s = [System.Web.HttpUtility]::HtmlDecode([string]$s)
				# remove parenthetical content
				$s = $s -replace '\s*\(.*?\)', ''
				# normalize form C then form D to strip diacritics
				$s = $s.Normalize([System.Text.NormalizationForm]::FormC)
				$decomposed = $s.Normalize([System.Text.NormalizationForm]::FormD)
				# remove non-spacing marks (diacritics)
				$chars = $decomposed.ToCharArray() | Where-Object {
					[globalization.charunicodeinfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark
				}
				$s = -join $chars
				# remove punctuation except spaces and alnum
				$s = $s -replace '[^\p{L}\p{N}\s]', ' '
				# collapse whitespace and lowercase
				$s = ($s -replace '\s+',' ').Trim().ToLowerInvariant()
				return $s
			}

			$foundTitle = $null; $foundArtist = $null; $foundAlbum = $null
			# derive artist/album from img title if present (format: Artist|Album)
			if ($imgTitle -and ($imgTitle.Trim() -ne '')) {
				$decoded = [System.Web.HttpUtility]::HtmlDecode([string]$imgTitle).Trim()
				$parts = $decoded -split '\|', 2
				if ($parts.Count -ge 2) {
					$foundArtist = $parts[0].Trim()
					$foundAlbum  = $parts[1].Trim()
				}
				else { $foundTitle = $decoded }
			}

			# If MatchTrack provided, iterate all track nodes under #playerTracks and pick first plausible match.
			if ($MatchTrack) {
				$matchNorm = Normalize-ForMatch $MatchTrack
				try {
					$trackNodes = $doc.SelectNodes("//*[@id='playerTracks']//div[contains(@class,'track')]")
					if ($trackNodes) {
						foreach ($t in $trackNodes) {
							$candidate = $null
							# 1) try data-track-v2 attribute (JSON-ish)
							try {
								if ($t.Attributes['data-track-v2']) {
									$raw = $t.Attributes['data-track-v2'].Value
									$raw = [System.Web.HttpUtility]::HtmlDecode($raw)
									try { $j = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { $j = $null }
									if ($j -and $j.item_name) { $candidate = [string]$j.item_name }
								}
							} catch {}
							# 2) try track__items title attribute or span text
							if (-not $candidate) {
								try {
									$items = $t.SelectSingleNode(".//div[contains(@class,'track__items')]")
									if ($items) {
										if ($items.Attributes['title']) { $candidate = $items.Attributes['title'].Value }
										else {
											$span = $items.SelectSingleNode(".//div[contains(@class,'track__item--name')]//span")
											if ($span) { $candidate = ($span.InnerText -as [string]) }
										}
									}
								} catch {}
							}
							if (-not $candidate) { continue }
							$cNorm = Normalize-ForMatch $candidate
							if (-not $cNorm) { continue }
							# match if either contains the other
							if (($cNorm.Contains($matchNorm)) -or ($matchNorm.Contains($cNorm))) {
								$foundTitle = $candidate.Trim()
								break
							}
						}
					}
				}
				catch { Write-Verbose ("[Get-QobuzPageImageInfo] playerTracks parse error: {0}" -f $_) }
			}

			# fallback small metadata extraction when not found
			if (-not $foundTitle) {
				try {
					$h1 = $doc.SelectSingleNode('//h1'); if ($h1) { $foundTitle = ($h1.InnerText -as [string]).Trim() }
					if (-not $foundArtist) { $artistNode = $doc.SelectSingleNode("//a[contains(@href,'/artist/') or contains(@class,'artist')]"); if ($artistNode) { $foundArtist = ($artistNode.InnerText -as [string]).Trim() } }
					if (-not $foundAlbum)  { $albumLink = $doc.SelectSingleNode("//a[contains(@href,'/album/') and not(contains(@class,'artist'))]"); if ($albumLink) { $foundAlbum = ($albumLink.InnerText -as [string]).Trim() } }
				} catch {}
			}

			# Build result object
			$obj = [PSCustomObject]@{
				Index     = $index
				ImageUrl  = $imgUrl
				TitleAttr = if ($foundTitle)  { [System.Web.HttpUtility]::HtmlDecode($foundTitle) } else { $null }
				AlbumAttr = if ($foundAlbum)  { [System.Web.HttpUtility]::HtmlDecode($foundAlbum) } else { $null }
				ArtistAttr= if ($foundArtist) { [System.Web.HttpUtility]::HtmlDecode($foundArtist) } else { $null }
				ResultLink= $Url
			}
			$results.Add($obj)
		}
		catch {
			throw "Error parsing image node from $Url : $($_.Exception.Message)"
		}

		Write-Output $results
	}
}