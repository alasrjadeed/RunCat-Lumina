# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for the Microsoft Store (MSIX) build of RunCat Lumina.
#
# Differences from RunCat-Lumina.spec:
#   - console=False  : tray app, no console window may flash on launch
#   - upx=False      : UPX-packed exes frequently trip antivirus heuristics
#                      during Microsoft Store certification


a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=[],
    datas=[('resources', 'resources'), ('config.json', '.'), ('resources/cat', 'resources/cat')],
    hiddenimports=['pystray._xorg', 'PIL._tkinter_finder'],
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
    a.binaries,
    a.datas,
    [],
    name='RunCat-Lumina',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
