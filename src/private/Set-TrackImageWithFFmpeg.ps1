<#
.SYNOPSIS
    Embeds an image into an audio file using FFmpeg.
.DESCRIPTION
    Uses FFmpeg to embed the specified image as cover art into the given audio file. Overwrites the original file.
.PARAMETER AudioFilePath
    Path to the audio file.
.PARAMETER ImagePath
    Path to the image file to embed.
#>
function Set-TrackImageWithFFmpeg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AudioFilePath,

        [Parameter(Mandatory)]
        [string]$ImagePath
    )

    # locate ffmpeg
    $ffmpegCmd = Get-Command -Name ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpegCmd) {
        Write-Output "ffmpeg executable not found on PATH."
        return $false
    }
    $ffmpegPath = $ffmpegCmd.Path

    # unique temp output in the user's temp folder
    $tempDir = [System.IO.Path]::GetTempPath()
    $tempOutput = Join-Path -Path $tempDir -ChildPath (([System.Guid]::NewGuid().ToString()) + [System.IO.Path]::GetExtension($AudioFilePath))

    try {
        if (Test-Path -LiteralPath $tempOutput) { Remove-Item -LiteralPath $tempOutput -Force }

        $ffmpegArgs = @(
            '-y',
            '-i', $AudioFilePath,
            '-i', $ImagePath,
            '-map', '0:0',
            '-map', '1:0',
            '-c', 'copy',
            '-id3v2_version', '3',
            '-metadata:s:v', 'title=Album cover',
            '-metadata:s:v', 'comment=Cover (front)',
            $tempOutput
        )

        Write-Verbose ("Running: {0} {1}" -f $ffmpegPath, ($ffmpegArgs -join ' '))

        # Run ffmpeg and capture combined stdout/stderr
        $ffmpegResult = & $ffmpegPath @ffmpegArgs 2>&1
        $ffmpegExit = $LASTEXITCODE

        # print ffmpeg output for diagnostics
        Write-Output $ffmpegResult
        Write-Verbose ("ffmpeg exit code: $ffmpegExit")
        Write-Verbose ("Expected output file: $tempOutput")

        # Wait a short time for the file to appear (handle AV/quarantine or race)
        $maxWaitMs = 3000
        $waitIntervalMs = 200
        $elapsed = 0
        while (-not (Test-Path -LiteralPath $tempOutput) -and ($elapsed -lt $maxWaitMs)) {
            Start-Sleep -Milliseconds $waitIntervalMs
            $elapsed += $waitIntervalMs
        }

        if ($ffmpegExit -ne 0 -or -not (Test-Path -LiteralPath $tempOutput)) {
            Write-Output ("FFmpeg failed to create output file. ExitCode={0}. Checked path exists: {1}" -f $ffmpegExit, (Test-Path -LiteralPath $tempOutput))
            if (Test-Path -LiteralPath $tempOutput) { Remove-Item -LiteralPath $tempOutput -Force }
            return $false
        }

        Move-Item -Path $tempOutput -Destination $AudioFilePath -Force
        Write-Output "Embedded cover image using FFmpeg."
        return $true
    } catch {
        Write-Output ("Failed to embed cover image with FFmpeg: {0}" -f $_)
        if (Test-Path -LiteralPath $tempOutput) { Remove-Item -LiteralPath $tempOutput -Force }
        return $false
    }
}