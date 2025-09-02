function Write-SummaryLine {
    [CmdletBinding()]
    param(
        [string] $InputArtist,
        [string] $InputAlbum,
        [string] $InputTitle,
        [string] $ResultArtist,
        [string] $ResultAlbum,
        [string] $ResultTitle,
        [string] $Location
    )

    $inArtist = if ($InputArtist) { $InputArtist } else { '<NONE>' }
    $inAlbum = if ($InputAlbum) { $InputAlbum } else { '<NONE>' }
    $inTitle = if ($InputTitle) { $InputTitle } else { '<NONE>' }

    $resArtist = if ($ResultArtist) { $ResultArtist } else { $inArtist }
    $resAlbum = if ($ResultAlbum) { $ResultAlbum } else { $inAlbum }
    $resTitle = if ($ResultTitle) { $ResultTitle } else { $inTitle }

    $loc = if ($Location) { $Location } else { '<none>' }

    Write-Output ("SUMMARY => INPUT: Artist:$inArtist | Album:$inAlbum | Title:$inTitle  →  RESULT: Artist:$resArtist | Album:$resAlbum | Title:$resTitle  | LOCATION: $loc")
}
