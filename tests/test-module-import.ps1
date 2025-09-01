```powershell
# Quick smoke test: import the module and list exported commands
Import-Module testAlbumDownloader -Force
Get-Command -Module testAlbumDownloader | Select-Object Name, CommandType

# Dry-run example using -WhatIf to avoid downloading
Save-QobuzArtistImage -ArtistName 'the beatles' -DestinationPath (Join-Path $env:TEMP 'qobuz-test') -FileNameStyle Hyphen -WhatIf

```
