#!/bin/bash
set -e

# SyncWave GitHub Release Script with Sparkle appcast update
# Usage: ./Scripts/create-release.sh [version] [--notes "Release notes"]

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

# Sign the zip with Sparkle EdDSA
SIGN_UPDATE=$(find "$PROJECT_DIR/.build" -name "sign_update" -type f 2>/dev/null | head -1)
SIGNATURE_INFO=""
if [ -n "$SIGN_UPDATE" ]; then
    echo "Signing zip with Sparkle EdDSA..."
    SIGNATURE_INFO=$("$SIGN_UPDATE" "$ZIP_FILE" 2>&1)
    echo "Signature: $SIGNATURE_INFO"
fi

# Update appcast.xml
DOWNLOAD_URL="https://github.com/Lenouw/SyncWave/releases/download/v$VERSION/$APP_NAME-$VERSION.zip"
FILE_SIZE=$(stat -f%z "$ZIP_FILE")
PUB_DATE=$(date -R 2>/dev/null || date "+%a, %d %b %Y %H:%M:%S %z")

# Extract sparkle:edSignature and length from sign_update output
ED_SIGNATURE=$(echo "$SIGNATURE_INFO" | grep -o 'sparkle:edSignature="[^"]*"' | head -1)
ED_LENGTH=$(echo "$SIGNATURE_INFO" | grep -o 'length="[^"]*"' | head -1)

cat > "$PROJECT_DIR/appcast.xml" << APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>SyncWave</title>
        <language>fr</language>
        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure url="$DOWNLOAD_URL"
                       type="application/octet-stream"
                       $ED_SIGNATURE
                       $ED_LENGTH />
        </item>
    </channel>
</rss>
APPCAST
echo "appcast.xml updated"

# Check if tag exists
if git tag -l "v$VERSION" | grep -q "v$VERSION"; then
    echo "Tag v$VERSION already exists. Deleting..."
    git tag -d "v$VERSION"
    gh release delete "v$VERSION" --yes 2>/dev/null || true
fi

# Commit VERSION + appcast update
git add VERSION appcast.xml
if ! git diff --cached --quiet 2>/dev/null; then
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
