#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)
STAGING=$(mktemp -d /tmp/qingping-air.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Qingping Air.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/QingpingAir" "$APP/Contents/MacOS/QingpingAir"
mkdir -p "$APP/Contents/Resources"
swift scripts/icon.swift .build/Air.iconset
iconutil -c icns .build/Air.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/Qingping-Air.zip
echo "Built: $PWD/dist/Qingping-Air.zip"
