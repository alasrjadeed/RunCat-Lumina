#!/usr/bin/env bash
set -euo pipefail
APP_NAME="runcat-lumina"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$APP_NAME"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
APP_MENU="${XDG_DATA_HOME:-$HOME/.local/share}/applications/runcat-lumina.desktop"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/runcat-lumina.desktop"

echo "Uninstalling RunCat Lumina"
rm -f "$BIN_DIR/runcat-lumina" "$APP_MENU" "$AUTOSTART"
if [ -d "$APP_DIR" ]; then
  rm -rf "$APP_DIR"
fi
echo "Removed."
