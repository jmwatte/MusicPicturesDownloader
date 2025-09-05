<#
.SYNOPSIS
    Parses Qobuz track search HTML to extract the first track image URL and metadata.
.DESCRIPTION
    Uses PowerHTML to parse the HTML and extract the image URL and track info from the first result.
.PARAMETER Html
    The HTML content from the Qobuz search page.
#>
function ConvertFrom-QTrackSearchResults {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Html,
		[int]$MaxCandidates = 10
	)

	$convertCmd = Get-Command -Name ConvertFrom-Html -Module PowerHTML -ErrorAction SilentlyContinue
	if (-not $convertCmd) {
		throw "Parsing requires the PowerHTML module. Install it from PSGallery: Install-Module -Name PowerHTML -Scope CurrentUser"
	}

	$doc = ConvertFrom-Html -Content $Html
	$results = [System.Collections.Generic.List[object]]::new()
	$index = 0

	$trackNodes = $doc.SelectNodes('//*[@id="search"]/section[2]/div/ul/li')
	if (-not $trackNodes) {
		Write-Output $results
		return
	}

	foreach ($li in $trackNodes) {
		if ($MaxCandidates -gt 0 -and $results.Count -ge $MaxCandidates) { break }

		# Image: prefer data-src then src
		$imgNode = $li.SelectSingleNode('.//div/a/img')
		if (-not $imgNode) { $imgNode = $li.SelectSingleNode('.//img') }
		$src = $null
		if ($imgNode) {
			if ($imgNode.Attributes['data-src']) { $src = $imgNode.Attributes['data-src'].Value }
			elseif ($imgNode.Attributes['src']) { $src = $imgNode.Attributes['src'].Value }
		}

		# Title: try user-supplied absolute XPath for this li, then relative fallbacks //*[@id="search"]/section[2]/div/ul/li[1]/div/div[1]/a
		$titleNode = $null
		try {
			$xpath = "//*[@id='search']/section[2]/div/ul/li[$($index + 1)]/div/div[1]/a"
			$titleNode = $doc.SelectSingleNode($xpath)
		}
		catch {
			$titleNode = $null
		}
		if (-not $titleNode) {
			$titleNode = $li.SelectSingleNode('.//div/div[1]/a')
		}
		if (-not $titleNode) { $titleNode = $li.SelectSingleNode('.//a') }
		$trackTitle = $null
		if ($titleNode) {
			# Prefer the 'title' attribute when present (many Qobuz anchors store the title there)
			try {
				if ($titleNode.Attributes['title'] -and ($titleNode.Attributes['title'].Value -as [string]).Trim() -ne '') {
					$trackTitle = $titleNode.Attributes['title'].Value
				}
				else {
					$trackTitle = ($titleNode.InnerText -as [string])
				}
			}
			catch {
				# Fallbacks if Attributes access fails
				$trackTitle = ($titleNode.InnerText -as [string])
				if (-not $trackTitle -or $trackTitle.Trim() -eq '') {
					if ($titleNode.PSObject.Properties['title']) { $trackTitle = $titleNode.PSObject.Properties['title'].Value }
				}
			}
			if ($trackTitle) { $trackTitle = $trackTitle.Trim() }
		}
		#//*[@id="search"]/section[2]/div/ul/li[1]/div/div[1]/p/text()
		# Album: paragraph under div/div[1]/p
		$albumNode = $li.SelectSingleNode('.//div/div[1]/p')
		$albumText = $null
		if ($albumNode) { $albumText = ($albumNode.InnerText -as [string]) }

		# Clean and extract artist/album when the <p> contains a block like:
		# "Artist\n•\nAlbum" or "Artist • Album" or multiline with artist then album
		$parsedArtist = $null
		$parsedAlbum = $null
		# ...existing code...
		# Clean and extract artist/album when the <p> contains a block like:
		# "Artist\n•\nAlbum" or "Artist • Album" or multiline with artist then album
    
		if ($albumText) {
			
			


			Add-Type -AssemblyName System.Web
			[string]$raw = $albumText
			$raw = $raw.Normalize([System.Text.NormalizationForm]::FormC)
			$raw = [System.Web.HttpUtility]::HtmlDecode($raw)
			# Normalize and canonicalize whitespace, handle NBSP, preserve separation by newline/bullet
			
			# Replace non-breaking space with regular space
			$raw = $raw -replace '\u00A0', ' '
			# Normalize CRLF to LF
			$raw = $raw -replace "`r`n", "`n"
			$raw = $raw -replace "`r", "`n"

			# Split on newline or bullet characters and trim each part
			$parts = ($raw -split '\s*[\n\u2022\u00B7]\s*') | ForEach-Object { ($_ -as [string]).Trim() } | Where-Object { $_ -ne '' }


			if ($parts.Count -ge 2) {
				$parsedArtist = $parts[0]
				$parsedAlbum = $parts[-1]
			}
			else {
				# fallback: try common separators (dash, en-dash, em-dash, colon)
				$sepParts = [regex]::Split($raw, '\s*[\u2013\u2014\-:]\s*', 2)
				if ($sepParts.Count -ge 2) {
					$parsedArtist = ($sepParts[0] -as [string]).Trim()
					$parsedAlbum = ($sepParts[1] -as [string]).Trim()
				}
				else {
					# Fall back to collapsing internal whitespace and using the whole text as album
					$parsedAlbum = ($raw -replace '\s+', ' ').Trim()
				}
			}

			# Remove only leading/trailing decorative punctuation/whitespace (preserve interior letters)
			if ($parsedArtist) {
				$parsedArtist = [string]$parsedArtist
				$parsedArtist = $parsedArtist -replace '^[\s\p{Pd}\u2022\u00B7:]+', ''
				$parsedArtist = $parsedArtist -replace '[\s\p{Pd}\u2022\u00B7:]+$', ''
			}
			if ($parsedAlbum) {
				$parsedAlbum = [string]$parsedAlbum
				$parsedAlbum = $parsedAlbum -replace '^[\s\p{Pd}\u2022\u00B7:]+', ''
				$parsedAlbum = $parsedAlbum -replace '[\s\p{Pd}\u2022\u00B7:]+$', ''
			}
		}
		# ...existing code...


		<# if ($albumText) {
			$raw = $albumText.Trim()
			# Prefer splitting on the bullet character
			if ($raw -match '•') {
				$parts = $raw -split '•' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
				if ($parts.Count -ge 2) {
					$parsedArtist = $parts[0]
					$parsedAlbum = $parts[1]
				}
				else {
					$parsedAlbum = ($raw -replace '\s+', ' ').Trim()
				}
			}
			else {
				# Try splitting on newlines (common when HTML renders as multiple text nodes)
				$lines = ($raw -split '\r?\n') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
				if ($lines.Count -ge 2) {
					$parsedArtist = $lines[0]
					$parsedAlbum = $lines[ -1 ]
				}
				else {
					# Try common separators (dash, en-dash, colon)
					if ($raw -match '(.+)[\u2013\u2014\-:]+(.+)') {
						$parsedArtist = $matches[1].Trim()
						$parsedAlbum = $matches[2].Trim()
					}
					else {
						$parsedAlbum = $raw
					}
				}
			} 		$trimChars = @(
				[char]0x20,      # space
				[char]0x09,      # tab
				[char]0x0D,      # CR
				[char]0x0A,      # LF
				[char]0x2022,    # • bullet
				[char]0x00B7,    # · middle dot
				'-',
				'–',
				'—',
				':'
			)
			# Trim decorative punctuation
			if ($parsedArtist) { $parsedArtist = $parsedArtist.Trim($trimChars) }
			if ($parsedAlbum) { $parsedAlbum = $parsedAlbum.Trim($trimChars) }
		}
 #>
		# Artist: sometimes present in title or elsewhere; attempt reasonable extraction
		$artist = $null
		# If title contains ' by ' pattern, prefer parsed artist
		if ($trackTitle -and ($trackTitle -cmatch '\bby\b')) {
            if ($trackTitle -cmatch '^(?<title>.+?)\s+by\s+(?<artist>.+)$') {
                $maybeTitle = $Matches['title'].Trim()
                $maybeArtist = $Matches['artist'].Trim(' .')
                # Basic plausibility: artist part should be more than one character and contain a letter
                if ($maybeArtist.Length -gt 1 -and ($maybeArtist -match '\p{L}')) {
                    # Only override when we don't already have a parsed artist from album block
                    if (-not $parsedArtist) {
                        $trackTitle = $maybeTitle
                        $artist = $maybeArtist
                    }
                }
            }
        }

		# Prefer artist parsed from album block when available
		if (-not $artist -and $parsedArtist) { $artist = $parsedArtist }
		# Prefer album parsed from album block when available
		if ($parsedAlbum) { $albumText = $parsedAlbum }

		# Result link
		$linkNode = $titleNode
		$href = $null
		if ($linkNode) { $href = $linkNode.Attributes['href'] ? $linkNode.Attributes['href'].Value : $null }
		if ($href -and $href.StartsWith('/')) { $href = "https://www.qobuz.com$href" }

		 Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
            $obj = [PSCustomObject]@{
                Index     = $index
                ImageUrl  = $src
                TitleAttr = [System.Web.HttpUtility]::HtmlDecode(($trackTitle -as [string]))
                AlbumAttr = if ($parsedAlbum)  { [System.Web.HttpUtility]::HtmlDecode(($parsedAlbum -as [string])) } else { $null }
                ArtistAttr= if ($parsedArtist) { [System.Web.HttpUtility]::HtmlDecode(($parsedArtist -as [string])) } else { $null }
                ResultLink= $href
            }
		$results.Add($obj)
		$index++
	}
	Write-Output $results
}
