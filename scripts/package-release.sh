#!/bin/bash

set -euo pipefail

projectDir="$(cd "$(dirname "$0")/.." && pwd)"
releaseDir="$projectDir/.build/release"
app="$projectDir/.build/CmdTabPro.app"
executable="$app/Contents/MacOS/CmdTabPro"
version="$(plutil -extract CFBundleShortVersionString raw "$projectDir/Resources/Info.plist")"
archive="$releaseDir/Cmd-Tab-Pro-v$version-macOS-26-arm64-adhoc.zip"
checksum="$archive.sha256"

CMD_TAB_PRO_BUILD_ONLY=1 CMD_TAB_PRO_ICON_OPTION=option2 bash "$projectDir/scripts/install.sh"
if [ "$(lipo -archs "$executable")" != "arm64" ]; then
  echo "Release executable is not arm64-only." >&2
  exit 1
fi

mkdir -p "$releaseDir"
rm -f "$archive" "$checksum"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
(cd "$releaseDir" && shasum -a 256 "$(basename "$archive")" > "$(basename "$checksum")")

echo "Created ad-hoc signed release package: $archive"
echo "Created checksum: $checksum"
echo "Gatekeeper may block first launch because this package is not notarized."
