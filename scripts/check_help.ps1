<#
.SYNOPSIS
    Scan module source for functions that lack comment-based help.

.DESCRIPTION
    Scans all .ps1 files under the module src folder and reports function names that
    do not have a preceding comment-based help block. Exits with code 0 when
    all functions have help, otherwise exits with code 2.

.EXAMPLE
    & .\scripts\check_help.ps1
#>
[CmdletBinding()]
param(
    [string] $SrcRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..\src')
)

$errors = @()
$files = Get-ChildItem -Path $SrcRoot -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue
foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $text) { continue }

    # Find all functions; for each function check if a comment-based help block directly precedes it
    $funcRegex = '(?m)^\s*function\s+([A-Za-z0-9_-]+)\s*\{'
    $funcMatches = [regex]::Matches($text, $funcRegex)
    foreach ($m in $funcMatches) {
        $funcName = $m.Groups[1].Value
        $funcPos = $m.Index
        # look back up to 1024 chars for a comment block ending right before the function
        $sliceStart = [math]::Max(0, $funcPos - 2048)
        $sliceLen = $funcPos - $sliceStart
        $prefix = $text.Substring($sliceStart, $sliceLen)
        # check if prefix ends with a comment block (#>), i.e. there is a <# ... #> before function
        if ($prefix -notmatch '<#(?s:.*?)#>\s*$') {
            $errors += [PSCustomObject]@{
                File = $file.FullName
                Function = $funcName
            }
        }
    }
}

if ($errors.Count -eq 0) {
    Write-Output "All functions in $SrcRoot have comment-based help blocks."
    exit 0
} else {
    Write-Output "Functions missing comment-based help:"
    $errors | ForEach-Object { Write-Output ("- {0} :: {1}" -f $_.File, $_.Function) }
    exit 2
}
