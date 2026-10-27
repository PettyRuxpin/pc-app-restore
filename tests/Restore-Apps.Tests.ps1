BeforeAll {
    $restoreScript = Join-Path $PSScriptRoot '..\Restore-Apps.ps1'
    $restoreManifest = Join-Path $PSScriptRoot '..\restore-apps.json'
    # A command stub allows mocking on test hosts without WinGet.
    function winget { param() }
    Import-Module (Join-Path $PSScriptRoot '..\Restore-DeveloperTools.psm1')
}

Describe 'App-only restore manifest' {
    It 'contains 32 distinct apps and excludes corporate productivity packages and separate Copilot CLI' {
        $manifest = Get-Content -LiteralPath $restoreManifest -Raw | ConvertFrom-Json
        $ids = @($manifest.Sources.Packages.PackageIdentifier)
        $ids.Count | Should -Be 32
        @($ids | Select-Object -Unique).Count | Should -Be 32
        $ids | Should -Not -Contain 'GitHub.Copilot'
        $ids | Should -Contain 'GitHub.CopilotApp'
        foreach ($id in @(
            'Microsoft.VisualStudioCode.Insiders', 'Microsoft.WindowsTerminal.Preview',
            'Microsoft.PowerShell.Preview', 'GitHub.GitHubDesktop',
            'JanDeDobbeleer.OhMyPosh', 'WinSCP.WinSCP', 'Microsoft.WindowsApp'
        )) { $ids | Should -Contain $id }
        $ids | Should -Contain '9MV6GL23XM59'
        foreach ($id in @('Microsoft.Office', 'Microsoft.Teams', 'Microsoft.OneDrive', 'Microsoft.Outlook')) {
            $ids | Should -Not -Contain $id
        }
        @($manifest.Sources.Packages | Where-Object Version).Count | Should -Be 0
    }

    It 'parses the entry point without syntax errors' {
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $restoreScript, [ref]$null, [ref]$parseErrors
        )
        $parseErrors.Count | Should -Be 0
    }
}

Describe 'App-only restore execution' {
    BeforeEach {
        Mock Write-Host {}
        Mock New-Item {}
        Mock Start-Transcript {}
        Mock Stop-Transcript {}
        Mock winget { $global:LASTEXITCODE = 0 }
        Mock Import-Module {}
        Mock Install-RestoreGitWithChocolatey {}
        Mock Update-RestoreProcessPath {}
        Mock Invoke-RestoreDeveloperTools {}
    }

    It 'previews without invoking WinGet or creating logs' {
        & $restoreScript -WhatIf
        Should -Invoke winget -Times 0 -Exactly
        Should -Invoke New-Item -Times 0 -Exactly
        Should -Invoke Start-Transcript -Times 0 -Exactly
        Should -Invoke Install-RestoreGitWithChocolatey -Times 0 -Exactly
        Should -Invoke Invoke-RestoreDeveloperTools -Times 0 -Exactly
    }

    It 'imports with no upgrades and no implicit agreement acceptance' {
        & $restoreScript
        Should -Invoke winget -Times 1 -Exactly -ParameterFilter {
            $args[0] -eq 'import' -and $args -contains '--no-upgrade' -and
            $args -contains (Get-Item $restoreManifest).FullName -and
            $args -notcontains '--accept-package-agreements' -and
            $args -notcontains '--accept-source-agreements' -and
            $args -notcontains '--ignore-unavailable'
        }
        Should -Invoke Stop-Transcript -Times 1 -Exactly
        Should -Invoke Install-RestoreGitWithChocolatey -Times 1 -Exactly
        Should -Invoke Invoke-RestoreDeveloperTools -Times 1 -Exactly -ParameterFilter {
            $NerdFont -eq 'CodeNewRoman'
        }
    }

    It 'accepts agreements only when requested' {
        & $restoreScript -AcceptAgreements
        Should -Invoke winget -Times 1 -Exactly -ParameterFilter {
            $args -contains '--accept-package-agreements' -and
            $args -contains '--accept-source-agreements' -and
            $args -contains '--disable-interactivity'
        }
    }

    It 'reports native failures and closes the transcript' {
        Mock winget { $global:LASTEXITCODE = -1978335212 }
        { & $restoreScript } | Should -Throw '*restore incomplete*code -1978335212*'
        Should -Invoke Stop-Transcript -Times 1 -Exactly
        Should -Invoke Invoke-RestoreDeveloperTools -Times 0 -Exactly
    }

    It 'closes the transcript if command invocation throws' {
        Mock winget { throw 'command invocation failed' }
        { & $restoreScript } | Should -Throw '*command invocation failed*'
        Should -Invoke Stop-Transcript -Times 1 -Exactly
    }

    It 'rejects malformed manifests before installing' {
        $invalid = Join-Path $TestDrive 'invalid.json'
        '{"Sources":[{"SourceDetails":{"Name":"winget"},"Packages":[{}]}]}' |
            Set-Content -LiteralPath $invalid
        { & $restoreScript -ManifestPath $invalid } | Should -Throw '*PackageIdentifier*'
        Should -Invoke winget -Times 0 -Exactly
        Should -Invoke Start-Transcript -Times 0 -Exactly
    }

    It 'rejects duplicate packages before installing' {
        $invalid = Join-Path $TestDrive 'duplicates.json'
        '{"Sources":[{"SourceDetails":{"Name":"winget"},"Packages":[{"PackageIdentifier":"Git.Git"},{"PackageIdentifier":"Git.Git"}]}]}' |
            Set-Content -LiteralPath $invalid
        { & $restoreScript -ManifestPath $invalid } | Should -Throw '*duplicate*'
        Should -Invoke winget -Times 0 -Exactly
    }

    It 'explains the prerequisite when WinGet is missing' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget' }
        { & $restoreScript } | Should -Throw '*WinGet is unavailable*'
        Should -Invoke Start-Transcript -Times 0 -Exactly
    }

    It 'passes a selected Nerd Font to developer setup' {
        & $restoreScript -NerdFont 'JetBrainsMono'
        Should -Invoke Invoke-RestoreDeveloperTools -Times 1 -Exactly -ParameterFilter {
            $NerdFont -eq 'JetBrainsMono'
        }
    }

    It 'surfaces developer setup failures and closes the transcript' {
        Mock Invoke-RestoreDeveloperTools { throw 'extension install failed' }
        { & $restoreScript } | Should -Throw '*extension install failed*'
        Should -Invoke Stop-Transcript -Times 1 -Exactly
    }
}
