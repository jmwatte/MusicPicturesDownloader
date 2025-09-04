
<#
.SYNOPSIS
    Find and save an album cover from Qobuz.

.DESCRIPTION
    Searches Qobuz for the given Album and Artist, scores candidate results, and downloads the
    best match according to provided options. Supports automatic download, file naming styles,
    download modes, and optional JSON report generation.

.PARAMETER Album
    The album name to search for. Mandatory.

.PARAMETER Artist
    The artist name to search for. Mandatory.

.PARAMETER DestinationFolder
    The folder where the album cover will be saved.

.PARAMETER Size
    Preferred image size: 230, 600, or max. Default is 230.

.PARAMETER DownloadMode
    Controls download behavior: Always (overwrite), IfBigger (only if remote image is larger), SkipIfExists (skip if file exists).

.PARAMETER FileNameStyle
    Naming scheme for saved images: Folder, Cover, Album-Artist, Artist-Album, or Custom.

.PARAMETER CustomFileName
    Template for custom file names when FileNameStyle is Custom. Use {Album} and {Artist} placeholders.

.PARAMETER Auto
    When set, automatically downloads the top-scoring candidate if it meets the -Threshold.

.PARAMETER Threshold
    Score threshold (0..1) for automatic download when -Auto is used. Default: 0.75

.PARAMETER GenerateReport
    When set, emits a JSON report containing candidate details and scores.

.PARAMETER MaxCandidates
    Maximum number of candidates to evaluate from the search results.

EXAMPLE
    # Download cover for an album (downloads by default)
    Save-QAlbumCover -Album 'Rumours' -Artist 'Fleetwood Mac' -DestinationFolder 'C:\Covers'

EXAMPLE
    # Preview / report-only: do not download
    Save-QAlbumCover -Album 'Kind Of Blue' -Artist 'Miles Davis' -DestinationFolder 'C:\Covers' -NoAuto -GenerateReport

.NOTES
    - Requires the PowerHTML module for HTML parsing.
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
    [switch]$NoAuto,
    [switch]$ShowRawTags,
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
    if (-not $NoAuto -and $scored.Count -gt 0 -and $scored[0].Score -ge $Threshold) {
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
            if (-not (Test-Path -LiteralPath $DestinationFolder)) {
                New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null
            }
            $report | ConvertTo-Json -Depth 4 | Out-File -FilePath $reportPath -Encoding UTF8
            Write-Verbose ("[Save-QAlbumCover] Report written: {0}" -f $reportPath)
        }

        if ($autoDownloaded) {
            # print one-line summary
            Write-SummaryLine -InputArtist $Artist -InputAlbum $Album -InputTitle $null -ResultArtist $Artist -ResultAlbum $Album -ResultTitle $null -Location $local
            if ($ShowRawTags -and $local) { Write-Output "Downloaded: $local" }
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
