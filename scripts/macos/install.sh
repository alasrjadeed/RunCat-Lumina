#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP_DIR="$HOME/Applications/RunCat Lumina.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
SUPPORT="$HOME/Library/Application Support/RunCatLumina"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required. Install from https://www.python.org/downloads/macos/"
  exit 1
fi

echo "Installing RunCat Lumina.app to $APP_DIR"
mkdir -p "$MACOS" "$RES/cat" "$SUPPORT/resources/cat" "$SUPPORT/scripts/macos"

cp "$ROOT/main.py" "$ROOT/config.json" "$ROOT/requirements.txt" "$ROOT/VERSION" "$ROOT/LICENSE" "$SUPPORT/"
cp "$ROOT/resources/cat/"*.ico "$RES/cat/"
cp "$ROOT/resources/cat/"*.ico "$SUPPORT/resources/cat/"
cp "$ROOT/scripts/macos/start.sh" "$ROOT/scripts/macos/uninstall.sh" "$SUPPORT/scripts/macos/"
chmod +x "$SUPPORT/scripts/macos/"*.sh

if [ ! -x "$SUPPORT/.venv/bin/python" ]; then
  python3 -m venv "$SUPPORT/.venv"
fi
"$SUPPORT/.venv/bin/python" -m pip install -q --upgrade pip
"$SUPPORT/.venv/bin/python" -m pip install -q -r "$SUPPORT/requirements.txt"

cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>RunCat Lumina</string>
  <key>CFBundleDisplayName</key>
  <string>RunCat Lumina</string>
  <key>CFBundleIdentifier</key>
  <string>com.alasarjadeed.runcatlumina</string>
  <key>CFBundleVersion</key>
  <string>$(tr -d '[:space:]' < "$ROOT/VERSION")</string>
  <key>CFBundleShortVersionString</key>
  <string>$(tr -d '[:space:]' < "$ROOT/VERSION")</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>RunCatLumina</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

cat > "$MACOS/RunCatLumina" << 'LAUNCH'
#!/usr/bin/env bash
SUPPORT="$HOME/Library/Application Support/RunCatLumina"
exec "$SUPPORT/scripts/macos/start.sh"
LAUNCH
chmod +x "$MACOS/RunCatLumina"

read -r -p "Start RunCat Lumina when you log in? [y/N] " AUTOSTART
if [[ "${AUTOSTART:-}" =~ ^[Yy]$ ]]; then
  osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$APP_DIR\", hidden:true}" || true
fi

echo
echo "Installed."
echo "Open: open \"$APP_DIR\""
echo "Or:   bash scripts/macos/start.sh"
