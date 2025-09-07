<#
.SYNOPSIS
    Score and rank artist search candidates.

.DESCRIPTION
    Match-QArtistResults applies a configurable scoring function to a list
    of artist candidates returned from Qobuz search. It uses normalized
    token overlap and a scaled album count boost to compute a combined score.

.PARAMETER InputArtist
    The artist name from the audio file.

.PARAMETER Candidates
    An array or collection of candidate objects with at least properties
    Name and AlbumCount.

.PARAMETER NameWeight
    Weight applied to the name similarity (0..1). Album weight is 1-NameWeight.

.PARAMETER AlbumWeightScale
    Scaling factor applied to the album count contribution.

.PARAMETER AlbumName
    Optional album name used for cross-check boosting.

.OUTPUTS
    Returns candidate objects augmented with MatchScore and Debug fields,
    sorted descending by MatchScore.
#>
function Match-QArtistResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string] $InputArtist,

        [Parameter(Mandatory=$true)]
        [object[]] $Candidates,

        [double] $NameWeight = 0.7,
        [double] $AlbumWeightScale = 0.3,
        [string] $AlbumName = $null
    )

    process {
        # Normalize input
        $normFunc = Get-Command -Name Convert-TextNormalized -ErrorAction SilentlyContinue
        if (-not $normFunc) { throw 'Convert-TextNormalized is required for matching.' }
        $normInput = Convert-TextNormalized -Text $InputArtist
        $normAlbum = $null
        if ($AlbumName) { $normAlbum = Convert-TextNormalized -Text $AlbumName }

        $out = @()
        foreach ($c in $Candidates) {
            $cName = ($c.Name -as [string])
            $normC = Convert-TextNormalized -Text $cName

            # Simple name similarity: token overlap ratio
            $inputTokens = if ($normInput) { $normInput -split ' ' } else { @() }
            $candTokens = if ($normC) { $normC -split ' ' } else { @() }
            $common = ($inputTokens | Where-Object { $candTokens -contains $_ })
            $tokenScore = 0.0
            if ($inputTokens.Count -gt 0) {
                $tokenScore = [double]($common.Count) / [double]([Math]::Max($inputTokens.Count, $candTokens.Count))
            }

            # Exact normalized equality gets a high base
            $exactBonus = 0.0
            if ($normInput -and $normInput -eq $normC) { $exactBonus = 0.5 }

            # Album count contribution (scaled logarithmically)
            $albumCount = 0
            if ($c.PSObject.Properties['AlbumCount'] -and $c.AlbumCount) { $albumCount = [int]$c.AlbumCount }
            $albumScore = 0.0
            if ($albumCount -gt 0) {
                $albumScore = [Math]::Log($albumCount + 1, 2) / 6.0  # normalize into ~0..1 (assumes albumCount up to ~63)
                if ($albumScore -gt 1) { $albumScore = 1 }
            }

            # Album name cross-check bonus
            $albumBonus = 0.0
            if ($normAlbum) {
                # If candidate name's artist page not fetched, we can heuristically check if the album name appears in the candidate link (cheap)
                if ($c.Link -and ($c.Link -match [regex]::Escape(($AlbumName -as [string]) -replace '\s+','-') )) {
                    $albumBonus = 0.25
                }
            }

            $combined = ($NameWeight * ($tokenScore + $exactBonus)) + ($AlbumWeightScale * $albumScore) + $albumBonus
            # clamp
            if ($combined -gt 1) { $combined = 1 }

            $obj = [PSCustomObject]@{
                Candidate = $c
                MatchScore = [math]::Round($combined, 3)
                Debug = [PSCustomObject]@{
                    TokenScore = [math]::Round($tokenScore,3)
                    ExactBonus = $exactBonus
                    AlbumScore = [math]::Round($albumScore,3)
                    AlbumBonus = $albumBonus
                    AlbumCount = $albumCount
                }
            }
            $out += $obj
        }

        # Sort by MatchScore desc, then AlbumCount desc
        $sorted = $out | Sort-Object -Property @{Expression = 'MatchScore'; Descending = $true}, @{Expression = { param($x) ($x.Debug.AlbumCount) }; Descending = $true }
        Write-Output $sorted
    }
}
