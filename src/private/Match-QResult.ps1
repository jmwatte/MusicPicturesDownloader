<#
.SYNOPSIS
Compute a simple match score between requested album/artist and a candidate result.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Album,
    [Parameter(Mandatory=$false)]
    [string]$Artist,
    [Parameter(Mandatory=$true)]
    $Candidate # object with TitleAttr property
)

process {
    function Get-NormalizedText([string]$s) {
        if (-not $s) { return '' }
        $t = $s.ToLowerInvariant()
        $t = [System.Text.RegularExpressions.Regex]::Replace($t, "\(.*?\)", '') # remove parentheses
        $t = [System.Text.RegularExpressions.Regex]::Replace($t, "[^\p{L}\p{Nd}\s]", '') # remove punctuation
        $t = [System.Text.NormalizationForm]::FormD
        $t = $t.Normalize([System.Text.NormalizationForm]::FormD)
        # remove diacritics
        $sb = New-Object System.Text.StringBuilder
        foreach ($ch in $t.ToCharArray()) {
            if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne 'NonSpacingMark') {
                [void]$sb.Append($ch)
            }
        }
        $clean = $sb.ToString().Normalize([System.Text.NormalizationForm]::FormC)
        $clean = [System.Text.RegularExpressions.Regex]::Replace($clean, '\s+', ' ').Trim()
        return $clean
    }

    $reqAlbum = Get-NormalizedText $Album
    $reqArtist = Get-NormalizedText $Artist
    $candTitle = Get-NormalizedText $Candidate.TitleAttr

    $reqAlbumTokens = if ($reqAlbum) { $reqAlbum -split ' ' } else { @() }
    $reqArtistTokens = if ($reqArtist) { $reqArtist -split ' ' } else { @() }
    $candTokens = if ($candTitle) { $candTitle -split ' ' } else { @() }

    function TokenOverlap($a,$b) {
        if (-not $a -or -not $b) { return 0 }
        $setA = [System.Collections.Generic.HashSet[string]]::new($a)
        $count = 0
        foreach ($t in $b) { if ($setA.Contains($t)) { $count++ } }
        $union = [Math]::Max($a.Count, $b.Count)
        if ($union -eq 0) { return 0 }
        return [double]$count / $union
    }

    $albumScore = TokenOverlap $reqAlbumTokens $candTokens
    $artistScore = if ($reqArtistTokens.Count -gt 0) { TokenOverlap $reqArtistTokens $candTokens } else { 0 }

    # Weighted score: album 0.7 artist 0.3
    $score = ($albumScore * 0.7) + ($artistScore * 0.3)

    $result = [PSCustomObject]@{
        Candidate = $Candidate
        AlbumScore = [math]::Round($albumScore,3)
        ArtistScore = [math]::Round($artistScore,3)
        Score = [math]::Round($score,3)
    }
    Write-Output $result
}
