#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/Scripts/harness_evidence.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/bitmatch-apfs-fault.XXXXXX")
HARNESS_MARKER="$WORK/.bitmatch-harness-root"
IMAGE="$WORK/fault-volume.dmg"
MOUNT="$WORK/mount"
DERIVED_DATA=${BITMATCH_DERIVED_DATA_PATH:-"$WORK/DerivedData"}
ATTACHED=0
touch "$HARNESS_MARKER"
mkdir "$MOUNT"
MOUNT_CANONICAL=$(cd "$MOUNT" && pwd -P)

is_fault_volume_mounted() {
  mount | grep -Fq " on $MOUNT_CANONICAL ("
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  remove_harness_test_run || {
    echo "Unable to remove temporary test configuration: ${HARNESS_XCTESTRUN:-unknown}" >&2
    status=1
  }
  if [[ "$ATTACHED" == 1 ]]; then
    hdiutil detach "$MOUNT_CANONICAL" >/dev/null 2>&1 \
      || hdiutil detach -force "$MOUNT_CANONICAL" >/dev/null 2>&1 \
      || true
  fi
  if is_fault_volume_mounted; then
    echo "Fault image is still mounted; preserving harness directory: $WORK" >&2
    status=1
  elif [[ -f "$HARNESS_MARKER" ]]; then
    rm -rf "$WORK" || {
      echo "Unable to remove harness directory: $WORK" >&2
      status=1
    }
  else
    echo "Refusing to remove unmarked APFS harness directory: $WORK" >&2
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

initialize_evidence apfs-fault
RESULT_BUNDLE="$EVIDENCE/results.xcresult"

# SafetyValidator requires a 1 GB free-space buffer before copying. A 2 GB
# image keeps this focused fault test above that production preflight threshold.
hdiutil create -quiet -size 2g -fs APFS -volname BitMatchFault "$IMAGE"
# Mark attachment as requiring cleanup before the attach command begins. This
# closes the signal window between a successful attach and state assignment.
ATTACHED=1
hdiutil attach -quiet -nobrowse -mountpoint "$MOUNT" "$IMAGE"
touch "$MOUNT_CANONICAL/.bitmatch-disposable-fixture"

xcodebuild -quiet \
  -project "$ROOT/BitMatch.xcodeproj" \
  -scheme BitMatch \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing 2>&1 | tee "$EVIDENCE/build.log"

prepare_harness_test_run
/usr/bin/python3 "$ROOT/Scripts/configure_harness_environment.py" "$XCTESTRUN" \
  "BITMATCH_FAULT_VOLUME=$MOUNT_CANONICAL"

if ! xcodebuild -quiet \
  test-without-building \
  -xctestrun "$XCTESTRUN" \
  -destination 'platform=macOS' \
  -resultBundlePath "$RESULT_BUNDLE" \
  -only-testing:BitMatchTests/TransferFaultIntegrationTests/testInaccessibleDestinationReportsFailuresWhileOtherDestinationSucceeds 2>&1 | tee "$EVIDENCE/test.log"; then
  xcrun xcresulttool get test-results tests --path "$RESULT_BUNDLE" --compact >&2 || true
  exit 1
fi
