function Set-FileGenresWithFFmpeg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string] $AudioFilePath,
        [Parameter(Mandatory=$true)] [string[]] $Genres,
        [switch] $Replace
    )

    if (-not (Test-Path $AudioFilePath)) { throw "Audio file not found: $AudioFilePath" }
    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpeg) { throw "ffmpeg is required to write tags. Ensure ffmpeg.exe is in PATH." }

    $genresStr = $Genres -join '; '
    $temp = Join-Path -Path $env:TEMP -ChildPath (New-Guid).Guid
    New-Item -Path $temp -ItemType Directory -Force | Out-Null
    $out = Join-Path -Path $temp -ChildPath ([IO.Path]::GetFileName($AudioFilePath))

    $metaArgs = @()
    if ($Replace) { $metaArgs += ('-metadata','genre=' + $genresStr) } else { $metaArgs += ('-metadata','genre=' + $genresStr) }

    $ffArgs = @('-y','-i',$AudioFilePath) + $metaArgs + @('-codec','copy',$out)
    $proc = & ffmpeg @ffArgs 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) {
        try { Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        throw "ffmpeg failed to write metadata: $proc"
    }

    # replace original
    try {
        Move-Item -Path $out -Destination $AudioFilePath -Force
        Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        throw "Failed to replace original file: $_"
    }

    return $true
}
