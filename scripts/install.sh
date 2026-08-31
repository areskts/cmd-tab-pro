#!/bin/bash

set -euo pipefail

projectDir="$(cd "$(dirname "$0")/.." && pwd)"
buildDir="$projectDir/.build"
stagedApp="$buildDir/Cmd Tab Pro.app"
installedApp="/Applications/Cmd Tab Pro.app"
previousApp="$buildDir/Cmd Tab Pro.previous.app"
legacyApp="/Applications/CmdTabReopener.app"
legacyBackup="$buildDir/CmdTabReopener.legacy.app"
executable="$stagedApp/Contents/MacOS/CmdTabPro"
iconSource="$projectDir/Assets/AppIcon.png"
iconset="$buildDir/AppIcon.iconset"

rm -rf "$stagedApp" "$previousApp" "$legacyBackup" "$iconset"
mkdir -p "$stagedApp/Contents/MacOS" "$stagedApp/Contents/Resources" "$iconset"
cp "$projectDir/Resources/Info.plist" "$stagedApp/Contents/Info.plist"
plutil -lint "$stagedApp/Contents/Info.plist"

xcrun swiftc -swift-version 5 -O -target arm64-apple-macos26.0 -framework AppKit -framework ServiceManagement \
  "$projectDir/Sources/Statistics/SwitchStatistics.swift" \
  "$projectDir/Sources/Dashboard/DashboardWindowController.swift" \
  "$projectDir/Sources/main.swift" \
  -o "$executable"

sips -z 16 16 "$iconSource" --out "$iconset/icon_16x16.png" >/dev/null
sips -z 32 32 "$iconSource" --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$iconSource" --out "$iconset/icon_32x32.png" >/dev/null
sips -z 64 64 "$iconSource" --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$iconSource" --out "$iconset/icon_128x128.png" >/dev/null
sips -z 256 256 "$iconSource" --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$iconSource" --out "$iconset/icon_256x256.png" >/dev/null
sips -z 512 512 "$iconSource" --out "$iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$iconSource" --out "$iconset/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$iconSource" --out "$iconset/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$iconset" -o "$stagedApp/Contents/Resources/AppIcon.icns"

"$executable" --self-test
codesign --force --deep --options runtime --sign - --identifier com.ares.cmd.tab "$stagedApp"
codesign --verify --deep --strict "$stagedApp"

"$executable" --terminate-running
for _ in {1..30}; do
  ! pgrep -f "$installedApp/Contents/MacOS/CmdTabPro" >/dev/null && \
    ! pgrep -f "$legacyApp/Contents/MacOS/CmdTabReopener" >/dev/null && break
  sleep 0.1
done
if pgrep -f "$installedApp/Contents/MacOS/CmdTabPro" >/dev/null || \
   pgrep -f "$legacyApp/Contents/MacOS/CmdTabReopener" >/dev/null; then
  echo "Existing Cmd Tab Pro or CmdTabReopener did not quit; installation stopped." >&2
  exit 1
fi
if [ -e "$installedApp" ]; then
  mv "$installedApp" "$previousApp"
fi
if ! ditto "$stagedApp" "$installedApp"; then
  [ ! -e "$previousApp" ] || mv "$previousApp" "$installedApp"
  exit 1
fi
rm -rf "$previousApp"
if [ -e "$legacyApp" ]; then
  mv "$legacyApp" "$legacyBackup"
fi
open "$installedApp"

echo "Installed and launched: $installedApp"
