
<#
.SYNOPSIS
Public wrapper to find and save an album cover from Q.
#>
function Save-QAlbumCover {
    [CmdletBinding()]
    param(
    [Parameter(Mandatory=$true)]
    [string]$Album,
    [Parameter(Mandatory=$true)]
    [string]$Artist,
    [Parameter(Mandatory=$true)]
    [string]$DestinationFolder,
    [ValidateSet('230','600','max')]
    [string]$Size = '230',
    [switch]$Auto,
    [double]$Threshold = 0.75,
    [switch]$GenerateReport
    )

    process {
    $url = Build-QSearchUrl -Album $Album -Artist $Artist
        Write-Verbose "[Save-QAlbumCover] Searching: $url"

        $html = Get-QSearchHtml -Url $url
        Write-Verbose ("[Save-QAlbumCover] HTML length: {0}" -f ($html.Length))

        $candidates = Parse-QSearchResults -HtmlContent $html
        Write-Verbose ("[Save-QAlbumCover] Candidates found: {0}" -f ($candidates.Count))
        if ($candidates.Count -gt 0) {
            $i = 0
            foreach ($c in $candidates) {
                Write-Verbose ("[Save-QAlbumCover] Candidate[{0}]: Title={1}, ImageUrl={2}" -f $i, $c.TitleAttr, $c.ImageUrl)
                $i++
            }
        }

        $scored = foreach ($c in $candidates) { Get-MatchQResult -Album $Album -Artist $Artist -Candidate $c }
        $scored = $scored | Sort-Object -Property Score -Descending
        Write-Verbose ("[Save-QAlbumCover] Scored candidates: {0}" -f ($scored.Count))
        if ($scored.Count -gt 0) {
            Write-Verbose ("[Save-QAlbumCover] Top score: {0}" -f ($scored[0].Score))
        }

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

        $reportPath = $null
        $local = $null
        $autoDownloaded = $false
        if ($Auto -and $scored.Count -gt 0 -and $scored[0].Score -ge $Threshold) {
            $best = $scored[0].Candidate
            $imgUrl = $best.ImageUrl
            if ($imgUrl -match '_\d+\.jpg$') {
                $imgUrl = $imgUrl -replace '_\d+\.jpg$', ('_{0}.jpg' -f $Size)
            } elseif ($imgUrl -match '_max\.jpg$') {
                $imgUrl = $imgUrl -replace '_max\.jpg$', ('_{0}.jpg' -f $Size)
            }
            Write-Verbose ("[Save-QAlbumCover] Auto mode: Downloading best candidate with score {0} and url {1}" -f $scored[0].Score, $imgUrl)
            $local = Download-Image -ImageUrl $imgUrl -DestinationFolder $DestinationFolder
            $autoDownloaded = $true
        }

        if ($GenerateReport) {
            $ts = (Get-Date).ToString('yyyyMMddHHmmss')
            $reportPath = Join-Path $DestinationFolder "q_search_report_$ts.json"
            if (-not (Test-Path -Path $DestinationFolder)) {
                New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null
            }
            $report | ConvertTo-Json -Depth 4 | Out-File -FilePath $reportPath -Encoding UTF8
            Write-Verbose ("[Save-QAlbumCover] Report written: {0}" -f $reportPath)
        }

        if ($autoDownloaded) {
            Write-Output $local
            if ($reportPath) { Write-Output $reportPath }
        } elseif ($scored.Count -gt 0) {
            Write-Output $scored
            if ($reportPath) { Write-Output $reportPath }
        } else {
            Write-Verbose "[Save-QAlbumCover] No candidates found or scored."
            Write-Output $null
            if ($reportPath) { Write-Output $reportPath }
        }
    }
}
