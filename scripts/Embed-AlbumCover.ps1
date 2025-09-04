<#
.SYNOPSIS
Downloads an album cover to a temp folder and embeds it into the specified audio file using TagLib# (PSTagLib).
#>

[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[string]$AudioFilePath,
	[string]$Album,
	[string]$Artist,
	[ValidateSet('230', '600', 'max')]
	[string]$Size = '230',
	[ValidateSet('Always', 'IfBigger', 'SkipIfExists')]
	[string]$DownloadMode = 'Always',
	[ValidateSet('Cover', 'Album-Artist', 'Artist-Album', 'Custom')]
	[string]$FileNameStyle = 'Cover',
	[string]$CustomFileName
)



# Prompt for Album/Artist if not provided
if (-not $Album -or $Album -eq '') {
	Write-Warning "Album tag is missing."
	$Album = Read-Host 'Enter Album name'
}
if (-not $Artist -or $Artist -eq '') {
	Write-Warning "Artist tag is missing."
	$Artist = Read-Host 'Enter Artist name'
}
if (-not $Album -or $Album -eq '' -or -not $Artist -or $Artist -eq '') {
	Write-Error "Both Album and Artist are required for Save-QAlbumCover. Aborting."
	return
}

Write-Output "Audio file: $AudioFilePath"
Write-Output "Album: $Album"
Write-Output "Artist: $Artist"


$tempDir = New-Item -ItemType Directory -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid().ToString()))
try {
	$coverPath = Save-QAlbumCover -Album $Album -Artist $Artist -DestinationFolder $tempDir.FullName -Size $Size -DownloadMode $DownloadMode -FileNameStyle $FileNameStyle -CustomFileName $CustomFileName -Auto -Verbose
	if (-not $coverPath -or -not (Test-Path -LiteralPath$coverPath)) {
		Write-Error "No cover image was downloaded."
		return
	}

	# Embed cover using FFmpeg
	$ffmpegPath = "ffmpeg"  # Assumes ffmpeg is in PATH
	$tempOutput = [System.IO.Path]::Combine($tempDir.FullName, ([System.IO.Path]::GetFileNameWithoutExtension($AudioFilePath) + "_withcover" + [System.IO.Path]::GetExtension($AudioFilePath)))

	$ffmpegArgs = @(
		'-y',
		'-i', $AudioFilePath,
		'-i', $coverPath,
		'-map', '0',
		'-map', '1',
		'-c', 'copy',
		'-id3v2_version', '3',
		'-metadata:s:v', 'title="Album cover"',
		'-metadata:s:v', 'comment="Cover (front)"',
		$tempOutput
	)
	Write-Output "Embedding cover image using FFmpeg..."
	$ffmpegResult = & $ffmpegPath @ffmpegArgs 2>&1
	if (!(Test-Path -LiteralPath $tempOutput)) {
		Write-Output "FFmpeg failed to create output file. Output: $ffmpegResult"
		Remove-Item -Path $coverPath -ErrorAction SilentlyContinue
		return
	}

	# Replace original file with new file
	Move-Item -Path $tempOutput -Destination $AudioFilePath -Force
	Write-Output "Embedded cover into $AudioFilePath using FFmpeg."
}
finally {
	Remove-Item -Path $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
