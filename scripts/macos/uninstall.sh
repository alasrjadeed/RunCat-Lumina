#!/usr/bin/env bash
set -euo pipefail
APP_DIR="$HOME/Applications/RunCat Lumina.app"
SUPPORT="$HOME/Library/Application Support/RunCatLumina"

echo "Uninstalling RunCat Lumina"
osascript -e 'tell application "System Events" to delete login item "RunCat Lumina"' 2>/dev/null || true
rm -rf "$APP_DIR" "$SUPPORT"
echo "Removed."
