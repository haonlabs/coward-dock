#!/bin/bash
# Builds build/Coward Dock.app (universal) and build/CowardDock-<version>.dmg.
# Optional: SIGN_ID="Developer ID Application: ..." to sign for distribution,
#           NOTARY_PROFILE=<notarytool keychain profile> to notarize the DMG.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Coward Dock.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
DMG="build/CowardDock-$VERSION.dmg"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/dmg

swiftc Sources/DockWatcher.swift Tests/main.swift -o build/selftest && build/selftest && rm build/selftest

for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos14" Sources/*.swift -o "build/CowardDock-$arch"
done
lipo -create build/CowardDock-arm64 build/CowardDock-x86_64 -output "$APP/Contents/MacOS/CowardDock"
cp Info.plist "$APP/Contents/"

swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# Default to the maintainer's self-signed identity when it's in the keychain: macOS then pins the
# Accessibility permission to that certificate instead of to each build, so it survives updates.
# Anyone else gets an ad hoc build.
SELF_ID="Coward Dock (haonlabs)"
if [[ -z "${SIGN_ID:-}" ]] && security find-certificate -c "$SELF_ID" >/dev/null 2>&1; then SIGN_ID=$SELF_ID; fi
codesign --force --options runtime --timestamp=none --sign "${SIGN_ID:--}" "$APP"
codesign --verify --strict "$APP"

cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "Coward Dock" -srcfolder build/dmg -ov -format UDZO "$DMG" >/dev/null
rm -rf build/dmg build/AppIcon.iconset build/CowardDock-arm64 build/CowardDock-x86_64

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  codesign --sign "$SIGN_ID" "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "Built $DMG"
