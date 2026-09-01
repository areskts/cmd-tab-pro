#!/bin/bash

set -euo pipefail

projectDir="$(cd "$(dirname "$0")/.." && pwd)"
buildDir="$projectDir/.build"
stagedApp="$buildDir/CmdTabPro.app"
installedApp="/Applications/CmdTabPro.app"
previousApp="$buildDir/CmdTabPro.previous.app"
executable="$stagedApp/Contents/MacOS/CmdTabPro"
iconSwitcher="$stagedApp/Contents/Helpers/CmdTabProIconSwitcher"
iconSource="$projectDir/Assets/AppIcon.png"
iconOptionsSource="$projectDir/Assets/IconOptions/Flat"
iconOptionsDestination="$stagedApp/Contents/Resources/IconOptions"
iconsetRoot="$buildDir/iconsets"

rm -rf "$stagedApp" "$previousApp" "$iconsetRoot"
mkdir -p "$stagedApp/Contents/MacOS" "$stagedApp/Contents/Helpers" "$iconOptionsDestination" "$iconsetRoot"
cp "$projectDir/Resources/Info.plist" "$stagedApp/Contents/Info.plist"
plutil -lint "$stagedApp/Contents/Info.plist"

xcrun swiftc -swift-version 5 -O -target arm64-apple-macos26.0 -framework AppKit -framework ServiceManagement \
  "$projectDir/Sources/Statistics/SwitchStatistics.swift" \
  "$projectDir/Sources/Appearance/AppIconOption.swift" \
  "$projectDir/Sources/Dashboard/DashboardStyle.swift" \
  "$projectDir/Sources/Dashboard/GeneralViewController.swift" \
  "$projectDir/Sources/Dashboard/StatisticsViewController.swift" \
  "$projectDir/Sources/Dashboard/AboutViewController.swift" \
  "$projectDir/Sources/Dashboard/DashboardWindowController.swift" \
  "$projectDir/Sources/main.swift" \
  -o "$executable"

xcrun swiftc -swift-version 5 -O -target arm64-apple-macos26.0 \
  "$projectDir/Sources/IconSwitcher/main.swift" -o "$iconSwitcher"

makeIcns() {
  local source="$1"
  local name="$2"
  local iconset="$iconsetRoot/$name.iconset"
  local output="$iconOptionsDestination/$name.icns"
  mkdir -p "$iconset"
  sips -z 16 16 "$source" --out "$iconset/icon_16x16.png" >/dev/null
  sips -z 32 32 "$source" --out "$iconset/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$source" --out "$iconset/icon_32x32.png" >/dev/null
  sips -z 64 64 "$source" --out "$iconset/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$source" --out "$iconset/icon_128x128.png" >/dev/null
  sips -z 256 256 "$source" --out "$iconset/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$source" --out "$iconset/icon_256x256.png" >/dev/null
  sips -z 512 512 "$source" --out "$iconset/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$source" --out "$iconset/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$source" --out "$iconset/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$iconset" -o "$output"
}

makeIcns "$iconOptionsSource/flat-option-1-window-switch.png" option1
makeIcns "$iconSource" option2
makeIcns "$iconOptionsSource/flat-option-3-window-reopen.png" option3
selectedIcon="${CMD_TAB_PRO_ICON_OPTION:-$(defaults read com.ares.cmd.tab appIconOption 2>/dev/null || echo option2)}"
if [ ! -f "$iconOptionsDestination/$selectedIcon.icns" ]; then selectedIcon="option2"; fi
cp "$iconOptionsDestination/$selectedIcon.icns" "$stagedApp/Contents/Resources/AppIcon.icns"

"$executable" --self-test
codesign --force --deep --options runtime --sign - --identifier com.ares.cmd.tab "$stagedApp"
codesign --verify --deep --strict "$stagedApp"

if [ "${CMD_TAB_PRO_BUILD_ONLY:-0}" = "1" ]; then
  echo "Built app: $stagedApp"
  exit 0
fi

"$executable" --terminate-running
for _ in {1..30}; do
  ! pgrep -f "$installedApp/Contents/MacOS/CmdTabPro" >/dev/null && break
  sleep 0.1
done
if pgrep -f "$installedApp/Contents/MacOS/CmdTabPro" >/dev/null; then
  echo "Existing Cmd Tab Pro did not quit; installation stopped." >&2
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
open "$installedApp"

echo "Installed and launched: $installedApp"
