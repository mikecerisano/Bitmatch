#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/bitmatch-apfs-fault.XXXXXX")
HARNESS_MARKER="$WORK/.bitmatch-harness-root"
IMAGE="$WORK/fault-volume.dmg"
MOUNT="$WORK/mount"
DERIVED_DATA="$WORK/DerivedData"
RESULT_BUNDLE="$WORK/apfs-fault-results.xcresult"
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
  if [[ "$ATTACHED" == 1 ]]; then
    hdiutil detach "$MOUNT_CANONICAL" >/dev/null 2>&1 \
      || hdiutil detach -force "$MOUNT_CANONICAL" >/dev/null 2>&1 \
      || true
  fi
  if is_fault_volume_mounted; then
    echo "Fault image is still mounted; preserving harness directory: $WORK" >&2
    status=1
  elif [[ -f "$HARNESS_MARKER" ]]; then
    rm -rf "$WORK"
  else
    echo "Refusing to remove unmarked APFS harness directory: $WORK" >&2
    status=1
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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
  build-for-testing

XCTESTRUN=$(find "$DERIVED_DATA" -name '*.xctestrun' -print -quit)
[[ -n "$XCTESTRUN" ]] || { echo "Unable to locate generated xctestrun file" >&2; exit 1; }
ENVIRONMENT_PATH=':TestConfigurations:0:TestTargets:1:EnvironmentVariables'
/usr/libexec/PlistBuddy -c "Add $ENVIRONMENT_PATH:BITMATCH_FAULT_VOLUME string '$MOUNT_CANONICAL'" "$XCTESTRUN"

if ! xcodebuild -quiet \
  test-without-building \
  -xctestrun "$XCTESTRUN" \
  -destination 'platform=macOS' \
  -resultBundlePath "$RESULT_BUNDLE" \
  -only-testing:BitMatchTests/TransferFaultIntegrationTests/testInaccessibleDestinationReportsFailuresWhileOtherDestinationSucceeds; then
  xcrun xcresulttool get test-results tests --path "$RESULT_BUNDLE" --compact >&2 || true
  exit 1
fi
