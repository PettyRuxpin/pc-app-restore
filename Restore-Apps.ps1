#Requires -Version 7.0
<#
.SYNOPSIS
Restores the reviewed app list without running the full developer bootstrap.
.DESCRIPTION
Imports restore-apps.json with WinGet, skipping upgrades of installed apps.
Corporate applications and manual follow-up steps are documented in README.md.
Use -WhatIf to preview without installing or writing logs. Package and source
agreements remain interactive unless -AcceptAgreements is explicitly supplied.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $ManifestPath = (Join-Path $PSScriptRoot 'restore-apps.json'),
    [switch] $AcceptAgreements,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]*$')]
    [string] $NerdFont = 'CodeNewRoman'
)

$ErrorActionPreference = 'Stop'
# Native exit codes are handled explicitly below, including in shells that opt in
# to treating nonzero native exits as PowerShell errors.
$PSNativeCommandUseErrorActionPreference = $false
Import-Module (Join-Path $PSScriptRoot 'Restore-DeveloperTools.psm1')

if (-not $IsWindows) {
    throw 'Restore-Apps.ps1 requires Windows.'
}
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'WinGet is unavailable. Install or update App Installer through your approved corporate channel, then retry.'
}

$manifestFile = Get-Item -LiteralPath $ManifestPath -ErrorAction Stop
if ($manifestFile.PSIsContainer) {
    throw "Manifest must be a JSON file: $ManifestPath"
}
$manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
$packageIds = @()
if (-not $manifest.Sources) {
    throw 'Manifest must contain at least one source.'
}
foreach ($source in $manifest.Sources) {
    if (-not $source.SourceDetails.Name -or -not $source.Packages) {
        throw 'Each manifest source must have a name and at least one package.'
    }
    foreach ($package in $source.Packages) {
        if ([string]::IsNullOrWhiteSpace($package.PackageIdentifier)) {
            throw 'Every manifest package must have a PackageIdentifier.'
        }
        $packageIds += $package.PackageIdentifier
        Write-Host ('{0}: {1}' -f $source.SourceDetails.Name, $package.PackageIdentifier)
    }
}
if (@($packageIds | Select-Object -Unique).Count -ne $packageIds.Count) {
    throw 'Manifest contains duplicate package identifiers.'
}

$arguments = @('import', '--import-file', $manifestFile.FullName, '--no-upgrade')
if ($AcceptAgreements) {
    $arguments += @('--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
}

if ($PSCmdlet.ShouldProcess(
    "$($packageIds.Count) apps from $($manifestFile.FullName); Work IQ, OmnySSH, $NerdFont Nerd Font, five extensions in both VS Code channels",
    'Restore applications and developer tools (no app upgrades)'
)) {
    $logDirectory = Join-Path $env:LOCALAPPDATA 'altered-carbon\restore-logs'
    $null = New-Item -Path $logDirectory -ItemType Directory -Force
    $logPath = Join-Path $logDirectory ("restore-{0}-{1}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid())
    Start-Transcript -Path $logPath | Out-Null
    try {
        Write-Host "Restoring apps. Transcript: $logPath"
        if ($packageIds -contains 'Git.Git') {
            Install-RestoreGitWithChocolatey -AcceptAgreements:$AcceptAgreements
        }
        & winget @arguments
        $importExitCode = $LASTEXITCODE
        if ($importExitCode -ne 0) {
            throw "App restore incomplete: WinGet exited with code $importExitCode. Review $logPath and WinGet logs (winget --logs), resolve the error, and rerun. Earlier packages may already be installed."
        }
        Update-RestoreProcessPath
        Invoke-RestoreDeveloperTools -NerdFont $NerdFont
        Write-Host 'App and developer-tool restore completed. Review the corporate and manual follow-up checklist in README.md.'
        Write-Host 'App data, sign-ins, settings, WSL distributions, and Windows optional features are not restored by this script.'
    } finally {
        Stop-Transcript | Out-Null
    }
}
