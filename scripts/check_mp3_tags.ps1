param()
$files = @(
 'C:\Users\resto\Music\Frank_Sinatra_-_In_the_Wee_Small_Hours-1991-OBSERVER\07_Frank_Sinatra_-_Cant_We_Be_Friends_..mp3',
 'C:\Users\resto\Music\Frank_Sinatra_-_In_the_Wee_Small_Hours-1991-OBSERVER\01_Frank_Sinatra_-_In_the_Wee_Small_Hours_of_the_Morning..mp3',
 'C:\Users\resto\Music\Frank_Sinatra_-_In_the_Wee_Small_Hours-1991-OBSERVER\02_Frank_Sinatra_-_Mood_Indigo..mp3',
 'C:\Users\resto\Music\Frank_Sinatra_-_In_the_Wee_Small_Hours-1991-OBSERVER\03_Frank_Sinatra_-_Glad_to_Be_Unhappy..mp3'
)
$ffprobe = Get-Command ffprobe -ErrorAction SilentlyContinue
Write-Output "ffprobe found: $([bool]$ffprobe)"
if (-not $ffprobe) { Write-Output "ffprobe not found; install FFmpeg and ensure ffprobe is in PATH."; exit 0 }
foreach ($f in $files) {
 if (-not (Test-Path -LiteralPathte $f)) { Write-Output "MISSING|$f"; continue }
 $json = & ffprobe -v error -print_format json -show_entries format=tags -i "$f" 2>$null
 $tags = $null
 try { $tags = ($json | ConvertFrom-Json).format.tags } catch { }
 $artist = if ($tags -and $tags.artist) { $tags.artist } else { '<NONE>' }
 $album = if ($tags -and $tags.album) { $tags.album } else { '<NONE>' }
 $title = if ($tags -and $tags.title) { $tags.title } else { '<NONE>' }
 $v = & ffprobe -v error -select_streams v -show_entries stream=codec_name -of csv=p=0 -i "$f" 2>$null
 $hasPic = -not [string]::IsNullOrWhiteSpace($v)
 Write-Output "RESULT|$([IO.Path]::GetFileName($f))|Artist:$artist|Album:$album|Title:$title|HasEmbeddedPicture:$hasPic"
}
