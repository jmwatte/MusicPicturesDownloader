<#
.SYNOPSIS
    Download artist images from Qobuz for one or more artists.

.DESCRIPTION
    Accepts artist names or objects (with ArtistName or Name properties) from the pipeline
    or as direct arguments and delegates to underlying helpers to download available artist images.

.PARAMETER ArtistInput
    Artist(s) to obtain images for. Accepts strings or objects with ArtistName/Name properties.

.PARAMETER DestinationFolder
    Local folder path where images will be saved. Mandatory.

.PARAMETER NoAuto
    When specified, do NOT automatically download images; by default this function will download
    images for each artist. This switch is accepted for API parity and will suppress automatic
    downloads (treated as a preview/dry-run for bulk operations).

.PARAMETER PreferredSize
    Preferred image size. Valid values: large, medium, small. Default is large.

.PARAMETER Force
    Switch to overwrite existing files when applicable.

EXAMPLE
    # Download a single artist image (downloads by default)
    Save-QArtistsImages 'Pink Floyd' -DestinationFolder 'C:\Music\ArtistImages'

EXAMPLE
    # Pipeline input with multiple artists
    'Adele','Coldplay' | Save-QArtistsImages -DestinationFolder 'C:\Music\ArtistImages'

EXAMPLE
    # Use object pipeline input
    [pscustomobject]@{ ArtistName = 'Radiohead' } | Save-QArtistsImages -DestinationFolder 'C:\Music\ArtistImages'

EXAMPLE
    # Preview / report-only for bulk: do not perform downloads
    'Adele','Coldplay' | Save-QArtistsImages -DestinationFolder 'C:\Music\ArtistImages' -NoAuto

.NOTES
    - This function delegates to Save-QobuzItems which performs the actual network calls and downloads.
#>
function Save-QArtistsImages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('InputObject')]
        [object[]]$ArtistInput,

    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNullOrEmpty()]
    [string]$DestinationFolder,

        [Parameter()]
        [ValidateSet('large','medium','small')]
        [string]$PreferredSize = 'large',

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$NoAuto,

    [Parameter()]
    [switch]$ShowRawTags
    )
    process {
        $splat = @{ DestinationFolder = $DestinationFolder; PreferredSize = $PreferredSize }
        if ($PSBoundParameters.ContainsKey('Force') -and $Force) { $splat.Force = $true }
        if ($PSBoundParameters.ContainsKey('WhatIf')) { $splat.WhatIf = $true }
        if ($PSBoundParameters.ContainsKey('Confirm')) { $splat.Confirm = $true }

        foreach ($item in $ArtistInput) {
            if ($null -eq $item) { continue }
            if ($item -is [string]) { $splat.ArtistName = $item }
            else {
                if ($item -is [pscustomobject] -and $item.PSObject.Properties.Match('ArtistName')) { $splat.ArtistName = $item.ArtistName }
                elseif ($item -is [pscustomobject] -and $item.PSObject.Properties.Match('Name')) { $splat.ArtistName = $item.Name }
                else { $splat.ArtistName = $item.ToString() }
            }

            if ($PSBoundParameters.ContainsKey('NoAuto') -and $NoAuto) { $splat.NoAuto = $true }
            Save-QobuzItems @splat
        }
    }
}