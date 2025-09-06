<#
.SYNOPSIS
    Interactive chooser for Qobuz track image candidates.

.DESCRIPTION
    Displays a numbered list of scored candidates and prompts the user to pick one, enter a
    pipe-separated correction string (Title|Artist|Album) to re-run the search, skip, or abort.

.PARAMETER Scored
    Array of scored candidate objects (sorted by score desc). Each item must have a Candidate
    with TitleAttr, ArtistAttr, AlbumAttr, ImageUrl and ResultLink and a numeric Score.

.PARAMETER Threshold
    Auto-select threshold (0..1). When the top candidate's score is >= Threshold the helper
    will return AutoSelected = $true and SelectedCandidate set to the top candidate.

.PARAMETER SearchTrack
    The search track string used (for display only).

.PARAMETER SearchArtist
    The search artist string used (for display only).

.PARAMETER SearchAlbum
    The search album string used (for display only).

.EXAMPLE
    $choice = Select-QobuzCandidate -Scored $scored -Threshold 0.75 -SearchTrack $t -SearchArtist $a
#>
function Select-QobuzCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Scored,
    [double]$Threshold = 0.75,
    [string]$SearchTrack,
    [string]$SearchArtist,
    [string]$SearchAlbum,
    [string]$SearchUrl
    )

    # Return shape: PSCustomObject with keys: SelectedCandidate, ManualSearch, AutoSelected, Action, Message
    try {
        if (-not $Scored -or $Scored.Count -eq 0) {
            return [PSCustomObject]@{ SelectedCandidate = $null; ManualSearch = $null; AutoSelected = $false; Action = 'NoCandidates'; Message = 'No candidates to choose from.' }
        }

        # Auto-select top candidate when above threshold
        if ($Scored[0].Score -ge $Threshold) {
            return [PSCustomObject]@{ SelectedCandidate = $Scored[0].Candidate; ManualSearch = $null; AutoSelected = $true; Action = 'AutoSelected'; Message = 'Top candidate auto-selected (score above threshold).' }
        }

    # Display candidates in the compact format requested: index + title|artist|album, then Image: and Page:
    Write-Information "Candidates for: Title='$SearchTrack' Artist='$SearchArtist' Album='$SearchAlbum'" -InformationAction Continue
        $i = 0
        foreach ($s in $Scored) {
            $c = $s.Candidate
            $title = if ($c.TitleAttr) { $c.TitleAttr } else { '' }
            $artist = if ($c.ArtistAttr) { $c.ArtistAttr } else { '' }
            $album = if ($c.AlbumAttr) { $c.AlbumAttr } else { '' }
            Write-Information ("[{0}] {1}|{2}|{3}  (score={4:N2})" -f $i, $title, $artist, $album, $s.Score) -InformationAction Continue
            Write-Information ("    Image: {0}" -f $c.ImageUrl) -InformationAction Continue
            # prefer ResultLink but accept ResultLink/ResultLink
            $page = if ($c.ResultLink) { $c.ResultLink } elseif ($c.PageUrl) { $c.PageUrl } else { $null }
            if ($page) { Write-Information ("    Page:  {0}" -f $page) -InformationAction Continue }
            $i++
        }

    Write-Information '' -InformationAction Continue
    if ($SearchUrl) { Write-Information ("Search URL: {0}" -f $SearchUrl) -InformationAction Continue }
        Write-Information "Enter the index number to select that candidate, press Enter to accept the top candidate," -InformationAction Continue
        Write-Information "or provide a pipe-separated correction string in the form: Title|Artist|Album (album optional)." -InformationAction Continue
        Write-Information "Type 's' to skip selection or 'q' to abort." -InformationAction Continue
        $resp = Read-Host -Prompt "Your choice"

        if ($null -eq $resp -or $resp.Trim() -eq '') {
            # user pressed Enter -> select top candidate
            return [PSCustomObject]@{ SelectedCandidate = $Scored[0].Candidate; ManualSearch = $null; AutoSelected = $false; Action = 'Selected'; Message = 'User accepted top candidate.' }
        }

        $r = $resp.Trim()
        if ($r -eq 'q') { return [PSCustomObject]@{ SelectedCandidate = $null; ManualSearch = $null; AutoSelected = $false; Action = 'Abort'; Message = 'User aborted.' } }
        if ($r -eq 's') { return [PSCustomObject]@{ SelectedCandidate = $null; ManualSearch = $null; AutoSelected = $false; Action = 'Skip'; Message = 'User skipped selection.' } }

        # numeric index?
        if ($r -match '^[0-9]+$') {
            $idx = [int]$r
            if ($idx -ge 0 -and $idx -lt $Scored.Count) {
                return [PSCustomObject]@{ SelectedCandidate = $Scored[$idx].Candidate; ManualSearch = $null; AutoSelected = $false; Action = 'Selected'; Message = 'User selected by index.' }
            }
            else {
                return [PSCustomObject]@{ SelectedCandidate = $null; ManualSearch = $null; AutoSelected = $false; Action = 'Invalid'; Message = 'Index out of range.' }
            }
        }

        # pipe-separated correction string
        if ($r -match '\|') {
            $parts = $r -split '\|' | ForEach-Object { $_.Trim() }
            $t = if ($parts.Count -ge 1) { $parts[0] } else { $null }
            $a = if ($parts.Count -ge 2) { $parts[1] } else { $null }
            $al = if ($parts.Count -ge 3) { $parts[2] } else { $null }
            $manual = @{ Title = $t; Artist = $a; Album = $al }
            return [PSCustomObject]@{ SelectedCandidate = $null; ManualSearch = $manual; AutoSelected = $false; Action = 'ManualSearch'; Message = 'User requested manual re-search.' }
        }

        return [PSCustomObject]@{ SelectedCandidate = $null; ManualSearch = $null; AutoSelected = $false; Action = 'UnknownInput'; Message = 'Unrecognized input.' }
    }
    catch {
        return [PSCustomObject]@{ SelectedCandidate = $null; ManualSearch = $null; AutoSelected = $false; Action = 'Error'; Message = $_.Exception.Message }
    }
}
