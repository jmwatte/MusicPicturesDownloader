<#
.SYNOPSIS
    Compute a match score between requested track/artist and a candidate search result.
.DESCRIPTION
    Similar to Get-MatchQResult but optimized for track matching. Uses token overlap and a hybrid similarity metric.
.PARAMETER Track
    The requested track title.
.PARAMETER Artist
    The requested artist name (optional).
.PARAMETER Candidate
    The candidate object produced by ConvertFrom-QTrackSearchResults (must have TitleAttr, ArtistAttr, AlbumAttr).
#>
function Get-MatchQTrackResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Track,
        [Parameter(Mandatory=$false)]
        [string]$Artist,
        [Parameter(Mandatory=$true)]
        $Candidate
    )

    # Normalize
    $reqTrack = Convert-TextNormalized $Track
    $reqArtist = Convert-TextNormalized $Artist

    $candTitleRaw = $Candidate.TitleAttr
    $candAlbumRaw = if ($Candidate.PSObject.Properties.Match('AlbumAttr')) { $Candidate.AlbumAttr } else { $null }
    $candArtistRaw = if ($Candidate.PSObject.Properties.Match('ArtistAttr')) { $Candidate.ArtistAttr } else { $null }

    $candTitle = Convert-TextNormalized $candTitleRaw
    $candAlbum = Convert-TextNormalized $candAlbumRaw
    $candArtist = Convert-TextNormalized $candArtistRaw

    $reqTrackTokens = if ($reqTrack) { $reqTrack -split ' ' } else { @() }
    $reqArtistTokens = if ($reqArtist) { $reqArtist -split ' ' } else { @() }
    $candTitleTokens = if ($candTitle) { $candTitle -split ' ' } else { @() }
    $candArtistTokens = if ($candArtist) { $candArtist -split ' ' } else { @() }
    $candAlbumTokens = if ($candAlbum) { $candAlbum -split ' ' } else { @() }

    function Measure-HybridSimilarity($a, $b) {
        if (-not $a -or -not $b) { return 0 }
        $setA = [System.Collections.Generic.HashSet[string]]::new([string[]]$a)
        $setB = [System.Collections.Generic.HashSet[string]]::new([string[]]$b)
        $allPresent = $true
        foreach ($tok in $setA) { if (-not $setB.Contains($tok)) { $allPresent = $false; break } }
        if ($allPresent) { return 0.95 }
        $inter = [System.Collections.Generic.HashSet[string]]::new($setA)
        $inter.IntersectWith($setB)
        $union = [System.Collections.Generic.HashSet[string]]::new($setA)
        $union.UnionWith($setB)
        if ($union.Count -eq 0) { return 0 }
        return [double]$inter.Count / $union.Count
    }

    $trackScore = Measure-HybridSimilarity $reqTrackTokens $candTitleTokens
    $artistScore = if ($reqArtistTokens.Count -gt 0) { Measure-HybridSimilarity $reqArtistTokens $candArtistTokens } else { 0 }
    $albumScore = Measure-HybridSimilarity $reqTrackTokens $candAlbumTokens

    # Weighting: track > artist > album
    $score = ($trackScore * 0.8) + ($artistScore * 0.15) + ($albumScore * 0.05)
    if ($trackScore -gt 0.8 -and $artistScore -gt 0.3) { $score += 0.1 }
    if ($score -gt 1) { $score = 1 }

    $result = [PSCustomObject]@{
        Candidate = $Candidate
        TrackScore = [math]::Round($trackScore,3)
        ArtistScore = [math]::Round($artistScore,3)
        AlbumScore = [math]::Round($albumScore,3)
        Score = [math]::Round($score,3)
    }
    Write-Output $result
}
