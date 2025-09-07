<#
.SYNOPSIS
    Build a Qobuz artist search URL for a given query and locale.

.DESCRIPTION
    Constructs a Qobuz artist search URL using a fixed set of allowed locales.
    Uses URI escaping for the query and returns the full URL string. Defaults
    to 'be-nl' (following example usage) but accepts other allowed locales.

.PARAMETER Query
    The artist search query string.

.PARAMETER Locale
    The locale path segment to use in the Qobuz URL (e.g. 'be-nl', 'us-en').

.OUTPUTS
    String - the fully constructed Qobuz search URL.
#>
function Build-QArtistSearchUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string] $Query,

        [Parameter(Mandatory=$false)]
        [string] $Locale = 'be-nl'
    )

    process {
        # Allowed locales - extend as needed
        $allowed = @('be-nl','en-us','en-gb','fr-fr','de-de','nl-nl')
        if (-not $allowed -contains $Locale.ToLowerInvariant()) {
            throw "Locale '$Locale' is not in the allowed list: $($allowed -join ', ')"
        }

        # Qobuz artist search format: https://www.qobuz.com/<locale>/search/artists/<urlencoded-query>
        $enc = [System.Uri]::EscapeDataString($Query)
        $localePart = $Locale.ToLowerInvariant().Trim()
        $url = "https://www.qobuz.com/$localePart/search/artists/$enc"
        Write-Output $url
    }
}
