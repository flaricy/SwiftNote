#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/swiftnote-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Source/Model.swift Source/Editor.swift Tests/main.swift -o "$TEST_DIR/tests"
"$TEST_DIR/tests" "$TEST_DIR/store"
