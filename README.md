# PC app restore

A standalone PowerShell script and reviewed 32-app WinGet manifest, plus Work IQ,
OmnySSH, a Nerd Font, and five extensions for both VS Code channels, for restoring
applications after a Windows corporate reimage.

## Before reimaging

Save a copy of this repository outside the disk being wiped. Back up files and
application settings separately, including local repositories, Obsidian vaults,
slicer profiles, and WSL data. This repository contains package identifiers,
not backups, licenses, credentials, or account sessions.

## Restore

After corporate imaging and enrollment, open PowerShell 7 as your normal user
in the downloaded repository folder. PowerShell 7, WinGet (App Installer), and
access to the `winget` and `msstore` sources are prerequisites. Obtain missing
prerequisites through your approved corporate software channel. Do not bypass
device-management, execution, Store, or installation policies.

```powershell
# Preview without installing apps or creating logs.
.\Restore-Apps.ps1 -WhatIf

# Install missing apps, with interactive package/source agreement prompts.
.\Restore-Apps.ps1

# Alternatively, explicitly accept package/source agreements for this run.
.\Restore-Apps.ps1 -AcceptAgreements

# Select a different Nerd Font (default: CodeNewRoman).
.\Restore-Apps.ps1 -NerdFont 'JetBrainsMono'
```

Installers can request elevation or interaction. Store authentication and
corporate policy can require manual action even with `-AcceptAgreements`.

The script uses
[`winget import --no-upgrade`](https://learn.microsoft.com/en-us/windows/package-manager/winget/import).
Already-installed apps are not upgraded; versions are not pinned. Unavailable
packages are not silently ignored. A failed import throws with its exit code
and transcript path; resolve the reported error and rerun. Earlier packages may
already be installed.

Keep `Restore-Apps.ps1`, `Restore-DeveloperTools.psm1`, and `restore-apps.json`
together. `-WhatIf` previews the full plan without invoking installers or
creating logs. All restore stages run inside the transcript; any developer-tool
failure stops the run, and previously completed steps can be rerun.

Logs are retained under `%LOCALAPPDATA%\altered-carbon\restore-logs`. Review
them before sharing. The script does not change shell/theme/npm settings,
enable Hyper-V, schedule logon tasks, or initiate a reboot.

## Included apps

| Group | Apps |
|---|---|
| Development | VS Code (Store), VS Code Insiders, Git, GitHub Desktop, GitHub CLI, GitHub Copilot desktop app, Node.js LTS, Python 3.12, PowerShell 7, PowerShell Preview, Azure CLI, Windows Terminal, Windows Terminal Preview, WSL, oh-my-posh, WinSCP, Windows App |
| Everyday tools | Bitwarden, Chrome, Obsidian, NanaZip, PowerToys (Store), Mouse without Borders, Snipaste (Store) |
| Communication | Discord, Signal, WhatsApp (Store) |
| Design / hardware | OpenSCAD, OrcaSlicer (Store), Jabra Direct, Canon Print Assistant (Store), Microsoft Accessory Center (Store) |

Package identities were checked against the configured WinGet/Store catalogs
when the manifest was prepared. Future availability is not known.

Store IDs: VS Code `XP9KHM4BK9FZ7Q`, PowerToys `XP89DCGQ3K6VLD`, Snipaste
`9P1WXPKB68KX`, WhatsApp `9NKSQGP7F2NH`, OrcaSlicer `9MV6GL23XM59`, Canon Print
Assistant `9NDR70LP5W3Q`, Microsoft Accessory Center `9N013P0KR5VX`.

Remove unwanted entries from `restore-apps.json` before running. To use another
WinGet manifest:

```powershell
.\Restore-Apps.ps1 -ManifestPath .\my-apps.json -WhatIf
```

The custom manifest changes the WinGet apps only. Work IQ, OmnySSH, font, and
extension steps still run and require their tools (including Node.js/npm,
oh-my-posh, VS Code, and VS Code Insiders) to be installed.

### Git and Chocolatey

If Git is already on PATH, the Chocolatey step does nothing. Otherwise, when
running elevated **and Chocolatey is already installed**, the script tries
`choco install git` first. It does not bootstrap Chocolatey or change execution
policy. Non-elevated runs, missing Chocolatey, and non-success Chocolatey exit
codes use the Git entry in the WinGet manifest as fallback, with an explicit
message/warning. `-AcceptAgreements` also supplies Chocolatey's `--yes`.
WinGet's `--no-upgrade` remains in effect. Run as the intended Windows user,
not with another account's credentials, so per-user tools and extensions go
into the correct account.

### Additional developer tools

- **Work IQ CLI:** installs the global npm package `@microsoft/workiq` only when
  absent and checks npm's global inventory afterward. Uses your existing npm
  registry; no corporate feed or authentication settings are changed. Sign-in
  and first-run consent remain manual.
- **Nerd Font:** installs `CodeNewRoman` by default through
  `oh-my-posh font install`. Select another family with `-NerdFont`; names
  accept letters, digits, and hyphens. An already registered Nerd Font is
  skipped. This installs the font but does not select it in terminal/editor
  settings or add oh-my-posh initialization to your PowerShell profile.
- **OmnySSH desktop:** downloads the latest Windows x64 NSIS installer from
  `timhartmann7/omnyssh` on GitHub, compares its SHA-256 hash with the asset
  digest returned by GitHub, runs it with `/S`, and checks uninstall
  registration. An existing OmnySSH registration is skipped. Missing digests,
  unexpected download URLs, non-x64 systems, checksum mismatches, installer
  errors, or missing registration stop the run. The temporary installer is
  removed afterward. Hash verification is not a security audit or independent
  publisher verification. Follow corporate approval requirements for this
  third-party app; do not bypass OS warnings.
- **GitHub CLI / Copilot CLI:** the separate `GitHub.Copilot` package was removed
  as requested. This setup installs GitHub CLI but does not separately install
  or verify Copilot CLI. It does not establish that a given GitHub CLI release
  bundles Copilot CLI. The previously included GitHub Copilot desktop app remains.

### VS Code extensions

The script installs these in **both VS Code and VS Code Insiders**, in each
editor's default profile:

| Extension | ID |
|---|---|
| Azure Resources | `ms-azuretools.vscode-azureresourcegroups` |
| Bicep | `ms-azuretools.vscode-bicep` |
| GitHub Copilot Chat | `github.copilot-chat` |
| GitHub Copilot for Azure | `ms-azuretools.vscode-azure-github-copilot` |
| AI Toolkit for Visual Studio Code | `ms-windows-ai-studio.windows-ai-studio` |

Installed extensions are skipped. Copilot Chat is also checked via its located
`package.json`, for editor releases that include it without listing it as a user
extension. Missing editors, extension CLI failures, and unsuccessful presence
checks stop the run rather than silently skipping a channel. Presence checks
do not establish enablement, account sign-in, or licensing. No existing
extensions are removed or forcibly upgraded.

### Troubleshooting developer setup

If a new tool is not found, open a fresh PowerShell 7 window and rerun as the
intended user. The script refreshes its process PATH after WinGet; conventional
VS Code/Insiders and oh-my-posh install paths are also checked. For nonstandard
locations, put each editor's CLI (`code` and `code-insiders`) on PATH.
Review the printed failure and transcript for npm registry/authentication,
extension marketplace, GitHub download, or corporate policy errors. Restore
does not copy tokens or bypass blocked sources.

## Corporate deployment checklist

These productivity apps are deliberately excluded from the automated import.
Check what corporate provisioning restored, then obtain missing apps through
Company Portal or your IT-approved deployment process. The inventory does not
establish licensing, corporate approval, or automatic redeployment.

- [ ] Microsoft 365 Apps, Project, Visio, and OneNote
- [ ] Teams, OneDrive, and Outlook
- [ ] Whiteboard, To Do, Journal, Power Automate, Clipchamp, and Designer

## Manual follow-up

- [ ] EMEETLINK: no matching package was found in the queried WinGet/Store
  catalogs when preparing the manifest. Use an approved vendor/corporate channel.
- [ ] Confirm required corporate management, security, and VPN clients with IT.
  This script does not deploy or reconfigure those agents.
- [ ] Restore backed-up app data/settings and sign in to apps. Restore WSL
  distributions separately and configure required Windows features through an
  approved process; installing the WSL package is not a data restore.
- [ ] Check hardware drivers, printer pairing, additional VS Code extensions,
  other global npm tools, and PowerShell modules separately.

## Tests

On Windows with PowerShell 7 and Pester 5 available:

```powershell
Invoke-Pester -Path .\tests -Output Detailed
```

Tests mock installation commands; they do not install applications.

## References

- [WinGet import (Microsoft Learn)](https://learn.microsoft.com/en-us/windows/package-manager/winget/import)
- [VS Code CLI](https://code.visualstudio.com/docs/configure/command-line)
- [Oh My Posh fonts (external project documentation)](https://ohmyposh.dev/docs/installation/fonts)
- [OmnySSH releases (external project source)](https://github.com/timhartmann7/omnyssh/releases)

## Background

Created while reviewing [altered-carbon](https://github.com/x3nc0n/altered-carbon)
as a reimage approach. This repository contains the separately created app-only
restore files, not that project's bootstrap scripts or Git history.
