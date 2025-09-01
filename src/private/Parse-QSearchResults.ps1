<#
.SYNOPSIS
Parses Q search HTML and extracts candidate image entries.

This parser uses resilient regex extraction so tests can run without external HTML libs.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HtmlContent
)

process {
    # Find img tags with src and title attributes
    $pattern = '<img[^>]*?src\s*=\s*"(?<src>[^"]+)"[^>]*?title\s*=\s*"(?<title>[^"]+)"[^>]*>'
    $matchColl = [regex]::Matches($HtmlContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $results = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($m in $matchColl) {
        $src = $m.Groups['src'].Value
        $title = $m.Groups['title'].Value

        # Attempt to find a nearby href for the album link (simple heuristic)
        $matchIndex = $m.Index
        $windowStart = [Math]::Max(0, $matchIndex - 500)
        $windowLen = [Math]::Min(1500, $HtmlContent.Length - $windowStart)
        $window = $HtmlContent.Substring($windowStart, $windowLen)
        $hrefPattern = 'href\s*=\s*"(?<href>[^"]+)"'
        $href = ([regex]::Match($window, $hrefPattern)).Groups['href'].Value

        $obj = [PSCustomObject]@{
            Index = $index
            ImageUrl = $src
            TitleAttr = $title
            ResultLink = $href
        }
        $results.Add($obj)
        $index++
    }

    Write-Output $results
}
