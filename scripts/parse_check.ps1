$files = @('src\private\Select-QobuzCandidate.ps1','src\public\Save-QTrackCover.ps1')
foreach ($f in $files) {
    Write-Output "Parsing $f"
    $s = Get-Content -Raw -Path $f
    try {
        [scriptblock]::Create($s) | Out-Null
        Write-Output 'OK'
    }
    catch {
        Write-Output "ERROR: $($_.Exception.Message)"
        exit 2
    }
}
Write-Output 'All files parsed successfully.'
