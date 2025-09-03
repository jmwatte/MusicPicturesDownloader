function ConvertTo-Genres {
    [CmdletBinding()]
    param(
        [string[]] $Tags,
        [ValidateSet('lower','camel','title')]
        [string]$Case = 'lower',
        [int] $Max = 3,
        [string] $Joiner = ';'
    )

    if (-not $Tags) { return @() }
    $clean = $Tags | ForEach-Object { $_.ToString().Trim().ToLower() } | Where-Object { $_ -ne '' }
    $clean = $clean | Select-Object -Unique | Select-Object -First $Max

    switch ($Case) {
        'lower' { $out = $clean }
        'camel' { $out = $clean | ForEach-Object { ($_ -split ' ') | ForEach-Object { if ($_ -ne '') { $_.Substring(0,1).ToUpper() + $_.Substring(1) } } -join ' ' } }
        'title' { $out = $clean | ForEach-Object { ($_ -split ' ') | ForEach-Object { if ($_ -ne '') { $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower() } } -join ' ' } }
    }

    return ,@($out)
}
