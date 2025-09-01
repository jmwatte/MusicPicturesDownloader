<#
.SYNOPSIS
Normalizes a string for robust text comparison (case, punctuation, diacritics, whitespace).
#>
function Convert-TextNormalized {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$Text
    )
    process {
        $t = $Text.ToLowerInvariant()
        $t = [System.Text.RegularExpressions.Regex]::Replace($t, "\(.*?\)", '') # remove parentheses
        $t = [System.Text.RegularExpressions.Regex]::Replace($t, "[^\p{L}\p{Nd}\s]", '') # remove punctuation
        $t = $t.Normalize([System.Text.NormalizationForm]::FormD)
        # remove diacritics
        $sb = New-Object System.Text.StringBuilder
        foreach ($ch in $t.ToCharArray()) {
            if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne 'NonSpacingMark') {
                [void]$sb.Append($ch)
            }
        }
        $clean = $sb.ToString().Normalize([System.Text.NormalizationForm]::FormC)
        $clean = [System.Text.RegularExpressions.Regex]::Replace($clean, '\s+', ' ').Trim()
        return $clean
    }
}
