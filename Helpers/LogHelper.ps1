<#
.SYNOPSIS
Centralized logging helper for testAlbumDownloader.
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [ValidateSet('Info','Verbose','Warning','Error','Debug')]
        [string]$Level = 'Info',

        [string]$Category
    )

    $time = Get-Date -Format o
    $prefix = if ($Category) { "[$Category]" } else { "" }

    switch ($Level) {
        'Verbose' { Write-Verbose "$prefix $Message" }
        'Debug'   { Write-Debug "$prefix $Message" }
        'Warning' { Write-Warning "$prefix $Message" }
        'Error'   { Write-Error "$prefix $Message" -ErrorAction Continue }
        default  { Write-Output "$time $prefix $Message" }
    }
}
