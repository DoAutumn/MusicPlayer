#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --show-sdk-path --sdk macosx)"
mkdir -p build

swiftc -parse-as-library -O -swift-version 5 \
  -sdk "$SDK" \
  -target arm64-apple-macosx14.0 \
  -framework SwiftUI \
  -framework AppKit \
  -framework AVFoundation \
  -framework CoreFoundation \
  -o build/MusicPlayer \
  Sources/*.swift

rm -rf "build/曲库.app" "build/Music.app"
APP="build/MusicPlayer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/MusicPlayer "$APP/Contents/MacOS/MusicPlayer"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/TrayIconTemplate.png \
   Resources/TrayIconTemplate@2x.png \
   Resources/TrayIconTemplate@3x.png \
   "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null
echo "$APP"
