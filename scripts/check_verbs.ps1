# temp script to scan function names and verify verbs
$matches = @()
Get-ChildItem -Path . -Recurse -File -Include *.ps1,*.psm1 | ForEach-Object {
    $s = Get-Content -Path $_.FullName -Raw
    [regex]::Matches($s,'^\s*function\s+([A-Za-z0-9_\-]+)','Multiline') | ForEach-Object {
            $found += [PSCustomObject]@{ File=$_.Path; Function=$_.Groups[1].Value }
    }
}
$out = @()
    foreach ($m in $found) {
    $fn = $m.Function
    if ($fn -match '^([^\-\s]+)-') { $verb = $Matches[1] } else { $verb = ($fn -split '-')[0] }
        $approved = $null -ne (Get-Verb -Name $verb -ErrorAction SilentlyContinue)
    $out += [PSCustomObject]@{ File = $m.File; Function = $fn; Verb = $verb; Approved = $approved }
}
$out | Sort-Object Function | Format-Table -AutoSize
$out | ConvertTo-Json -Depth 5 | Set-Content -Path .\function-verb-check.json
Write-Output 'DONE'
