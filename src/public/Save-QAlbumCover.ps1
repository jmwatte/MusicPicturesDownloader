<#
.SYNOPSIS
Public wrapper to find and save an album cover from Q.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Album,
    [string]$Artist,
    [Parameter(Mandatory=$true)]
    [string]$DestinationFolder,
    [switch]$Auto,
    [double]$Threshold = 0.75,
    [switch]$GenerateReport
)

process {
    # Build URL
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\private\Build-QSearchUrl.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\private\Get-QSearchHtml.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\private\Parse-QSearchResults.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\private\Match-QResult.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\private\Download-Image.ps1')

    $url = Build-QSearchUrl -Album $Album
    Write-Verbose "Searching: $url"

    $html = Get-QSearchHtml -Url $url
    $candidates = Parse-QSearchResults -HtmlContent $html

    $scored = foreach ($c in $candidates) { Match-QResult -Album $Album -Artist $Artist -Candidate $c }
    $scored = $scored | Sort-Object -Property Score -Descending

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

    if ($Auto -and $scored.Count -gt 0 -and $scored[0].Score -ge $Threshold) {
        $best = $scored[0].Candidate
        $local = Download-Image -ImageUrl $best.ImageUrl -DestinationFolder $DestinationFolder
        #$downloaded = $local
        Write-Output $local
    }
    else {
        # If not auto or no good match, just produce report
        if ($GenerateReport) {
            $ts = (Get-Date).ToString('yyyyMMddHHmmss')
            $reportPath = Join-Path $DestinationFolder "q_search_report_$ts.json"
            if (-not (Test-Path -Path $DestinationFolder)) {
				 New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null }
            $report | ConvertTo-Json -Depth 4 | Out-File -FilePath $reportPath -Encoding UTF8
            Write-Output $reportPath
        }
        elseif ($scored.Count -gt 0) {
            # show top candidates to the pipeline for manual decision
            Write-Output $scored
        }
        else {
            Write-Output $null
        }
    }
}
