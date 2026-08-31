#!/bin/bash

set -euo pipefail

testDir="$(cd "$(dirname "$0")" && pwd)"
projectDir="$(cd "$testDir/../.." && pwd)"
buildDir="$projectDir/.build/acceptance"
fixtureApp="$buildDir/Fixture.app"
fixtureExecutable="$fixtureApp/Contents/MacOS/Fixture"
activateExecutable="$buildDir/activate"
stateFile="/tmp/cmd-tab-pro-fixture-state"
readyFile="/tmp/cmd-tab-pro-fixture-ready"
visibleReopenFile="/tmp/cmd-tab-pro-fixture-visible-reopen"
expectTool="$1"

rm -rf "$buildDir"
mkdir -p "$fixtureApp/Contents/MacOS"
rm -f "$stateFile" "$readyFile" "$visibleReopenFile"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos26.0 -framework AppKit "$testDir/Fixture.swift" -o "$fixtureExecutable"
cp "$testDir/Info.plist" "$fixtureApp/Contents/Info.plist"
codesign --force --deep --sign - "$fixtureApp"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos26.0 -framework AppKit "$testDir/Activate.swift" -o "$activateExecutable"

"$activateExecutable" com.ares.cmd.tab.fixture --terminate 2>/dev/null || true
open -n "$fixtureApp"
for _ in {1..30}; do
  [ "$(cat "$readyFile" 2>/dev/null || true)" = "ready" ] && break
  sleep 0.1
done
[ "$(cat "$readyFile" 2>/dev/null || true)" = "ready" ]
[ "$(cat "$stateFile" 2>/dev/null || true)" = "opened" ]

if [ "$expectTool" = "1" ]; then
  for _ in {1..30}; do
    [ "$(cat "$visibleReopenFile" 2>/dev/null || true)" = "1" ] && break
    sleep 0.1
  done
  [ "$(cat "$visibleReopenFile" 2>/dev/null || true)" = "1" ]
  [ "$(cat "$stateFile" 2>/dev/null || true)" = "opened" ]
fi

fixturePid="$(pgrep -n -f "$fixtureExecutable")"
kill -USR1 "$fixturePid"
for _ in {1..30}; do
  [ "$(cat "$stateFile" 2>/dev/null || true)" = "closed" ] && break
  sleep 0.1
done
[ "$(cat "$stateFile" 2>/dev/null || true)" = "closed" ]

"$activateExecutable" com.apple.finder
"$activateExecutable" com.ares.cmd.tab.fixture
for _ in {1..40}; do
  [ "$(cat "$stateFile" 2>/dev/null || true)" = "reopened" ] && break
  sleep 0.1
done

result="$(cat "$stateFile" 2>/dev/null || true)"
"$activateExecutable" com.ares.cmd.tab.fixture --terminate 2>/dev/null || true
if [ "$expectTool" = "1" ]; then
  [ "$result" = "reopened" ]
  echo "acceptance passed: existing window stayed single and windowless activation reopened"
else
  [ "$result" = "closed" ]
  echo "control passed: windowless activation stayed closed without Cmd Tab Pro"
fi
