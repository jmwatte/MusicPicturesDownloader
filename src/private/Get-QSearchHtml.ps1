
<#
.SYNOPSIS
Fetches HTML for a given URL.
#>
function Get-QSearchHtml {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Url,
		[int]$TimeoutSeconds = 15
	)

	process {
		$headers = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT) PowerShell/1.0' }
		$invokeParams = @{
			Uri         = $Url
			Method      = 'GET'
			Headers     = $headers
			TimeoutSec  = $TimeoutSeconds
			ErrorAction = 'Stop'
		}

		try {
			$response = Invoke-WebRequest @invokeParams
			Write-Output $response.Content
		}
		catch {
			Write-Verbose "Failed to fetch URL: $Url -- $_"
			throw
		}
	}
}
