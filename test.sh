#!/usr/bin/env bash
set -euo pipefail

SCHEME=${1:-BitMatch}
DESTINATION=${DESTINATION:-platform=macOS}

echo "Running unit tests for scheme: $SCHEME"
xcodebuild test \
  -project BitMatch.xcodeproj \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:BitMatchTests

echo
echo "Done."
