# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for the standalone Linux build of RunCat Lumina.
#
# One-file executable with the cat sprites and icons embedded, so the release
# tarball runs without a Python interpreter on the target machine.
from pathlib import Path

ROOT = Path(SPECPATH).resolve().parents[1]

a = Analysis(
    [str(ROOT / 'main.py')],
    pathex=[],
    binaries=[],
    datas=[
        (str(ROOT / 'resources'), 'resources'),
        (str(ROOT / 'config.json'), '.'),
    ],
    hiddenimports=['pystray._xorg'],
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
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
