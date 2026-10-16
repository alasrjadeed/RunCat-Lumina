#!/usr/bin/env python3
"""Render the macOS iconset PNGs from resources/icon.png.

The .icns itself is assembled by macOS' iconutil:

    python3 packaging/macos/make_icon.py
    iconutil -c icns build/macos/iconset -o packaging/macos/AppIcon.icns
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
# Logical sizes; each also gets a pixel-doubled @2x (retina) variant.
LOGICAL_SIZES = [16, 32, 128, 256, 512]


def main() -> None:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build" / "macos" / "iconset"
    out.mkdir(parents=True, exist_ok=True)

    src = Image.open(ROOT / "resources" / "icon.png").convert("RGBA")
    for size in LOGICAL_SIZES:
        src.resize((size, size), Image.LANCZOS).save(out / f"icon_{size}x{size}.png", "PNG")
        src.resize((size * 2, size * 2), Image.LANCZOS).save(out / f"icon_{size}x{size}@2x.png", "PNG")
        print(f"wrote icon_{size}x{size}.png (+ @2x)")


if __name__ == "__main__":
    main()
