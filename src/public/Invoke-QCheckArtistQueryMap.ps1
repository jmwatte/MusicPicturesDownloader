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
Locale used when querying remote sources and for cache keys. Default is 'en-US'.

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
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Low')]
param(
    [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()] [string] $Path,

    [Parameter()]
    [ValidateNotNullOrEmpty()] [string] $Locale = 'en-US',

    [Parameter()]
    [ValidateRange(0,100)] [int] $AutoApplyThreshold = 90,

    [Parameter()]
    [bool] $UseCache = $true
)

begin {
    # Minimal validation and initialization
    $LiteralPath = [IO.Path]::GetFullPath($Path)
    Write-Verbose "Invoke-QCheckArtistQueryMap starting. Path: $LiteralPath Locale: $Locale AutoApplyThreshold: $AutoApplyThreshold"

    # Prepare the QueryMap as an ordered hashtable to keep deterministic processing order
    $QueryMap = [ordered]@{}

    # Create helper local functions where useful (small, internal only)
    function Add-ToQueryMap {
        param(
            [string] $NormalizedKey,
            [string] $OriginalQuery,
            [string] $FilePath,
            [string] $Field
        )
        if (-not $QueryMap.ContainsKey($NormalizedKey)) {
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
    # Accept file or directory path. If dir, enumerate files.
    $filesToProcess = @()
    if (Test-Path -LiteralPath $LiteralPath -PathType Container) {
        $filesToProcess = Get-ChildItem -LiteralPath $LiteralPath -File -Recurse | Where-Object { $_.Extension -match '\.mp3$|\.flac$|\.m4a$' } | ForEach-Object { $_.FullName }
    } elseif (Test-Path -LiteralPath $LiteralPath -PathType Leaf) {
        $filesToProcess = @($LiteralPath)
    } else {
        throw "Path not found: $LiteralPath"
    }

    foreach ($file in $filesToProcess) {
        # Use existing private helper to read track metadata
        $meta = Get-TrackMetadataFromFile -Path $file -ErrorAction SilentlyContinue
        if ($null -eq $meta) {
            Write-Verbose ("Skipping {0}: unable to read metadata" -f $file)
            continue
        }
        foreach ($field in @('Artist','AlbumArtist')) {
            $val = $meta.$field
            if ([string]::IsNullOrWhiteSpace($val)) { continue }
            $norm = Normalize-Text -InputString $val
            $key = "${norm}|${Locale}"
            Add-ToQueryMap -NormalizedKey $key -OriginalQuery $val -FilePath $file -Field $field
        }
    }
}
end {
    # Fetch or load candidates for each normalized query
    foreach ($entry in $QueryMap.GetEnumerator()) {
        $key = $entry.Key
        $obj = $entry.Value
        if ($UseCache) {
            $cached = Cache-QArtistResults -Key $key -ErrorAction SilentlyContinue
            if ($null -ne $cached -and $cached.Count -gt 0) {
                $obj.Candidates = $cached
                Write-Verbose "Cache hit for $key (Candidates: $($cached.Count))"
                continue
            }
        }
        # Not cached or not using cache: perform remote search
        $html = Get-QSearchHtml -Query $obj.Normalized -Locale $obj.Locale -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($html)) {
            Write-Verbose "No HTML returned for query $($obj.Normalized)"
            $obj.Candidates = @()
            continue
        }
        $cands = Parse-QArtistSearchResults -Html $html -ErrorAction SilentlyContinue
        if ($null -eq $cands) { $cands = @() }
        $obj.Candidates = $cands
        # Cache non-empty result sets
        if ($UseCache -and $cands.Count -gt 0) {
            Cache-QArtistResults -Key $key -Candidates $cands | Out-Null
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

            $result = Select-QArtistResults -Candidates $candidates -OriginalValue $provOrig -ErrorAction SilentlyContinue
            if ($null -eq $result) {
                Write-Verbose "Selector returned no result for $provOrig"
                continue
            }

            # Decision: per-file per-field
            if ($result.Confidence -ge $AutoApplyThreshold) {
                $candidateName = $result.TopCandidate.Name
                $shouldApply = $PSCmdlet.ShouldProcess("$provFile", "Set $provField to $candidateName")
                if ($shouldApply) {
                    Set-TrackImageWithFFmpeg -Path $provFile -Field $provField -Value $candidateName -WhatIf:$false -ErrorAction SilentlyContinue
                    Write-QCheckLog -FilePath $provFile -Field $provField -OriginalValue $provOrig -Candidate $result.TopCandidate -Confidence $result.Confidence -Action 'AutoApplied' -ErrorAction SilentlyContinue
                }
            } else {
                # Suggest only
                Write-QCheckLog -FilePath $provFile -Field $provField -OriginalValue $provOrig -Candidate $result.TopCandidate -Confidence $result.Confidence -Action 'Suggested' -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Verbose "Invoke-QCheckArtistQueryMap completed. Processed $($QueryMap.Count) normalized queries and $($QueryMap.Values | Measure-Object -Property Files -Sum).Sum provenance items."
}
