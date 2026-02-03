#!/bin/bash
set -e

APP_NAME="FineTerm"
APP_BUNDLE="$APP_NAME.app"
ICON_PNG_MASTER="icon_1024.png"
BUNDLE_ID="com.local.FineTerm"

# --- 1. Clean previous builds (Safe cleanup) ---
echo "▶ Cleaning up..."
mkdir -p /tmp/FineTerm_trash
[ -d "$APP_BUNDLE" ] && mv "$APP_BUNDLE" "/tmp/FineTerm_trash/${APP_NAME}_$(date +%s).app"
[ -d "$APP_NAME.iconset" ] && mv "$APP_NAME.iconset" "/tmp/FineTerm_trash/iconset_$(date +%s)"
[ -d "bin" ] && mv "bin" "/tmp/FineTerm_trash/bin_$(date +%s)"
rm -f "$ICON_PNG_MASTER" "$APP_NAME.icns"

# --- 2. Generate Professional Icon ---
echo "▶ Generating Pro Icon from FineTerm.png..."

# Run the Swift icon generator (uses icon_gen.swift in project root)
swift icon_gen.swift

if [ ! -f "$ICON_PNG_MASTER" ]; then
    echo "⚠️  WARNING: Icon generation failed."
else
    # Generate .icns file
    mkdir "$APP_NAME.iconset"
    sips -z 16 16     "$ICON_PNG_MASTER" --out "$APP_NAME.iconset/icon_16x16.png" >/dev/null
    sips -z 32 32     "$ICON_PNG_MASTER" --out "$APP_NAME.iconset/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "$ICON_PNG_MASTER" --out "$APP_NAME.iconset/icon_32x32.png" >/dev/null
    sips -z 64 64     "$ICON_PNG_MASTER" --out "$APP_NAME.iconset/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "$ICON_PNG_MASTER" --out "$APP_NAME.iconset/icon_128x128.png" >/dev/null
    sips -z 256 256   "$ICON_PNG_MASTER" --out "$APP_NAME.iconset/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_PNG_MASTER" --out "$APP_NAME.iconset/icon_256x256.png" >/dev/null
    sips -z 512 512   "$ICON_PNG_MASTER" --out "$APP_NAME.iconset/icon_512x512.png" >/dev/null
    sips -z 512 512   "$ICON_PNG_MASTER" --out "$APP_NAME.iconset/icon_512x512@2x.png" >/dev/null
    sips -z 1024 1024 "$ICON_PNG_MASTER" --out "$APP_NAME.iconset/icon_1024x1024.png" >/dev/null
    
    iconutil -c icns "$APP_NAME.iconset" -o "$APP_NAME.icns"
    
    # Cleanup generated artifacts (keep icon_gen.swift as it's a project file)
    mv "$APP_NAME.iconset" "/tmp/FineTerm_trash/iconset_done_$(date +%s)"
    rm "$ICON_PNG_MASTER"
fi

# --- 3. Create Bundle Structure ---
echo "▶ Creating App Bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

if [ -f "$APP_NAME.icns" ]; then
    mv "$APP_NAME.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# --- 4. Compile Swift ---
echo "▶ Compiling Sources..."
# Targeting macOS 12.0 for SwiftUI features
swiftc ./src/*.swift \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    -target arm64-apple-macosx12.0 \
    -O

# --- 5. Create Info.plist ---
echo "▶ Creating Info.plist..."
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
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
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>This app needs to control Terminal to open tabs and run commands.</string>
</dict>
</plist>
PLIST

# --- 6. Sign Code ---
echo "▶ Signing..."
# Use Apple Development certificate for consistent signing (accessibility permissions persist across rebuilds)
# Find the first available Apple Development identity (use SHA-1 hash to avoid ambiguity)
SIGN_HASH=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | awk '{print $2}')

if [ -n "$SIGN_HASH" ]; then
    SIGN_NAME=$(security find-identity -v -p codesigning 2>/dev/null | grep "$SIGN_HASH" | sed 's/.*"\(.*\)".*/\1/')
    echo "   Using: $SIGN_NAME"
    codesign --force --deep --sign "$SIGN_HASH" "$APP_BUNDLE"
else
    echo "   No Apple Development certificate found, using ad-hoc signing"
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "--------------------------------------------------------"
echo "✅  Build Complete: $APP_BUNDLE"
echo "--------------------------------------------------------"
