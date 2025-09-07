
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
		
		$headers = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'; 'Accept-Language' = 'en-US,en;q=0.9' }
			
		$invokeParams = @{
			Uri             = $Url
			Method          = 'GET'
			Headers         = $headers
			TimeoutSec      = $TimeoutSeconds
			ErrorAction     = 'Stop'

			UseBasicParsing = $true
		}



		#P$response = Invoke-WebRequest -Uri $searchUrl -Headers $headers -UseBasicParsing -ErrorAction Stop
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
