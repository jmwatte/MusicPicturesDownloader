# Disposable debug script used by VS Code launch.json
Import-Module 'c:\Users\resto\Documents\PowerShell\Modules\MusicPicturesDownloader\MusicPicturesDownloader.psd1' -Force

$DestinationPath = Join-Path $env:TEMP 'qobuz-debug'
if (-not (Test-Path -Path $DestinationPath)) { New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null }

Write-Output "Running: @('The Beatles') | Save-QArtistsImages -DestinationPath $DestinationPath -Verbose"
#@("The Beatles") | Save-QArtistsImages -DestinationPath $DestinationPath -PreferredSize large -Verbose -Force
Save-QAlbumCover -Album Revolver -Artist "The Beatles" -DestinationFolder $DestinationPath -verbose -GenerateReport -Auto -Size max  #-PreferredSize large -Verbose -Force
Write-Output "Done. Files in $DestinationPath :"
Get-ChildItem -Path $DestinationPath -ErrorAction SilentlyContinue | ForEach-Object { Write-Output $_.FullName }