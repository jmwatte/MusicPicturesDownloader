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
