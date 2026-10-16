# RunCat Lumina

A running cat on your taskbar for Windows, Linux, and macOS.

The cat icon is the original RunCat sprite. Recolor it with presets or any custom color. Speed follows CPU usage.

Inspired by [RunCat for Linux](https://github.com/Jas0nG/RunCat_for_Linux) and [RunCat for Windows](https://github.com/Kyome22/RunCat_for_windows).

## Features

- Original 5-frame cat running animation
- Settings window: color presets, any custom color, live preview
- Speed follows CPU usage
- Live CPU usage in the tray tooltip and the Settings window
- Works on Windows, Linux, and macOS
- Web preview with Windows / Linux / macOS tray layouts

## Settings

Click the cat in the tray to open the **RunCat Lumina Settings** window. There you can:

- pick a preset color or any custom hex color (live preview)
- switch dark/light icons
- toggle "Higher CPU, faster cat"
- watch the live CPU usage bar
- quit the app

The tray tooltip also shows the current CPU usage, e.g. `RunCat Lumina - CPU 42%`.

On Windows and macOS you can also right-click the tray icon for the full menu
(colors, dark mode, author, quit). On Linux/X11 the tray protocol pystray uses
has no menu, so clicking the cat opens the Settings window instead. If the app
is already running, launching it again also opens the Settings window.

## Web preview

Open `index.html` in a browser.

## Desktop app

On Windows:

```bat
scripts\windows\start.bat
```

On Linux:

```bash
bash start-linux.sh
```

or double-click `RunCat Lumina.desktop`.

On macOS:

```bash
bash scripts/macos/start.sh
```

Install for daily use:

- Windows: `scripts\windows\install.bat`
- Linux: `bash scripts/linux/install.sh`
- macOS: `bash scripts/macos/install.sh`

Build zip/tarball packages:

```bash
bash scripts/package-all.sh
```

Microsoft Store (MSIX) package: `scripts\windows\build-msix.bat` on Windows
(see `DEPLOY.md` → *Microsoft Store (MSIX)*, full publishing guide in `docs/`)

Windows installer (no Python needed): download
`RunCatLumina-<version>-Setup.exe` from
https://github.com/alasrjadeed/RunCat-Lumina/releases — built with
`scripts\windows\build-installer.bat`

Linux (no Python needed): `RunCatLumina-<version>-linux-x86_64.tar.gz` from the
same releases page → extract then `bash scripts/linux/install.sh`

macOS (no Python needed): `RunCatLumina-<version>-macos-<arch>.dmg` → open and
drag RunCat Lumina.app to Applications (right-click → Open on first launch, the
app is not notarized yet)

Full packaging and install steps: `DEPLOY.md`

Change color from the tray menu, or set `cat_color` in `config.json`.

## Author

AL ASAR JADEED
https://alasarjadeed.com
info@alasarjadeed.com

## Credits

Cat sprites come from [Jas0nG/RunCat_for_Linux](https://github.com/Jas0nG/RunCat_for_Linux) (Apache-2.0), originally inspired by RunCat for Windows.
