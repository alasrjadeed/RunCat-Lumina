#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
OUT="$ROOT/dist/linux"
STAGE="$OUT/RunCatLumina-$VERSION"

echo "Building Linux package..."

mkdir -p "$STAGE/resources/cat" "$STAGE/scripts/linux"

cp "$ROOT/main.py" "$ROOT/config.json" "$ROOT/requirements.txt" "$ROOT/VERSION" "$ROOT/LICENSE" "$ROOT/README.md" "$ROOT/DEPLOY.md" "$STAGE/"
cp "$ROOT/resources/cat/"*.ico "$STAGE/resources/cat/"
# The menu/taskbar icon. install.sh copies this to the hicolor icon theme; if it
# is missing the launcher shows a blank icon.
cp "$ROOT/resources/icon.png" "$STAGE/resources/"
cp "$ROOT/scripts/linux/"*.sh "$ROOT/scripts/linux/"*.desktop "$STAGE/scripts/linux/"
chmod +x "$STAGE/scripts/linux/"*.sh

# Validate the staged package before packaging
echo "Validating Linux package..."
if [[ ! -f "$STAGE/main.py" ]] || [[ ! -f "$STAGE/config.json" ]] || [[ ! -f "$STAGE/requirements.txt" ]]; then
    echo "ERROR: Essential files missing in Linux package staging area"
    exit 1
fi

tar -C "$OUT" -czf "$OUT/RunCatLumina-$VERSION-linux.tar.gz" "RunCatLumina-$VERSION"
echo "Created $OUT/RunCatLumina-$VERSION-linux.tar.gz"
echo "To deploy: extract, then bash scripts/linux/install.sh"