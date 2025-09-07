function Set-FileArtistWithFFmpeg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$AudioFilePath,
        [string]$Artist,
        [string]$AlbumArtist,
        [switch]$Replace
    )

    if (-not (Test-Path -LiteralPath $AudioFilePath)) { throw "Audio file not found: $AudioFilePath" }
    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpeg) { throw "ffmpeg is required to write tags. Ensure ffmpeg.exe is in PATH." }

    $temp = Join-Path -Path $env:TEMP -ChildPath (New-Guid).Guid
    New-Item -Path $temp -ItemType Directory -Force | Out-Null
    $out = Join-Path -Path $temp -ChildPath ([IO.Path]::GetFileName($AudioFilePath))

    # Build metadata args: map existing metadata and set artist and/or albumartist if requested
    $metaArgs = @('-map_metadata','0')
    if ($Artist) { $metaArgs += @('-metadata', ("artist={0}" -f $Artist)) }
    if ($AlbumArtist) { $metaArgs += @('-metadata', ("albumartist={0}" -f $AlbumArtist)) }

    $ffArgs = @('-y','-i',$AudioFilePath) + $metaArgs + @('-codec','copy',$out)
    $proc = & ffmpeg @ffArgs 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) {
        try { Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        throw "ffmpeg failed to write metadata: $proc"
    }

    try {
        # capture old artist before replacing
        $oldMeta = $null
        try { $oldMeta = Get-TrackMetadataFromFile -AudioFilePath $AudioFilePath -ErrorAction SilentlyContinue } catch {}
        $oldArtist = $null
        $oldAlbumArtist = $null
        if ($oldMeta -and $oldMeta.Tags) {
            if ($oldMeta.Tags.ContainsKey('artist')) { $oldArtist = $oldMeta.Tags['artist'] }
            if ($oldMeta.Tags.ContainsKey('albumartist')) { $oldAlbumArtist = $oldMeta.Tags['albumartist'] }
        }

        # Replace original file with retry/backoff
        $maxAttempts = 5; $attempt = 0; $copied = $false
        while (-not $copied -and $attempt -lt $maxAttempts) {
            try {
                if (Test-Path -LiteralPath $AudioFilePath) {
                    try { Set-ItemProperty -LiteralPath $AudioFilePath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue } catch {}
                    try { Remove-Item -LiteralPath $AudioFilePath -Force -ErrorAction SilentlyContinue } catch {}
                }
                Copy-Item -LiteralPath $out -Destination $AudioFilePath -Force -ErrorAction Stop
                $copied = $true
            } catch {
                $attempt++
                $wait = [math]::Min(2, [math]::Pow(2, $attempt) * 0.2)
                Start-Sleep -Seconds $wait
                if ($attempt -ge $maxAttempts) { throw "Failed to replace original file after $maxAttempts attempts: $_" }
            }
        }
    Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue
    return @{ Ok = $true; OldArtist = $oldArtist; OldAlbumArtist = $oldAlbumArtist }
    } catch {
        throw "Failed to replace original file: $_"
    }
}
