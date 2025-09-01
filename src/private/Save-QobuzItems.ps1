#. (Join-Path $PSScriptRoot 'LogHelper.ps1')

<#
.SYNOPSIS
Download artist images in bulk from Qobuz.

.DESCRIPTION
`Save-QobuzItems` accepts a single artist name, an array of artist names, or pipeline input and downloads each artist's image using `Save-QobuzArtistImage`.

.PARAMETER Input
Artist name(s) as string or pipeline input. Accepts property names `ArtistName` or `InputObject`.

.PARAMETER DestinationFolder
Directory to save downloaded images.

.PARAMETER FileNameStyle
Either 'Hyphen' (default) or 'Spaces' for generated filenames.

.PARAMETER PreferredSize
Preferred image size: large (default), medium or small.

.PARAMETER Force
Overwrite existing files.

.OUTPUTS
Returns an array of PSCustomObject with properties: Artist, Path, Status, ErrorMessage.
#>
function Save-QobuzItems {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    Param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('ArtistName','InputObject')]
        [string[]]$ArtistInput,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationFolder,

    [ValidateSet('Hyphen','Spaces')]
    [string]$FileNameStyle = 'Hyphen',

    [ValidateSet('large','medium','small')]
    [string]$PreferredSize = 'large',

    [switch]$Force
    )


    Begin {
        #also test if the $DestinationFolder is in the $ArtistInput
        if ($ArtistInput -contains $DestinationFolder) {
            Write-Log -Message "DestinationFolder is in the input" -Level Debug -Category Bulk
        }
        if (-not (Test-Path -Path $DestinationFolder)) { New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null }
        Write-Log -Message "Bulk operation begin" -Level Debug -Category Bulk
        $results = @()
    }

    Process {
        
        if ($null -ne $ArtistInput) {
            foreach ($item in $ArtistInput) {
                $artist = $item.ToString()
                try {
                    $artistImageParameters = @{ ArtistName = $artist; DestinationFolder = $DestinationFolder; FileNameStyle = $FileNameStyle; PreferredSize = $PreferredSize; ErrorAction = 'Stop' }
                    if ($Force) { $artistImageParameters.Force = $true }

                    if ($PSCmdlet.ShouldProcess($artist, "Download image to $DestinationFolder")) {
                        Write-Log -Message "Processing item: $artist" -Level Verbose -Category Bulk
                        $out = Save-QobuzArtistImage @artistImageParameters
                        $results += [PSCustomObject]@{ Artist = $artist; Path = $out; Status = 'Success'; ErrorMessage = $null }
                    }
                }
                catch {
                    $results += [PSCustomObject]@{ Artist = $artist; Path = $null; Status = 'Failed'; ErrorMessage = $_.Exception.Message }
                }
            }
        }
    }

    End {
        return $results
    }
}
