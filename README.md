# MusicPicturesDownloader

PowerShell module to search Qobuz for album, artist, and track cover images and either save them locally or embed them into audio files using FFmpeg.

Requirements
- PowerShell 5.1 or 7+
- PowerHTML module (ConvertFrom-Html) for parsing Qobuz search pages
- FFmpeg (ffmpeg.exe and ffprobe) available in PATH for embedding and tag reading

Public functions
-- Save-QAlbumCover: search and save album covers (downloads by default; use -NoAuto for preview)
-- Save-QArtistsImages: batch download artist images (downloads by default; use -NoAuto for preview)
-- Save-QTrackCover: search track covers and optionally embed into a track file (downloads by default; use -NoAuto for preview)

Examples

Save the best album cover for an album:

```powershell
Import-Module .\MusicPicturesDownloader.psd1
Save-QAlbumCover -Album 'Rumours' -Artist 'Fleetwood Mac' -DestinationFolder 'C:\Covers' -Auto
```

Embed a track cover into an MP3 using tags from the file:

```powershell
Save-QTrackCover -AudioFilePath 'C:\Music\song.mp3' -UseTags Track,Artist -Embed -Auto
```

Batch download artist images:

```powershell
'Adele','Coldplay' | Save-QArtistsImages -DestinationFolder 'C:\ArtistImages'
```

All public functions download matches by default. Use the `-NoAuto` switch to perform a preview
or report-only run (no files will be written). This behavior keeps common usage simple while
allowing explicit preview/dry-run when needed.

For detailed help, use Get-Help <FunctionName> -Full
