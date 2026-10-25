#!/bin/bash
set -euo pipefail
projectDir="$(cd "$(dirname "$0")/../.." && pwd)"
output="$projectDir/.build/ui-regression"
mkdir -p "$output"
previewApp="$output/DashboardPreview.app"
mkdir -p "$previewApp/Contents/MacOS" "$previewApp/Contents/Resources"
cp "$projectDir/Resources/Info.plist" "$previewApp/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.ares.cmd.tab.ui.preview "$previewApp/Contents/Info.plist"
plutil -replace CFBundleExecutable -string DashboardPreview "$previewApp/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string 'Cmd Tab Pro 设置预览' "$previewApp/Contents/Info.plist"
if [ -d "$projectDir/.build/CmdTabPro.app/Contents/Resources/IconOptions" ]; then
  cp -R "$projectDir/.build/CmdTabPro.app/Contents/Resources/IconOptions" "$previewApp/Contents/Resources/"
  cp "$projectDir/.build/CmdTabPro.app/Contents/Resources/AppIcon.icns" "$previewApp/Contents/Resources/"
fi
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos26.0 -framework AppKit -framework ServiceManagement -framework ScreenCaptureKit \
  "$projectDir/Sources/Statistics/SwitchStatistics.swift" "$projectDir/Sources/Appearance/AppIconOption.swift" \
  "$projectDir/Sources/Reopen/CmdTabMonitor.swift" "$projectDir/Sources/Windows/EnhancementSettings.swift" \
  "$projectDir/Sources/Windows/WindowPolicy.swift" "$projectDir/Sources/Windows/WindowAccess.swift" \
  "$projectDir/Sources/Dock/DockPolicy.swift" "$projectDir/Sources/Dock/DockPreviewPanel.swift" \
  "$projectDir/Sources/Dock/WindowPreviewCapture.swift" \
  "$projectDir/Sources/Dashboard/"*.swift "$projectDir/Tests/UI/DashboardTests.swift" -o "$previewApp/Contents/MacOS/DashboardPreview"
dockPreviewApp="$output/DockPreview.app"
ditto "$previewApp" "$dockPreviewApp"
plutil -replace CFBundleIdentifier -string com.ares.cmd.tab.ui.dockpreview "$dockPreviewApp/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string 'Cmd Tab Pro Dock 预览' "$dockPreviewApp/Contents/Info.plist"
"$previewApp/Contents/MacOS/DashboardPreview" "$output"
