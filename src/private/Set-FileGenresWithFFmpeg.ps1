function Set-FileGenresWithFFmpeg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string] $AudioFilePath,
        [Parameter(Mandatory=$true)] [string[]] $Genres,
        [switch] $Replace
    )

    if (-not (Test-Path -LiteralPath $AudioFilePath)) { throw "Audio file not found: $AudioFilePath" }
    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpeg) { throw "ffmpeg is required to write tags. Ensure ffmpeg.exe is in PATH." }

    # Join genres with ';' (no extra spaces) to match module defaults
    $genresStr = $Genres -join ';'
    $temp = Join-Path -Path $env:TEMP -ChildPath (New-Guid).Guid
    New-Item -Path $temp -ItemType Directory -Force | Out-Null
    $out = Join-Path -Path $temp -ChildPath ([IO.Path]::GetFileName($AudioFilePath))

    # Build metadata args correctly: use '-metadata','genre=VALUE' as two separate args
    # Also explicitly map metadata from the input (-map_metadata 0) so existing tags are preserved
    $metaArgs = @('-map_metadata','0','-metadata', "genre=$genresStr")

    # Ensure output is the temp file path and preserve existing metadata
    $ffArgs = @('-y','-i',$AudioFilePath) + $metaArgs + @('-codec','copy',$out)
    $proc = & ffmpeg @ffArgs 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) {
        try { Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        throw "ffmpeg failed to write metadata: $proc"
    }

    # replace original and return previous genres if available
    try {
        # capture old genres before replacing
        $oldMeta = $null
        try { $oldMeta = Get-TrackMetadataFromFile -AudioFilePath $AudioFilePath -ErrorAction SilentlyContinue } catch {}
        $oldGenres = $null
        if ($oldMeta -and $oldMeta.Tags) {
            if ($oldMeta.Tags.ContainsKey('genre')) { $oldGenres = ,($oldMeta.Tags['genre'] -as [string]) -replace '\s*;\s*', ';' }
            else { $oldGenres = $null }
        }

        # Copy output over original with retry/backoff to handle transient locks
        $maxAttempts = 5
        $attempt = 0
        $copied = $false
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
        return @{ Ok = $true; OldGenres = $oldGenres }
    } catch {
        throw "Failed to replace original file: $_"
    }
}
