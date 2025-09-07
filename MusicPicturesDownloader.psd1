@{
    GUID = 'b7d9b3a8-6c4e-4a4b-8d9e-e6f7b8c9d012'
    RootModule = 'MusicPicturesDownloader.psm1'
    Author = 'Auto-generated'
    CompanyName = 'Local'
    Description = 'MusicPicturesDownloader public module that forwards to src/private implementations.'
    ModuleVersion = '0.1.0'
    PowerShellVersion = '7.0'
    RequiredAssemblies = @('lib\\taglib-sharp.dll')
    FunctionsToExport = @('Invoke-QCheckArtist','Save-QArtistsImages','Save-QAlbumCover','Save-QTrackCover','Update-GenresForDirectory','Update-TrackGenresFromLastFm')
}
