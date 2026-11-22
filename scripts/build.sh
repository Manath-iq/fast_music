#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/dist/Fast Music.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FastMusic "$APP/Contents/MacOS/FastMusic"
cp packaging/Info.plist "$APP/Contents/Info.plist"
cp assets/reference-cover.png "$APP/Contents/Resources/reference-cover.png"
cp assets/track-glow.png "$APP/Contents/Resources/track-glow.png"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
echo "$APP"
