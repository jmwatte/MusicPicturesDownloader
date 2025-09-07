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

    # Preserve input ordering in the compact Title|Artist||Album form for the INPUT line
    $inputLine = "INPUT: Title:$inTitle | Artist:$inArtist | Album:$inAlbum"
    $resultLine = "RESULT: Title:$resTitle | Artist:$resArtist | Album:$resAlbum"
    $locationLine = "LOCATION: $loc"

    $prefix = 'SUMMARY => '
    # compute where the 'Title:' token starts in the input and result lines so we can align the field columns
    $inputTitlePos = $inputLine.IndexOf('Title:')
    $resultTitlePos = $resultLine.IndexOf('Title:')
    if ($inputTitlePos -lt 0) { $inputTitlePos = 0 }
    if ($resultTitlePos -lt 0) { $resultTitlePos = 0 }

    $baseIndent = $prefix.Length + $inputTitlePos - $resultTitlePos
    if ($baseIndent -lt 0) { $baseIndent = 0 }
    $indent = ' ' * $baseIndent

    Write-Output ("$prefix$inputLine")
    Write-Output ("$indent$resultLine")
    # Align LOCATION same as RESULT so its text column lines up with the Title/Artist fields
    Write-Output ("$indent$locationLine")
}
