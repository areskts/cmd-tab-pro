#!/bin/bash
set -euo pipefail
projectDir="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$projectDir/.build"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos26.0 -framework AppKit \
  "$projectDir/Sources/Windows/WindowPolicy.swift" \
  "$projectDir/Sources/Windows/EnhancementSettings.swift" \
  "$projectDir/Sources/Dock/DockPolicy.swift" \
  "$projectDir/Sources/Reopen/CmdTabMonitor.swift" \
  "$projectDir/Tests/Windows/WindowPolicyTests.swift" -o "$projectDir/.build/WindowPolicyTests"
"$projectDir/.build/WindowPolicyTests"
