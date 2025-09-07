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
        if (-not (Test-Path -LiteralPath $AudioFilePath)) {
            throw "Audio file not found: $AudioFilePath"
        }

        # Try TagLib# first for fast, in-process metadata reads. If TagLib is not available
        # or an error occurs reading the file, fall back to the existing ffprobe-based logic below.
        try {
            if ([System.Type]::GetType('TagLib.File, TagLib') -or (Get-Command -Name Add-Type -ErrorAction SilentlyContinue)) {
                try {
                    $tagFile = [TagLib.File]::Create($AudioFilePath)
                } catch {
                    throw $_
                }

                $t = $tagFile.Tag
                $tags = [hashtable]::new([System.StringComparer]::InvariantCultureIgnoreCase)

                if ($t.Title) { $tags['title'] = $t.Title }
                if ($t.Album) { $tags['album'] = $t.Album }

                if ($t.Performers -and $t.Performers.Length -gt 0) {
                    $tags['artist'] = ($t.Performers -join '; ')
                } elseif ($t.FirstPerformer) {
                    $tags['artist'] = $t.FirstPerformer
                }

                if ($t.AlbumArtists -and $t.AlbumArtists.Length -gt 0) {
                    $tags['albumartist'] = ($t.AlbumArtists -join '; ')
                }

                if ($t.Genres -and $t.Genres.Length -gt 0) { $tags['genre'] = ($t.Genres -join '; ') }
                if ($t.Composers -and $t.Composers.Length -gt 0) { $tags['composer'] = ($t.Composers -join '; ') }
                if ($t.Comment) { $tags['comment'] = $t.Comment }
                if ($t.Year -and $t.Year -ne 0) { $tags['date'] = $t.Year.ToString() }
                if ($t.Track -and $t.Track -ne 0) { $tags['track'] = $t.Track.ToString() }

                # Pictures are binary; expose the count so callers know if embedded art exists
                if ($t.Pictures -and $t.Pictures.Length -gt 0) { $tags['pictureCount'] = $t.Pictures.Length }

                # TagLib reading succeeded; assume this is an audio file.
                $audioCount = 1

                Write-Verbose ([string]::Format('Get-TrackMetadataFromFile (TagLib): audioCount={0}; tags={1}; albumartist={2}; artist={3}',
                    $audioCount,
                    ($tags.Keys -join ','),
                    ($tags.ContainsKey('albumartist') ? $tags['albumartist'] : '<none>'),
                    ($tags.ContainsKey('artist') ? $tags['artist'] : '<none>')
                ))

                return [PSCustomObject]@{
                    Title = ($tags.ContainsKey('title') ? $tags['title'] : $null)
                    Album = ($tags.ContainsKey('album') ? $tags['album'] : $null)
                    Artist = ($tags.ContainsKey('artist') ? $tags['artist'] : $null)
                    AlbumArtist = ($tags.ContainsKey('albumartist') ? $tags['albumartist'] : $null)
                    Tags = $tags
                    audioCount = $audioCount
                }
            }
        } catch {
            Write-Verbose "TagLib read failed, falling back to ffprobe: $_"
            # continue to ffprobe fallback below
        }

    #     $ffprobeCmd = Get-Command -Name ffprobe -ErrorAction SilentlyContinue
    #     if (-not $ffprobeCmd) {
    #         throw "ffprobe (part of ffmpeg) is required to read tags. Install ffmpeg and ensure 'ffprobe' is in PATH."
    #     }

    # # Request both format tags and streams so we can detect audio streams reliably
    # # Use -show_streams which reliably emits stream objects in ffprobe JSON
    #     $ffprobeArgs = @('-v','quiet','-print_format','json','-show_format','-show_streams','-i',$AudioFilePath)
    #     try {
    #         $raw = & ffprobe @ffprobeArgs 2>&1
    #     } catch {
    #         throw "ffprobe failed: $_"
    #     }

    #     try {
    #         $json = $raw | Out-String | ConvertFrom-Json -ErrorAction Stop
    #     } catch {
    #         Write-Verbose "ffprobe JSON parse failed: $_"
    #         # If running on PowerShell 7+, try ConvertFrom-Json -AsHashtable which tolerates empty property names
    #         try {
    #             if ($PSVersionTable.PSVersion.Major -ge 7) {
    #                 $json = $raw | Out-String | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    #                 # Convert hashtable to object-ish shape expected below
    #                 $json = [PSCustomObject]@{ format = $json.format; streams = $json.streams }
    #             } else {
    #                 # PowerShell < 7: ConvertFrom-Json rejects empty property names. Attempt a lightweight sanitization
    #                 # Replace occurrences of "": with a placeholder key then parse. If this fails, fall back to regex.
    #                 $text = $raw | Out-String
    #                 $sanitized = $text -replace '""\s*:', '"_empty":'
    #                 $json = $sanitized | ConvertFrom-Json -ErrorAction Stop
    #             }
    #         } catch {
    #             # Final fallback: attempt to extract "tags" key/value pairs using a forgiving regex from the raw text
    #             Write-Verbose 'Falling back to regex-based tag extraction from ffprobe output.'
    #             $text = $raw -join "`n"
    #             $tags = [hashtable]::new([System.StringComparer]::InvariantCultureIgnoreCase)
    #             # find all "tags" objects and extract key/value pairs inside them
    #             $tagBlocks = [regex]::Matches($text, '"tags"\s*:\s*\{([^}]*)\}', 'Singleline') | ForEach-Object { $_.Groups[1].Value }
    #             foreach ($block in $tagBlocks) {
    #                 $pairs = [regex]::Matches($block, '"([^"\\]*)"\s*:\s*"([^"\\]*)"')
    #                 foreach ($p in $pairs) {
    #                     $k = $p.Groups[1].Value.ToString().Trim()
    #                     $v = $p.Groups[2].Value.ToString().Trim()
    #                     # Skip empty keys or empty values; avoid adding blank-name tags
    #                     if ($k.Length -gt 0 -and $v.Length -gt 0 -and -not $tags.ContainsKey($k)) {
    #                         $tags[$k] = $v
    #                     }
    #                 }
    #             }
    #             # Try to detect audio streams from the raw ffprobe output (fallback when JSON parse fails)
    #             $audioCount = 0
    #             try {
    #                 $audioCount = ([regex]::Matches($text, '"codec_type"\s*:\s*"audio"', 'IgnoreCase')).Count
    #                 if ($audioCount -eq 0) {
    #                     # also attempt a looser match for stream lines if ffprobe output is not strict JSON
    #                     $audioCount = ([regex]::Matches($text, 'Stream\s+#[^:]+:\s*Audio', 'IgnoreCase')).Count
    #                 }
    #             } catch { $audioCount = 0 }

    #             return [PSCustomObject]@{ Title = $null; Album = $null; Artist = $null; Tags = $tags; audioCount = $audioCount }
    #         }
    #     }

    # Build a case-insensitive hashtable of tags merging format and stream tags
        # $tags = [hashtable]::new([System.StringComparer]::InvariantCultureIgnoreCase)
        # if ($json.format -and $json.format.tags) {
        #     $ftags = $json.format.tags
        #     if ($ftags -is [System.Collections.IDictionary]) {
        #         foreach ($k in $ftags.Keys) {
        #             $name = $k.ToString().Trim()
        #             $value = ($null -ne $ftags[$k]) ? $ftags[$k].ToString().Trim() : $null
        #             if ($name.Length -gt 0 -and $name -ne '_empty' -and $value) { $tags[$name] = $value }
        #         }
        #     } else {
        #         $json.format.tags.PSObject.Properties | ForEach-Object {
        #             $name = $_.Name.ToString().Trim()
        #             $value = ($null -ne $_.Value) ? $_.Value.ToString().Trim() : $null
        #             if ($name.Length -gt 0 -and $name -ne '_empty' -and $value) { $tags[$name] = $value }
        #         }
        #     }
        # }
        # if ($json.streams) {
        #     foreach ($s in $json.streams) {
        #         if ($s.tags) {
        #             $st = $s.tags
        #             if ($st -is [System.Collections.IDictionary]) {
        #                 foreach ($k in $st.Keys) {
        #                     $name = $k.ToString().Trim()
        #                     $value = ($null -ne $st[$k]) ? $st[$k].ToString().Trim() : $null
        #                     if ($name.Length -gt 0 -and $name -ne '_empty' -and $value -and -not $tags.ContainsKey($name)) {
        #                         $tags[$name] = $value
        #                     }
        #                 }
        #             } else {
        #                 $s.tags.PSObject.Properties | ForEach-Object {
        #                     $name = $_.Name.ToString().Trim()
        #                     $value = ($null -ne $_.Value) ? $_.Value.ToString().Trim() : $null
        #                     if ($name.Length -gt 0 -and $name -ne '_empty' -and $value -and -not $tags.ContainsKey($name)) {
        #                         $tags[$name] = $value
        #                     }
        #                 }
        #             }
        #         }
        #     }
        # }

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

    #     # Normalize common tag key variants to canonical names
    #     try {
    #         # remove any blank-name tag entries which sometimes appear in ffprobe output
    #         if ($tags.ContainsKey('')) { $null = $tags.Remove('') }
    #         if ($tags.ContainsKey('_empty')) { $null = $tags.Remove('_empty') }

    #         # map album_artist / album-artist / "album artist" -> albumartist
    #         $albumAliases = @('album_artist','album-artist','album artist')
    #         foreach ($a in $albumAliases) {
    #             if ($tags.ContainsKey($a) -and -not $tags.ContainsKey('albumartist')) {
    #                 $tags['albumartist'] = $tags[$a]
    #             }
    #             if ($tags.ContainsKey($a)) { $null = $tags.Remove($a) }
    #         }
    #     } catch { }

    #     # Common candidate keys (cover ID3v2 frames and common names)
    #     $titleKeys = @('title','TIT2','TITLE')
    #     $albumKeys = @('album','TALB','ALBUM')
    #     $artistKeys = @('artist','TPE1','artist_sort','artists','artist;albumartist','albumartist','album_artist','TPE2','performer','performer_sort','composer')

    #     $title = Get-FirstTagValue -keys $titleKeys
    #     $album = Get-FirstTagValue -keys $albumKeys
    #     $artist = Get-FirstTagValue -keys $artistKeys

    #     # Fallbacks and normalization
    #     if (-not $title) { $title = $null }
    #     if (-not $album) { $album = $null }
    #     if (-not $artist) { $artist = $null }

    #     # Count audio streams (if available) so callers can skip non-audio files
    #     $audioCount = 0
    #     try {
    #         if ($json -and $json.streams) {
    #             $audioCount = ($json.streams | Where-Object { $_.codec_type -eq 'audio' }).Count
    #         }
    #     } catch { $audioCount = 0 }

    #     # If audioCount is zero, try a fast, robust ffprobe text query as a last-resort
    #     # (this mirrors the command you provided which is tolerant of odd JSON output)
    #     if ($audioCount -le 0) {
    #         try {
    #             $probeArgs = @('-v','error','-show_entries','stream=codec_type','-of','default=noprint_wrappers=1:nokey=1',$AudioFilePath)
    #             $probeOut = & ffprobe @probeArgs 2>&1
    #             if ($probeOut) {
    #                 $audioMatches = ([regex]::Matches($probeOut -join "`n", 'audio', 'IgnoreCase')).Count
    #                 if ($audioMatches -gt 0) { $audioCount = $audioMatches }
    #             }
    #         } catch {
    #             # ignore probe fallback errors
    #         }
    #     }

    #     # Verbose diagnostic: show audioCount and key tag names (and albumartist if present)
    #     Write-Verbose ([string]::Format('Get-TrackMetadataFromFile: audioCount={0}; tags={1}; albumartist={2}',
    #         $audioCount,
    #         ($tags.Keys -join ','),
    #         ($tags.ContainsKey('albumartist') ? $tags['albumartist'] : '<none>')
    #     ))

    #     return [PSCustomObject]@{
    #         Title = $title
    #         Album = $album
    #         Artist = $artist
    #         Tags = $tags
    #         audioCount = $audioCount
    #     }
    }
}
