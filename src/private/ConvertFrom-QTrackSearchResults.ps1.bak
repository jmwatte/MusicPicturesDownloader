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

        # Title: try user-supplied absolute XPath for this li, then relative fallbacks
        $titleNode = $null
        try {
            $xpath = "//*[@id='search']/section[2]/div/ul/li[$($index + 1)]/div/div[1]/a"
            $titleNode = $doc.SelectSingleNode($xpath)
        } catch {
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
                } else {
                    $trackTitle = ($titleNode.InnerText -as [string])
                }
            } catch {
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
        if ($albumText) {
            $raw = $albumText.Trim()
            # Prefer splitting on the bullet character
            if ($raw -match '•') {
                $parts = $raw -split '•' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
                if ($parts.Count -ge 2) {
                    $parsedArtist = $parts[0]
                    $parsedAlbum = $parts[1]
                } else {
                    $parsedAlbum = ($raw -replace '\s+', ' ').Trim()
                }
            } else {
                # Try splitting on newlines (common when HTML renders as multiple text nodes)
                $lines = ($raw -split '\r?\n') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
                if ($lines.Count -ge 2) {
                    $parsedArtist = $lines[0]
                    $parsedAlbum = $lines[ -1 ]
                } else {
                    # Try common separators (dash, en-dash, colon)
                    if ($raw -match '(.+)[\u2013\u2014\-:]+(.+)') {
                        $parsedArtist = $matches[1].Trim()
                        $parsedAlbum = $matches[2].Trim()
                    } else {
                        $parsedAlbum = $raw
                    }
                }
            }

            # Trim decorative punctuation
            if ($parsedArtist) { $parsedArtist = $parsedArtist.Trim(' \t\r\n\u2022\u00B7-–—:') }
            if ($parsedAlbum) { $parsedAlbum = $parsedAlbum.Trim(' \t\r\n\u2022\u00B7-–—:') }
        }

        # Artist: sometimes present in title or elsewhere; attempt reasonable extraction
        $artist = $null
        # If title contains ' by ' pattern, prefer parsed artist
        if ($trackTitle -and $trackTitle -match '\bby\b') {
            # attempt to split '... by ...' pattern
            if ($trackTitle -match '(.+)\s+by\s+(.+)$') {
                $maybeTitle = $matches[1].Trim()
                $maybeArtist = $matches[2].Trim(' .')
                # if albumText seems like album, keep it; otherwise override
                $trackTitle = $maybeTitle
                $artist = $maybeArtist
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

        $obj = [PSCustomObject]@{
            Index = $index
            ImageUrl = $src
            TitleAttr = ($trackTitle -as [string])
            AlbumAttr = ($albumText -as [string])
            ArtistAttr = ($artist -as [string])
            ResultLink = $href
        }
        $results.Add($obj)
        $index++
    }
    Write-Output $results
}
