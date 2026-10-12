#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo
echo "===================================="
echo "   RunCat Lumina  Linux Installer"
echo "===================================="
echo
echo "Folder: $ROOT"
echo "Author: AL ASAR JADEED"
echo "Web:    https://alasarjadeed.com"
echo

if [ ! -f "$ROOT/main.py" ] || [ ! -d "$ROOT/resources/cat" ]; then
  echo "This folder is missing main.py or resources/cat."
  echo "Open the RunCat Lumina project folder, then run:"
  echo "  bash install.sh"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is missing."
  echo "Run: sudo apt install python3 python3-venv python3-pip"
  exit 1
fi

if ! python3 -c "import venv" >/dev/null 2>&1; then
  echo "python3-venv is missing."
  echo "Run: sudo apt install python3-venv"
  exit 1
fi

read -r -p "Install RunCat Lumina now? [Y/n] " OK
if [[ "${OK:-Y}" =~ ^[Nn]$ ]]; then
  echo "Cancelled."
  exit 0
fi

echo
echo "Setting up Python environment..."
if [ ! -x "$ROOT/.venv/bin/python" ]; then
  python3 -m venv "$ROOT/.venv"
fi
"$ROOT/.venv/bin/python" -m pip install -q --upgrade pip
"$ROOT/.venv/bin/python" -m pip install -q -r "$ROOT/requirements.txt"

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
APP_MENU="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
AUTOSTART_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
mkdir -p "$BIN_DIR" "$APP_MENU" "$ICON_DIR"

chmod +x "$ROOT/start-linux.sh" "$ROOT/install.sh"

# Install a real PNG icon so launchers/menus show the cat instead of a blank box.
if [ -f "$ROOT/resources/icon.png" ]; then
  cp "$ROOT/resources/icon.png" "$ICON_DIR/runcat-lumina.png"
fi

ln -sfn "$ROOT/start-linux.sh" "$BIN_DIR/runcat-lumina"

cat > "$APP_MENU/runcat-lumina.desktop" << DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=RunCat Lumina
GenericName=CPU Cat
Comment=Running cat on the Linux taskbar with custom colors
Exec="$ROOT/start-linux.sh"
Path=$ROOT
Icon=$ICON_DIR/runcat-lumina.png
Terminal=false
Categories=Utility;Monitor;
Keywords=cat;cpu;taskbar;tray;runcat;lumina;
StartupNotify=false
StartupWMClass=RunCat_Lumina
DESKTOP
chmod +x "$APP_MENU/runcat-lumina.desktop"

echo
echo "Installed."
echo "Start command: runcat-lumina"
echo "Or: bash \"$ROOT/start-linux.sh\""
echo

read -r -p "Start RunCat Lumina when you log in? [y/N] " AUTOSTART
if [[ "${AUTOSTART:-}" =~ ^[Yy]$ ]]; then
  mkdir -p "$AUTOSTART_DIR"
  cp "$APP_MENU/runcat-lumina.desktop" "$AUTOSTART_DIR/runcat-lumina.desktop"
  echo "Autostart enabled."
fi

echo
read -r -p "Start RunCat Lumina now? [Y/n] " STARTNOW
if [[ ! "${STARTNOW:-Y}" =~ ^[Nn]$ ]]; then
  echo "Starting..."
  exec "$ROOT/.venv/bin/python" "$ROOT/main.py"
fi
