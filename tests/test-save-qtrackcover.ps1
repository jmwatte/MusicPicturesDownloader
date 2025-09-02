# Test for Save-QTrackCover

Import-Module ..\MusicPicturesDownloader.psd1 -Force

Describe 'Save-QTrackCover' {
    It 'Should download and save a track cover image from Qobuz' {
        $result = Save-QTrackCover -Track 'Back to Black' -Artist 'Amy Winehouse' -DestinationFolder $env:TEMP -DownloadMode Always -FileNameStyle 'Track-Artist'
        $files = Get-ChildItem -Path $env:TEMP -Filter '*Back*Black*Amy*Winehouse*.*' | Where-Object { $_.Extension -match 'jpg|jpeg|png' }
        $files.Count | Should -BeGreaterThan 0
    }
    It 'Should embed a track cover image into an audio file' {
        $testMp3 = 'C:\Users\resto\Music\Frank_Sinatra_-_In_the_Wee_Small_Hours-1991-OBSERVER\09_Frank_Sinatra_-_What_is_this_Thing_Called_Love..mp3'
        $result = Save-QTrackCover -Track 'Back to Black' -Artist 'Amy Winehouse' -AudioFilePath $testMp3 -Embed -DownloadMode Always
        ($result -eq $true) | Should -BeTrue
        (Get-Item $testMp3).Length | Should -BeGreaterThan 0
    }
}
