# PC app restore

A standalone PowerShell script and reviewed 26-app WinGet manifest for restoring
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
```

Installers can request elevation or interaction. Store authentication and
corporate policy can require manual action even with `-AcceptAgreements`.

The script uses
[`winget import --no-upgrade`](https://learn.microsoft.com/en-us/windows/package-manager/winget/import).
Already-installed apps are not upgraded; versions are not pinned. Unavailable
packages are not silently ignored. A failed import throws with its exit code
and transcript path; resolve the reported error and rerun. Earlier packages may
already be installed.

Logs are retained under `%LOCALAPPDATA%\altered-carbon\restore-logs`. Review
them before sharing. The script does not change shell/theme/npm settings,
enable Hyper-V, schedule logon tasks, or initiate a reboot.

## Included apps

| Group | Apps |
|---|---|
| Development | VS Code (Store), Git, GitHub CLI, Copilot CLI, GitHub Copilot desktop app, Node.js LTS, Python 3.12, PowerShell 7, Azure CLI, Windows Terminal, WSL |
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
- [ ] Check hardware drivers, printer pairing, VS Code extensions, global npm
  tools, and PowerShell modules separately.

## Tests

On Windows with PowerShell 7 and Pester 5 available:

```powershell
Invoke-Pester -Path .\tests\Restore-Apps.Tests.ps1 -Output Detailed
```

Tests mock installation commands; they do not install applications.

## Background

Created while reviewing [altered-carbon](https://github.com/x3nc0n/altered-carbon)
as a reimage approach. This repository contains the separately created app-only
restore files, not that project's bootstrap scripts or Git history.
