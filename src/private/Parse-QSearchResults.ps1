<#
.SYNOPSIS
Parses Qobuz album search HTML and extracts candidate album cover entries using PowerHTML and XPath.
#>
function Parse-QSearchResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HtmlContent,
        [int]$MaxCandidates = 10
    )

    process {
        $convertCmd = Get-Command -Name ConvertFrom-Html -Module PowerHTML -ErrorAction SilentlyContinue
        if (-not $convertCmd) {
            throw "Parsing requires the PowerHTML module. Install it from PSGallery: Install-Module -Name PowerHTML -Scope CurrentUser"
        }

        $docNode = ConvertFrom-Html -Content $HtmlContent
        $results = [System.Collections.Generic.List[object]]::new()
        $index = 0

        # XPath for album candidates: all li nodes under the album search results section
        $albumNodes = $docNode.SelectNodes('//*[@id="search"]/section[2]/div/ul/li')
        foreach ($li in $albumNodes) {
            if ($MaxCandidates -gt 0 -and $results.Count -ge $MaxCandidates) { break }
            # Image node: usually under div/img or div/div[1]/img
            $imgNode = $li.SelectSingleNode('.//img')
            $aNode = $li.SelectSingleNode('.//div[1]/a')
            if ($imgNode -and $aNode) {
                # Prefer data-src, then src
                $src = $null
                if ($imgNode.Attributes['data-src']) { $src = $imgNode.Attributes['data-src'].Value }
                elseif ($imgNode.Attributes['src']) { $src = $imgNode.Attributes['src'].Value }
                # Title attribute from the <a> node
                $title = $aNode.Attributes['title'] ? $aNode.Attributes['title'].Value : $null
                # Link to album result
                $href = $aNode.Attributes['href'] ? $aNode.Attributes['href'].Value : $null

                $obj = [PSCustomObject]@{
                    Index = $index
                    ImageUrl = $src
                    TitleAttr = $title
                    ResultLink = $href
                }
                $results.Add($obj)
                $index++
            }
        }
        Write-Output $results
    }
}
