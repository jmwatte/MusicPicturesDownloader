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
            Write-Verbose "ffprobe output not JSON or empty: $_"
            return [PSCustomObject]@{ Title = $null; Album = $null; Artist = $null; Tags = @{} }
        }

        # Build a case-insensitive hashtable of tags merging format and stream tags
        $tags = [hashtable]::new([System.StringComparer]::InvariantCultureIgnoreCase)
        if ($json.format -and $json.format.tags) {
            $json.format.tags.PSObject.Properties | ForEach-Object { $tags[$_.Name] = $_.Value }
        }
        if ($json.streams) {
            foreach ($s in $json.streams) {
                if ($s.tags) { $s.tags.PSObject.Properties | ForEach-Object { if (-not $tags.ContainsKey($_.Name)) { $tags[$_.Name] = $_.Value } } }
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
