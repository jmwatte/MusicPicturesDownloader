
<#
.SYNOPSIS
Downloads an image URL to the destination folder.
#>
function Save-Image {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ImageUrl,
        [Parameter(Mandatory=$true)]
        [string]$DestinationFolder,
        [ValidateSet('Always','IfBigger','SkipIfExists')]
        [string]$DownloadMode = 'Always',
        [ValidateSet('Folder','Cover','Album-Artist','Artist-Album','Custom')]
        [string]$FileNameStyle = 'Cover',
        [string]$CustomFileName,
        [string]$Album,
        [string]$Artist,
        [string]$FileName
    )

    process {
        if (-not (Test-Path -LiteralPath $DestinationFolder)) { New-Item -LiteralPath $DestinationFolder -ItemType Directory -Force | Out-Null }
        # Determine file name based on style
        switch ($FileNameStyle) {
            'Folder' { $FileName = 'folder.jpg' } # literal string 'folder.jpg'
            'Cover' { $FileName = 'cover.jpg' }
            'Album-Artist' { $FileName = ("{0}-{1}.jpg" -f $Album, $Artist) -replace '[\\/:*?"<>|]', '_' }
            'Artist-Album' { $FileName = ("{0}-{1}.jpg" -f $Artist, $Album) -replace '[\\/:*?"<>|]', '_' }
            'Custom' {
                if ($CustomFileName) {
                    $FileName = $CustomFileName -replace '{Album}', $Album -replace '{Artist}', $Artist
                    $FileName = $FileName -replace '[\\/:*?"<>|]', '_'
                } else {
                    $FileName = 'cover.jpg'
                }
            }
            default {
                if (-not $FileName) {
                    $uri = [System.Uri]::new($ImageUrl)
                    $FileName = [System.IO.Path]::GetFileName($uri.LocalPath)
                    if (-not $FileName) { $FileName = "image_$([guid]::NewGuid().ToString()).jpg" }
                }
            }
        }
        $outPath = Join-Path $DestinationFolder $FileName

        # DownloadMode logic
        if (Test-Path -LiteralPath $outPath -PathType Leaf -ErrorAction SilentlyContinue) {
            switch ($DownloadMode) {
                'SkipIfExists' { return $outPath }
                'IfBigger' {
                    try {
                        $existing = Get-Item -Path $outPath
                        $uri = [System.Uri]::new($ImageUrl)
                        $webReq = [System.Net.WebRequest]::Create($uri)
                        $webReq.Method = 'HEAD'
                        $webResp = $webReq.GetResponse()
                        $remoteSize = $webResp.ContentLength
                        $webResp.Close()
                        if ($remoteSize -le $existing.Length) { return $outPath }
                    } catch { }
                }
                'Always' { Remove-Item -Path $outPath -Force -ErrorAction SilentlyContinue }
            }
        }

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
