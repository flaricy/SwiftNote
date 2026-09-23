#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_ARCH=${ARCH:-$(uname -m)}
case "$BUILD_ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $BUILD_ARCH" >&2; exit 1 ;; esac
xcodebuild -quiet -project SwiftNote.xcodeproj -scheme SwiftNoteMac -configuration Release -derivedDataPath build/Derived ARCHS="$BUILD_ARCH" CODE_SIGNING_ALLOWED=NO build
rm -rf 'build/随记.app'
ditto 'build/Derived/Build/Products/Release/随记.app' 'build/随记.app'
codesign --force --deep --sign - 'build/随记.app'
