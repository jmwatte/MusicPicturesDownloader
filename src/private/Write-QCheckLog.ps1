<#
.SYNOPSIS
    Write structured JSON-lines logs for QCheck operations.

.DESCRIPTION
    Write-QCheckLog appends JSON lines to a log file. It accepts a hashtable
    or object and writes a timestamped record. Also writes verbose output.

.PARAMETER Record
    The object or hashtable to log.

.PARAMETER LogPath
    Optional path to the log file. Defaults to $env:TEMP\MusicPicturesDownloader\qcheck.log
#>
function Write-QCheckLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)] [object] $Record,
        [string] $LogPath = (Join-Path -Path $env:TEMP -ChildPath 'MusicPicturesDownloader\qcheck.log')
    )

    process {
        try {
            $dir = Split-Path -Path $LogPath -Parent
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -LiteralPath $dir -ItemType Directory -Force | Out-Null }
            $payload = [PSCustomObject]@{
                Timestamp = (Get-Date).ToString('o')
                Record = $Record
            }
            $json = $payload | ConvertTo-Json -Depth 10
            # Use Set-Content with -LiteralPath to avoid parsing issues with complex paths
            # Append using Add-Content (supported consistently) and ensure literal path
            Add-Content -LiteralPath $LogPath -Value $json -Encoding UTF8
            Write-Verbose "Wrote qcheck log to ${LogPath}"
        }
        catch {
            Write-Verbose "Failed to write qcheck log to ${LogPath}: ${_}"
        }
    }
}
