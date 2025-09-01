````markdown
# testAlbumDownloader

PowerShell module to download artist cover images from qobuz.com search pages.

Usage example:

```powershell
Import-Module testAlbumDownloader
Save-QobuzArtistImage -ArtistName 'jean-michel jarre' -DestinationPath C:\Temp -Verbose
```

Notes and assumptions:
- The function builds the Qobuz search URL as `https://www.qobuz.com/be-nl/search/artists/{uri-encoded artist}`.
- It extracts the first `<img class="CoverModelImage">` on the search page and prefers the `data-src` or `src` attribute.
- If the found URL references a non-large size (e.g. `medium`), the function will attempt to replace it with `large`.
- Filenames default to replacing spaces with hyphens; use `-FileNameStyle Spaces` to keep spaces.
- The module was implemented to be compatible with Windows PowerShell 5.1 (uses `Invoke-WebRequest -UseBasicParsing`).

If you want different filename sanitization or alternate locales for Qobuz, I can add options.

````
