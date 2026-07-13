#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/bitmatch-soak.XXXXXX")
MARKER="$WORK/.bitmatch-disposable-fixture"
DERIVED_DATA="$WORK/DerivedData"
RESULT="$WORK/soak-result.json"
touch "$MARKER"

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ -f "$MARKER" ]]; then
    rm -rf "$WORK"
  else
    echo "Refusing to remove unmarked soak directory: $WORK" >&2
    status=1
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

BITMATCH_SOAK_SEED=${BITMATCH_SOAK_SEED:-20260711}
BITMATCH_SOAK_ITERATIONS=${BITMATCH_SOAK_ITERATIONS:-25}
[[ "$BITMATCH_SOAK_SEED" =~ ^[0-9]+$ ]] || { echo "BITMATCH_SOAK_SEED must be an unsigned integer" >&2; exit 64; }
[[ "$BITMATCH_SOAK_ITERATIONS" =~ ^[1-9][0-9]*$ ]] || { echo "BITMATCH_SOAK_ITERATIONS must be a positive integer" >&2; exit 64; }

xcodebuild -quiet \
  -project "$ROOT/BitMatch.xcodeproj" \
  -scheme BitMatch \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing

XCTESTRUN=$(find "$DERIVED_DATA" -name '*.xctestrun' -print -quit)
[[ -n "$XCTESTRUN" ]] || { echo "Unable to locate generated xctestrun file" >&2; exit 1; }
ENVIRONMENT_PATH=':TestConfigurations:0:TestTargets:1:EnvironmentVariables'
/usr/libexec/PlistBuddy -c "Add $ENVIRONMENT_PATH:BITMATCH_RUN_SOAK string '1'" "$XCTESTRUN"
/usr/libexec/PlistBuddy -c "Add $ENVIRONMENT_PATH:BITMATCH_SOAK_SEED string '$BITMATCH_SOAK_SEED'" "$XCTESTRUN"
/usr/libexec/PlistBuddy -c "Add $ENVIRONMENT_PATH:BITMATCH_SOAK_ITERATIONS string '$BITMATCH_SOAK_ITERATIONS'" "$XCTESTRUN"
/usr/libexec/PlistBuddy -c "Add $ENVIRONMENT_PATH:BITMATCH_SOAK_RESULT string '$RESULT'" "$XCTESTRUN"

xcodebuild -quiet \
  test-without-building \
  -xctestrun "$XCTESTRUN" \
  -destination 'platform=macOS' \
  -only-testing:BitMatchTests/TransferSoakTests

/usr/bin/python3 -m json.tool "$RESULT" >/dev/null
cat "$RESULT"
