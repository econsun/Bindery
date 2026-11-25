#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h}
BUILD_DIR=$(/usr/bin/mktemp -d /tmp/bindery-tests.XXXXXX)
trap '/bin/rm -rf "$BUILD_DIR"' EXIT
SDK_PATH=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"
export SWIFT_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"

/usr/bin/swiftc -sdk "$SDK_PATH" \
  "$PROJECT_DIR/Sources/Model_Binding.swift" \
  "$PROJECT_DIR/Sources/Model_Store.swift" \
  "$PROJECT_DIR/Sources/Store_Catalog.swift" \
  "$PROJECT_DIR/Sources/BackupFilename.swift" \
  "$PROJECT_DIR/Sources/Store_Binding.swift" \
  "$PROJECT_DIR/Sources/Engine_Backup.swift" \
  "$PROJECT_DIR/Sources/Engine_Digest.swift" \
  "$PROJECT_DIR/Sources/Engine_Scan.swift" \
  "$PROJECT_DIR/Tests/Test_Binding.swift" \
  -o "$BUILD_DIR/BinderyTests" -parse-as-library
"$BUILD_DIR/BinderyTests"
