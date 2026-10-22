#!/bin/bash
# Builds swda and SwiftDefaultApps.app as universal binaries (arm64 + x86_64).
# Output: ./swda, ./build/SwiftDefaultApps.app and the release zips in ./dist
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64
BIN=.build/apple/Products/Release

APP=build/SwiftDefaultApps.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SwiftDefaultApps" "$APP/Contents/MacOS/SwiftDefaultApps"
cp "$BIN/swda" "$APP/Contents/Resources/swda"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN/swda" ./swda

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SwiftDefaultApps</string>
    <key>CFBundleDisplayName</key><string>SwiftDefaultApps</string>
    <key>CFBundleIdentifier</key><string>com.swiftdefaultapps.app</string>
    <key>CFBundleExecutable</key><string>SwiftDefaultApps</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>3.0.1</string>
    <key>CFBundleVersion</key><string>4</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run it on this Mac.
codesign --force --sign - "$APP/Contents/Resources/swda"
codesign --force --sign - "$APP"
codesign --force --sign - ./swda

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
rm -rf dist
mkdir -p dist
ditto -c -k --keepParent "$APP" "dist/SwiftDefaultApps-$VERSION.zip"
ditto -c -k ./swda "dist/swda-$VERSION.zip"

echo "Done: $(pwd)/$APP, $(pwd)/swda and the zips in $(pwd)/dist"
