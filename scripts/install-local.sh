#!/bin/bash
# Build the fork and install it to /Applications, signed with a local self-signed
# certificate ("Lockpaw Local Signing" in the login keychain). The designated requirement
# is pinned to that certificate, so Accessibility survives rebuilds — unlike ad-hoc
# signing, where every build is a new identity to macOS.
#
# No hardened runtime: Sparkle.framework is re-signed with the same certificate, and
# without a Team ID library validation would refuse it under the runtime.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="Lockpaw Local Signing"
APP=/Applications/Lockpaw.app
BUILT=build/DerivedData/Build/Products/Release/Lockpaw.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

security find-certificate -c "$IDENTITY" >/dev/null 2>&1 || { echo "Missing '$IDENTITY' certificate in the keychain." >&2; exit 1; }

xcodegen generate >/dev/null
xcodebuild -project Lockpaw.xcodeproj -scheme Lockpaw -configuration Release \
  -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

# Quit (refused while locked, which is what we want: never swap a guarding app).
osascript -e 'tell application "Lockpaw" to quit' 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8; do pgrep -x Lockpaw >/dev/null || break; sleep 1; done
pgrep -x Lockpaw >/dev/null && { echo "Lockpaw is still running (locked?). Unlock and re-run." >&2; exit 1; }

ENTITLEMENTS=$(mktemp)
trap 'rm -f "$ENTITLEMENTS"' EXIT
codesign -d --entitlements :- "$BUILT" > "$ENTITLEMENTS" 2>/dev/null

rm -rf "$APP"
ditto "$BUILT" "$APP"
# Inside-out: nested code first, the app last. Build copies are removed so System
# Settings lists one Lockpaw.
codesign --force --deep --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" "$APP/Contents/SharedSupport/lockpaw"
codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"
"$LSREGISTER" -u "$PWD/$BUILT" 2>/dev/null || true
rm -rf "$BUILT" build/DerivedData/Build/Products/Debug/Lockpaw.app
"$LSREGISTER" -f "$APP"

open "$APP"
echo "Installed: $(codesign -dr - "$APP" 2>&1 | tail -1)"
