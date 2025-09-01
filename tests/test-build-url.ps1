# Simple test for Build-QSearchUrl
$script = Join-Path $PSScriptRoot '..\src\private\Build-QSearchUrl.ps1'
. $script

$url = Build-QSearchUrl -Album 'let it bleed'
if ($url -match 'let%20it%20bleed') { Write-Output 'PASS' } else { Write-Error 'FAIL - encoding not found' }
