<#
.SYNOPSIS
Downloads album and artist pictures for each album-artist pair in a text file.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile
)

$baseDir = 'C:\temp\albums'
if (-not (Test-Path -LiteralPath $baseDir)) { New-Item -Path $baseDir -ItemType Directory | Out-Null }

Get-Content -LiteralPath $InputFile | ForEach-Object {
    if ($_ -match "^(.*?)\t(.*?)$") {
        $album = $matches[1].Trim()
        $artist = $matches[2].Trim()
        $albumDir = Join-Path $baseDir ("{0}-{1}" -f $album, $artist -replace '[\\/:*?"<>|]', '_')
        if (-not (Test-Path -LiteralPath $albumDir)) { New-Item -Path $albumDir -ItemType Directory | Out-Null }
        # Download album cover
		$AlbumSplat = @{
			Album = $album
			Artist = $artist
			DestinationFolder = $albumDir
			Auto = $true
			Size = "max"
		}
        Save-QAlbumCover @AlbumSplat
        # Download artist picture
        $artistPicDir = Join-Path $albumDir 'ArtistPicture'
        if (-not (Test-Path -LiteralPath $artistPicDir)) { New-Item -Path $artistPicDir -ItemType Directory | Out-Null }
		$ArtistSplat = @{
			ArtistInput = $artist
			DestinationFolder = $artistPicDir
			PreferredSize = "large"
			Force = $true
		}
        Save-QArtistsImages @ArtistSplat
    }
}
