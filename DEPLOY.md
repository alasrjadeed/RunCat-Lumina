# Deploy RunCat Lumina

Author: AL ASAR JADEED
Web: https://alasarjadeed.com
Email: info@alasarjadeed.com

This guide covers packaging and installing the desktop app on Windows, Linux, and macOS.

## Requirements

- Python 3.9 or newer
- Internet access for the first install (pip packages: Pillow, psutil, pystray)
- A desktop session with a system tray / menu bar
  - Windows: notification area
  - Linux: GNOME, KDE, XFCE, Cinnamon, or another tray-capable panel
  - macOS: menu bar (AppKit backend via pystray)

## Quick start from source

Windows:

```bat
scripts\windows\start.bat
```

Linux:

```bash
bash scripts/linux/start.sh
```

macOS:

```bash
bash scripts/macos/start.sh
```

Each start script creates a local `.venv`, installs dependencies, then runs `main.py`.

## Build packages

From the project root:

```bash
bash scripts/package-all.sh
```

Output:

- `dist/windows/RunCatLumina-VERSION-windows.tar.gz`
- `dist/linux/RunCatLumina-VERSION-linux.tar.gz`
- `dist/macos/RunCatLumina-VERSION-macos.tar.gz`

On a Windows machine you can also zip with:

```bat
scripts\windows\package.bat
```

That creates `dist\windows\RunCatLumina-VERSION-windows.zip`.

## Microsoft Store (MSIX)

Build the Microsoft Store package (Windows only):

```bat
scripts\windows\build-msix.bat
```

or, with your Partner Center Publisher string:

```powershell
powershell -ExecutionPolicy Bypass -File packaging\windows\build-msix.ps1 -Publisher "CN=<Partner Center Publisher ID>"
```

Output: `dist\msix\RunCatLumina-VERSION-x64.msix` (+ test `.cer`).
Package logos are generated with `python3 packaging/windows/generate_assets.py`.
CI builds: GitHub Actions workflow `msix`.

Store publishing guide:

- `docs/PARTNER-CENTER.md` — account, Publisher string, name reservation
- `docs/STORE-SUBMISSION.md` — step-by-step submission runbook
- `docs/STORE-LISTING.md` — paste-ready listing copy + asset checklist
- `docs/STORE-PRIVACY-POLICY.md` — privacy policy for the listing URL


## Windows deploy

1. Install Python 3 from https://www.python.org/downloads/
2. Enable **Add python.exe to PATH**
3. Extract `RunCatLumina-VERSION-windows.tar.gz` or `.zip`
4. Double-click `scripts\windows\install.bat`
5. Optional: choose autostart at login
6. Launch from Start Menu: **RunCat Lumina**

Run without installing:

```bat
scripts\windows\start.bat
```

Uninstall:

```bat
scripts\windows\uninstall.bat
```

Install location: `%LOCALAPPDATA%\RunCatLumina`

## Linux deploy

1. Install Python 3 and venv, for example:
   - Debian / Ubuntu: `sudo apt install python3 python3-venv python3-pip`
   - Fedora: `sudo dnf install python3 python3-pip`
   - Arch: `sudo pacman -S python python-pip`
2. Extract `RunCatLumina-VERSION-linux.tar.gz`
3. Run:

```bash
bash scripts/linux/install.sh
```

4. Optional: choose autostart at login
5. Launch with `runcat-lumina` or from the applications menu

Run without installing:

```bash
bash scripts/linux/start.sh
```

Uninstall:

```bash
bash scripts/linux/uninstall.sh
```

Install location: `~/.local/share/runcat-lumina`
Launcher: `~/.local/bin/runcat-lumina`
Desktop file: `~/.local/share/applications/runcat-lumina.desktop`

If the tray icon does not appear on GNOME, install an AppIndicator extension.

## macOS deploy

1. Install Python 3 from https://www.python.org/downloads/macos/ or Homebrew: `brew install python`
2. Extract `RunCatLumina-VERSION-macos.tar.gz`
3. Run:

```bash
bash scripts/macos/install.sh
```

4. Optional: choose autostart at login
5. Open `~/Applications/RunCat Lumina.app`

Run without installing:

```bash
bash scripts/macos/start.sh
```

Or double-click `scripts/macos/RunCatLumina.command`

Uninstall:

```bash
bash scripts/macos/uninstall.sh
```

Install location:
- App: `~/Applications/RunCat Lumina.app`
- Data and venv: `~/Library/Application Support/RunCatLumina`

If macOS blocks the `.command` file, open **System Settings > Privacy & Security** and allow it.

## Color and settings after deploy

Tray menu:

- Cat color
- Dark mode icons
- Higher CPU, faster cat
- Author (website and email)
- Quit

Or edit `config.json` next to `main.py`:

```json
{
    "author": {
        "name": "AL ASAR JADEED",
        "web": "https://alasarjadeed.com",
        "email": "info@alasarjadeed.com"
    },
    "settings": {
        "dark_mode": true,
        "positive_correlation": true,
        "cat_color": "#FF9F43"
    }
}
```

## Script map

| OS | Start | Install | Uninstall | Package |
| --- | --- | --- | --- | --- |
| Windows | `scripts\windows\start.bat` | `scripts\windows\install.bat` | `scripts\windows\uninstall.bat` | `scripts\windows\package.bat` |
| Linux | `scripts/linux/start.sh` | `scripts/linux/install.sh` | `scripts/linux/uninstall.sh` | `scripts/linux/package.sh` |
| macOS | `scripts/macos/start.sh` | `scripts/macos/install.sh` | `scripts/macos/uninstall.sh` | `scripts/macos/package.sh` |

All platforms: `scripts/package-all.sh`
