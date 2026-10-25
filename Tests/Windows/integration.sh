#!/bin/bash
set -euo pipefail
projectDir="$(cd "$(dirname "$0")/../.." && pwd)"
buildDir="$projectDir/.build/window-integration"
fixture="$buildDir/Fixture.app"
mkdir -p "$fixture/Contents/MacOS"
cp "$projectDir/Tests/Acceptance/Info.plist" "$fixture/Contents/Info.plist"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos26.0 -framework AppKit \
  "$projectDir/Tests/Acceptance/Fixture.swift" -o "$fixture/Contents/MacOS/Fixture"
codesign --force --sign - "$fixture"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos26.0 -framework AppKit -framework ScreenCaptureKit \
  "$projectDir/Sources/Windows/WindowPolicy.swift" "$projectDir/Sources/Windows/WindowAccess.swift" \
  "$projectDir/Sources/Windows/EnhancementSettings.swift" "$projectDir/Sources/Dock/"*.swift \
  "$projectDir/Sources/Dashboard/DashboardStyle.swift" \
  "$projectDir/Sources/Statistics/SwitchStatistics.swift" \
  "$projectDir/Sources/Reopen/CmdTabMonitor.swift" "$projectDir/Sources/Reopen/ReopenController.swift" \
  "$projectDir/Tests/Windows/WindowIntegrationTests.swift" -o "$buildDir/WindowIntegrationTests"
if [ "${CMD_TAB_PRO_INSTALLED_RECOVERY:-0}" = "1" ]; then
  "$buildDir/WindowIntegrationTests" "$fixture/Contents/MacOS/Fixture" --installed-recovery "$@"
else
  "$buildDir/WindowIntegrationTests" "$fixture/Contents/MacOS/Fixture" "$@"
fi
