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
		 # defensive HtmlDecode and string coercion before normalization
        if ($null -ne $Text) {
            Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
            $t = [System.Web.HttpUtility]::HtmlDecode(($Text -as [string]))
        } else {
            $t = ''
        }
        $t = $Text.ToLowerInvariant()
        # If you want to keep the text inside parentheses but discard the '(' and ')', do:
        $t = $t -replace '[\(\)]', ''
        # If you instead want to remove the entire parenthetical (current behavior), use:
        # $t = [System.Text.RegularExpressions.Regex]::Replace($t, '\(.*?\)', '')
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
