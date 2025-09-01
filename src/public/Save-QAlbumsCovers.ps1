<#
.SYNOPSIS
Downloads and saves album cover images for the specified album(s).

.DESCRIPTION
Save-QAlbumCovers accepts album-artist names or objects (with AlbumArtistName properties) from the pipeline
or as direct arguments and delegates to Save-QAlbumItems to download images. Supports PreferredSize and Force
and respects common parameters like -WhatIf and -Confirm.

.PARAMETER Input
ArtistAlbun(s) to obtain images for. Accepts:
- string values (artist-album names) from the pipeline or as arguments.
- objects from the pipeline that contain an ArtistAlbum property.
ValueFromPipeline and ValueFromPipelineByPropertyName are enabled.

.PARAMETER DestinationPath
Local folder path where images will be saved. Mandatory.

.PARAMETER PreferredSize
Preferred image size. Valid values: large, medium, small. Default is large.

.PARAMETER Force
Switch to overwrite existing files when applicable.

.INPUTS
string, PSCustomObject

.OUTPUTS
None. The function delegates operations to Save-QAlbumItems.

.EXAMPLE
# Positional use (artist name and destination)
Save-QAlbumCovers 'Pink Floyd - The Wall' 'C:\Music\AlbumCovers'

.EXAMPLE
# Pipeline of strings
'Adele 24','Beatle Help!' | Save-QAlbumCovers -DestinationPath 'C:\Music\AlbumCovers'

.EXAMPLE
# Pipeline of objects with ArtistAlbum or Name property
[pscustomobject]@{ ArtistAlbum = 'Radiohead - OK Computer' }, [pscustomobject]@{ Name = 'Nirvana - Nevermind' } |
    Save-QAlbumCovers -DestinationPath 'C:\Music\AlbumCovers' -PreferredSize medium

.EXAMPLE
# Use Force and common parameters like -WhatIf
'Radiohead - OK Computer' | Save-QAlbumCovers -DestinationPath 'C:\Music\AlbumCovers' -Force -WhatIf

.NOTES
This function relies on Save-QAlbumItems to perform the actual download work.
#>

function Save-QAlbumCovers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('InputObject')]
        [object[]]$Input,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath,

        [Parameter()]
        [ValidateSet('large','medium','small')]
        [string]$PreferredSize = 'large',

        [Parameter()]
        [switch]$Force
    )
    process {
        $splat = @{ DestinationPath = $DestinationPath; PreferredSize = $PreferredSize }
        if ($PSBoundParameters.ContainsKey('Force') -and $Force) { $splat.Force = $true }
        if ($PSBoundParameters.ContainsKey('WhatIf')) { $splat.WhatIf = $true }
        if ($PSBoundParameters.ContainsKey('Confirm')) { $splat.Confirm = $true }

        foreach ($item in $Input) {
            if ($null -eq $item) { continue }
            if ($item -is [string]) { $splat.ArtistAlbum = $item }
            else {
                if ($item -is [pscustomobject] -and $item.PSObject.Properties.Match('ArtistAlbum')) { $splat.ArtistAlbum = $item.ArtistAlbum }
                elseif ($item -is [pscustomobject] -and $item.PSObject.Properties.Match('Name')) { $splat.ArtistAlbum = $item.Name }
                else { $splat.ArtistAlbum = $item.ToString() }
            }

            Save-QAlbumItems @splat
        }
    }
}