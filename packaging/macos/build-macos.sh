#!/usr/bin/env bash
# Build the standalone macOS release package:
#   dist/unix/RunCatLumina-<version>-macos-<arch>.dmg
#
# Contains a real .app bundle (menu bar only, LSUIElement) built with
# PyInstaller. Universal2 when the runner's Python supports both arches,
# otherwise the native architecture. No Python needed on the target machine.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
VERSION="$(tr -d '[:space:]' < VERSION)"
OUT="$ROOT/dist/unix"
BUILD="$ROOT/build/macos"
mkdir -p "$OUT"

echo "Building app icon (version $VERSION)..."
rm -rf "$BUILD/RunCatLumina.iconset"
python3 packaging/macos/make_icon.py "$BUILD/RunCatLumina.iconset"
iconutil -c icns "$BUILD/RunCatLumina.iconset" -o packaging/macos/AppIcon.icns
echo "Wrote packaging/macos/AppIcon.icns"

PYEXE="$(python3 -c 'import sys; print(sys.executable)')"
ARCHS="$(lipo -archs "$PYEXE")"
case "$ARCHS" in
  *arm64*x86_64*|*x86_64*arm64*) APP_ARCH="universal2" ;;
  *arm64*)                       APP_ARCH="arm64" ;;
  *)                             APP_ARCH="x86_64" ;;
esac
echo "Python architectures: $ARCHS -> building $APP_ARCH"

python3 -m PyInstaller --noconfirm --clean \
    --distpath "$OUT/app" --workpath "$BUILD/work" \
    --target-arch "$APP_ARCH" \
    packaging/macos/RunCat-Lumina.macos.spec

APP="$OUT/app/RunCat Lumina.app"
BINARY="$APP/Contents/MacOS/RunCat Lumina"

# Advisory smoke test: keep it alive for 8s and see whether it is still
# running. Failure only warns, since CI sessions can be unfriendly to
# menu bar apps.
echo "Smoke-testing the bundle..."
"$BINARY" >/dev/null 2>&1 &
PID=$!
sleep 8
if kill -0 "$PID" 2>/dev/null; then
  echo "Smoke test passed (app stayed up)."
  kill "$PID" 2>/dev/null || true
else
  wait "$PID" || true
  echo "WARNING: app exited during smoke test (advisory only - continuing)"
fi

echo "Creating DMG..."
STAGE="$BUILD/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "RunCat Lumina" -srcfolder "$STAGE" -ov -format UDZO \
    "$OUT/RunCatLumina-$VERSION-macos-$APP_ARCH.dmg"
rm -rf "$STAGE" "$OUT/app"

echo
echo "Created $OUT/RunCatLumina-$VERSION-macos-$APP_ARCH.dmg"
echo "Install: open the DMG and drag RunCat Lumina.app to Applications"
ls -la "$OUT"/*.dmg
