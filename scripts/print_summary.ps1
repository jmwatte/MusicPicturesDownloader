<#
.SYNOPSIS
Print a single-line summary comparing input metadata and result metadata and where the image was saved or embedded.
#>
param(
 [string] $AudioFilePath,
 [string] $Artist,
 [string] $Album,
 [string] $Title,
 [string] $ResultArtist,
 [string] $ResultAlbum,
 [string] $ResultTitle,
 [string] $DownloadedImagePath,
 [switch] $Embedded
)

function Get-TagsFromFile {
 param([string] $Path)
 $ffprobe = Get-Command ffprobe -ErrorAction SilentlyContinue
 if (-not $ffprobe) { return $null }
 try {
  $json = & ffprobe -v error -print_format json -show_entries format=tags -i "$Path" 2>$null
  $tags = $null
  try { $tags = ($json | ConvertFrom-Json).format.tags } catch { }
  return $tags
 } catch {
  return $null
 }
}

# Determine input metadata (prefer tags if audio file provided)
$inArtist = $Artist
$inAlbum = $Album
$inTitle = $Title
if ($AudioFilePath) {
 if (-not (Test-Path $AudioFilePath)) {
  Write-Output "ERROR: Audio file not found: $AudioFilePath"
  exit 2
 }
 $tags = Get-TagsFromFile -Path $AudioFilePath
 if ($tags) {
  if (-not $inArtist) { $inArtist = $tags.artist }
  if (-not $inAlbum)  { $inAlbum  = $tags.album }
  if (-not $inTitle)  { $inTitle  = $tags.title }
 }
 # fallback to filename parsing if still missing
 if (-not $inTitle) { $inTitle = [IO.Path]::GetFileNameWithoutExtension($AudioFilePath) }
}

$inArtist = if ($inArtist) { $inArtist } else { '<NONE>' }
$inAlbum  = if ($inAlbum)  { $inAlbum  } else { '<NONE>' }
$inTitle  = if ($inTitle)  { $inTitle  } else { '<NONE>' }

# Determine result metadata
$resArtist = if ($ResultArtist) { $ResultArtist } else { $inArtist }
$resAlbum  = if ($ResultAlbum)  { $ResultAlbum  } else { $inAlbum }
$resTitle  = if ($ResultTitle)  { $ResultTitle  } else { $inTitle }

# Determine location string
$location = $null
if ($DownloadedImagePath) {
 $location = $DownloadedImagePath
} elseif ($Embedded -and $AudioFilePath) {
 $location = "embedded in $AudioFilePath"
} else {
 $location = '<none>'
}

# Single-line summary
$summary = "INPUT => Artist:$inArtist | Album:$inAlbum | Title:$inTitle  →  RESULT => Artist:$resArtist | Album:$resAlbum | Title:$resTitle  | LOCATION: $location"
Write-Output $summary
