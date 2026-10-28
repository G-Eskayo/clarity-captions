#!/bin/bash
# Seal Speak for Mac as a download (#172, #173): builds the Release app, signs it with Developer ID, packs it in
# Seal-Speak-mac.dmg, notarizes and staples the DMG, then checks it the way Gatekeeper will on someone else's Mac.
#   scripts/release-mac.sh            build + check; prints the DMG path
#   scripts/release-mac.sh --publish  also publishes it as the latest GitHub Release, so
#                                     https://github.com/G-Eskayo/clarity-captions/releases/latest/download/Seal-Speak-mac.dmg
#                                     always serves the newest build
# Needs, once per Mac: a "Developer ID Application" certificate (Xcode > Settings > Accounts > Manage Certificates) and
# a notary login stored as `seal-speak-notary` (xcrun notarytool store-credentials seal-speak-notary --apple-id ...
# --team-id 2T6F3QLYNU). The speaker model must be in Apps/Mac/Resources/Models (scripts/fetch-diarizer-models.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM="2T6F3QLYNU"
PROFILE="${NOTARY_PROFILE:-seal-speak-notary}"
OUT="${OUT:-${TMPDIR:-/tmp}/seal-speak-mac-release}"
DMG_NAME="Seal-Speak-mac.dmg"
GH="${GH:-$HOME/.agents/bin/gh}"
REPO="G-Eskayo/clarity-captions"

fail() { echo "release-mac: $*" >&2; exit 1; }

# Preflight: everything Apple and the build need, before spending ten minutes building.
IDENTITY=$(security find-identity -v -p codesigning | sed -n "s/.*\"\(Developer ID Application: .*($TEAM)\)\"/\1/p" | head -1)
[ -n "$IDENTITY" ] || fail "no Developer ID Application certificate for team $TEAM in the keychain"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 || fail "no notary login stored as '$PROFILE'"
[ -d "$ROOT/Apps/Mac/Resources/Models/Sortformer_v2.1.mlmodelc" ] || fail "speaker model missing from Apps/Mac/Resources/Models"

rm -rf "$OUT" && mkdir -p "$OUT"
cd "$ROOT/Apps/Mac" && xcodegen generate --quiet
xcodebuild -project CaptionMac.xcodeproj -scheme CaptionMac -configuration Release \
  -archivePath "$OUT/SealSpeak.xcarchive" DEVELOPMENT_TEAM="$TEAM" -allowProvisioningUpdates archive -quiet

cat > "$OUT/export.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>destination</key><string>export</string>
<key>teamID</key><string>$TEAM</string>
<key>signingStyle</key><string>automatic</string>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath "$OUT/SealSpeak.xcarchive" -exportOptionsPlist "$OUT/export.plist" \
  -exportPath "$OUT/export" -allowProvisioningUpdates -quiet
APP="$OUT/export/Seal Speak.app"
[ -d "$APP" ] || fail "export made no Seal Speak.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")

# The DMG: the app and a shortcut to Applications, to drag it across.
mkdir -p "$OUT/dmg" && cp -R "$APP" "$OUT/dmg/" && ln -s /Applications "$OUT/dmg/Applications"
DMG="$OUT/$DMG_NAME"
hdiutil create -volname "Seal Speak" -srcfolder "$OUT/dmg" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"

# Notarize (covers the app inside) and staple the ticket, so it opens even offline.
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --output-format json > "$OUT/notary.json" || true
STATUS=$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "$OUT/notary.json")
if [ "$STATUS" != "Accepted" ]; then
  ID=$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "$OUT/notary.json")
  [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" >&2 || true
  fail "notarization status: ${STATUS:-none}"
fi
xcrun stapler staple "$DMG" >/dev/null

# Check it as Gatekeeper will: the DMG is notarized and stapled, and the app inside is a notarized Developer ID app.
xcrun stapler validate "$DMG" >/dev/null || fail "no stapled ticket on the DMG"
spctl --assess --type open --context context:primary-signature "$DMG" 2>/dev/null || fail "Gatekeeper rejects the DMG"
MNT=$(mktemp -d)
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MNT" >/dev/null
trap 'hdiutil detach "$MNT" -quiet 2>/dev/null || true' EXIT
codesign --verify --deep --strict "$MNT/Seal Speak.app" || fail "the app's signature doesn't verify"
spctl --assess --type execute "$MNT/Seal Speak.app" 2>/dev/null || fail "Gatekeeper rejects the app"
codesign -d --entitlements - "$MNT/Seal Speak.app" 2>/dev/null | grep -q "com.apple.security.device.audio-input" || fail "microphone entitlement missing"
/usr/libexec/PlistBuddy -c "Print :NSAudioCaptureUsageDescription" "$MNT/Seal Speak.app/Contents/Info.plist" >/dev/null || fail "System Audio Recording usage text missing"
hdiutil detach "$MNT" -quiet; trap - EXIT
echo "checked: $DMG (Seal Speak $VERSION ($BUILD), notarized, stapled, Gatekeeper accepts)"

[ "${1:-}" = "--publish" ] || exit 0
TAG="mac-v$VERSION-$BUILD"
"$GH" release create "$TAG" "$DMG" -R "$REPO" --latest --title "Seal Speak for Mac $VERSION ($BUILD)" \
  --notes "Seal Speak for Mac $VERSION ($BUILD): live captions of FaceTime and phone calls on the Mac (#172). Open the DMG and drag Seal Speak to Applications. macOS 26 or newer."
# The model pre-release must never become "latest".
"$GH" release view models-ultra-pal6 -R "$REPO" --json isPrerelease --jq .isPrerelease 2>/dev/null | grep -q true \
  || echo "release-mac: warning: models-ultra-pal6 is not a pre-release" >&2
echo "published: https://github.com/$REPO/releases/latest/download/$DMG_NAME"
