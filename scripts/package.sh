#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh
mkdir -p dist
BUILD_ARCH=${ARCH:-$(uname -m)}
ARCHIVE="SwiftNote-1.1.2-macOS-${BUILD_ARCH}.zip"
ditto -c -k --sequesterRsrc --keepParent 'build/随记.app' "dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
echo "dist/$ARCHIVE"
