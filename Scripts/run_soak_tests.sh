#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/Scripts/harness_evidence.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/bitmatch-soak.XXXXXX")
MARKER="$WORK/.bitmatch-disposable-fixture"
DERIVED_DATA=${BITMATCH_DERIVED_DATA_PATH:-"$WORK/DerivedData"}
RESULT="$WORK/soak-result.json"
touch "$MARKER"

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  remove_harness_test_run || {
    echo "Unable to remove temporary test configuration: ${HARNESS_XCTESTRUN:-unknown}" >&2
    status=1
  }
  local preserve_work=0
  if [[ -f "$RESULT" ]]; then
    if [[ -z "${EVIDENCE:-}" ]] || ! cp "$RESULT" "$EVIDENCE/soak-result.json"; then
      echo "Unable to retain soak result; preserving original at: $RESULT" >&2
      preserve_work=1
      status=1
    fi
  fi
  if [[ "$preserve_work" == 1 ]]; then
    echo "Preserving harness directory: $WORK" >&2
  elif [[ -f "$MARKER" ]]; then
    rm -rf "$WORK" || {
      echo "Unable to remove harness directory: $WORK" >&2
      status=1
    }
  else
    echo "Refusing to remove unmarked soak directory: $WORK" >&2
    status=1
  fi
  finish_evidence "$status" || {
    echo "Unable to finalize evidence metadata: ${EVIDENCE:-unknown}; run failed" >&2
    status=1
  }
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

initialize_evidence soak
RESULT_BUNDLE="$EVIDENCE/results.xcresult"

BITMATCH_SOAK_SEED=${BITMATCH_SOAK_SEED:-20260711}
BITMATCH_SOAK_ITERATIONS=${BITMATCH_SOAK_ITERATIONS:-25}
printf 'seed=%s\niterations=%s\n' "$BITMATCH_SOAK_SEED" "$BITMATCH_SOAK_ITERATIONS" >> "$EVIDENCE/environment.txt"
[[ "$BITMATCH_SOAK_SEED" =~ ^[0-9]+$ ]] || { echo "BITMATCH_SOAK_SEED must be an unsigned integer" >&2; exit 64; }
[[ "$BITMATCH_SOAK_ITERATIONS" =~ ^[1-9][0-9]*$ ]] || { echo "BITMATCH_SOAK_ITERATIONS must be a positive integer" >&2; exit 64; }

xcodebuild -quiet \
  -project "$ROOT/BitMatch.xcodeproj" \
  -scheme BitMatch \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing 2>&1 | tee "$EVIDENCE/build.log"

prepare_harness_test_run
/usr/bin/python3 "$ROOT/Scripts/configure_harness_environment.py" "$XCTESTRUN" \
  BITMATCH_RUN_SOAK=1 \
  "BITMATCH_SOAK_SEED=$BITMATCH_SOAK_SEED" \
  "BITMATCH_SOAK_ITERATIONS=$BITMATCH_SOAK_ITERATIONS" \
  "BITMATCH_SOAK_RESULT=$RESULT"

xcodebuild -quiet \
  test-without-building \
  -xctestrun "$XCTESTRUN" \
  -destination 'platform=macOS' \
  -resultBundlePath "$RESULT_BUNDLE" \
  -only-testing:BitMatchTests/TransferSoakTests 2>&1 | tee "$EVIDENCE/test.log"

/usr/bin/python3 -m json.tool "$RESULT" >/dev/null
cp "$RESULT" "$EVIDENCE/soak-result.json"
cat "$RESULT"
