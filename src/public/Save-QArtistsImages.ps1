<#
.SYNOPSIS
Downloads and saves artist images for the specified artist(s).

.DESCRIPTION
Save-QArtistsImages accepts artist names or objects (with ArtistName or Name properties) from the pipeline
or as direct arguments and delegates to Save-QobuzItems to download images. Supports PreferredSize and Force
and respects common parameters like -WhatIf and -Confirm.

.PARAMETER Input
Artist(s) to obtain images for. Accepts:
- string values (artist names) from the pipeline or as arguments.
- objects from the pipeline that contain an ArtistName or Name property.
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
None. The function delegates operations to Save-QobuzItems.

.EXAMPLE
# Positional use (artist name and destination)
Save-QArtistsImages 'Pink Floyd' 'C:\Music\ArtistImages'

.EXAMPLE
# Pipeline of strings
'Adele','Coldplay' | Save-QArtistsImages -DestinationPath 'C:\Music\ArtistImages'

.EXAMPLE
# Pipeline of objects with ArtistName or Name property
[pscustomobject]@{ ArtistName = 'Radiohead' }, [pscustomobject]@{ Name = 'Nirvana' } |
    Save-QArtistsImages -DestinationPath 'C:\Music\ArtistImages' -PreferredSize medium

.EXAMPLE
# Use Force and common parameters like -WhatIf
'The Beatles' | Save-QArtistsImages -DestinationPath 'C:\Music\ArtistImages' -Force -WhatIf

.NOTES
This function relies on Save-QobuzItems to perform the actual download work.
#>
function Save-QArtistsImages {
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
            if ($item -is [string]) { $splat.ArtistName = $item }
            else {
                if ($item -is [pscustomobject] -and $item.PSObject.Properties.Match('ArtistName')) { $splat.ArtistName = $item.ArtistName }
                elseif ($item -is [pscustomobject] -and $item.PSObject.Properties.Match('Name')) { $splat.ArtistName = $item.Name }
                else { $splat.ArtistName = $item.ToString() }
            }

            Save-QobuzItems @splat
        }
    }
}