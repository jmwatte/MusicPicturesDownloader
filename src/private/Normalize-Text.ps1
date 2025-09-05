<#
.SYNOPSIS
    Normalize a string for robust comparisons (case, punctuation, diacritics, whitespace).

.DESCRIPTION
    Convert-TextNormalized performs a consistent normalization suitable for matching/searching:
    - HTML-decodes common entities,
    - coerces to string and lowercase,
    - removes punctuation (optionally configurable via code),
    - strips diacritics,
    - collapses whitespace.
    It does NOT remove inner parenthetical text when configured to keep parentheses; see implementation comments.

.PARAMETER Text
    Input string to normalize. Accepts pipeline input.

.EXAMPLE
    'Hound Dog (1953) ' | Convert-TextNormalized
    # Returns: hound dog 1953  (diacritics removed, lowercased, whitespace collapsed)

.NOTES
    Designed for internal use in matching/search routines. If you need a different normalization
    policy (remove parentheticals vs keep inner text) adjust the regex used in the function body.

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

        # ensure we normalize on a string (avoid enum/object issues)
        $t = ($t -as [string]).ToLowerInvariant()

        # If you want to preserve inner text of parentheses but remove the parentheses characters, use:
        # $t = $t -replace '[\(\)]', ''
        # If you prefer to remove entire parenthetical content (default previous behaviour), uncomment:
        # $t = [System.Text.RegularExpressions.Regex]::Replace($t, '\(.*?\)', '')

        # remove punctuation except letters/numbers/space
        $t = [System.Text.RegularExpressions.Regex]::Replace($t, "[^\p{L}\p{Nd}\s]", '')

        # normalize form and strip diacritics
        $t = $t.Normalize([System.Text.NormalizationForm]::FormD)
        $sb = New-Object System.Text.StringBuilder
        foreach ($ch in $t.ToCharArray()) {
            if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
                [void]$sb.Append($ch)
            }
        }
        $clean = $sb.ToString().Normalize([System.Text.NormalizationForm]::FormC)
        $clean = [System.Text.RegularExpressions.Regex]::Replace($clean, '\s+', ' ').Trim()
        return $clean
    }
}
