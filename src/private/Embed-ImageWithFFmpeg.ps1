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
    $ffmpegPath = "ffmpeg"
    $tempOutput = [System.IO.Path]::GetTempFileName() + [System.IO.Path]::GetExtension($AudioFilePath)
    try {
        if (Test-Path -LiteralPath $tempOutput) { Remove-Item -LiteralPath $tempOutput -Force }
        $ffmpegArgs = @(
            '-y',
            '-i', $AudioFilePath,
            '-i', $ImagePath,
            '-map', '0',
            '-map', '1',
            '-c', 'copy',
            '-id3v2_version', '3',
            '-metadata:s:v', 'title="Album cover"',
            '-metadata:s:v', 'comment="Cover (front)"',
            $tempOutput
        )
        $ffmpegResult = & $ffmpegPath @ffmpegArgs 2>&1
        if (!(Test-Path -LiteralPath $tempOutput)) {
            Write-Output "FFmpeg failed to create output file. Output: $ffmpegResult"
            return $false
        }
        Move-Item -Path $tempOutput -Destination $AudioFilePath -Force
        Write-Output "Embedded cover image using FFmpeg."
        return $true
    } catch {
        Write-Output "Failed to embed cover image with FFmpeg: $_"
        if (Test-Path -LiteralPath $tempOutput) { Remove-Item -LiteralPath $tempOutput -Force }
        return $false
    }
}
