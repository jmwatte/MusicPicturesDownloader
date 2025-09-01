<#
.SYNOPSIS
Initialize local git repo (if needed), create a GitHub repository and push current project.

.DESCRIPTION
Interactive script that checks for git and gh, initializes a local repository if none,
creates a remote repository on GitHub using gh, commits the current files, and pushes to origin.

.PARAMETER RepoName
Name of the GitHub repository to create. Defaults to the current folder name.

.PARAMETER Description
Repository description.

.PARAMETER Visibility
Repository visibility: public or private. Default is public.

.PARAMETER Force
If specified, overwrite remote settings if needed.

.EXAMPLE
.\Publish-To-GitHub.ps1 -RepoName MusicPicturesDownloader -Visibility public

#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$RepoName = (Split-Path -Leaf (Get-Location)),

    [Parameter()]
    [string]$Description = '',

    [Parameter()]
    [ValidateSet('public','private')]
    [string]$Visibility = 'public',

    [Parameter()]
    [switch]$Force
)

try {
    # Check prerequisites
    $git = Get-Command -Name git -ErrorAction SilentlyContinue
    if (-not $git) {
        Write-Output 'Git is not installed or not in PATH. Install Git and try again: https://git-scm.com/downloads'
        return
    }

    $gh = Get-Command -Name gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        Write-Output 'GitHub CLI (gh) is not installed or not in PATH. Install from https://cli.github.com/ and authenticate with "gh auth login".'
        return
    }

    # Confirm gh authentication
    try {
        $whoami = & gh auth status 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Output 'gh is not authenticated. Run: gh auth login'
            return
        }
    } catch {
        Write-Output 'Unable to check gh authentication. Run: gh auth login'
        return
    }

    Write-Output "Target repository name: $RepoName"
    Write-Output "Visibility: $Visibility"

    # Initialize git repo if missing
    if (-not (Test-Path -Path '.git')) {
        Write-Output 'No local git repository found. Initializing...'
        & git init
        if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
    } else {
        Write-Output 'Local git repository detected.'
    }

    # Ensure there is at least one commit
    $hasCommits = $false
    try {
        & git rev-parse --verify HEAD > $null 2>&1
        if ($LASTEXITCODE -eq 0) { $hasCommits = $true }
    } catch { $hasCommits = $false }

    if (-not $hasCommits) {
        Write-Output 'Creating initial commit...'
        & git add --all
        if ($LASTEXITCODE -ne 0) { throw 'git add failed' }
        & git commit -m 'Initial commit' --no-verify
        if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }
    } else {
        Write-Output 'Repository already has commits.'
    }

    # Create remote repository using gh
    $visibilityFlag = if ($Visibility -eq 'public') { '--public' } else { '--private' }

    # Check if remote origin already exists
    $remoteExists = $false
    & git remote get-url origin > $null 2>&1
    if ($LASTEXITCODE -eq 0) { $remoteExists = $true }

    if ($remoteExists -and -not $Force) {
        Write-Output 'Remote "origin" already exists. Use -Force to override or remove the remote manually and retry.'
    } else {
        if ($remoteExists -and $Force) {
            Write-Output 'Removing existing remote "origin"...'
            & git remote remove origin
            if ($LASTEXITCODE -ne 0) { throw 'git remote remove origin failed' }
        }

        Write-Output "Creating repository on GitHub: $RepoName"
        $createArgs = @('repo','create',$RepoName,$visibilityFlag,'--source','.','--remote','origin','--push')
        if ($Description -ne '') { $createArgs += @('--description', $Description) }
        # Run gh repo create ...
        & gh @createArgs
        if ($LASTEXITCODE -ne 0) { throw 'gh repo create failed' }
    }

    # Ensure push (in case remote existed but not yet pushed)
    Write-Output 'Pushing local branch to origin...'
    & git push --set-upstream origin HEAD
    if ($LASTEXITCODE -ne 0) { throw 'git push failed' }

    # Get repository URL
    try {
        $repoUrl = & gh repo view $RepoName --json url --jq .url 2>$null
        if ($repoUrl) {
            Write-Output "Repository created and pushed: $repoUrl"
        } else {
            Write-Output 'Repository created and pushed. Unable to retrieve repository URL via gh.'
        }
    } catch {
        Write-Output 'Repository created and pushed.'
    }

} catch {
    Write-Output "Error: $($_.Exception.Message)"
    return
}
