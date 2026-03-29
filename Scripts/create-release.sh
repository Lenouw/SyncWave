#!/bin/bash
set -e

# SyncWave GitHub Release Script
# Usage: ./Scripts/create-release.sh [version] [--notes "Release notes"]
# Example: ./Scripts/create-release.sh 1.0.0 --notes "Initial release"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

VERSION="${1:-$(cat VERSION)}"
NOTES="${3:-"SyncWave v$VERSION"}"
APP_NAME="SyncWave"
ZIP_FILE="$PROJECT_DIR/dist/$APP_NAME-$VERSION.zip"

# Build if zip doesn't exist
if [ ! -f "$ZIP_FILE" ]; then
    echo "Building release first..."
    bash "$SCRIPT_DIR/build-release.sh" "$VERSION"
fi

echo "=== Creating GitHub Release v$VERSION ==="

# Check if tag exists
if git tag -l "v$VERSION" | grep -q "v$VERSION"; then
    echo "Tag v$VERSION already exists. Deleting..."
    git tag -d "v$VERSION"
    gh release delete "v$VERSION" --yes 2>/dev/null || true
fi

# Commit VERSION update if changed
if ! git diff --quiet VERSION 2>/dev/null; then
    git add VERSION
    git commit -m "Release v$VERSION"
fi

# Create tag
git tag -a "v$VERSION" -m "Release v$VERSION"

# Push
git push origin main --tags

# Create GitHub release with zip
gh release create "v$VERSION" \
    "$ZIP_FILE" \
    --title "$APP_NAME v$VERSION" \
    --notes "$NOTES"

echo ""
echo "=== Release v$VERSION published ==="
echo "URL: https://github.com/Lenouw/SyncWave/releases/tag/v$VERSION"
