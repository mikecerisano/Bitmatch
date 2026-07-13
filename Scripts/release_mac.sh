#!/usr/bin/env bash
set -euo pipefail

VERSION=${1:-0.1.3}
PROJECT=${PROJECT:-BitMatch.xcodeproj}
SCHEME=${SCHEME:-BitMatch}
CONFIGURATION=${CONFIGURATION:-Release}
TEAM_ID=${DEVELOPMENT_TEAM:-AUJW7AGG26}
SIGN_IDENTITY=${SIGN_IDENTITY:-Developer ID Application: Michael Cerisano (AUJW7AGG26)}
NOTARY_PROFILE=${NOTARY_PROFILE:-bitmatch-notary}
SKIP_NOTARIZE=${SKIP_NOTARIZE:-0}

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DIST_DIR="$ROOT_DIR/dist"
DERIVED_DATA_PATH="$DIST_DIR/DerivedData"
ARCHIVE_PATH="$DIST_DIR/BitMatch-$VERSION.xcarchive"
ZIP_PATH="$DIST_DIR/BitMatch-$VERSION.app.zip"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/BitMatch-$VERSION.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
APP_PATH="$ARCHIVE_PATH/Products/Applications/BitMatch.app"

cd "$ROOT_DIR"
mkdir -p "$DIST_DIR"
rm -rf "$DERIVED_DATA_PATH" "$ARCHIVE_PATH" "$ZIP_PATH" "$DMG_ROOT" "$DMG_PATH" "$CHECKSUM_PATH"

echo "Building signed archive for BitMatch $VERSION"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY"

echo "Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --display --verbose=4 "$APP_PATH"

echo "Creating notarization zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  echo "Submitting app to Apple notary service with keychain profile: $NOTARY_PROFILE"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "Stapling app notarization ticket"
  xcrun stapler staple "$APP_PATH"
fi

echo "Creating DMG"
mkdir -p "$DMG_ROOT"
ditto "$APP_PATH" "$DMG_ROOT/BitMatch.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "BitMatch $VERSION" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_ROOT"
codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  echo "Submitting DMG to Apple notary service"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "Stapling DMG notarization ticket"
  xcrun stapler staple "$DMG_PATH"

  echo "Assessing Gatekeeper acceptance for app and DMG"
  spctl -a -vvv -t exec "$APP_PATH"
  spctl -a -vvv -t open --context context:primary-signature "$DMG_PATH"
fi

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo
echo "Release artifact:"
echo "  $DMG_PATH"
echo "Checksum:"
cat "$CHECKSUM_PATH"
