#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h}
APP_NAME="Bindery.app"
APP_DIR="$PROJECT_DIR/$APP_NAME"
BUILD_DIR=$(/usr/bin/mktemp -d /tmp/bindery-build.XXXXXX)
trap '/bin/rm -rf "$BUILD_DIR"' EXIT

SDK_PATH=$(/usr/bin/xcrun --sdk macosx26.5 --show-sdk-path 2>/dev/null || /usr/bin/xcrun --sdk macosx --show-sdk-path)
ARCH=$(/usr/bin/uname -m)
TARGET="${ARCH}-apple-macosx15.0"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"
export SWIFT_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"

STAGED_APP="$BUILD_DIR/$APP_NAME"
CONTENTS_DIR="$STAGED_APP/Contents"
/bin/mkdir -p "$CONTENTS_DIR/MacOS"
SOURCE_FILES=("$PROJECT_DIR"/Sources/*.swift(N))
if (( ${#SOURCE_FILES[@]} == 0 )); then
  print -u2 "Sources 目录中没有 Swift 源文件"
  exit 1
fi

/usr/bin/swiftc -sdk "$SDK_PATH" "${SOURCE_FILES[@]}" \
  -target "$TARGET" \
  -o "$CONTENTS_DIR/MacOS/Bindery" \
  -framework SwiftUI -framework AppKit -parse-as-library -O
/bin/mkdir -p "$CONTENTS_DIR/Resources"
/bin/cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
/bin/cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

FINDER_SOURCE="$PROJECT_DIR/Sources/FinderSync/BinderyFinderSync.swift"
if [[ -f "$FINDER_SOURCE" ]]; then
  APPEX="$CONTENTS_DIR/PlugIns/BinderyFinder.appex"
  /bin/mkdir -p "$APPEX/Contents/MacOS"
  /bin/cp "$PROJECT_DIR/Resources/FinderSync-Info.plist" "$APPEX/Contents/Info.plist"
  /usr/bin/swiftc -sdk "$SDK_PATH" "$FINDER_SOURCE" \
    -target "$TARGET" -module-name BinderyFinder \
    -framework FinderSync -framework AppKit \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$APPEX/Contents/MacOS/BinderyFinder"
  /usr/bin/xattr -cr "$APPEX"
  /usr/bin/codesign --force --sign - --entitlements "$PROJECT_DIR/Resources/FinderSync.entitlements" "$APPEX"
fi

/usr/bin/xattr -cr "$STAGED_APP"
/usr/bin/codesign --force --sign - --requirements '=designated => identifier "com.econsun.bindery"' "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"

/bin/rm -rf "$APP_DIR"
/usr/bin/ditto --noextattr --noqtn "$STAGED_APP" "$APP_DIR"
/usr/bin/xattr -cr "$APP_DIR"
print "$APP_DIR"
