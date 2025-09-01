
<#
.SYNOPSIS
Downloads an image URL to the destination folder.
#>
function Download-Image {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ImageUrl,
        [Parameter(Mandatory=$true)]
        [string]$DestinationFolder,
        [string]$FileName
    )

    process {
        if (-not (Test-Path -Path $DestinationFolder)) { New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null }
        if (-not $FileName) {
            $uri = [System.Uri]::new($ImageUrl)
            $FileName = [System.IO.Path]::GetFileName($uri.LocalPath)
            if (-not $FileName) { $FileName = "image_$([guid]::NewGuid().ToString()).jpg" }
        }
        $outPath = Join-Path $DestinationFolder $FileName

        $params = @{
            Uri = $ImageUrl
            OutFile = $outPath
            ErrorAction = 'Stop'
        }
        try {
            Invoke-WebRequest @params | Out-Null
            Write-Output $outPath
        }
        catch {
            Write-Verbose "Failed to download image $ImageUrl -- $_"
            throw
        }
    }
}
