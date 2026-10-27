BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot '..\Restore-DeveloperTools.psm1')
}

InModuleScope Restore-DeveloperTools {
    BeforeAll {
        function script:choco {}
        function script:winget {}
        function script:TestNpm {}
        function script:TestPosh {}
        function script:code {}
        function script:code-insiders {}
    }

    Describe 'Chocolatey installation' {
        BeforeEach {
            Mock Write-Host {}
            Mock Update-RestoreProcessPath {}
            $script:chocoAvailable = $false
            Mock Get-Command {
                if ($script:chocoAvailable) { @{ Source = 'choco' } }
            } -ParameterFilter { $Name -eq 'choco' }
            Mock winget {
                $script:chocoAvailable = $true
                $global:LASTEXITCODE = 0
            }
        }

        It 'skips an existing Chocolatey installation' {
            $script:chocoAvailable = $true
            Install-RestoreChocolatey
            Should -Invoke winget -Times 0 -Exactly
        }

        It 'installs the exact package without upgrades or implicit agreement acceptance' {
            Install-RestoreChocolatey
            Should -Invoke winget -Times 1 -Exactly -ParameterFilter {
                $args[0] -eq 'install' -and $args -contains 'Chocolatey.Chocolatey' -and
                $args -contains '--exact' -and $args -contains '--no-upgrade' -and
                $args -contains 'winget' -and $args -notcontains '--accept-package-agreements'
            }
            Should -Invoke Update-RestoreProcessPath -Times 2 -Exactly
        }

        It 'forwards explicit agreement acceptance' {
            Install-RestoreChocolatey -AcceptAgreements
            Should -Invoke winget -Times 1 -Exactly -ParameterFilter {
                $args -contains '--accept-package-agreements' -and
                $args -contains '--accept-source-agreements' -and
                $args -contains '--disable-interactivity'
            }
        }

        It 'reports installer failure' {
            Mock winget { $global:LASTEXITCODE = 1 }
            { Install-RestoreChocolatey } | Should -Throw '*Chocolatey installation failed with code 1*'
        }

        It 'reports missing Chocolatey after a successful installer exit' {
            Mock winget { $global:LASTEXITCODE = 0 }
            { Install-RestoreChocolatey } | Should -Throw '*not available on PATH after installation*'
        }
    }

    Describe 'Chocolatey Git preference' {
        BeforeEach {
            Mock Write-Host {}
            Mock Write-Warning {}
            Mock Update-RestoreProcessPath {}
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'git' }
            Mock Get-Command { @{ Source = 'choco' } } -ParameterFilter { $Name -eq 'choco' }
            Mock Test-RestoreAdministrator { $true }
            Mock choco { $global:LASTEXITCODE = 0 }
        }

        It 'uses available Chocolatey when elevated, without implicitly accepting agreements' {
            Install-RestoreGitWithChocolatey
            Should -Invoke choco -Times 1 -Exactly -ParameterFilter {
                $args[0] -eq 'install' -and $args[1] -eq 'git' -and $args -notcontains '--yes'
            }
        }

        It 'allows agreement acceptance when explicitly supplied' {
            Install-RestoreGitWithChocolatey -AcceptAgreements
            Should -Invoke choco -Times 1 -Exactly -ParameterFilter { $args -contains '--yes' }
        }

        It 'leaves non-elevated installation to WinGet' {
            Mock Test-RestoreAdministrator { $false }
            Install-RestoreGitWithChocolatey
            Should -Invoke choco -Times 0 -Exactly
        }

        It 'leaves installation to WinGet when Chocolatey is absent' {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'choco' }
            Install-RestoreGitWithChocolatey
            Should -Invoke choco -Times 0 -Exactly
        }

        It 'does not reinstall existing Git' {
            Mock Get-Command { @{ Source = 'git' } } -ParameterFilter { $Name -eq 'git' }
            Install-RestoreGitWithChocolatey
            Should -Invoke choco -Times 0 -Exactly
        }

        It 'warns and allows the WinGet fallback on Chocolatey failure' {
            Mock choco { $global:LASTEXITCODE = 1 }
            Install-RestoreGitWithChocolatey
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter {
                $Message -like '*failed with code 1*WinGet*'
            }
        }
    }

    Describe 'Work IQ npm installation' {
        BeforeEach {
            Mock Resolve-RestoreCommand { 'TestNpm' }
            Mock Write-Host {}
            $script:workIqInstalled = $false
            Mock TestNpm {
                $global:LASTEXITCODE = 0
                if ($args[0] -eq 'install') { $script:workIqInstalled = $true }
                elseif ($script:workIqInstalled) { '{"dependencies":{"@microsoft/workiq":{"version":"1.0.1"}}}' }
                else { '{"dependencies":{}}' }
            }
        }

        It 'installs and verifies the global package' {
            Install-RestoreWorkIq
            Should -Invoke TestNpm -Times 1 -Exactly -ParameterFilter {
                $args[0] -eq 'install' -and $args -contains '--global' -and $args -contains '@microsoft/workiq'
            }
        }

        It 'skips an already installed global package' {
            $script:workIqInstalled = $true
            Install-RestoreWorkIq
            Should -Invoke TestNpm -Times 0 -Exactly -ParameterFilter { $args[0] -eq 'install' }
        }

        It 'throws on npm inventory failure' {
            Mock TestNpm { $global:LASTEXITCODE = 1 }
            { Install-RestoreWorkIq } | Should -Throw '*inventory failed*'
        }

        It 'throws on npm install failure' {
            Mock TestNpm { $global:LASTEXITCODE = 1 } -ParameterFilter { $args[0] -eq 'install' }
            { Install-RestoreWorkIq } | Should -Throw '*installation failed*'
        }
    }

    Describe 'Nerd Font selection' {
        BeforeEach {
            Mock Write-Host {}
            Mock Resolve-RestoreCommand { 'TestPosh' }
            Mock Test-RestoreNerdFont { $true }
            Mock TestPosh { $global:LASTEXITCODE = 0 }
        }

        It 'skips an installed font' {
            Install-RestoreNerdFont -Name 'CodeNewRoman'
            Should -Invoke TestPosh -Times 0 -Exactly
        }

        It 'passes the selected family to oh-my-posh and checks the result' {
            $script:fontChecks = 0
            Mock Test-RestoreNerdFont { $script:fontChecks++; return $script:fontChecks -gt 1 }
            Install-RestoreNerdFont -Name 'JetBrainsMono'
            Should -Invoke TestPosh -Times 1 -Exactly -ParameterFilter {
                $args[0] -eq 'font' -and $args[1] -eq 'install' -and $args[2] -eq 'JetBrainsMono'
            }
        }

        It 'does not claim success when a font remains absent' {
            Mock Test-RestoreNerdFont { $false }
            { Install-RestoreNerdFont -Name 'CodeNewRoman' } | Should -Throw '*not found in the font registry*'
        }
    }

    Describe 'Nerd Font registry matching' {
        It 'matches family names with display-name whitespace' {
            Mock Test-Path { $true }
            Mock Get-ItemProperty { [pscustomobject]@{ 'Code New Roman Nerd Font Regular (TrueType)' = 'font.ttf' } }
            Test-RestoreNerdFont -Name 'CodeNewRoman' | Should -BeTrue
        }

        It 'does not treat a non-Nerd version of the family as installed' {
            Mock Test-Path { $true }
            Mock Get-ItemProperty { [pscustomobject]@{ 'Code New Roman Regular (TrueType)' = 'font.ttf' } }
            Test-RestoreNerdFont -Name 'CodeNewRoman' | Should -BeFalse
        }
    }

    Describe 'VS Code extension restoration' {
        BeforeEach {
            Mock Write-Host {}
            Mock Get-RestoreEditor { $Name }
            $script:stableIds = @()
            $script:insidersIds = @()
            Mock code {
                $global:LASTEXITCODE = 0
                switch ($args[0]) {
                    '--list-extensions' { $script:stableIds }
                    '--install-extension' { $script:stableIds += $args[1] }
                }
            }
            Mock code-insiders {
                $global:LASTEXITCODE = 0
                switch ($args[0]) {
                    '--list-extensions' { $script:insidersIds }
                    '--install-extension' { $script:insidersIds += $args[1] }
                }
            }
        }

        It 'installs exactly the requested five extensions in each editor' {
            Install-RestoreExtensions
            foreach ($id in @(
                'ms-azuretools.vscode-azureresourcegroups', 'ms-azuretools.vscode-bicep',
                'github.copilot-chat', 'ms-azuretools.vscode-azure-github-copilot',
                'ms-windows-ai-studio.windows-ai-studio'
            )) {
                $script:stableIds | Should -Contain $id
                $script:insidersIds | Should -Contain $id
            }
            $script:stableIds.Count | Should -Be 5
            $script:insidersIds.Count | Should -Be 5
            Install-RestoreExtensions
            Should -Invoke code -Times 5 -Exactly -ParameterFilter { $args[0] -eq '--install-extension' }
            Should -Invoke code-insiders -Times 5 -Exactly -ParameterFilter { $args[0] -eq '--install-extension' }
        }

        It 'recognizes bundled Copilot Chat by package identity' {
            $extensionFolder = Join-Path $TestDrive 'copilot-chat'
            $null = New-Item -ItemType Directory -Path $extensionFolder
            '{"publisher":"github","name":"copilot-chat","version":"1.0"}' |
                Set-Content -LiteralPath (Join-Path $extensionFolder 'package.json')
            Mock code { $global:LASTEXITCODE = 0; $extensionFolder } -ParameterFilter {
                $args[0] -eq '--locate-extension'
            }
            Test-RestoreExtension -Editor code -Id 'github.copilot-chat' -Installed @() | Should -BeTrue
        }

        It 'surfaces editor inventory failure' {
            Mock code { $global:LASTEXITCODE = 1 }
            { Install-RestoreExtensions } | Should -Throw '*inventory failed*'
        }

        It 'surfaces extension installation failure' {
            Mock code { $global:LASTEXITCODE = 1 } -ParameterFilter { $args[0] -eq '--install-extension' }
            { Install-RestoreExtensions } | Should -Throw '*install failed*'
        }
    }

    Describe 'OmnySSH official release installation' {
        BeforeEach {
            Mock Write-Host {}
            Mock Test-RestoreOmnySsh { $false }
            Mock Invoke-RestMethod {
                @{
                    tag_name = 'v1.1.5'
                    assets = @(@{
                        name = 'OmnySSH-x86_64-setup.exe'
                        digest = 'sha256:' + ('a' * 64)
                        browser_download_url = 'https://github.com/timhartmann7/omnyssh/releases/download/v1.1.5/OmnySSH-x86_64-setup.exe'
                    })
                }
            }
            Mock Invoke-WebRequest {}
            Mock Get-FileHash { @{ Hash = ('a' * 64) } }
            Mock Start-Process { @{ ExitCode = 0 } }
            Mock Test-Path { $false }
        }

        It 'skips installed OmnySSH without downloading' {
            Mock Test-RestoreOmnySsh { $true }
            Install-RestoreOmnySsh
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'rejects a checksum mismatch before launching' {
            Mock Get-FileHash { @{ Hash = ('b' * 64) } }
            { Install-RestoreOmnySsh } | Should -Throw '*checksum mismatch*'
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'downloads, verifies, waits for installation and checks registration' {
            $script:omnyChecks = 0
            Mock Test-RestoreOmnySsh { $script:omnyChecks++; return $script:omnyChecks -gt 1 }
            Install-RestoreOmnySsh
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $ArgumentList -eq '/S' -and $Wait -and $PassThru
            }
        }

        It 'rejects a release without a digest' {
            Mock Invoke-RestMethod { @{ assets = @(@{ name = 'OmnySSH-x86_64-setup.exe' }) } }
            { Install-RestoreOmnySsh } | Should -Throw '*SHA-256 digest*'
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'does not report success when registration is absent' {
            { Install-RestoreOmnySsh } | Should -Throw '*not registered*'
        }

        It 'rejects unexpected asset download URLs' {
            Mock Invoke-RestMethod {
                @{ assets = @(@{
                    name = 'OmnySSH-x86_64-setup.exe'
                    digest = 'sha256:' + ('a' * 64)
                    browser_download_url = 'https://example.com/OmnySSH-x86_64-setup.exe'
                }) }
            }
            { Install-RestoreOmnySsh } | Should -Throw '*unexpected download URL*'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It 'surfaces an installer failure' {
            Mock Start-Process { @{ ExitCode = 1 } }
            { Install-RestoreOmnySsh } | Should -Throw '*installer failed with code 1*'
        }
    }
}
