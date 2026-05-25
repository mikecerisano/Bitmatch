#!/usr/bin/env bash
set -euo pipefail

VERSION=${1:-0.1.1}
PROJECT=${PROJECT:-BitMatch.xcodeproj}
SCHEME=${SCHEME:-BitMatch}
CONFIGURATION=${CONFIGURATION:-Release}
TEAM_ID=${DEVELOPMENT_TEAM:-AUJW7AGG26}
SIGN_IDENTITY=${SIGN_IDENTITY:-Developer ID Application: Michael Cerisano (AUJW7AGG26)}
NOTARY_PROFILE=${NOTARY_PROFILE:-bitmatch-notary}
SKIP_NOTARIZE=${SKIP_NOTARIZE:-0}

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE_PATH="$DIST_DIR/BitMatch-$VERSION.xcarchive"
ZIP_PATH="$DIST_DIR/BitMatch-$VERSION-macOS.zip"
CHECKSUM_PATH="$ZIP_PATH.sha256"
APP_PATH="$ARCHIVE_PATH/Products/Applications/BitMatch.app"

cd "$ROOT_DIR"
mkdir -p "$DIST_DIR"
rm -rf "$ARCHIVE_PATH" "$ZIP_PATH" "$CHECKSUM_PATH"

echo "Building signed archive for BitMatch $VERSION"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
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
  echo "Submitting to Apple notary service with keychain profile: $NOTARY_PROFILE"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "Stapling notarization ticket"
  xcrun stapler staple "$APP_PATH"

  echo "Rebuilding zip with stapled app"
  rm -f "$ZIP_PATH" "$CHECKSUM_PATH"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

  echo "Assessing Gatekeeper acceptance"
  spctl -a -vvv -t exec "$APP_PATH"
fi

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo
echo "Release artifact:"
echo "  $ZIP_PATH"
echo "Checksum:"
cat "$CHECKSUM_PATH"
