#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/swiftnote-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcodebuild -quiet -project SwiftNote.xcodeproj -scheme Regression -configuration Debug -derivedDataPath build/Derived CODE_SIGNING_ALLOWED=NO build
LOCALNOTES_DATA_DIR="$TEST_DIR/store" build/Derived/Build/Products/Debug/Regression "$TEST_DIR/store"
