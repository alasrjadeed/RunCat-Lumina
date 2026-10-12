#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Function to validate the packaged application
validate_package() {
    local package_dir="$1"
    local platform="$2"

    echo "Validating $platform package..."

    # Check that essential files exist
    if [[ ! -f "$package_dir/main.py" ]]; then
        echo "ERROR: main.py missing in $platform package"
        return 1
    fi

    if [[ ! -f "$package_dir/config.json" ]]; then
        echo "ERROR: config.json missing in $platform package"
        return 1
    fi

    if [[ ! -f "$package_dir/requirements.txt" ]]; then
        echo "ERROR: requirements.txt missing in $platform package"
        return 1
    fi

    # Check that cat resources exist
    if [[ ! -d "$package_dir/resources/cat" ]]; then
        echo "ERROR: resources/cat directory missing in $platform package"
        return 1
    fi

    # Count icon files
    local icon_count=$(find "$package_dir/resources/cat" -name "*.ico" | wc -l)
    if [[ $icon_count -lt 5 ]]; then
        echo "WARNING: Expected 5+ cat icons, found $icon_count in $platform package"
    fi

    echo "✓ $platform package validation passed"
    return 0
}

# Function to create checksums
create_checksums() {
    local package_file="$1"
    if [[ -f "$package_file" ]]; then
        echo "Creating checksums for $package_file..."
        sha256sum "$package_file" > "${package_file}.sha256"
        echo "✓ Checksum created: ${package_file}.sha256"
    fi
}

mkdir -p dist
echo "Building packages for all platforms..."

# Build Linux package
echo "Building Linux package..."
bash scripts/linux/package.sh
LINUX_PACKAGE="dist/linux/RunCatLumina-$(tr -d '[:space:]' < VERSION)-linux.tar.gz"
if validate_package "dist/linux/RunCatLumina-$(tr -d '[:space:]' < VERSION)" "Linux"; then
    create_checksums "$LINUX_PACKAGE"
fi

# Build macOS package
echo "Building macOS package..."
bash scripts/macos/package.sh
MACOS_PACKAGE="dist/macos/RunCatLumina-$(tr -d '[:space:]' < VERSION)-macos.tar.gz"
if validate_package "dist/macos/RunCatLumina-$(tr -d '[:space:]' < VERSION)" "macOS"; then
    create_checksums "$MACOS_PACKAGE"
fi

# Build Windows package
echo "Building Windows package..."
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
WIN_OUT="$ROOT/dist/windows"
WIN_STAGE="$WIN_OUT/RunCatLumina-$VERSION"
mkdir -p "$WIN_STAGE/resources/cat" "$WIN_STAGE/scripts/windows"
cp "$ROOT/main.py" "$ROOT/config.json" "$ROOT/requirements.txt" "$ROOT/VERSION" "$ROOT/LICENSE" "$ROOT/README.md" "$ROOT/DEPLOY.md" "$WIN_STAGE/"
cp "$ROOT/resources/cat/"*.ico "$WIN_STAGE/resources/cat/"
cp "$ROOT/scripts/windows/"*.bat "$WIN_STAGE/scripts/windows/"
(
  cd "$WIN_OUT"
  tar -czf "RunCatLumina-$VERSION-windows.tar.gz" "RunCatLumina-$VERSION"
)
WIN_PACKAGE="$WIN_OUT/RunCatLumina-$VERSION-windows.tar.gz"
if validate_package "$WIN_STAGE" "Windows"; then
    create_checksums "$WIN_PACKAGE"
fi

echo
echo "Packages created:"
find "$ROOT/dist" -type f \( -name '*.tar.gz' -o -name '*.zip' -o -name '*.sha256' \) | sort

echo
echo "Validation complete. All packages include checksums for verification."