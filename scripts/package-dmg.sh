#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Build each architecture explicitly so packaging is independent of the host Mac.
bash scripts/build.sh
swift build -c release --scratch-path .build/universal-arm --triple arm64-apple-macosx14.0 --product FastMusic
swift build -c release --scratch-path .build/universal-intel --triple x86_64-apple-macosx14.0 --product FastMusic
ARM_DIR=$(swift build -c release --scratch-path .build/universal-arm --triple arm64-apple-macosx14.0 --show-bin-path)
INTEL_DIR=$(swift build -c release --scratch-path .build/universal-intel --triple x86_64-apple-macosx14.0 --show-bin-path)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' packaging/Info.plist)
APP="$PWD/dist/Fast Music.app"
DMG="$PWD/dist/Fast-Music-${VERSION}-universal.dmg"
STAGE=$(mktemp -d "$PWD/dist/dmg-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

lipo -create "$ARM_DIR/FastMusic" "$INTEL_DIR/FastMusic" -output "$APP/Contents/MacOS/FastMusic"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
ARCHS=$(xcrun lipo -archs "$APP/Contents/MacOS/FastMusic")
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]]

ditto "$APP" "$STAGE/Fast Music.app"
ln -s /Applications "$STAGE/Applications"
cp packaging/INSTALL.txt "$STAGE/Установка.txt"
hdiutil create -volname "Fast Music" -srcfolder "$STAGE" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "$DMG"
