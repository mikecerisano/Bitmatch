#!/usr/bin/env bash
# Shared by the fault and soak harnesses; evidence lives outside disposable media.
initialize_evidence() {
  local harness=$1
  local evidence_root=${BITMATCH_EVIDENCE_ROOT:-${TMPDIR:-/tmp}/bitmatch-evidence}
  mkdir -p "$evidence_root"
  EVIDENCE=$(mktemp -d "$evidence_root/$harness.XXXXXX")
  EVIDENCE=$(cd "$EVIDENCE" && pwd -P)
  {
    echo "harness=$harness"
    echo "started_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "revision=$(git -C "$ROOT" rev-parse HEAD)"
    echo "working_tree_changes_begin"
    git -C "$ROOT" status --short
    echo "working_tree_changes_end"
    sw_vers
    xcodebuild -version
    echo "architecture=$(uname -m)"
  } > "$EVIDENCE/environment.txt"
  echo "Evidence directory: $EVIDENCE"
}

finish_evidence() {
  local status=$1
  if [[ -n "${EVIDENCE:-}" ]]; then
    {
      echo "finished_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      echo "exit_status=$status"
    } >> "$EVIDENCE/environment.txt" || return 1
    echo "Evidence retained: $EVIDENCE (exit $status)"
  fi
}

prepare_harness_test_run() {
  local original
  original=$(/usr/bin/python3 - "$DERIVED_DATA/Build/Products" <<'PY'
import sys
from pathlib import Path
candidates = list(Path(sys.argv[1]).glob('BitMatch*_macosx*.xctestrun'))
if not candidates:
    sys.exit('Unable to locate a macOS BitMatch xctestrun in Build/Products')
print(max(candidates, key=lambda path: path.stat().st_mtime))
PY
  )
  # Keep the copy beside the original so __TESTROOT__ retains its meaning.
  # Never inject temporary fixture paths into a reusable build's original file.
  HARNESS_XCTESTRUN=$(mktemp "$DERIVED_DATA/Build/Products/.bitmatch-harness.XXXXXX")
  cp "$original" "$HARNESS_XCTESTRUN"
  mv "$HARNESS_XCTESTRUN" "$HARNESS_XCTESTRUN.xctestrun"
  HARNESS_XCTESTRUN="$HARNESS_XCTESTRUN.xctestrun"
  XCTESTRUN="$HARNESS_XCTESTRUN"
}

remove_harness_test_run() {
  if [[ -n "${HARNESS_XCTESTRUN:-}" ]]; then
    rm -f "$HARNESS_XCTESTRUN" "$HARNESS_XCTESTRUN.xctestrun"
  fi
}
