<#
.SYNOPSIS
    Reads common tag metadata from an audio file using ffprobe (ffmpeg).
.DESCRIPTION
    Uses ffprobe to extract tag metadata (title, album, artist) from an audio file and returns a PSCustomObject.
    Falls back with a clear message if ffprobe is not available.
.PARAMETER AudioFilePath
    Path to the audio file to inspect.
.OUTPUTS
    PSCustomObject with properties: Title, Album, Artist, Tags (hashtable)
#>
function Get-TrackMetadataFromFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$AudioFilePath
    )

    process {
        if (-not (Test-Path -Path $AudioFilePath)) {
            throw "Audio file not found: $AudioFilePath"
        }

        $ffprobeCmd = Get-Command -Name ffprobe -ErrorAction SilentlyContinue
        if (-not $ffprobeCmd) {
            throw "ffprobe (part of ffmpeg) is required to read tags. Install ffmpeg and ensure 'ffprobe' is in PATH."
        }

        $args = @('-v','quiet','-print_format','json','-show_format','-show_entries','format=tags','-i',$AudioFilePath)
        try {
            $raw = & ffprobe @args 2>&1
        } catch {
            throw "ffprobe failed: $_"
        }

        try {
            $json = $raw | Out-String | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Verbose "ffprobe JSON parse failed: $_"
            # If running on PowerShell 7+, try ConvertFrom-Json -AsHashtable which tolerates empty property names
            try {
                if ($PSVersionTable.PSVersion.Major -ge 7) {
                    $json = $raw | Out-String | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                    # Convert hashtable to object-ish shape expected below
                    $json = [PSCustomObject]@{ format = $json.format; streams = $json.streams }
                } else {
                    # PowerShell < 7: ConvertFrom-Json rejects empty property names. Attempt a lightweight sanitization
                    # Replace occurrences of "": with a placeholder key then parse. If this fails, fall back to regex.
                    $text = $raw | Out-String
                    $sanitized = $text -replace '""\s*:', '"_empty":'
                    $json = $sanitized | ConvertFrom-Json -ErrorAction Stop
                }
            } catch {
                # Final fallback: attempt to extract "tags" key/value pairs using a forgiving regex from the raw text
                Write-Verbose 'Falling back to regex-based tag extraction from ffprobe output.'
                $text = $raw -join "`n"
                $tags = [hashtable]::new([System.StringComparer]::InvariantCultureIgnoreCase)
                # find all "tags" objects and extract key/value pairs inside them
                $tagBlocks = [regex]::Matches($text, '"tags"\s*:\s*\{([^}]*)\}', 'Singleline') | ForEach-Object { $_.Groups[1].Value }
                foreach ($block in $tagBlocks) {
                    $pairs = [regex]::Matches($block, '"([^"\\]*)"\s*:\s*"([^"\\]*)"')
                    foreach ($p in $pairs) {
                        $k = $p.Groups[1].Value.ToString().Trim()
                        $v = $p.Groups[2].Value.ToString().Trim()
                        # Skip empty keys or empty values; avoid adding blank-name tags
                        if ($k.Length -gt 0 -and $v.Length -gt 0 -and -not $tags.ContainsKey($k)) {
                            $tags[$k] = $v
                        }
                    }
                }
                return [PSCustomObject]@{ Title = $null; Album = $null; Artist = $null; Tags = $tags }
            }
        }

        # Build a case-insensitive hashtable of tags merging format and stream tags
        $tags = [hashtable]::new([System.StringComparer]::InvariantCultureIgnoreCase)
        if ($json.format -and $json.format.tags) {
            $ftags = $json.format.tags
            if ($ftags -is [System.Collections.IDictionary]) {
                foreach ($k in $ftags.Keys) {
                    $name = $k.ToString().Trim()
                    $value = ($ftags[$k] -ne $null) ? $ftags[$k].ToString().Trim() : $null
                    if ($name.Length -gt 0 -and $name -ne '_empty' -and $value) { $tags[$name] = $value }
                }
            } else {
                $json.format.tags.PSObject.Properties | ForEach-Object {
                    $name = $_.Name.ToString().Trim()
                    $value = ($_.Value -ne $null) ? $_.Value.ToString().Trim() : $null
                    if ($name.Length -gt 0 -and $name -ne '_empty' -and $value) { $tags[$name] = $value }
                }
            }
        }
        if ($json.streams) {
            foreach ($s in $json.streams) {
                if ($s.tags) {
                    $st = $s.tags
                    if ($st -is [System.Collections.IDictionary]) {
                        foreach ($k in $st.Keys) {
                            $name = $k.ToString().Trim()
                            $value = ($st[$k] -ne $null) ? $st[$k].ToString().Trim() : $null
                            if ($name.Length -gt 0 -and $name -ne '_empty' -and $value -and -not $tags.ContainsKey($name)) {
                                $tags[$name] = $value
                            }
                        }
                    } else {
                        $s.tags.PSObject.Properties | ForEach-Object {
                            $name = $_.Name.ToString().Trim()
                            $value = ($_.Value -ne $null) ? $_.Value.ToString().Trim() : $null
                            if ($name.Length -gt 0 -and $name -ne '_empty' -and $value -and -not $tags.ContainsKey($name)) {
                                $tags[$name] = $value
                            }
                        }
                    }
                }
            }
        }

        # Helper: return first non-empty tag from a list of candidate keys (case-insensitive)
        function Get-FirstTagValue { param([string[]] $keys) 
            foreach ($k in $keys) {
                if ($k -and $tags.ContainsKey($k)) {
                    $v = $tags[$k]
                    if ($v -and ($v.ToString().Trim().Length -gt 0)) { return $v.ToString().Trim() }
                }
            }
            return $null
        }

        # Common candidate keys (cover ID3v2 frames and common names)
        $titleKeys = @('title','TIT2','TITLE')
        $albumKeys = @('album','TALB','ALBUM')
        $artistKeys = @('artist','TPE1','artist_sort','artists','artist;albumartist','albumartist','album_artist','TPE2','performer','performer_sort','composer')

        $title = Get-FirstTagValue -keys $titleKeys
        $album = Get-FirstTagValue -keys $albumKeys
        $artist = Get-FirstTagValue -keys $artistKeys

        # Fallbacks and normalization
        if (-not $title) { $title = $null }
        if (-not $album) { $album = $null }
        if (-not $artist) { $artist = $null }

        return [PSCustomObject]@{
            Title = $title
            Album = $album
            Artist = $artist
            Tags = $tags
        }
    }
}
