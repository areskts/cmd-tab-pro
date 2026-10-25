#!/bin/bash
set -euo pipefail
projectDir="$(cd "$(dirname "$0")/.." && pwd)"
for script in "$projectDir/scripts/"*.sh "$projectDir/Tests/Acceptance/run.sh" \
  "$projectDir/Tests/Windows/run.sh" "$projectDir/Tests/Windows/integration.sh" "$projectDir/Tests/UI/run.sh" "$projectDir/Tests/Signing/run.sh"; do
  bash -n "$script"
done
CMD_TAB_PRO_BUILD_ONLY=1 bash "$projectDir/scripts/install.sh"
if [ -f "$HOME/.config/cmd-tab-pro/signing-identity" ] || [ -n "${CMD_TAB_PRO_SIGN_IDENTITY:-}" ]; then
  bash "$projectDir/Tests/Signing/run.sh"
fi
bash "$projectDir/Tests/Statistics/run.sh"
bash "$projectDir/Tests/Windows/run.sh"
bash "$projectDir/Tests/UI/run.sh"
bash "$projectDir/Tests/Windows/integration.sh"
app="$projectDir/.build/CmdTabPro.app"
codesign --verify --deep --strict "$app"
test "$(lipo -archs "$app/Contents/MacOS/CmdTabPro")" = "arm64"
test "$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")" = "com.ares.cmd.tab"
for icon in option1 option2 option3; do
  test -s "$app/Contents/Resources/IconOptions/$icon.icns"
done
set +e
"$app/Contents/Helpers/CmdTabProIconSwitcher"
result=$?
set -e
test "$result" = "2"
echo "automated regression passed; native Cmd+Tab, login and hardware scenarios require the documented acceptance checks"
