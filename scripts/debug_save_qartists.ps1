# Disposable debug script used by VS Code launch.json
# Resolve module path relative to this script, fallback to installed module if necessary
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$moduleCandidates = @(
	(Join-Path -Path $scriptDir -ChildPath '..\MusicPicturesDownloader.psd1'),
	(Join-Path -Path $scriptDir -ChildPath '..\MusicPicturesDownloader.psm1')
)
$found = $null
foreach ($c in $moduleCandidates) {
	try { $p = Resolve-Path -LiteralPath $c -ErrorAction SilentlyContinue } catch { $p = $null }
	if ($p) { $found = $p.Path; break }
}
if (-not $found) {
	$m = Get-Module -ListAvailable -Name MusicPicturesDownloader | Sort-Object Version -Descending | Select-Object -First 1
	if ($m) { $found = $m.Path }
}
if (-not $found) { throw 'MusicPicturesDownloader module not found (looked for local PSD1/PSM1 and installed module).' }
# Import-Module accepts the path as the first positional argument across PS versions
Import-Module $found -Force -ErrorAction Stop
#$album = "Back in black"
#$artist = "AC/DC"
$filepath="D:\1000 Songs Every Rock Fan Should Know\0114 - Blues Traveler - Runaround (1995).mp3"
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
	interactive=$true
	
	#CorrectUrl ="https://www.qobuz.com/be-nl/album/good-girl-gone-bad-reloaded-rihanna/0060251772142"
	#verbose = $true
}
#Save-QArtistsImages @ArtistSplat
 Invoke-QCheckArtist -AudioFilePath 'D:\The Beatles\1966 - Revolver\01 - Taxman.mp3' -Mode Automatic -Verbose
#save-QTrackCover @TrackSplat
#Update-GenresForDirectory -Path 'D:\Buddy Rich - Take It Away (1968) [EAC-FLAC]' -AlbumArtistPolicy Smart -ThrottleSeconds 0 -Verbose -ConfirmEach
#Update-TrackGenresFromLastFm -AudioFilePath "D:\220 Greatest Old Songs [MP3-128 & 320kbps]\Green,Green Grass Of Home.MP3" -Merge
# Get-ChildItem "C:\Music\Covers" | ForEach-Object {
#     $TrackSplat.AudioFilePath = $_.FullName
#     Save-QTrackCover @TrackSplat
# }
#  Save-QTrackCover @TrackSplat
# Write-Output "Done. Files in $DestinationPath :"
#Get-ChildItem -Path $DestinationPath -ErrorAction SilentlyContinue | ForEach-Object { Write-Output $_.FullName }