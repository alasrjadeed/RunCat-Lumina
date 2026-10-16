#!/usr/bin/env bash
# Build the standalone Linux release package:
#   dist/unix/RunCatLumina-<version>-linux-x86_64.tar.gz
#
# Contains a single-file PyInstaller binary plus install/uninstall scripts, so
# no Python interpreter is needed on the target machine. Build on the oldest
# glibc you want to support (CI uses ubuntu-22.04).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
VERSION="$(tr -d '[:space:]' < VERSION)"
OUT="$ROOT/dist/unix"
STAGE_NAME="RunCatLumina-$VERSION-linux-x86_64"
STAGE="$OUT/$STAGE_NAME"
mkdir -p "$OUT"

echo "Building standalone Linux binary (version $VERSION)..."
python3 -m PyInstaller --noconfirm --clean \
    --distpath "$OUT/linux-bin" --workpath "$ROOT/build/linux" \
    packaging/linux/RunCat-Lumina.linux.spec

# Smoke test: the binary must survive 10s of running under Xvfb (timeout
# kills it with 124). Anything else means it crashed on startup.
if command -v xvfb-run >/dev/null 2>&1; then
  echo "Smoke-testing the binary under Xvfb..."
  rc=0
  timeout 10 xvfb-run -a "$OUT/linux-bin/RunCat-Lumina" >/dev/null 2>&1 || rc=$?
  pkill -f 'linux-bin/RunCat-Lumina' 2>/dev/null || true
  if [ "$rc" -ne 124 ]; then
    echo "ERROR: binary exited early (code $rc) - not packaging it."
    exit 1
  fi
  echo "Smoke test passed (app stayed up)."
else
  echo "WARNING: xvfb-run not found - skipping the startup smoke test."
fi

echo "Staging package..."
rm -rf "$STAGE"
mkdir -p "$STAGE/resources" "$STAGE/scripts/linux"
cp "$OUT/linux-bin/RunCat-Lumina" "$STAGE/"
cp "$ROOT/resources/icon.png" "$STAGE/resources/"
cp "$ROOT/scripts/linux/install.sh" \
   "$ROOT/scripts/linux/uninstall.sh" \
   "$ROOT/scripts/linux/runcat-lumina.desktop" "$STAGE/scripts/linux/"
cp "$ROOT/LICENSE" "$ROOT/README.md" "$STAGE/"
chmod +x "$STAGE/RunCat-Lumina" "$STAGE/scripts/linux/"*.sh

tar -C "$OUT" -czf "$OUT/$STAGE_NAME.tar.gz" "$STAGE_NAME"
rm -rf "$STAGE" "$OUT/linux-bin"

echo
echo "Created $OUT/$STAGE_NAME.tar.gz"
echo "Install: extract, then bash scripts/linux/install.sh (no Python required)"
ls -la "$OUT"/*.tar.gz
