#!/bin/bash

set -euo pipefail

projectDir="$(cd "$(dirname "$0")/../.." && pwd)"
executable="$projectDir/.build/SwitchStatisticsTests"

mkdir -p "$(dirname "$executable")"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos26.0 \
  "$projectDir/Sources/Statistics/SwitchStatistics.swift" \
  "$projectDir/Tests/Statistics/SwitchStatisticsTests.swift" \
  -o "$executable"
"$executable"
