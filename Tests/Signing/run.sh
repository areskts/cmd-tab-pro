#!/bin/bash
set -euo pipefail
projectDir="$(cd "$(dirname "$0")/../.." && pwd)"
output="$projectDir/.build/signing-tests"
identity="${CMD_TAB_PRO_SIGN_IDENTITY:-$(cat "$HOME/.config/cmd-tab-pro/signing-identity")}"
if [ "$identity" = "-" ]; then
  echo "SKIP: certificate update checks require a certificate signing identity; ad-hoc mode selected."
  exit 0
fi
mkdir -p "$output/Original.app/Contents/MacOS"
cp "$projectDir/Resources/Info.plist" "$output/Original.app/Contents/Info.plist"
printf 'print("original signing fixture")\n' > "$output/main.swift"
xcrun swiftc -swift-version 5 "$output/main.swift" -o "$output/Original.app/Contents/MacOS/CmdTabPro"
rm -rf "$output/Updated.app" "$output/Adhoc.app" "$output/Tampered.app"
ditto "$output/Original.app" "$output/Updated.app"
printf 'print("updated signing fixture")\n' > "$output/main.swift"
xcrun swiftc -swift-version 5 "$output/main.swift" -o "$output/Updated.app/Contents/MacOS/CmdTabPro"
for app in Original Updated; do
  codesign --force --options runtime --sign "$identity" --identifier com.ares.cmd.tab "$output/$app.app"
done
ditto "$output/Updated.app" "$output/Adhoc.app"
codesign --force --options runtime --sign - --identifier com.ares.cmd.tab "$output/Adhoc.app"
requirement="$(codesign -d -r- "$output/Original.app" 2>&1 | sed -n 's/^designated => //p')"
codesign --verify --strict -R "=$requirement" "$output/Updated.app"
if codesign --verify --strict -R "=$requirement" "$output/Adhoc.app" 2>"$output/rejected-adhoc.log"; then
  echo "Ad-hoc replacement unexpectedly satisfied the certificate requirement." >&2
  exit 1
fi
echo "codesign update requirement checks passed (2 checks)"
ditto "$output/Original.app" "$output/Tampered.app"
plutil -replace CFBundleVersion -string 999 "$output/Tampered.app/Contents/Info.plist"
xcrun swiftc -swift-version 5 -framework Security -framework CryptoKit \
  "$projectDir/Sources/IconSwitcher/CodeSignature.swift" "$projectDir/Tests/Signing/CodeSignatureTests.swift" -o "$output/CodeSignatureTests"
"$output/CodeSignatureTests" "$output/Original.app" "$output/Updated.app" "$output/Adhoc.app" "$output/Tampered.app" "$identity"
