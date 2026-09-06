#!/usr/bin/env python3
"""Check that both demo destinations contain every expected file and hash."""
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / "expected-sha256.json").read_text())
failures = []
for destination_name in ("Backup A", "Backup B"):
    destination = root / destination_name
    for name, expected in manifest.items():
        candidates = list(destination.rglob(name))
        if len(candidates) != 1:
            failures.append(f"{destination_name}/{name}: expected 1 copy, found {len(candidates)}")
            continue
        data = candidates[0].read_bytes()
        if len(data) != expected["bytes"] or hashlib.sha256(data).hexdigest() != expected["sha256"]:
            failures.append(f"{destination_name}/{name}: bytes or SHA-256 differ")
if failures:
    print("\n".join(failures))
    sys.exit(1)
print(f"PASS: {len(manifest)} files match the independent SHA-256 manifest in each of 2 destinations.")
