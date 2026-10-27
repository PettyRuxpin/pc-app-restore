#Requires -Version 7.0
# Helpers only; Restore-Apps.ps1 owns consent, transcript, and orchestration.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Update-RestoreProcessPath {
    $paths = @(
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
        [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path
    )
    $env:Path = ($paths | Where-Object { $_ }) -join ';'
}

function Test-RestoreAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        return ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
    } finally {
        $identity.Dispose()
    }
}

function Install-RestoreGitWithChocolatey {
    param([switch] $AcceptAgreements)

    if (Get-Command git -ErrorAction SilentlyContinue) { return }
    if (-not (Test-RestoreAdministrator) -or -not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host 'Git: using WinGet fallback (Chocolatey must already be installed and the shell elevated).'
        return
    }
    $chocoArguments = @('install', 'git', '--no-progress')
    if ($AcceptAgreements) { $chocoArguments += '--yes' }
    & choco @chocoArguments | Out-Host
    $chocoExit = $LASTEXITCODE
    if ($chocoExit -notin @(0, 1641, 3010)) {
        Write-Warning "Chocolatey Git install failed with code $chocoExit; trying WinGet through the manifest."
        return
    }
    if ($chocoExit -ne 0) {
        Write-Warning "Chocolatey Git returned reboot-required code $chocoExit. Reboot manually if needed."
    }
    Update-RestoreProcessPath
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warning 'Git is still not on PATH after Chocolatey; trying WinGet through the manifest.'
    }
}

function Resolve-RestoreCommand {
    param([string] $Name, [string[]] $Candidates = @())

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($candidate in $Candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw "Required command '$Name' was not found. Open a new PowerShell 7 window as the intended user and rerun after checking its installation and PATH."
}

function Install-RestoreWorkIq {
    $npm = Resolve-RestoreCommand -Name 'npm.cmd'
    $inventory = @(& $npm list --global --depth=0 --json)
    if ($LASTEXITCODE -ne 0) { throw "npm global package inventory failed with code $LASTEXITCODE." }
    $packages = ($inventory -join "`n") | ConvertFrom-Json
    if ($packages.dependencies.'@microsoft/workiq') {
        Write-Host 'Work IQ: npm package already installed.'
        return
    }
    & $npm install --global '@microsoft/workiq' | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Work IQ installation failed with code $LASTEXITCODE." }
    $inventory = @(& $npm list --global --depth=0 --json)
    if ($LASTEXITCODE -ne 0) { throw "Work IQ verification failed with code $LASTEXITCODE." }
    $packages = ($inventory -join "`n") | ConvertFrom-Json
    if (-not $packages.dependencies.'@microsoft/workiq') {
        throw 'npm reported success but @microsoft/workiq was not found in the global package inventory.'
    }
}

function Test-RestoreNerdFont {
    param([string] $Name)

    $normalizedName = $Name -replace '[^a-zA-Z0-9]', ''
    foreach ($key in @(
        'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    )) {
        if (-not (Test-Path -LiteralPath $key)) { continue }
        foreach ($property in (Get-ItemProperty -LiteralPath $key).PSObject.Properties) {
            $normalizedEntry = $property.Name -replace '[^a-zA-Z0-9]', ''
            if ($normalizedEntry.StartsWith($normalizedName, [StringComparison]::OrdinalIgnoreCase) -and
                $normalizedEntry -match 'NerdFont') {
                return $true
            }
        }
    }
    return $false
}

function Install-RestoreNerdFont {
    param([string] $Name)

    if (Test-RestoreNerdFont -Name $Name) {
        Write-Host "Nerd Font ${Name}: already installed."
        return
    }
    $posh = Resolve-RestoreCommand -Name 'oh-my-posh' -Candidates @(
        (Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\bin\oh-my-posh.exe')
    )
    & $posh font install $Name | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Nerd Font '$Name' installation failed with code $LASTEXITCODE." }
    if (-not (Test-RestoreNerdFont -Name $Name)) {
        throw "The '$Name' Nerd Font was not found in the font registry after installation. Review the oh-my-posh output."
    }
}

function Get-RestoreEditor {
    param([ValidateSet('code', 'code-insiders')] [string] $Name)

    $folder = if ($Name -eq 'code') { 'Microsoft VS Code' } else { 'Microsoft VS Code Insiders' }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\$folder\bin\$Name.cmd")
        (Join-Path $env:ProgramFiles "$folder\bin\$Name.cmd")
    )
    return Resolve-RestoreCommand -Name $Name -Candidates $candidates
}

function Test-RestoreExtension {
    param([string] $Editor, [string] $Id, [string[]] $Installed)

    if ($Installed -contains $Id) { return $true }
    if ($Id -ne 'github.copilot-chat') { return $false }
    # Included Copilot Chat builds can be absent from the user-extension listing.
    $locations = @(& $Editor --locate-extension $Id)
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not locate bundled $Id in $Editor; attempting normal extension installation."
        return $false
    }
    foreach ($location in $locations) {
        $path = ([string]$location).Trim()
        if (-not [IO.Path]::IsPathRooted($path)) { continue }
        $manifestPath = Join-Path $path 'package.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }
        $extension = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ("$($extension.publisher).$($extension.name)" -ieq $Id -and $extension.version) { return $true }
    }
    return $false
}

function Install-RestoreExtensions {
    $extensions = @(
        'ms-azuretools.vscode-azureresourcegroups',
        'ms-azuretools.vscode-bicep',
        'github.copilot-chat',
        'ms-azuretools.vscode-azure-github-copilot',
        'ms-windows-ai-studio.windows-ai-studio'
    )
    foreach ($channel in @('code', 'code-insiders')) {
        $editor = Get-RestoreEditor -Name $channel
        $installed = @(& $editor --list-extensions)
        if ($LASTEXITCODE -ne 0) { throw "$channel extension inventory failed with code $LASTEXITCODE." }
        foreach ($id in $extensions) {
            if (Test-RestoreExtension -Editor $editor -Id $id -Installed $installed) {
                Write-Host "${channel}: $id already present."
                continue
            }
            & $editor --install-extension $id | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "$channel extension '$id' install failed with code $LASTEXITCODE." }
            $installed = @(& $editor --list-extensions)
            if ($LASTEXITCODE -ne 0) { throw "$channel extension verification failed with code $LASTEXITCODE." }
            if (-not (Test-RestoreExtension -Editor $editor -Id $id -Installed $installed)) {
                throw "$channel extension '$id' was not found after installation."
            }
        }
    }
}

function Test-RestoreOmnySsh {
    $keys = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $keys) {
        if (-not (Test-Path -Path $key)) { continue }
        if (Get-ItemProperty -Path $key | Where-Object DisplayName -EQ 'OmnySSH') { return $true }
    }
    return $false
}

function Install-RestoreOmnySsh {
    if (Test-RestoreOmnySsh) {
        Write-Host 'OmnySSH: already registered as installed.'
        return
    }
    if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [Runtime.InteropServices.Architecture]::X64) {
        throw 'The verified OmnySSH installer supports Windows x64 only. No installer was launched.'
    }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/timhartmann7/omnyssh/releases/latest'
    $assets = @($release.assets | Where-Object name -CEQ 'OmnySSH-x86_64-setup.exe')
    if ($assets.Count -ne 1 -or $assets[0].digest -notmatch '^sha256:[a-fA-F0-9]{64}$') {
        throw 'OmnySSH release must contain one Windows x64 installer with a GitHub SHA-256 digest.'
    }
    $asset = $assets[0]
    if ($asset.browser_download_url -notmatch '^https://github\.com/timhartmann7/omnyssh/releases/download/[^/]+/OmnySSH-x86_64-setup\.exe$') {
        throw 'OmnySSH release returned an unexpected download URL.'
    }
    $downloadPath = Join-Path ([IO.Path]::GetTempPath()) ("omnyssh-{0}.exe" -f [guid]::NewGuid())
    try {
        Write-Host "Downloading OmnySSH $($release.tag_name) from the official GitHub release."
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath
        $actualHash = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash
        if ($actualHash -ine $asset.digest.Substring(7)) { throw 'OmnySSH installer checksum mismatch; installation stopped.' }
        $process = Start-Process -FilePath $downloadPath -ArgumentList '/S' -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "OmnySSH installer failed with code $($process.ExitCode)." }
        if (-not (Test-RestoreOmnySsh)) { throw 'OmnySSH was not registered as installed after the installer exited.' }
    } finally {
        if (Test-Path -LiteralPath $downloadPath) { Remove-Item -LiteralPath $downloadPath -Force }
    }
}

function Invoke-RestoreDeveloperTools {
    param([string] $NerdFont)

    Install-RestoreWorkIq
    Install-RestoreNerdFont -Name $NerdFont
    Install-RestoreOmnySsh
    Install-RestoreExtensions
}
