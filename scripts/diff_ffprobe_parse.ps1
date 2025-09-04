param([string]$FilePath)
if (-not $FilePath) { Write-Output 'Usage: .\diff_ffprobe_parse.ps1 <filePath>'; exit 2 }
if (-not (Test-Path -LiteralPath $FilePath)) { Write-Output "File not found: $FilePath"; exit 2 }
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\MusicPicturesDownloader.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) { Write-Output "Module file not found: $modulePath"; exit 2 }
Import-Module -LiteralPath $modulePath -Force
$helper = Join-Path -Path $PSScriptRoot -ChildPath '..\src\private\Get-TrackMetadataFromFile.ps1'
if (-not (Test-Path -LiteralPath $helper)) { Write-Output "Helper not found: $helper"; exit 2 }
. $helper
Write-Output "--- RAW FFPROBE format.tags ---"
$raw = & ffprobe -v quiet -print_format json -show_format -show_streams -i $FilePath 2>$null
if ($raw) {
    try { $obj = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $obj = $null }
    if ($obj -and $obj.format -and $obj.format.tags) { $obj.format.tags | ConvertTo-Json -Depth 5 | Write-Output } else { Write-Output '<no format.tags>' }
    if ($obj -and $obj.streams -and $obj.streams[0].tags) { Write-Output '--- RAW FFPROBE streams[0].tags ---'; $obj.streams[0].tags | ConvertTo-Json -Depth 5 | Write-Output } else { Write-Output '<no stream tags>' }
} else { Write-Output 'ffprobe returned no JSON' }

Write-Output '--- MODULE PARSE (Get-TrackMetadataFromFile) ---'
$m = Get-TrackMetadataFromFile -AudioFilePath $FilePath -Verbose
$m | ConvertTo-Json -Depth 5 | Write-Output
if ($m.Tags) { Write-Output '--- TAG ENUM ---'; $m.Tags.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Output ("{0} = {1}" -f $_.Name,$_.Value) } }
