# Scan repository for PowerShell functions and check verbs against approved verbs
$found = @()
$files = Get-ChildItem -Path . -Recurse -File -Include *.ps1,*.psm1 -ErrorAction SilentlyContinue
foreach ($file in $files) {
    try {
        $s = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
    } catch { continue }
    if (-not $s) { continue }
    $matches = [regex]::Matches($s, '(?m)^\s*function\s+([A-Za-z0-9_-]+)')
    foreach ($m in $matches) {
        $found += [PSCustomObject]@{ File = $file.FullName; Function = $m.Groups[1].Value }
    }
}
$out = @()
foreach ($item in $found) {
    $fn = $item.Function
    $verb = ($fn -split '-')[0]
    if (-not $verb) { $verb = $fn }
    $approved = $null -ne (Get-Verb -Verb $verb -ErrorAction SilentlyContinue)
    $out += [PSCustomObject]@{ File = $item.File; Function = $fn; Verb = $verb; Approved = $approved }
}
$out | Sort-Object Function | Format-Table -AutoSize
$out | ConvertTo-Json -Depth 5 | Set-Content -Path .\function-verb-check.json -Encoding UTF8
Write-Output 'DONE'
