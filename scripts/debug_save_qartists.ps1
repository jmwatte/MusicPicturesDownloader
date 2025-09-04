# Disposable debug script used by VS Code launch.json
Import-Module 'c:\Users\resto\Documents\PowerShell\Modules\MusicPicturesDownloader\MusicPicturesDownloader.psd1' -Force
$album = "Back in black"
$artist = "AC/DC"
$filepath="C:\Users\resto\Music\Frank_Sinatra_-_In_the_Wee_Small_Hours-1991-OBSERVER\02_Frank_Sinatra_-_Mood_Indigo..mp3"
$DestinationPath = Join-Path $env:TEMP 'qobuz-debug'
if (-not (Test-Path -LiteralPath $DestinationPath)) { New-Item -LiteralPath $DestinationPath -ItemType Directory -Force | Out-Null }

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
	Verbose = $true
	Embed = $true
	Auto = $true
}
#Save-QArtistsImages @ArtistSplat

#save-QTrackCover @TrackSplat
Update-TrackGenresFromLastFm -AudioFilePath "D:\220 Greatest Old Songs [MP3-128 & 320kbps]\Green,Green Grass Of Home.MP3" -Merge
Write-Output "Done. Files in $DestinationPath :"
#Get-ChildItem -Path $DestinationPath -ErrorAction SilentlyContinue | ForEach-Object { Write-Output $_.FullName }