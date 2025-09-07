<#
.SYNOPSIS
    Fetch HTML for a Qobuz artist search URL with optional throttling and caching.

.DESCRIPTION
    Uses Build-QArtistSearchUrl to construct the URL and Get-QSearchHtml to fetch
    the content. This wrapper adds a simple throttling delay and returns the
    HTML content string.

.PARAMETER Query
    The artist search query string.

.PARAMETER Locale
    Locale to use in the search URL.

.PARAMETER ThrottleSeconds
    Seconds to wait before performing the web request (default 1).

.OUTPUTS
    String - HTML content of the search page.
#>
function Get-QArtistSearchHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string] $Query,

        [string] $Locale = 'be-nl',

        [int] $ThrottleSeconds = 1
    )

    process {
        $url = Build-QArtistSearchUrl -Query $Query -Locale $Locale
        if ($ThrottleSeconds -gt 0) { Start-Sleep -Seconds $ThrottleSeconds }
        try {
            $html = Get-QSearchHtml -Url $url -TimeoutSeconds 20
            return $html
        }
        catch {
            Write-Verbose "Failed to fetch artist search HTML for '$Query' ($url): $_"
            throw
        }
    }
}
