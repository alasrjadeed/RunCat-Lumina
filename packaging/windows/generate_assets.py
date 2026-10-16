#!/usr/bin/env python3
"""Generate MSIX package logos and the Microsoft Store product logo.

Reads resources/icon.png (256x256 RGBA) and writes:

  packaging/windows/msix/Assets/StoreLogo.png          50x50
  packaging/windows/msix/Assets/Square44x44Logo.png    44x44
  packaging/windows/msix/Assets/Square150x150Logo.png  150x150
  packaging/windows/msix/Assets/Wide310x150Logo.png    310x150
  packaging/windows/store-assets/ProductLogo-512.png   512x512 (Store listing)

Tiles keep ~10% padding around the icon (Microsoft tile guidance); the
Store listing logo is full-bleed. Run from the repo root:

    python3 packaging/windows/generate_assets.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "resources" / "icon.png"
MSIX_ASSETS = ROOT / "packaging" / "windows" / "msix" / "Assets"
STORE_ASSETS = ROOT / "packaging" / "windows" / "store-assets"

PAD = 0.8  # fraction of the tile the icon occupies on tiles


def fit(canvas, pad=True):
    """Scale icon to `canvas` (or ~80% with padding) and center on transparent square."""
    icon = Image.open(SOURCE).convert("RGBA")
    inner = int(canvas * PAD) if pad else canvas
    if icon.size != (inner, inner):
        icon = icon.resize((inner, inner), Image.LANCZOS)
    tile = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    offset = (canvas - icon.width) // 2
    tile.paste(icon, (offset, offset), icon)
    return tile


def wide(w, h, icon_h):
    icon = Image.open(SOURCE).convert("RGBA")
    icon = icon.resize((icon_h, icon_h), Image.LANCZOS)
    tile = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    tile.paste(icon, ((w - icon.width) // 2, (h - icon.height) // 2), icon)
    return tile


def main():
    MSIX_ASSETS.mkdir(parents=True, exist_ok=True)
    STORE_ASSETS.mkdir(parents=True, exist_ok=True)

    outputs = {
        MSIX_ASSETS / "StoreLogo.png": fit(50, pad=False),
        MSIX_ASSETS / "Square44x44Logo.png": fit(44),
        MSIX_ASSETS / "Square150x150Logo.png": fit(150),
        MSIX_ASSETS / "Wide310x150Logo.png": wide(310, 150, int(150 * PAD)),
        STORE_ASSETS / "ProductLogo-512.png": fit(512, pad=False),
    }
    for path, image in outputs.items():
        image.save(path, "PNG")
        print(f"wrote {path.relative_to(ROOT)} {image.size}")


if __name__ == "__main__":
    main()
