#!/bin/bash
set -e

# SyncWave Release Build Script
# Usage: ./Scripts/build-release.sh [version]
# Example: ./Scripts/build-release.sh 1.0.0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

VERSION="${1:-$(cat VERSION)}"
APP_NAME="SyncWave"
BUNDLE_ID="com.syncwave.app"
APP_DIR="$PROJECT_DIR/dist/$APP_NAME.app"
ZIP_FILE="$PROJECT_DIR/dist/$APP_NAME-$VERSION.zip"

echo "=== Building $APP_NAME v$VERSION ==="

# 1. Update VERSION file
echo "$VERSION" > VERSION

# 2. Build release
echo "Building release..."
swift build -c release 2>&1 | tail -3

# 3. Create .app bundle
echo "Creating .app bundle..."
rm -rf "$PROJECT_DIR/dist"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy Python scripts to Resources
cp Scripts/sync_multi.py "$APP_DIR/Contents/Resources/sync_multi.py"
cp Scripts/sync_correlate.py "$APP_DIR/Contents/Resources/sync_correlate.py"

# Copy icon if exists
if [ -f "Resources/icon_1024.png" ]; then
    # Try to create icns from png
    ICONSET="/tmp/$APP_NAME.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    for size in 16 32 64 128 256 512; do
        sips -z $size $size "Resources/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" 2>/dev/null
        sips -z $((size*2)) $((size*2)) "Resources/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" 2>/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    rm -rf "$ICONSET"
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.video</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/Lenouw/SyncWave/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>1AvZry8Dl0dM3/B2UjkbZeziG7erROR+03HNyrP8T+E=</string>
</dict>
</plist>
PLIST

# 4. Copy Sparkle.framework into the app bundle
echo "Copying Sparkle.framework..."
SPARKLE_FW=$(find "$PROJECT_DIR/.build" -path "*/Sparkle.framework" -type d -maxdepth 5 | head -1)
if [ -n "$SPARKLE_FW" ]; then
    mkdir -p "$APP_DIR/Contents/Frameworks"
    cp -R "$SPARKLE_FW" "$APP_DIR/Contents/Frameworks/"
    echo "Sparkle.framework copied"
else
    echo "WARNING: Sparkle.framework not found"
fi

# 5. Fix rpath so the executable finds Sparkle.framework in Contents/Frameworks
echo "Fixing rpath..."
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# 6. Sign
echo "Signing..."
codesign --force --deep --sign - "$APP_DIR"

# 5. Create zip (using ditto to preserve app bundle structure)
echo "Creating zip..."
cd "$PROJECT_DIR/dist"
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$APP_NAME-$VERSION.zip"
cd "$PROJECT_DIR"

echo ""
echo "=== Build complete ==="
echo "App:  $APP_DIR"
echo "Zip:  $ZIP_FILE"
echo "Size: $(du -h "$ZIP_FILE" | cut -f1)"

# 6. Also install to /Applications
echo ""
echo "Installing to /Applications..."
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
echo "Installed to /Applications/$APP_NAME.app"
