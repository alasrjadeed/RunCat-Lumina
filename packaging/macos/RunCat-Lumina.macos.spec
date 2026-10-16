# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for the macOS app bundle of RunCat Lumina.
#
# LSUIElement keeps the app menu-bar only (no Dock icon), matching the tray
# behaviour on Windows and Linux.
#
# The icon is generated next to this spec before building:
#   python3 packaging/macos/make_icon.py
#   iconutil -c icns build/macos/iconset -o packaging/macos/AppIcon.icns
from pathlib import Path

ROOT = Path(SPECPATH).resolve().parents[1]
VERSION = (ROOT / 'VERSION').read_text().strip()
ICON = str(Path(SPECPATH) / 'AppIcon.icns')

a = Analysis(
    [str(ROOT / 'main.py')],
    pathex=[],
    binaries=[],
    datas=[
        (str(ROOT / 'resources'), 'resources'),
        (str(ROOT / 'config.json'), '.'),
    ],
    hiddenimports=['pystray._darwin'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='RunCat Lumina',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=ICON,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name='RunCat Lumina',
)

app = BUNDLE(
    coll,
    name='RunCat Lumina.app',
    icon=ICON,
    bundle_identifier='com.alasarjadeed.runcatlumina',
    version=VERSION,
    info_plist={
        'CFBundleName': 'RunCat Lumina',
        'CFBundleDisplayName': 'RunCat Lumina',
        'CFBundleShortVersionString': VERSION,
        'CFBundleVersion': VERSION,
        'LSUIElement': True,
        'NSHighResolutionCapable': True,
        'LSMinimumSystemVersion': '10.15',
        'NSHumanReadableCopyright': 'Copyright 2026 AL ASAR JADEED - alasarjadeed.com',
    },
)
