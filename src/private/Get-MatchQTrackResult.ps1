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

    # existing similarity measures
    $trackScore  = Measure-HybridSimilarity $reqTrackTokens   $candTitleTokens
    $artistScore = if ($reqArtistTokens.Count -gt 0) { Measure-HybridSimilarity $reqArtistTokens  $candArtistTokens } else { 0 }
    $albumScore  = Measure-HybridSimilarity $reqTrackTokens   $candAlbumTokens

    # Base weighted score
    $score = ($trackScore * 0.8) + ($artistScore * 0.15) + ($albumScore * 0.05)
    if ($trackScore -gt 0.8 -and $artistScore -gt 0.3) { $score += 0.1 }

    # --- NEW: exact-match and containment bonuses (tie-breakers) ---
    # Normalize for exact/contains comparisons (use existing helper)
    $normReqTrack  = if ($reqTrack)  { Convert-TextNormalized $reqTrack }  else { $null }
    $normReqArtist = if ($reqArtist) { Convert-TextNormalized $reqArtist } else { $null }
    $normCandTitle = if ($candTitle) { Convert-TextNormalized $candTitle } else { $null }
    $normCandAlbum = if ($candAlbum) { Convert-TextNormalized $candAlbum } else { $null }
    $normCandArtist= if ($candArtist){ Convert-TextNormalized $candArtist } else { $null }

    # exact title match (strong but not saturating)
    $exactTitleBonus = 0.0
    if ($normReqTrack -and $normCandTitle -and ($normReqTrack -eq $normCandTitle)) {
        $exactTitleBonus = 0.20
    }

    # album contains track title (useful when release named after the single)
    $albumContainsBonus = 0.0
    if ($normReqTrack -and $normCandAlbum -and ($normCandAlbum.Contains($normReqTrack))) {
        $albumContainsBonus = 0.08
    }

    # exact artist match (moderate boost)
    $exactArtistBonus = 0.0
    if ($normReqArtist -and $normCandArtist -and ($normReqArtist -eq $normCandArtist)) {
        $exactArtistBonus = 0.06
    }

    # existing position bonus (small nudge for earlier results)
    try {
        $positionWeight = 0.03
        $posIndex = 0
        if ($Candidate -and $Candidate.PSObject.Properties.Match('Index')) {
            $posIndex = [int]$Candidate.Index
        }
        $positionBonus = $positionWeight * (1.0 / (1.0 + [double]$posIndex))
    } catch {
        $positionBonus = 0.0
    }

    # Apply bonuses (order: exactTitle -> albumContains -> exactArtist -> position)
    $score += $exactTitleBonus + $albumContainsBonus + $exactArtistBonus + $positionBonus

    # keep full precision internally; round only for output (4 decimals)
    $result = [PSCustomObject]@{
        Candidate       = $Candidate
        TrackScore      = [math]::Round($trackScore,3)
        ArtistScore     = [math]::Round($artistScore,3)
        AlbumScore      = [math]::Round($albumScore,3)
        ExactTitleBonus = [math]::Round($exactTitleBonus,3)
        AlbumContainsBonus = [math]::Round($albumContainsBonus,3)
        ExactArtistBonus= [math]::Round($exactArtistBonus,3)
        PositionBonus   = [math]::Round($positionBonus,3)
        Score           = [math]::Round($score,4)
    }
    Write-Output $result
}

