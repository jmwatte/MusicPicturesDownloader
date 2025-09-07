<#
.SYNOPSIS
Invoke-QCheckArtistQueryMap - Check and correct Artist and AlbumArtist tags using a query-map approach.

.DESCRIPTION
This public function implements a QueryMap-based workflow that preserves per-file and per-field provenance
while deduplicating remote queries by normalized artist name and locale. It is intended to replace the older
`groupKey` grouping approach with a cleaner per-field, per-file decision model.

.PARAMETER Path
Path to a file or directory of audio files. Accepts pipeline input. Uses literal paths internally.

.PARAMETER Locale
Locale used when querying remote sources and for cache keys. Default is 'us-en'.

.PARAMETER AutoApplyThreshold
Confidence threshold (0-100) above which corrections will be auto-applied. Default 90.

.PARAMETER UseCache
If specified, use cached query results when present. Default: $true.

.PARAMETER WhatIf
Supports standard PowerShell -WhatIf behavior via CmdletBinding.

.EXAMPLE
Invoke-QCheckArtistQueryMap -Path C:\Music -AutoApplyThreshold 95 -WhatIf

.NOTES
- This public function only defines the command and delegates heavy lifting to private helpers in src/private.
- It uses approved verbs and comment-based help. It does not dot-source private scripts; the module should export
  or have them available when the module is imported.
#>
function Invoke-QCheckArtistQueryMap {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)] [string[]] $AudioFilePath,
        [ValidateSet('Manual','Automatic','Interactive')] [string] $Mode = 'Interactive',
        [ValidateNotNullOrEmpty()] [string] $Locale = 'us-en',
        [int] $CacheMinutes = 60,
        [switch] $ForceRefresh,
        [int] $ThrottleSeconds = 1,
        [string] $LogPath = (Join-Path -Path $env:TEMP -ChildPath 'MusicPicturesDownloader\qcheck.log'),
        [switch] $DryRun,
        [ValidateRange(0,100)] [int] $AutoApplyThreshold = 90,
        [bool] $UseCache = $true
    )

    begin {
        # Minimal validation and initialization
        $runId = [guid]::NewGuid().ToString()
        Write-Verbose "Invoke-QCheckArtistQueryMap RUNID=${runId} Mode=${Mode} Locale=${Locale} AutoApplyThreshold=${AutoApplyThreshold}"

        # Detect TagLib# availability. This function assumes TagLib# is used for tag edits
        try { $taglibLoaded = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -match 'TagLib' } } catch { $taglibLoaded = $null }
        $TagLibAvailable = ($null -ne $taglibLoaded -and $taglibLoaded.Count -gt 0)
        if ($Mode -eq 'Automatic' -and -not $TagLibAvailable) {
            throw "Automatic mode requires TagLib# to be installed and loaded. Load TagLib# before running." }

        # Prepare the QueryMap as an ordered hashtable to keep deterministic processing order
        $QueryMap = [ordered]@{}

        # files collector
        $files = @()

        # Create helper local functions where useful (small, internal only)
        function Add-ToQueryMap {
            param(
                [string] $NormalizedKey,
                [string] $OriginalQuery,
                [string] $FilePath,
                [string] $Field
            )
            if (-not $QueryMap.Contains($NormalizedKey)) {
                $QueryMap[$NormalizedKey] = [pscustomobject]@{
                    Key = $NormalizedKey
                    Normalized = $NormalizedKey.Split('|')[0]
                    Locale = $NormalizedKey.Split('|')[1]
                    OriginalQueries = @($OriginalQuery)
                    Files = @()
                    Candidates = @()
                }
            } else {
                $QueryMap[$NormalizedKey].OriginalQueries += $OriginalQuery
            }
            $QueryMap[$NormalizedKey].Files += [pscustomobject]@{ FilePath = $FilePath; Field = $Field; OriginalValue = $OriginalQuery }
        }
    }

    process {
        foreach ($f in $AudioFilePath) { $files += $f }
    }

    end {
        if ($files.Count -eq 0) { return }

        # Build QueryMap from files
        foreach ($file in $files) {
            # Use existing private helper to read track metadata
            $meta = Get-TrackMetadataFromFile -AudioFilePath $file -ErrorAction SilentlyContinue
            if ($null -eq $meta) {
                Write-Verbose ("Skipping {0}: unable to read metadata" -f $file)
                continue
            }
            foreach ($field in @('Artist','AlbumArtist')) {
                $val = $meta.$field
                if ([string]::IsNullOrWhiteSpace($val)) { continue }
                $norm = Convert-TextNormalized -Text $val
                $key = "${norm}|${Locale}"
                Add-ToQueryMap -NormalizedKey $key -OriginalQuery $val -FilePath $file -Field $field
            }
        }
        # Fetch or load candidates for each normalized query
        foreach ($entry in $QueryMap.GetEnumerator()) {
        $key = $entry.Key
        $obj = $entry.Value
        $UseCache=$false
        if ($UseCache) {
            # Use the original (raw) query for cache lookups to remain compatible with Get-CachedArtistResult
            $cacheQuery = if ($obj.OriginalQueries -and $obj.OriginalQueries.Count -gt 0) { $obj.OriginalQueries[0] } else { $obj.Normalized }
            $cached = Get-CachedArtistResult -Query $cacheQuery -Locale $obj.Locale -CacheMinutes $CacheMinutes -ErrorAction SilentlyContinue
            if ($null -ne $cached -and $cached.Count -gt 0) {
                $obj.Candidates = $cached
                Write-Verbose "Cache hit for query '$cacheQuery' (Candidates: $($cached.Count))"
                continue
            }
        }
        # Not cached or not using cache: perform remote search
        #$url = Build-QArtistSearchUrl -Query $obj.Normalized -Locale $obj.Locale
        $html = Get-QArtistSearchHtml -Query $obj.Normalized -Locale $obj.Locale -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($html)) {
            Write-Verbose "No HTML returned for query $($obj.Normalized)"
            $obj.Candidates = @()
            continue
        }
        $cands = ConvertFrom-QTrackSearchResults -Html $html -ErrorAction SilentlyContinue
        if ($null -eq $cands) { $cands = @() }
        $obj.Candidates = $cands
        # Cache non-empty result sets using Set-CachedArtistResult
        if ($UseCache -and $cands.Count -gt 0) {
            $cacheQuery = if ($obj.OriginalQueries -and $obj.OriginalQueries.Count -gt 0) { $obj.OriginalQueries[0] } else { $obj.Normalized }
            Set-CachedArtistResult -Query $cacheQuery -Result $cands -Locale $obj.Locale | Out-Null
        }
    }

    # Score and apply or suggest per-provenance item
        foreach ($entry in $QueryMap.Values) {
        foreach ($prov in $entry.Files) {
            $provFile = $prov.FilePath
            $provField = $prov.Field
            $provOrig = $prov.OriginalValue
            $candidates = $entry.Candidates

            if ($candidates.Count -eq 0) {
                Write-Verbose "No candidates for $($entry.Key) (file $provFile field $provField)"
                continue
            }

                $result = Select-QArtistResults -Candidates $candidates -InputArtist $provOrig -ErrorAction SilentlyContinue
            if ($null -eq $result) {
                Write-Verbose "Selector returned no result for $provOrig"
                continue
            }

            # Decision: per-file per-field
            if ($result[0].MatchScore*100 -ge $AutoApplyThreshold) {
                $candidateName = $result[0].Candidate
                $shouldApply = $PSCmdlet.ShouldProcess("$provFile", "Set $provField to $candidateName")
                        if ($shouldApply) {
                        # Ensure TagLib# available — we do not allow the ffmpeg fallback in this function
                        if (-not $DryRun -and -not $TagLibAvailable) {
                            throw "TagLib# is required to apply tag changes. ffmpeg fallback is disabled for this operation."
                        }
                        # Apply artist/albumartist using TagLib helper (TagLib# must be available)
                        try {
                            if ($provField -eq 'Artist') {
                                $res = Set-FileArtistWithFFmpeg -AudioFilePath $provFile -Artist $candidateName -Replace:$true -ErrorAction Stop
                            } else {
                                $res = Set-FileArtistWithFFmpeg -AudioFilePath $provFile -AlbumArtist $candidateName -Replace:$true -ErrorAction Stop
                            }
                            $applyRecord = [PSCustomObject]@{
                                RunId = $runId
                                File = $provFile
                                Field = $provField
                                OldValue = if ($provField -eq 'Artist') { $res.OldArtist } else { $res.OldAlbumArtist }
                                NewValue = $candidateName
                                Confidence = $result[0].MatchScore*100

                                AppliedAt = (Get-Date).ToString('o')
                            }
                            Write-QCheckLog -Record $applyRecord -LogPath $LogPath -ErrorAction SilentlyContinue
                        }
                        catch {
                            Write-Warning "Failed to apply $provField on $provFile : $_"
                        }
                }
            } else {
                # Suggest only
                    $suggestRecord = [PSCustomObject]@{
                        RunId = $runId
                        File = $provFile
                        Field = $provField
                        OriginalValue = $provOrig
                        Candidate = $result[0].Candidate
                        Confidence = $result[0].MatchScore*100
                        Action = 'Suggested'
                        CreatedAt = (Get-Date).ToString('o')
                    }
                    Write-QCheckLog -Record $suggestRecord -LogPath $LogPath -ErrorAction SilentlyContinue
            }
        }
    }

        Write-Verbose "Invoke-QCheckArtistQueryMap completed. Processed $($QueryMap.Count) normalized queries and $($QueryMap.Values | Measure-Object -Property $files -Sum).Sum provenance items."
    }
}


