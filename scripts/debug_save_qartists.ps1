# Disposable debug script used by VS Code launch.json
Import-Module 'c:\Users\resto\Documents\PowerShell\Modules\MusicPicturesDownloader\MusicPicturesDownloader.psd1' -Force
$album = "Back in black"
$artist = "AC/DC"
$DestinationPath = Join-Path $env:TEMP 'qobuz-debug'
if (-not (Test-Path -Path $DestinationPath)) { New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null }

Write-Output "Running: @($artist - $album) | Save-QArtistsImages -DestinationPath $DestinationPath -Verbose"
$AlbumSplat=@{
	Album = $album
	Artist = $artist
	DestinationFolder = $DestinationPath
	GenerateReport = $true
	Auto = $true
	Size = "max"
}

Save-QAlbumCover @AlbumSplat 
$ArtistSplat = @{
	ArtistInput = $artist
	DestinationFolder = $DestinationPath
	PreferredSize = "large"
	Force = $true
}

Save-QArtistsImages @ArtistSplat
Write-Output "Done. Files in $DestinationPath :"
Get-ChildItem -Path $DestinationPath -ErrorAction SilentlyContinue | ForEach-Object { Write-Output $_.FullName }