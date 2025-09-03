<#
.SYNOPSIS
  Example: batch run to update genres for a music folder using the MusicPicturesDownloader module.

USAGE
  Edit the variables below to point to your music folder, backup location and API key, then run this script.

WHAT IT DOES
  - Performs a conservative DryRun first (no files changed) and writes a report.
  - If you review the report and are happy, change DryRun to $false (or run the Resume step shown) to perform the actual write.
  - Uses a persistent cache file so repeated runs will reuse Last.fm results and can be resumed.
#>

# --- Configuration - edit these values ---
$MusicPath = 'C:\Users\resto\Music'    # <-- update this
$BackupFolder = 'C:\temp' # optional: where originals will be copied before changes
$CacheFile = Join-Path -Path $env:TEMP -ChildPath 'MusicPicturesDownloader-lastfm-cache.json'
$ApiKey = $env:LASTFM_API_KEY                # prefer storing your key in env var or lastFMKeys.json

# --- Safety check: import module ---
Import-Module (Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath '..\MusicPicturesDownloader.psm1') -Force -ErrorAction Stop

Write-Output "Music path: $MusicPath"
Write-Output "Backup folder: $BackupFolder"
Write-Output "Cache file: $CacheFile"

# --- Dry run: no files will be modified ---
$drySplat = @{
    Path = $MusicPath
    Filter = '*.mp3'
    Recurse = $true
    DryRun = $true
    ApiKey = $ApiKey
    CacheFile = $CacheFile
    BackupFolder = $BackupFolder
    ThrottleSeconds = 1
	Verbose = $true
    LogFile = (Join-Path -Path (Get-Location) -ChildPath 'genre-dryrun.json')
}

Write-Output 'Starting dry-run. This will not modify any files. A report will be saved to genre-dryrun.json'
$dryReport = Update-GenresForDirectory @drySplat
$dryReport | ConvertTo-Json -Depth 4 | Set-Content -Path $drySplat.LogFile -Encoding UTF8

Write-Output 'Dry-run complete. Inspect the report and backup folder (if configured).'
Write-Output "To resume with real writes, run the 'Resume' section below. The cache file ($CacheFile) will speed up Last.fm queries."

# --- Resume / Run for real (uncomment and run when you're ready) ---
# $runSplat = $drySplat
# $runSplat.DryRun = $false
# # optionally choose Replace or Merge behaviour:
# # $runSplat.Replace = $true    # replace genres
# # $runSplat.Merge = $true      # merge new tags with existing genres
#
# Write-Output 'Running actual update (this will modify files).'
# Update-GenresForDirectory @runSplat

Write-Output 'Example complete.'
