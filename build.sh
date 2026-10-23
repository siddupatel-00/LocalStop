#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product LocalStop
BUILD_PRODUCTS=(".build/release/LocalStop")

APP="LocalStop.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
if [[ ${#BUILD_PRODUCTS[@]} -gt 1 ]]; then
    lipo -create "${BUILD_PRODUCTS[@]}" -output "$APP/Contents/MacOS/LocalStop"
else
    cp "${BUILD_PRODUCTS[0]}" "$APP/Contents/MacOS/LocalStop"
fi
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if ! codesign --force --sign - "$APP" >/dev/null 2>&1; then
    echo "warning: codesign failed" >&2
fi

if [[ "${1:-}" == "--run" ]]; then
    open -n "$APP"
else
    echo "Built $(pwd)/$APP"
fi
