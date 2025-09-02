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

        $tags = @{}
        if ($json.format -and $json.format.tags) {
            foreach ($k in $json.format.tags.PSObject.Properties.Name) {
                $tags[$k] = $json.format.tags.$k
            }
        }

        # Normalize common keys (case-insensitive)
        $getTag = {
            param($keys)
            foreach ($k in $keys) {
                if ($tags.ContainsKey($k)) { return $tags[$k] }
                $low = $k.ToLower()
                foreach ($tk in $tags.Keys) { if ($tk.ToLower() -eq $low) { return $tags[$tk] } }
            }
            return $null
        }

        $title = & $getTag @('title','TIT2')
        $album = & $getTag @('album','ALBUM')
        $artist = & $getTag @('artist','ARTIST','performer','PERFORMER')

        return [PSCustomObject]@{
            Title = $title
            Album = $album
            Artist = $artist
            Tags = $tags
        }
    }
}
