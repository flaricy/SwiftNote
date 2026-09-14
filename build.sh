#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP='build/随记.app'
BUILD_CACHE=$(mktemp -d "${TMPDIR:-/tmp}/swiftnote-build.XXXXXX")
trap 'rm -rf "$BUILD_CACHE"' EXIT
BUILD_ARCH=${ARCH:-$(uname -m)}
case "$BUILD_ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $BUILD_ARCH" >&2; exit 1 ;; esac
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -O -target "$BUILD_ARCH-apple-macos14.0" -module-cache-path "$BUILD_CACHE" Source/Model.swift Source/Editor.swift Source/App.swift Source/main.swift -o "$APP/Contents/MacOS/LocalNotes"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.flaricy.SwiftNote</string><key>CFBundleExecutable</key><string>LocalNotes</string><key>CFBundleName</key><string>随记</string><key>CFBundleDisplayName</key><string>随记</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1.0.0</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/><key>NSHumanReadableCopyright</key><string>Copyright © 2026 flaricy. MIT License.</string>
</dict></plist>
PLIST
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
