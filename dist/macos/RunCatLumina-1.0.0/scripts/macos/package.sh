#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
OUT="$ROOT/dist/macos"
STAGE="$OUT/RunCatLumina-$VERSION"

echo "Building macOS package..."

mkdir -p "$STAGE/resources/cat" "$STAGE/scripts/macos"

cp "$ROOT/main.py" "$ROOT/config.json" "$ROOT/requirements.txt" "$ROOT/VERSION" "$ROOT/LICENSE" "$ROOT/README.md" "$ROOT/DEPLOY.md" "$STAGE/"
cp "$ROOT/resources/cat/"*.ico "$STAGE/resources/cat/"
cp "$ROOT/resources/icon.png" "$STAGE/resources/"
cp "$ROOT/scripts/macos/"*.sh "$ROOT/scripts/macos/"*.command "$STAGE/scripts/macos/"
chmod +x "$STAGE/scripts/macos/"*.sh "$STAGE/scripts/macos/"*.command

# Validate the staged package before packaging
echo "Validating macOS package..."
if [[ ! -f "$STAGE/main.py" ]] || [[ ! -f "$STAGE/config.json" ]] || [[ ! -f "$STAGE/requirements.txt" ]]; then
    echo "ERROR: Essential files missing in macOS package staging area"
    exit 1
fi

tar -C "$OUT" -czf "$OUT/RunCatLumina-$VERSION-macos.tar.gz" "RunCatLumina-$VERSION"
echo "Created $OUT/RunCatLumina-$VERSION-macos.tar.gz"
echo "To deploy: extract, then bash scripts/macos/install.sh"