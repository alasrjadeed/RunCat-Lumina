#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP_NAME="runcat-lumina"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$APP_NAME"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
APP_MENU="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
AUTOSTART_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"

# Binary packages ship a standalone PyInstaller executable; source packages
# need Python + venv. Detect which one we were extracted from.
BINARY="$ROOT/RunCat-Lumina"

if [ -f "$BINARY" ]; then
  LAUNCH="$APP_DIR/RunCat-Lumina"
else
  LAUNCH="$APP_DIR/scripts/linux/start.sh"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Python 3 is required. Install python3 and python3-venv, then retry."
    exit 1
  fi
fi

echo "Installing RunCat Lumina to $APP_DIR"
mkdir -p "$APP_DIR/resources" "$BIN_DIR" "$APP_MENU"

cp "$ROOT/resources/icon.png" "$APP_DIR/resources/" 2>/dev/null || true

if [ -f "$BINARY" ]; then
  install -m 755 "$BINARY" "$APP_DIR/RunCat-Lumina"
  ln -sfn "$APP_DIR/RunCat-Lumina" "$BIN_DIR/runcat-lumina"
else
  mkdir -p "$APP_DIR/resources/cat" "$APP_DIR/scripts/linux"
  cp "$ROOT/main.py" "$ROOT/config.json" "$ROOT/requirements.txt" "$ROOT/VERSION" "$ROOT/LICENSE" "$APP_DIR/"
  cp "$ROOT/resources/cat/"*.ico "$APP_DIR/resources/cat/"
  cp "$ROOT/scripts/linux/start.sh" "$ROOT/scripts/linux/uninstall.sh" "$APP_DIR/scripts/linux/"
  chmod +x "$APP_DIR/scripts/linux/"*.sh

  if [ ! -x "$APP_DIR/.venv/bin/python" ]; then
    python3 -m venv "$APP_DIR/.venv"
  fi
  "$APP_DIR/.venv/bin/python" -m pip install -q --upgrade pip
  "$APP_DIR/.venv/bin/python" -m pip install -q -r "$APP_DIR/requirements.txt"

  ln -sfn "$APP_DIR/scripts/linux/start.sh" "$BIN_DIR/runcat-lumina"
fi

# Install a PNG icon under the user's hicolor theme so the "Icon=runcat-lumina"
# key in the desktop entry resolves in application menus.
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
mkdir -p "$ICON_DIR"
if [ -f "$APP_DIR/resources/icon.png" ]; then
  cp "$APP_DIR/resources/icon.png" "$ICON_DIR/runcat-lumina.png"
fi

cat > "$APP_MENU/runcat-lumina.desktop" << DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=RunCat Lumina
GenericName=CPU Cat
Comment=Running cat on the Linux taskbar with custom colors
Exec="$LAUNCH"
TryExec="$LAUNCH"
Path=$APP_DIR
Icon=runcat-lumina
Terminal=false
Categories=Utility;Monitor;
Keywords=cat;cpu;taskbar;tray;runcat;lumina;
StartupNotify=false
StartupWMClass=RunCat_Lumina
DESKTOP
chmod +x "$APP_MENU/runcat-lumina.desktop"

read -r -p "Start RunCat Lumina when you log in? [y/N] " AUTOSTART
if [[ "${AUTOSTART:-}" =~ ^[Yy]$ ]]; then
  mkdir -p "$AUTOSTART_DIR"
  cp "$APP_MENU/runcat-lumina.desktop" "$AUTOSTART_DIR/runcat-lumina.desktop"
fi

echo
echo "Installed."
echo "Run: runcat-lumina"
if [ ! -f "$BINARY" ]; then
  echo "Or:  $APP_DIR/scripts/linux/start.sh"
fi
