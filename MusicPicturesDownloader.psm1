## Load TagLibSharp (required for in-place tag edits on PowerShell 7)
$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$taglibPath = Join-Path -Path $moduleRoot -ChildPath 'lib\TagLibSharp.dll'
try {
    $already = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -match 'TagLib' }
    if (-not $already) {
        if (Test-Path -LiteralPath $taglibPath) {
            Add-Type -Path $taglibPath -ErrorAction Stop
        }
        else {
            throw "Missing required dependency TagLibSharp. Run `scripts\Install-TagLibSharp.ps1` or place TagLibSharp.dll into the module's lib\\ folder: $taglibPath"
        }
    }
}
catch {
    throw "Failed to load TagLibSharp: $_"
}

Get-ChildItem -Path "$PSScriptRoot/src/Private/*.ps1" | ForEach-Object {
    . $_.FullName
}
# Import Helpers
Get-ChildItem -Path "$PSScriptRoot/Helpers/*.ps1" | ForEach-Object {
    . $_.FullName
}

# Import public functions
Get-ChildItem -Path "$PSScriptRoot/src/Public/*.ps1" | ForEach-Object {
    . $_.FullName
    Export-ModuleMember -Function $_.BaseName
}
#Export-ModuleMember -Function Save-QArtistImage, Save-QArtistsImages
