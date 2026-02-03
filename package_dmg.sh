#!/bin/bash
set -e

APP_NAME="FineTerm"
APP_BUNDLE="$APP_NAME.app"
DMG_NAME="${APP_NAME}.dmg"
VOL_NAME="$APP_NAME"

# Always clean and rebuild
echo "▶ Cleaning previous builds..."
rm -rf "$APP_BUNDLE"
rm -f "$DMG_NAME"

echo "▶ Running build script..."
./build.sh

echo "▶ Packaging $APP_BUNDLE into $DMG_NAME..."

rm -f "$DMG_NAME"
rm -f "temp.dmg"

# Create a folder for the DMG content
mkdir -p dist
cp -R "$APP_BUNDLE" dist/
ln -s /Applications dist/Applications

# Create DMG from folder
hdiutil create -volname "$VOL_NAME" -srcfolder dist -ov -format UDZO "temp.dmg"

# Cleanup dist safely
mkdir -p /tmp/FineTerm_trash
mv dist "/tmp/FineTerm_trash/dist_$(date +%s)"

# Finalize name
mv "temp.dmg" "$DMG_NAME"

echo "✅  DMG Created: $DMG_NAME"
