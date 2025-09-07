<#
.SYNOPSIS
    Parse Qobuz FollowingCard nodes to extract artist-like entries.

.DESCRIPTION
    This function uses the PowerHTML DOM parser only and expects the
    node pattern: //*[@id="search"]/section[2]/div/ul/li/div[@class="FollowingCard"].
    For each FollowingCard it reads the title attribute as the display name,
    reads the first token of the ReleaseCardInfosSubtitle span as the release count
    (parsed as an integer when possible), and extracts a thumbnail URL from an
    inner <img> element (data-src then src).

.PARAMETER Html
    The HTML content string returned by Qobuz search.

.PARAMETER MaxCandidates
    Maximum number of candidates to return (0 or negative = unlimited).
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

    $nodes = $doc.SelectNodes('//*[@id="search"]/section[2]/div/ul/li/div[@class="FollowingCard"]')
    if (-not $nodes -or $nodes.Count -eq 0) {
        Write-Output $results
        return
    }

    foreach ($node in $nodes) {
        if ($MaxCandidates -gt 0 -and $results.Count -ge $MaxCandidates) { break }

        # Name from title attribute
        $name = $null
        try { if ($node.Attributes['title']) { $name = ($node.Attributes['title'].Value -as [string]).Trim() } } catch { $name = $null }

        # Release count: first token of the subtitle span, parsed as int when possible
        $albumCount = $null
        $span = $node.SelectSingleNode('.//span[contains(@class,"ReleaseCardInfosSubtitle")]')
        if ($span -and $span.InnerText) {
            $text = ($span.InnerText -as [string]).Trim()
            $parts = $text -split '\s+'
            if ($parts.Count -gt 0) {
                $val = 0
                if ([int]::TryParse($parts[0], [ref]$val)) { $albumCount = $val }
            }
        }

        # Thumbnail
        $thumb = $null
        $img = $node.SelectSingleNode('.//img')
        if ($img -and $img.Attributes) {
            if ($img.Attributes['data-src']) { $thumb = $img.Attributes['data-src'].Value }
            elseif ($img.Attributes['src']) { $thumb = $img.Attributes['src'].Value }
        }

        $obj = [PSCustomObject]@{
            Index = $index
            Name = $name
            AlbumCount = ($albumCount -as [int])
            Thumbnail = $thumb
        }
        $results.Add($obj)
        $index++
    }

    Write-Output $results
}
