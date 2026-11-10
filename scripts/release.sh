#!/bin/bash
# Developer ID signed, notarized and stapled build/Beam.app and build/Beam.dmg.
#   NOTARY_PROFILE  notarytool keychain profile (default: beam-notary), created once with
#                   xcrun notarytool store-credentials beam-notary
#   SIGN_ID         signing identity (default: the Developer ID Application cert)
#   SKIP_NOTARIZE=1 sign only (checks the signing steps without Apple's service)
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_ID="${SIGN_ID:-Developer ID Application: Uval Blumenfeld (P9GCM9K6AH)}"
PROFILE="${NOTARY_PROFILE:-beam-notary}"
APP=build/Beam.app
DMG=build/Beam.dmg
ENT=Resources/Beam.entitlements
SIGN=(codesign --force --timestamp --options runtime --sign "$SIGN_ID")

security find-identity -v -p codesigning | grep -qF "$SIGN_ID" || { echo "Signing identity not in keychain: $SIGN_ID" >&2; exit 1; }
if [ -z "${SKIP_NOTARIZE:-}" ]; then
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 || {
    echo "No notarytool profile '$PROFILE'. Create it in your own terminal:" >&2
    echo "  xcrun notarytool store-credentials $PROFILE --apple-id <apple id> --team-id P9GCM9K6AH" >&2
    exit 1
  }
fi

# Release hygiene: clean tree and a version bump.
if [ -z "${ALLOW_DIRTY:-}" ]; then
  if ! git diff --quiet HEAD || [ -n "$(git status --porcelain)" ]; then
    echo "Git tree is dirty; commit or stash first (or ALLOW_DIRTY=1)." >&2
    exit 1
  fi
fi
NEW_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)
if [ -f build/last-version ]; then
  LAST_VERSION=$(tr -d '[:space:]' < build/last-version)
  if [ -n "$LAST_VERSION" ] && ! [ "$NEW_VERSION" -gt "$LAST_VERSION" ]; then
    echo "CFBundleVersion $NEW_VERSION is not greater than last released $LAST_VERSION (build/last-version). Bump it in Resources/Info.plist." >&2
    exit 1
  fi
fi

# Build the bundle via the dev target, then re-sign it below.
make app
# KeyboardShortcuts' resources (localized strings): without them Settings crashes on open.
[ -d "$APP/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle" ] || { echo "Missing KeyboardShortcuts resource bundle in $APP" >&2; exit 1; }
# Sign nested code first, inside out, each with its own signature (no --deep).
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for x in "$SPK"/XPCServices/*.xpc; do [ -e "$x" ] && "${SIGN[@]}" --preserve-metadata=entitlements "$x"; done
"${SIGN[@]}" "$SPK/Autoupdate"
"${SIGN[@]}" "$SPK/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
for b in "$APP"/Contents/Resources/*.bundle; do [ -e "$b" ] && "${SIGN[@]}" "$b"; done
"${SIGN[@]}" --entitlements "$ENT" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

rm -rf build/dmg "$DMG"
mkdir -p build/dmg
cp -R "$APP" build/dmg/Beam.app
ln -s /Applications build/dmg/Applications
hdiutil create -volname Beam -srcfolder build/dmg -ov -format UDZO "$DMG"
rm -rf build/dmg
"${SIGN[@]}" "$DMG"

if [ -n "${SKIP_NOTARIZE:-}" ]; then echo "Signed only (SKIP_NOTARIZE)."; exit 0; fi

# Notarizing the dmg covers the app inside it; staple both afterwards.
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
# The app in the dmg is stapled by the dmg's ticket lookup, but staple build/Beam.app too.
xcrun stapler staple "$APP"

xcrun stapler validate "$DMG"
xcrun stapler validate "$APP"
spctl -a -vv "$APP"
spctl -a -vv -t open --context context:primary-signature "$DMG"
echo "Release ready: $DMG"
mkdir -p build; echo "$NEW_VERSION" > build/last-version
