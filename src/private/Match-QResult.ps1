<#
.SYNOPSIS
Compute a simple match score between requested album/artist and a candidate result.
#>
function Get-MatchQResult {
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
        $candTitleRaw = $Candidate.TitleAttr

        # Extract album and artist from candidate title (Qobuz format: 'More details on {album} by {artist}.')
        $candAlbum = ''
        $candArtist = ''
        if ($candTitleRaw -match 'More details on (.+) by (.+)\.?$') {
            $candAlbum = $matches[1]
            $candArtist = $matches[2]
        } else {
            $candAlbum = $candTitleRaw
        }
        $candAlbum = Get-NormalizedText $candAlbum
        $candArtist = Get-NormalizedText $candArtist

        $reqAlbumTokens = if ($reqAlbum) { $reqAlbum -split ' ' } else { @() }
        $reqArtistTokens = if ($reqArtist) { $reqArtist -split ' ' } else { @() }
        $candAlbumTokens = if ($candAlbum) { $candAlbum -split ' ' } else { @() }
        $candArtistTokens = if ($candArtist) { $candArtist -split ' ' } else { @() }



        function HybridSimilarity($a, $b) {
            if (-not $a -or -not $b) { return 0 }
            $setA = [System.Collections.Generic.HashSet[string]]::new([string[]]$a)
            $setB = [System.Collections.Generic.HashSet[string]]::new([string[]]$b)
            # If all tokens in $a are present in $b, return high score
            $allPresent = $true
            foreach ($tok in $setA) { if (-not $setB.Contains($tok)) { $allPresent = $false; break } }
            if ($allPresent) { return 0.9 }
            # Otherwise, use Jaccard
            $inter = [System.Collections.Generic.HashSet[string]]::new($setA)
            $inter.IntersectWith($setB)
            $union = [System.Collections.Generic.HashSet[string]]::new($setA)
            $union.UnionWith($setB)
            if ($union.Count -eq 0) { return 0 }
            return [double]$inter.Count / $union.Count
        }

        function TokenOverlap($a,$b) {
            if (-not $a -or -not $b) { return 0 }
            if ($a -isnot [System.Collections.IEnumerable]) { return 0 }
            if ($b -isnot [System.Collections.IEnumerable]) { return 0 }
            $setA = [System.Collections.Generic.HashSet[string]]::new([string[]]$a)
            $count = 0
            foreach ($t in $b) { if ($null -ne $t -and $setA.Contains($t)) { $count++ } }
            $denom = $a.Count
            if ($denom -eq 0) { return 0 }
            return [double]$count / $denom
        }

    $albumScore = HybridSimilarity $reqAlbumTokens $candAlbumTokens
    $artistScore = if ($reqArtistTokens.Count -gt 0) { HybridSimilarity $reqArtistTokens $candArtistTokens } else { 0 }

        # Increase album weight and add a bonus if both album and artist have a nonzero match
        $score = ($albumScore * 0.85) + ($artistScore * 0.15)
        if ($albumScore -gt 0.7 -and $artistScore -gt 0.2) { $score += 0.15 }
        if ($score -gt 1) { $score = 1 }

        $result = [PSCustomObject]@{
            Candidate = $Candidate
            AlbumScore = [math]::Round($albumScore,3)
            ArtistScore = [math]::Round($artistScore,3)
            Score = [math]::Round($score,3)
        }
        Write-Output $result
    }
}
