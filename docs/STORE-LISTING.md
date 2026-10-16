# Microsoft Store listing content — RunCat Lumina

Paste-ready content for the **Store listing** step of a Partner Center
submission. Package/branding assets are generated with:

```bash
python3 packaging/windows/generate_assets.py
```

## Asset checklist

| Asset | Size | File / source |
|---|---|---|
| Product logo | 512×512 PNG (transparent) | `packaging/windows/store-assets/ProductLogo-512.png` |
| Screenshots | ≥ 1 required, 16:9 recommended (1280×720+), max 10 | capture on Windows (see list below) |
| Package logos | generated | `packaging/windows/msix/Assets/` (used inside the .msix) |

### Screenshots to capture (in order of priority)

1. **Settings window** — color presets, live preview, live CPU bar (hero shot)
2. **Taskbar close-up** — the animated cat in the notification area (light icon)
3. **Taskbar close-up** — dark icon variant
4. **Tray tooltip** — showing `RunCat Lumina - CPU 42%`
5. **Custom color** — a custom hex color applied with live preview

Capture at 1280×720 or larger, PNG, no decorative frames needed.

## Short description

(keep within the character limit shown in the form)

```
A running cat in your taskbar. Recolor it, then watch it sprint as your CPU works harder.
```

## Description

```
RunCat Lumina puts an animated cat in your Windows taskbar. It runs — and the harder your CPU works, the faster it goes.

FEATURES
• Original 5-frame running cat sprite in the notification area
• Speed follows live CPU usage: idle = a stroll, busy = a sprint
• Live CPU percentage in the tray tooltip and in Settings
• Color presets plus any custom hex color, with live preview
• Dark and light icon variants
• Right-click tray menu for colors, dark mode, author info, and quit
• Single instance: launching the app again opens Settings
• Lightweight — no account, no ads, no telemetry, no internet connection

SETTINGS
Click the cat in the tray to open RunCat Lumina Settings: pick a preset or type any hex color, switch dark/light icons, toggle "Higher CPU, faster cat", and watch live CPU usage while you work.

PRIVACY
RunCat Lumina runs entirely on your device. It collects no data and makes no network connections.

ALSO AVAILABLE ON
Windows, Linux, and macOS — see the author's website for other platforms.

CREDITS
Cat sprite based on RunCat for Linux by Jas0nG (Apache-2.0).
```

## What's new (version 1.0.0)

```
First Microsoft Store release.
• Animated tray cat whose speed follows CPU usage
• Color presets, custom hex colors, and live preview
• Dark and light icons, live CPU monitor in the tooltip and Settings
```

## Fields

| Field | Value |
|---|---|
| Support contact URL | `https://alasarjadeed.com` |
| Support email | `info@alasarjadeed.com` |
| Privacy policy URL | `https://alasarjadeed.com/privacy` (publish `docs/STORE-PRIVACY-POLICY.md` first) |
| Copyright | `© 2026 AL ASAR JADEED` |
| Website | `https://alasarjadeed.com` |
| Categories | **Utilities & tools**, **Personalization** |
| Price | **Free** |
| Markets | All |

## Age ratings questionnaire

- No user-generated content, no social features, no ads, no in-app purchases
- No violence, no gambling, no mature content, no external browsing links inside the app
- Result: suitable for all ages (Everyone / 3+ equivalent)

## Notes for certification

```
RunCat Lumina is a notification-area (system tray) application. After launch there is
NO main window: look for the animated cat icon in the system tray (notification area)
at the right side of the taskbar — the cat speeds up as CPU usage rises.

How to verify it works:
1. Launch "RunCat Lumina" from the Start menu (no sign-in, no network, no test credentials).
2. Find the animated cat in the notification area (you may need to expand the "^" overflow).
3. Left-click the tray icon -> the Settings window opens (color presets, live preview, CPU bar).
4. Launch the app a second time -> the Settings window opens again (single instance).
5. Uninstall from Settings > Apps -> the package is removed completely.
```
