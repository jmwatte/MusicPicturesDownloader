
<#
.SYNOPSIS
Finds and saves an album cover from Qobuz for a given album and artist.

.DESCRIPTION
Searches Qobuz for the specified album and artist, scores candidates, and downloads the best match according to the specified options. Supports automatic download, candidate reporting, file naming, and download mode control.

.PARAMETER Album
The album name to search for. Mandatory.

.PARAMETER Artist
The artist name to search for. Mandatory.

.PARAMETER DestinationFolder
The folder where the album cover will be saved. Mandatory.

.PARAMETER Size
Preferred image size: 230, 600, or max. Default is 230.

.PARAMETER DownloadMode
Controls download behavior: Always (overwrite), IfBigger (only if remote image is larger), SkipIfExists (skip if file exists). Default is Always.

.PARAMETER FileNameStyle
Controls file naming: Folder (folder.jpg), Cover (cover.jpg), Album-Artist, Artist-Album, or Custom (use CustomFileName). Default is Cover.

.PARAMETER CustomFileName
Custom file name format string (use {Album} and {Artist} as placeholders). Used if FileNameStyle is Custom.

.PARAMETER Auto
If set, automatically downloads the best candidate if its score meets the threshold.

.PARAMETER Threshold
Minimum score required for auto-download. Default is 0.75.

.PARAMETER GenerateReport
If set, generates a JSON report of all candidates and their scores.

.PARAMETER MaxCandidates
Maximum number of candidates to consider. Default is 10.

.OUTPUTS
If -Auto is used and a cover is downloaded: outputs the local file path. If a report is generated, also outputs the report file path.
If -Auto is not used: outputs an array of scored candidate objects. If a report is generated, also outputs the report file path.
If no candidates are found: outputs $null (and report path if generated).

.EXAMPLE
Save-QAlbumCover -Album "Back in Black" -Artist "AC/DC" -DestinationFolder "C:\Covers" -Auto -Verbose

.EXAMPLE
Save-QAlbumCover -Album "Thriller" -Artist "Michael Jackson" -DestinationFolder "C:\Covers" -GenerateReport -FileNameStyle Album-Artist

.NOTES
Requires PowerHTML module for HTML parsing.
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
    [ValidateSet('Always','IfBigger','SkipIfExists')]
    [string]$DownloadMode = 'Always',
    [ValidateSet('Folder','Cover','Album-Artist','Artist-Album','Custom')]
    [string]$FileNameStyle = 'Cover',
    [string]$CustomFileName,
    [switch]$Auto,
    [double]$Threshold = 0.75,
    [switch]$GenerateReport,
    [int]$MaxCandidates = 10
    )

    process {
    $url = Build-QSearchUrl -Album $Album -Artist $Artist
    Write-Verbose "[Save-QAlbumCover] Searching: $url"

    $html = Get-QSearchHtml -Url $url
    Write-Verbose ("[Save-QAlbumCover] HTML length: {0}" -f ($html.Length))

    $candidates = Parse-QSearchResults -HtmlContent $html -MaxCandidates $MaxCandidates
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
            $local = Download-Image -ImageUrl $imgUrl -DestinationFolder $DestinationFolder -DownloadMode $DownloadMode -FileNameStyle $FileNameStyle -CustomFileName $CustomFileName -Album $Album -Artist $Artist
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
