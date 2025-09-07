<#
.SYNOPSIS
    Download and install TagLibSharp.dll for PowerShell 7 (PowerShell Core / .NET Core compatible build).
.DESCRIPTION
    This script downloads the TagLibSharp NuGet package, extracts the lib/netstandard2.0/TagLibSharp.dll
    and places it into the module's lib\ folder. Intended for development/personal use.
.PARAMETER ModuleRoot
    Optional path to the module root. Defaults to the script parent folder's parent.
#>
param(
    [string]$ModuleRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition))
)

$nuget = 'https://www.nuget.org/api/v2/package/TagLib' # TagLib (TagLibSharp) package id
$work = Join-Path -Path $env:TEMP -ChildPath (New-Guid).Guid
New-Item -Path $work -ItemType Directory -Force | Out-Null
$zip = Join-Path -Path $work -ChildPath 'taglib.nupkg'

Write-Output "Downloading TagLib package to $zip ..."
try {
    Invoke-WebRequest -Uri $nuget -OutFile $zip -UseBasicParsing -ErrorAction Stop
} catch {
    Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
    throw "Failed to download TagLib package: $_"
}

Write-Output "Extracting package..."
try {
    Expand-Archive -LiteralPath $zip -DestinationPath $work -Force
} catch {
    Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
    throw "Failed to extract package: $_"
}

# locate netstandard2.0 build or any dll under lib
$libFolder = Get-ChildItem -Path $work -Directory | Where-Object { $_.Name -eq 'lib' } | Select-Object -First 1
if (-not $libFolder) { Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue; throw 'lib folder not found in package' }

# prefer netstandard2.0 or netstandard2.1
$preferred = @('netstandard2.1','netstandard2.0','net5.0','netcoreapp3.1')
$foundDll = $null
foreach ($p in $preferred) {
    $pPath = Join-Path $libFolder.FullName $p
    if (Test-Path $pPath) {
        $dll = Get-ChildItem -Path $pPath -Filter 'TagLib*.dll' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dll) { $foundDll = $dll; break }
    }
}
if (-not $foundDll) {
    # fallback: any DLL under lib
    $foundDll = Get-ChildItem -Path $libFolder.FullName -Filter 'TagLib*.dll' -File -Recurse | Select-Object -First 1
}
if (-not $foundDll) { Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue; throw 'TagLib dll not found in package' }

$destDir = Join-Path -Path $ModuleRoot -ChildPath 'lib'
New-Item -Path $destDir -ItemType Directory -Force | Out-Null
$dest = Join-Path -Path $destDir -ChildPath $foundDll.Name

Copy-Item -LiteralPath $foundDll.FullName -Destination $dest -Force
Write-Output "Installed TagLib dll to $dest"

# cleanup
Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Output 'Done.'
