#. (Join-Path $PSScriptRoot 'LogHelper.ps1')

<#
.SYNOPSIS
Download a single artist image from Qobuz.

.DESCRIPTION
`Save-QobuzArtistImage` searches Qobuz for the provided artist name, follows the artist page if needed, and downloads the preferred-size cover image to the specified destination.

.PARAMETER ArtistName
Artist name to search for.

.PARAMETER DestinationPath
Directory to save the downloaded image.

.PARAMETER FileNameStyle
Either 'Hyphen' (default) or 'Spaces' for generated filenames.

.PARAMETER PreferredSize
Preferred image size: large (default), medium or small.

.PARAMETER Force
Overwrite existing files.

.OUTPUTS
Returns the full path of the downloaded file on success.
#>
function Save-QobuzArtistImage {
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
	Param(
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$ArtistName,

		[Parameter(Mandatory = $true, Position = 1)]
		[ValidateNotNullOrEmpty()]
		[string]$DestinationPath,

		[ValidateSet('Hyphen', 'Spaces')]
		[string]$FileNameStyle = 'Hyphen',

		[ValidateSet('large', 'medium', 'small')]
		[string]$PreferredSize = 'large',

		[switch]$Force
	)

	Begin {
		if (-not (Test-Path -Path $DestinationPath)) { New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null }
		$searchUrl = 'https://www.qobuz.com/be-nl/search/artists/' + [System.Uri]::EscapeDataString($ArtistName)
		Write-Log -Message "Searching Qobuz: $searchUrl" -Level Verbose -Category Search
	}

	Process {
		try {
			$headers = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'; 'Accept-Language' = 'en-US,en;q=0.9' }
			$response = Invoke-WebRequest -Uri $searchUrl -Headers $headers -UseBasicParsing -ErrorAction Stop
			$html = $response.Content
			Write-Log -Message "Fetched HTML length inside function: $($html.Length)" -Level Verbose -Category Fetch

			# Require PowerHTML's ConvertFrom-Html (HtmlAgilityPack). Provide installation hint if missing.
			$convertCmd = Get-Command -Name ConvertFrom-Html -Module PowerHTML -ErrorAction SilentlyContinue
			if (-not $convertCmd) {
				throw "Parsing requires the PowerHTML module. Install it from PSGallery: Install-Module -Name PowerHTML -Scope CurrentUser"
			}

			Write-Log -Message "Using PowerHTML ConvertFrom-Html for parsing" -Level Debug -Category Parser
			try {
				$docNode = ConvertFrom-Html -Content $html
			}
			catch {
				throw "ConvertFrom-Html failed: $($_.Exception.Message)"
			}

			try {
				$searchResultImg = $docNode.SelectSingleNode('//*[@id="search"]/section[2]/div/ul/li[1]/div/div[1]/img')
				if ($searchResultImg) {
					# prefer data-src, data-srcset, srcset, then src — use Attributes collection first for reliability
					$srVal = $null
					if ($searchResultImg.Attributes['data-src']) { $srVal = $searchResultImg.Attributes['data-src'].Value }
					elseif ($searchResultImg.Attributes['data-srcset']) { $srVal = $searchResultImg.Attributes['data-srcset'].Value }
					elseif ($searchResultImg.Attributes['srcset']) { $srVal = $searchResultImg.Attributes['srcset'].Value }
					elseif ($searchResultImg.Attributes['src']) { $srVal = $searchResultImg.Attributes['src'].Value }
					else {
						# fallback to GetAttributeValue if the wrapper provides it
						try { $srVal = $searchResultImg.GetAttributeValue('data-src', $null) } catch {}
						if (-not $srVal) { try { $srVal = $searchResultImg.GetAttributeValue('data-srcset', $null) } catch {} }
						if (-not $srVal) { try { $srVal = $searchResultImg.GetAttributeValue('srcset', $null) } catch {} }
						if (-not $srVal) { try { $srVal = $searchResultImg.GetAttributeValue('src', $null) } catch {} }
					}

					if (-not $srVal) {
						# helpful debug output when running with -Verbose
						Write-Verbose ("Search-result img attributes: " + ($searchResultImg.Attributes | ForEach-Object { $_.Name + '=' + $_.Value } -join '; '))
					}

					if ($srVal) {
						$imgUrl = $srVal
						Write-Log -Message "Found image in search results XPath; using candidate: $imgUrl" -Level Verbose -Category Parser
					}
				}
			}
			catch {
				Write-Log -Message "Search-results XPath check failed: $($_.Exception.Message)" -Level Debug -Category Parser
			}



			if ($imgUrl.StartsWith('//')) { $imgUrl = 'https:' + $imgUrl }
			elseif ($imgUrl.StartsWith('/')) { $imgUrl = 'https://www.qobuz.com' + $imgUrl }

			# Normalize to the user's preferred size folder
			if ($imgUrl -match '/covers/[^/]+/') {
				$imgUrl = $imgUrl -replace '/covers/[^/]+/', "/covers/$PreferredSize/"
			}
			else {
				# replace any known size token with preferred size
				$imgUrl = $imgUrl -replace '(large|medium|small|xlarge|original)', $PreferredSize
			}

			Write-Log -Message "Resolved image URL: $imgUrl" -Level Verbose -Category URL

			if ($FileNameStyle -eq 'Hyphen') { $fileBase = ($ArtistName -replace '\s+', '-') } else { $fileBase = $ArtistName }
			$invalid = [System.IO.Path]::GetInvalidFileNameChars()
			$chars = $fileBase.ToCharArray() | Where-Object { $invalid -notcontains $_ }
			$fileBase = -join $chars
			$fileName = ($fileBase.Trim() + '.jpg')
			$outPath = Join-Path -Path $DestinationPath -ChildPath $fileName

			if (Test-Path -Path $outPath -PathType Leaf -ErrorAction SilentlyContinue) {
				if (-not $Force) { throw "File already exists: $outPath. Use -Force to overwrite." } else { Remove-Item -Path $outPath -Force -ErrorAction Stop }
			}

			if ($PSCmdlet.ShouldProcess($outPath, 'Download image from Qobuz')) {
				Write-Log -Message "Downloading image to $outPath" -Level Verbose -Category Download
				Invoke-WebRequest -Uri $imgUrl -OutFile $outPath -UseBasicParsing -ErrorAction Stop
				Write-Log -Message $outPath -Level Info -Category Result
				return $outPath
			}
		}
		catch { Throw $_ }
	}
}
