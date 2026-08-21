# Labforge

One-click lab environments for college practicals — DevOps, Databases, Unix and more.

## Install

**Ubuntu / Debian / Mint / Pop!_OS / Fedora / Arch**

```bash
curl -fsSL https://raw.githubusercontent.com/vedantterse/labforge-dist/main/install.sh | bash
```

Then open **Labforge** from your applications menu.

**Windows 10 / 11**

Download `Labforge-Setup-x.y.z.exe` from [Releases](../../releases/latest) and run it.

## First launch

Open the **Environment** tab and press the fix buttons. Labforge installs and
configures Docker for you — it asks for your password once, and never again.

## What you need

- 8 GB RAM recommended (4 GB works for one lab at a time)
- 25 GB free disk for the full set of lab images
- Internet the first time you launch each lab

Docker does **not** need to be installed first.

## Updates

The app updates itself. New and updated labs arrive automatically without
reinstalling anything.

## Verifying a download

Every release includes `SHA256SUMS`:

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

## What is in this repository

Installers, update manifests, the signed lab catalog and this installer script.
The application source is maintained privately.

## Problems?

Open an [issue](../../issues) with:

- your operating system and version (`lsb_release -a` on Linux)
- the Labforge version from the Settings tab
- what the Environment tab shows
