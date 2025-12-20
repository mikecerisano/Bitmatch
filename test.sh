#!/usr/bin/env bash
set -euo pipefail

SCHEME=${1:-BitMatch}
OUT=${2:-coverage.xcresult}

echo "Running tests with coverage for scheme: $SCHEME"
xcodebuild test \
  -scheme "$SCHEME" \
  -enableCodeCoverage YES \
  -resultBundlePath "$OUT"

echo "\nCoverage summary (human readable):"
xcrun xccov view --report "$OUT" || true

echo "\nCoverage JSON (for tooling):"
xcrun xccov view --report --json "$OUT" || true

echo "\nDone. Result bundle: $OUT"
