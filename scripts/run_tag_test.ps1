$ErrorActionPreference = 'Stop'
$src = 'D:\220 Greatest Old Songs [MP3-128 & 320kbps]\Green,Green Grass Of Home.MP3'
if (-not (Test-Path -LiteralPath $src)) { Write-Output "FILE NOT FOUND: $src"; exit 1 }
# Import module and dot-source private helper (Set-FileGenresWithFFmpeg) for testing
Import-Module -Name .\MusicPicturesDownloader.psm1 -Force
$helper = Join-Path -Path $PSScriptRoot -ChildPath '..\src\private\Set-FileGenresWithFFmpeg.ps1'
if (-not (Test-Path -LiteralPath $helper)) { Write-Output "Helper not found: $helper"; exit 2 }
. $helper
# backup
$backup = Join-Path $env:TEMP ([guid]::NewGuid().Guid + '-' + [IO.Path]::GetFileName($src))
Copy-Item -LiteralPath $src -Destination $backup -Force
Write-Output "BACKUP: $backup"
# function to get tags via ffprobe
function Get-FfTags($path){
    $json = & ffprobe -v quiet -print_format json -show_format -show_streams -i $path 2>$null
    if (-not $json) { return $null }
    $j = $json | ConvertFrom-Json
    $obj = [PSCustomObject]@{
        Path = $path
        FormatTags = ($j.format.tags -as [hashtable])
        Stream0Tags = (($j.streams[0].tags) -as [hashtable])
    }
    return $obj
}
Write-Output "--- BEFORE ---"
$before = Get-FfTags $src
if ($null -eq $before) { Write-Output 'ffprobe returned no JSON'; exit 2 }
Write-Output "Format tags (before):"
$before.FormatTags | Format-List -Force
Write-Output "Stream[0] tags (before):"
$before.Stream0Tags | Format-List -Force
# write test genres
Write-Output "Writing test genres (UnitTestGenreA;UnitTestGenreB)"
$res = Set-FileGenresWithFFmpeg -AudioFilePath $src -Genres @('UnitTestGenreA','UnitTestGenreB') -Replace
Write-Output "Write result: $($res | ConvertTo-Json -Depth 3)"
Write-Output "--- AFTER ---"
$after = Get-FfTags $src
Write-Output "Format tags (after):"
$after.FormatTags | Format-List -Force
Write-Output "Stream[0] tags (after):"
$after.Stream0Tags | Format-List -Force
# restore
Copy-Item -LiteralPath $backup -Destination $src -Force
Remove-Item -LiteralPath $backup -Force
Write-Output "Restored from backup and removed backup"
Write-Output 'DONE'
