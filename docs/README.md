````markdown
# testAlbumDownloader

PowerShell module to download artist cover images from qobuz.com search pages.

Usage example:

```powershell
Import-Module testAlbumDownloader
Save-QobuzArtistImage -ArtistName 'jean-michel jarre' -DestinationPath C:\Temp -Verbose
```

Notes and assumptions:

If you want different filename sanitization or alternate locales for Qobuz, I can add options.
# MusicPicturesDownloader

PowerShell module to search Qobuz for artist/album/track images, download them, and optionally embed them into audio files using ffmpeg. The module also includes a helper to fetch top tags from Last.fm and write genres into audio files.

## Requirements

- PowerShell 5.1 or PowerShell 7+
- ffmpeg and ffprobe on PATH (for embedding and metadata reads/writes)
- PowerHTML module for HTML parsing (Install-Module -Name PowerHTML)

## Placing Last.fm API credentials

The module supports reading a Last.fm API key from either an environment variable or a local JSON file named `lastFMKeys.json` placed in the repository root (the module will also look up parent folders if needed).

### Environment variable (preferred for automation)

- Set `LASTFM_API_KEY` to your Last.fm API key.

### Local JSON file (convenient for local testing)

- Create a file named `lastFMKeys.json` in the repository root (and add it to `.gitignore` so it isn't committed).
- Expected JSON format (example):

```json
{
	"APIKey": "YOUR_LASTFM_API_KEY",
	"SharedSecret": "(optional)"
}
```

## Usage examples

Import the module (from the repo root):

```powershell
Import-Module .\MusicPicturesDownloader.psm1 -Force
Get-Command -Module MusicPicturesDownloader
```

Download a track cover (preview only):

```powershell
Save-QTrackCover -Track 'Mood Indigo' -Artist 'Frank Sinatra' -NoAuto -GenerateReport -MaxCandidates 5
```

Embed the best found image into a local MP3 (uses ffmpeg):

```powershell
Save-QTrackCover -AudioFilePath 'C:\Music\track.mp3' -UseTags Track,Artist -Embed
```

Fill genres from Last.fm (dry-run):

```powershell
Update-TrackGenresFromLastFm -AudioFilePath 'C:\Music\track.mp3' -DryRun -MaxTags 3
```

## Notes

- If using `lastFMKeys.json`, ensure it is included in `.gitignore` (the repo already contains a rule to ignore it). For CI or automation, use the `LASTFM_API_KEY` environment variable instead.
- The module assumes `ffmpeg`/`ffprobe` are on PATH. Embedding and metadata operations will fail otherwise.
- Public functions live in `src/public` and private helpers in `src/private` (one function per file). Filenames match function names.

If you want, I can add an example `lastFMKeys.json.sample` and a small `scripts/setup_env.ps1` that helps set the environment variable for local testing.
````
