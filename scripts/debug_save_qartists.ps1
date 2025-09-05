# Disposable debug script used by VS Code launch.json
Import-Module 'C:\Users\jmw\Documents\PowerShell\Modules\MusicPictureDownloader\MusicPicturesDownloader\MusicPicturesDownloader.psd1' -Force
#$album = "Back in black"
#$artist = "AC/DC"
$filepath="D:\1000 Songs Every Rock Fan Should Know\0074 - The Beatles - I Want To Hold Your Hand (1963).mp3"
$DestinationPath = Join-Path $env:TEMP 'qobuz-debug'
if (-not (Test-Path -LiteralPath $DestinationPath)) { New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null }

Write-Output "Running: @($artist - $album) | Save-QArtistsImages -DestinationPath $DestinationPath -Verbose"
$AlbumSplat=@{
	Album = $album
	Artist = $artist
	DestinationFolder = $DestinationPath
	GenerateReport = $true
	Auto = $true
	Size = "max"
}

#Save-QAlbumCover @AlbumSplat 
$ArtistSplat = @{
	ArtistInput = $artist
	DestinationFolder = $DestinationPath
	PreferredSize = "large"
	Force = $true
}
$TrackSplat=@{
	AudioFilePath = $filepath
	size="600"
	Embed = $true
	UseTags = @('Artist','Track')
	Maxcandidates = 5
	generateReport = $true
	CorrectUrl = 'https://www.qobuz.com/be-nl/album/1-the-beatles/0060254767350'
	verbose = $true
}
#Save-QArtistsImages @ArtistSplat

#save-QTrackCover @TrackSplat
#Update-GenresForDirectory -Path 'D:\Buddy Rich - Take It Away (1968) [EAC-FLAC]' -AlbumArtistPolicy Smart -ThrottleSeconds 0 -Verbose -ConfirmEach
#Update-TrackGenresFromLastFm -AudioFilePath "D:\220 Greatest Old Songs [MP3-128 & 320kbps]\Green,Green Grass Of Home.MP3" -Merge
# Get-ChildItem "D:\1000 Songs Every Rock Fan Should Know" | ForEach-Object {
#     $TrackSplat.AudioFilePath = $_.FullName
#     Save-QTrackCover @TrackSplat
# }
Save-QTrackCover @TrackSplat
Write-Output "Done. Files in $DestinationPath :"
#Get-ChildItem -Path $DestinationPath -ErrorAction SilentlyContinue | ForEach-Object { Write-Output $_.FullName }