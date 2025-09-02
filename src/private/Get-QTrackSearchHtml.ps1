<#
.SYNOPSIS
    Downloads the HTML for a Qobuz track search.
.DESCRIPTION
    Uses Invoke-WebRequest to fetch the HTML for the Qobuz track search URL.
.PARAMETER Url
    The Qobuz search URL.
#>
function Get-QTrackSearchHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [int]$TimeoutSeconds = 15
    )
    # Reuse Get-QSearchHtml splatting and behavior
    return Get-QSearchHtml -Url $Url -TimeoutSeconds $TimeoutSeconds
}
